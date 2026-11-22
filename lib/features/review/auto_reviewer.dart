import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/providers/agent_provider.dart' show AgentAccess;
import '../../core/providers/structured_run.dart';
import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../agents/agent_file.dart';
import '../agents/codex_agent.dart';
import '../board/board_rules.dart';
import '../board/orchestrator/orchestrator_rules.dart';
import '../board/orchestrator/step_plan.dart';
import '../board/spec_runner.dart';
import '../board/step_gate.dart';
import '../project/project_config.dart';
import '../project/project_memory.dart';
import 'reviewer_findings.dart';
import 'reviewer_provider.dart';
import '../sessions/app_notifier.dart';
import '../specs/spec_service.dart';

/// The project's own reviewer agent (`.claude/agents/spec-reviewer.md`).
const reviewerAgentName = 'spec-reviewer';

/// `review_phase` values of a spec in the Review column.
abstract final class ReviewPhase {
  /// The automatic reviewer works on it (or its corrections run).
  static const auto = 'auto';

  /// Waiting for the user.
  static const human = 'human';
}

/// Instructions of the built-in reviewer. A project may replace them with
/// its own `.claude/agents/spec-reviewer.md` (then `--agent spec-reviewer`).
const builtinReviewerPrompt = '''
Você é o revisor automático do Promptorium. Revise a implementação de uma spec
antes do humano: leia a spec, o diff da branch e, se precisar, os arquivos do
repositório (somente leitura).

Aprove quando todos os requisitos estiverem implementados, os critérios de
aceite atendidos e não houver erro evidente. Peça correção só para o que
importa: requisito faltando ou errado, bug, teste ausente para um requisito,
quebra de algo que já existia, segredo no código. Não peça mudanças de estilo
ou gosto pessoal.

Cada comentário diz o arquivo e a linha do arquivo novo, como numerada no diff (linha 0 = o arquivo todo; arquivo
vazio = a spec como um todo), o que está errado e o que fazer, com o requisito
(R1, R2…) quando houver. Escreva em português, curto e direto.''';

/// `--json-schema` of the reviewer's answer.
final reviewerSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['veredito', 'resumo', 'comentarios', 'criterios'],
  'properties': {
    'criterios': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['indice', 'atendido'],
        'properties': {
          'indice': {'type': 'integer'},
          'atendido': {'type': 'boolean'},
        },
      },
    },
    'veredito': {
      'type': 'string',
      'enum': ['aprovar', 'corrigir'],
    },
    'resumo': {'type': 'string'},
    'comentarios': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['arquivo', 'linha', 'texto', 'severidade', 'requisito'],
        'properties': {
          'arquivo': {'type': 'string'},
          'linha': {'type': 'integer'},
          'texto': {'type': 'string'},
          'severidade': {
            'type': 'string',
            'enum': ['alta', 'media', 'baixa'],
          },
          'requisito': {'type': 'string'},
        },
      },
    },
  },
};

/// One comment of the reviewer's answer.
@immutable
class ReviewerComment {
  const ReviewerComment({
    required this.text,
    this.path,
    this.line,
    this.severity,
    this.requirement,
  });

  final String text;
  final String? path;
  final int? line;
  final String? severity;
  final String? requirement;

  String get location => path == null
      ? 'spec'
      : line == null || line == 0
      ? path!
      : '$path:$line';
}

/// The reviewer's answer.
@immutable
class ReviewerVerdict {
  const ReviewerVerdict({
    required this.approve,
    this.summary = '',
    this.comments = const [],
    this.met = const {},
  });

  final bool approve;
  final String summary;
  final List<ReviewerComment> comments;

  /// Indices (0-based, as listed in the prompt) of the acceptance criteria
  /// the reviewer found met.
  final Set<int> met;

  /// The verdict with its comments normalized (SPEC-102 R8).
  ReviewerVerdict normalized({
    required String diff,
    required String worktree,
    Set<String>? requirements,
  }) => ReviewerVerdict(
    approve: approve,
    summary: summary,
    met: met,
    comments: normalizeReviewerComments(
      comments,
      diff: diff,
      worktree: worktree,
      requirements: requirements,
    ),
  );

  static ReviewerVerdict? parse(Object? data) {
    if (data is! Map) return null;
    String? opt(Object? v) {
      final s = v == null ? '' : '$v'.trim();
      return s.isEmpty ? null : s;
    }

    final comments = [
      for (final c in (data['comentarios'] as List? ?? const []))
        if (c is Map && opt(c['texto']) != null)
          ReviewerComment(
            text: opt(c['texto'])!,
            path: opt(c['arquivo']),
            line: (c['linha'] as num?)?.toInt(),
            severity: opt(c['severidade']),
            requirement: opt(c['requisito']),
          ),
    ];
    return ReviewerVerdict(
      // "corrigir" without anything to fix is an approval.
      approve: data['veredito'] != 'corrigir' || comments.isEmpty,
      summary: opt(data['resumo']) ?? '',
      comments: comments,
      met: {
        for (final c in (data['criterios'] as List? ?? const []))
          if (c is Map && c['atendido'] == true && c['indice'] is num)
            (c['indice'] as num).toInt() - 1,
      },
    );
  }
}

/// Text of the `REVn` step: what the session must fix.
String reviewStepBody(int round, List<ReviewerComment> comments) {
  final b = StringBuffer(
    'Corrigir os apontamentos do revisor automático (rodada $round):',
  );
  for (final c in comments) {
    final req = c.requirement == null ? '' : ' [${c.requirement}]';
    b.write('\n  - ${c.location}$req — ${c.text}');
  }
  return b.toString();
}

/// Prompt of a review round.
String reviewerPrompt({
  required Spec spec,
  required String specText,
  required String diff,
  required int round,
  List<String> gates = const [],
  List<ReviewCommentRow> previous = const [],
  String? memory,
  List<String> criteria = const [],
}) {
  final b = StringBuffer()
    ..writeln(
      'Revise a implementação da spec ${spec.code} — ${spec.title} '
      '(rodada $round).',
    )
    ..writeln()
    ..writeln('<spec>')
    ..writeln(specText.trimRight())
    ..writeln('</spec>');
  if (memory != null && memory.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('Memória do projeto:')
      ..writeln(memory.trim());
  }
  if (criteria.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        'Critérios de aceite (responda em "criterios" quais estão atendidos, '
        'pelo número):',
      );
    for (final (i, c) in criteria.indexed) {
      b.writeln('${i + 1}. $c');
    }
  }
  if (gates.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Última verificação de cada etapa (testes / lint / commit):');
    for (final g in gates) {
      b.writeln('- $g');
    }
  }
  if (previous.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        'Apontamentos das rodadas anteriores (confira se foram resolvidos):',
      );
    for (final c in previous) {
      b.writeln('- rodada ${c.round}: ${c.path ?? 'spec'} — ${c.body}');
    }
  }
  // Also for a project's own reviewer agent, which skips the built-in
  // system prompt: the Review anchors each comment on this line.
  b
    ..writeln()
    ..writeln(
      'Em cada comentário, informe o arquivo e a linha do arquivo novo, como '
      'numerada no diff (linha 0 = o arquivo todo; sem arquivo = comentário '
      'geral).',
    )
    ..writeln()
    ..writeln('Diff da branch contra a base:')
    ..writeln('```diff')
    ..writeln(diff.trimRight())
    ..writeln('```');
  return b.toString().trimRight();
}

/// Prompt of "Rodar revisor" on a PR brought into the app (SPEC-050 R6):
/// the PR's title and description stand in for the spec.
String prReviewerPrompt({
  required String title,
  required String body,
  required String diff,
  required int round,
  List<ReviewCommentRow> previous = const [],
  String? memory,
}) {
  final b = StringBuffer()
    ..writeln(
      'Revise o pull request "$title" (rodada $round). Ele não tem spec.',
    )
    ..writeln()
    ..writeln('<descricao-do-pr>')
    ..writeln(body.trim().isEmpty ? '(sem descrição)' : body.trimRight())
    ..writeln('</descricao-do-pr>');
  if (memory != null && memory.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('Memória do projeto:')
      ..writeln(memory.trim());
  }
  if (previous.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Apontamentos anteriores (confira se foram resolvidos):');
    for (final c in previous) {
      b.writeln('- rodada ${c.round}: ${c.path ?? 'geral'} — ${c.body}');
    }
  }
  b
    ..writeln()
    ..writeln(
      'Não há critérios de aceite: deixe "criterios" vazio. Em cada '
      'comentário, informe o arquivo e a linha do arquivo novo, como numerada '
      'no diff (linha 0 = o arquivo todo; sem arquivo = comentário geral).',
    )
    ..writeln()
    ..writeln('Diff da branch contra a base:')
    ..writeln('```diff')
    ..writeln(diff.trimRight())
    ..writeln('```');
  return b.toString().trimRight();
}

/// Automatic review of a finished spec (F5): a read-only run with a
/// structured verdict. "corrigir" with rounds left → a `REVn` step with the
/// comments runs like any step (gate included) and the reviewer runs again;
/// "aprovar" or no rounds left → the user's Review.
class AutoReviewer {
  AutoReviewer(this._ref);

  /// Start of the comment left when a round fails (the user's turn).
  static const failurePrefix = 'O revisor automático falhou';

  final Ref _ref;

  static const maxDiff = 80000;
  static const timeout = Duration(minutes: 10);

  /// Specs being reviewed now.
  final Set<int> _running = {};

  bool isRunning(int specId) => _running.contains(specId);

  /// [providerOnce]: "Revisar com o … desta vez" after a failure (R2): this
  /// round only, the config never changes.
  Future<void> review(int specId, {String? providerOnce}) async {
    if (!_running.add(specId)) return;
    try {
      await _review(specId, providerOnce: providerOnce);
    } on ReviewerRunFailure catch (e) {
      debugPrint('revisor automático de $specId: $e');
      await _handOver(specId, failure: e.message, provider: e.provider);
    } catch (e) {
      debugPrint('revisor automático de $specId: $e');
      await _handOver(specId, failure: '$e');
    } finally {
      _running.remove(specId);
    }
  }

  /// The project's `spec-reviewer` translated for the Codex (SPEC-106
  /// R10), read-only like every reviewer round. Null = unreadable file.
  CodexAgentPlan? _reviewerPlan(
    String root,
    Map<String, String> settings,
    String? model,
  ) {
    try {
      final file = AgentFile.parse(
        File('$root/.claude/agents/$reviewerAgentName.md').readAsStringSync(),
      );
      return codexAgentPlanFrom(
        settings,
        file,
        name: reviewerAgentName,
        access: AgentAccess.ask,
        runModel: model ?? 'inherit',
      );
    } catch (e) {
      debugPrint('revisor: $reviewerAgentName não traduzido — $e');
      return null;
    }
  }

  Future<void> _review(int specId, {String? providerOnce}) async {
    final specs = _ref.read(specsRepoProvider);
    final spec = await specs.getById(specId);
    if (spec == null || spec.worktreePath == null) return;
    final ws = await _ref
        .read(workspacesRepoProvider)
        .getById(spec.workspaceId);
    if (ws == null) return;
    final config = ProjectConfig.loadSync(ws.path);
    final text = await _ref.read(specServiceProvider).read(ws, spec) ?? '';
    final round = spec.reviewRounds + 1;
    final git = _ref.read(gitServiceFactoryProvider)(spec.worktreePath!);
    final full = await _fullDiff(git, await _base(ws, spec));
    final rows = await _ref.read(specStepsRepoProvider).bySpec(specId);
    final previous = await _ref.read(reviewCommentsRepoProvider).bySpec(specId);
    final sessions = await _ref.read(sessionsRepoProvider).bySpec(specId);
    final criteria = parseCriteria(text);
    final ownAgent = File('${ws.path}/.claude/agents/spec-reviewer.md')
        .existsSync();
    // SPEC-102 R2, R3: who reviews. In Automático (SPEC-035 R8: the steps
    // have a plan) the rule Revisão holds, unless `provedor:` is explicit.
    final choice = resolveReviewerChoice(
      config.reviewer,
      executedBy: executionProviderOf(sessions.map((s) => s.provider)),
      auto: runsInAuto(rows),
    );
    final provider = providerOnce ?? choice.provider;
    final claude = isClaudeCode(provider);
    final rule = choice.fromPlan && claude
        ? reviewRuleOf(
            _ref.read(appSettingsProvider),
            specId,
            _ref.read(orchestratorPrefsProvider),
          )
        : null;
    // R7: the project's own agent goes as `--agent` on the Claude Code;
    // on the Codex it is translated (SPEC-106 R10): its body before the
    // built-in instructions, its model and effort through the table.
    final agent = ownAgent && claude;
    final settings = _ref.read(appSettingsProvider);
    final codexModel = claude
        ? null
        : reviewerCodexModel(config.reviewer, settings);
    final reviewerPlan =
        ownAgent && provider == ProviderCapabilities.codex.providerId
        ? _reviewerPlan(ws.path, settings, codexModel)
        : null;
    final StructuredResult r;
    try {
      r = await runStructured(
        _ref,
        StructuredIntent(
          flow: AppFlow.autoReview,
          workspaceId: ws.id,
          cwd: spec.worktreePath!,
          // R6: on the Codex the limit is the time (turn/interrupt).
          timeout: timeout,
          // SPEC-081 R2: the reviewer of the spec, by round.
          specId: specId,
          usageSource: UsageSource.revisor,
          usageStep: 'rodada $round',
          // R2: the resolved provider, never switched silently.
          providerId: provider,
          claude: ClaudeStructuredExtras(
            model: rule?.model ?? config.reviewer.model,
            effort: rule?.effort,
            agent: agent ? reviewerAgentName : null,
            maxBudgetUsd: config.reviewer.budgetUsd > 0
                ? config.reviewer.budgetUsd
                : null,
          ),
          // R4: `modelo-codex` / `codex.model.reviewer`; never a Claude alias.
          modelOverride: reviewerPlan == null
              ? codexModel
              : reviewerPlan.model == 'inherit'
              ? codexModel
              : reviewerPlan.model,
          effortOverride: reviewerPlan == null
              ? null
              : reviewerPlan.effort ?? 'default',
          instructions: agent
              ? null
              : codexAgentInstructions(
                  reviewerPlan?.instructions,
                  builtinReviewerPrompt,
                ),
          schema: reviewerSchema,
          prompt: reviewerPrompt(
            spec: spec,
            specText: text,
            diff: _cut(full),
            round: round,
            gates: [
              for (final row in rows)
                if (GateReport.decode(row.gateReport) case final g?)
                  '${row.step}: ${g.ok ? 'aprovada' : 'falhou (${g.summary})'}',
            ],
            previous: previous,
            memory: ProjectMemory.loadSync(ws.path).toPrompt(),
            criteria: [for (final c in criteria) c.text],
          ),
        ),
      );
    } catch (e) {
      throw ReviewerRunFailure(provider, '$e');
    }
    final parsed = ReviewerVerdict.parse(r.data);
    if (parsed == null) {
      throw ReviewerRunFailure(
        provider,
        '${const PlannerException('O revisor não devolveu um veredito.')}',
      );
    }
    // R8: the same findings, whoever reviewed.
    final verdict = parsed.normalized(
      diff: full,
      worktree: spec.worktreePath!,
      requirements: {for (final q in spec.requirements) q.id},
    );
    for (final i in verdict.met) {
      if (i < 0 || i >= criteria.length) continue;
      await _ref
          .read(reviewCommentsRepoProvider)
          .setCriterion(specId, criteria[i].text, checked: true, by: 'revisor');
    }
    final head = await git.headSha();
    await _ref.read(reviewCommentsRepoProvider).insertAll([
      ReviewCommentsCompanion.insert(
        specId: Value(specId),
        round: round,
        author: 'revisor',
        body: verdict.summary.isEmpty
            ? (verdict.approve ? 'Aprovado.' : 'Correções pedidas.')
            : verdict.summary,
        verdict: Value(verdict.approve ? 'aprovar' : 'corrigir'),
        commitSha: Value(head),
        // R9, P3: who reviewed, on the verdict line.
        provider: Value(r.provider),
        model: Value(r.model),
      ),
      for (final c in verdict.comments)
        ReviewCommentsCompanion.insert(
          specId: Value(specId),
          round: round,
          author: 'revisor',
          path: Value(c.path),
          line: Value(c.line),
          body: c.text,
          severity: Value(c.severity),
          requirement: Value(c.requirement),
          commitSha: Value(head),
        ),
    ]);
    if (verdict.approve || spec.reviewRounds >= config.reviewer.rounds) {
      await _handOver(specId);
      return;
    }
    // Corrections: a REVn step, run like any other — on the provider that
    // executed the spec, not the reviewer's (R11).
    final step = 'REV$round';
    await _ref
        .read(specStepsRepoProvider)
        .addExtra(specId, step, reviewStepBody(round, verdict.comments));
    await specs.setReview(specId, phase: ReviewPhase.auto, rounds: round);
    await specs.setStage(specId, SpecStage.running);
    final last = sessions.lastOrNull;
    await _ref
        .read(specRunnerProvider)
        .runNext(
          specId,
          mode: ClaudePermissionMode.fromCli(last?.permissionMode),
          provider: choice.executedBy,
          model: last?.model,
          effort: last?.effort,
          ignoreBlockers: true,
        );
  }

  /// The user's turn: phase `human` (a failure is kept as a comment).
  Future<void> _handOver(
    int specId, {
    String? failure,
    String? provider,
  }) async {
    final specs = _ref.read(specsRepoProvider);
    final spec = await specs.getById(specId);
    if (spec == null) return;
    if (failure != null) {
      await _ref.read(reviewCommentsRepoProvider).insertAll([
        ReviewCommentsCompanion.insert(
          specId: Value(specId),
          round: spec.reviewRounds + 1,
          author: 'revisor',
          body: '${AutoReviewer.failurePrefix}: $failure',
          // R2: the provider that failed; the Review offers the other one
          // "desta vez".
          provider: Value(provider),
        ),
      ]);
    }
    await specs.setReview(specId, phase: ReviewPhase.human);
    if (spec.stage != SpecStage.review) {
      await specs.setStage(specId, SpecStage.review);
    }
    unawaited(
      _ref
          .read(appNotifierProvider)
          .show('Pronta para review', '${spec.code} · ${spec.title}'),
    );
    unawaited(
      _ref
          .read(notificationsRepoProvider)
          .add(
            title: 'Pronta para review',
            body: '${spec.code} · ${spec.title}',
            section: 'review',
          )
          .catchError((_) {}),
    );
  }

  /// Sessions of PRs without spec being reviewed now.
  final Set<String> _runningSessions = {};

  bool isRunningSession(String sessionId) =>
      _runningSessions.contains(sessionId);

  /// "Rodar revisor" on a PR brought into the app (SPEC-050 R6): off by
  /// default, run only on demand. The verdict and the comments go to the
  /// session's history (no spec, no criteria, no `REVn` step); a failure
  /// becomes a comment too. `execucao` / `outro` resolve from the PR's
  /// session provider (SPEC-102 R2).
  Future<void> reviewSession(
    String sessionId, {
    required String title,
    String body = '',
    String? providerOnce,
  }) async {
    if (!_runningSessions.add(sessionId)) return;
    final repo = _ref.read(reviewCommentsRepoProvider);
    final previous = await repo.bySession(sessionId);
    final round = previous.isEmpty
        ? 1
        : previous.map((c) => c.round).reduce((a, b) => a > b ? a : b) + 1;
    String? provider;
    try {
      final s = await _ref.read(sessionsRepoProvider).getById(sessionId);
      if (s == null) return;
      final ws = await _ref.read(workspacesRepoProvider).getById(s.workspaceId);
      if (ws == null) return;
      final config = ProjectConfig.loadSync(ws.path);
      final git = _ref.read(gitServiceFactoryProvider)(s.worktreePath);
      final full = await _fullDiff(git, s.baseBranch ?? 'main');
      provider =
          providerOnce ??
          resolveReviewerChoice(
            config.reviewer,
            executedBy: s.provider,
          ).provider;
      final claude = isClaudeCode(provider);
      final r = await runStructured(
        _ref,
        StructuredIntent(
          flow: AppFlow.autoReview,
          workspaceId: ws.id,
          cwd: s.worktreePath,
          timeout: timeout,
          specId: s.specId,
          usageSource: UsageSource.revisor,
          usageStep: 'rodada $round',
          providerId: provider,
          instructions: builtinReviewerPrompt,
          schema: reviewerSchema,
          claude: ClaudeStructuredExtras(
            model: config.reviewer.model,
            maxBudgetUsd: config.reviewer.budgetUsd > 0
                ? config.reviewer.budgetUsd
                : null,
          ),
          modelOverride: claude
              ? null
              : reviewerCodexModel(
                  config.reviewer,
                  _ref.read(appSettingsProvider),
                ),
          prompt: prReviewerPrompt(
            title: title,
            body: body,
            diff: _cut(full),
            round: round,
            previous: [
              for (final c in previous)
                if (c.author == 'revisor') c,
            ],
            memory: ProjectMemory.loadSync(ws.path).toPrompt(),
          ),
        ),
      );
      final parsed = ReviewerVerdict.parse(r.data);
      if (parsed == null) {
        throw const PlannerException('O revisor não devolveu um veredito.');
      }
      final verdict = parsed.normalized(
        diff: full,
        worktree: s.worktreePath,
        requirements: const {},
      );
      final head = await git.headSha();
      await repo.insertAll([
        ReviewCommentsCompanion.insert(
          sessionId: Value(sessionId),
          round: round,
          author: 'revisor',
          body: verdict.summary.isEmpty
              ? (verdict.approve ? 'Aprovado.' : 'Correções pedidas.')
              : verdict.summary,
          verdict: Value(verdict.approve ? 'aprovar' : 'corrigir'),
          commitSha: Value(head),
          provider: Value(r.provider),
          model: Value(r.model),
        ),
        for (final c in verdict.comments)
          ReviewCommentsCompanion.insert(
            sessionId: Value(sessionId),
            round: round,
            author: 'revisor',
            path: Value(c.path),
            line: Value(c.line),
            body: c.text,
            severity: Value(c.severity),
            commitSha: Value(head),
          ),
      ]);
    } catch (e) {
      debugPrint('revisor do PR da sessão $sessionId: $e');
      await repo.insertAll([
        ReviewCommentsCompanion.insert(
          sessionId: Value(sessionId),
          round: round,
          author: 'revisor',
          body: '${AutoReviewer.failurePrefix}: $e',
          provider: Value(provider),
        ),
      ]);
    } finally {
      _runningSessions.remove(sessionId);
    }
  }

  /// "Pular revisor" (Review screen) / interrupted run: straight to the user.
  Future<void> skip(int specId) => _handOver(specId);

  /// The base of the spec's branch.
  Future<String> _base(Workspace ws, Spec spec) async =>
      spec.baseBranch ??
      await _ref.read(gitServiceFactoryProvider)(ws.path).currentBranch() ??
      'main';

  /// `git diff <merge-base with base>` of a worktree, whole: the findings
  /// are normalized against it (R8); the prompt gets it cut ([_cut]).
  Future<String> _fullDiff(GitService git, String base) async {
    try {
      final mb = (await git.git(['merge-base', base, 'HEAD'])).trim();
      return await git.git([
        'diff',
        '--no-color',
        '--no-ext-diff',
        '--unified=3',
        mb,
      ]);
    } on GitException catch (e) {
      return '(diff indisponível: $e)';
    }
  }

  /// The diff of the prompt, cut at [maxDiff].
  static String _cut(String d) => d.length <= maxDiff
      ? d
      : '${d.substring(0, maxDiff)}\n…(diff cortado em $maxDiff caracteres)';
}

/// A round that did not finish (R2): the provider that ran it, for the
/// failure line and "Revisar com o … desta vez".
class ReviewerRunFailure implements Exception {
  const ReviewerRunFailure(this.provider, this.message);

  final String provider;
  final String message;

  @override
  String toString() => message;
}

final autoReviewerProvider = Provider(AutoReviewer.new);

/// Whether the automatic reviewer should take [spec] (all steps done).
bool reviewerApplies(ProjectConfig config) => config.reviewer.enabled;

/// Steps that make [spec] wait for corrections of the reviewer.
List<StepView> reviewSteps(List<StepView> steps) => [
  for (final s in steps)
    if (isReviewStep(s.id)) s,
];

/// Card / Review label of the reviewer's state.
String? reviewerLabel(Spec spec, {required bool running}) {
  if (spec.reviewPhase != ReviewPhase.auto) return null;
  if (spec.stage == SpecStage.review) {
    return running ? 'revisor automático revisando…' : 'aguardando o revisor';
  }
  return 'corrigindo apontamentos do revisor (rodada ${spec.reviewRounds})';
}

/// Session that is a correction round (title / filter).
bool isReviewSession(Session s) => parseSessionSteps(s.steps).any(isReviewStep);
