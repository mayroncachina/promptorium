import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/claude_event.dart';
import '../../core/claude/run_prefs.dart';
import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../sessions/session_manager.dart';
import '../sessions/widgets/composer.dart' show lastPermissionModeKey;
import '../specs/spec_service.dart';
import 'board_rules.dart';

class SpecRunException implements Exception {
  const SpecRunException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Line the agent writes when it finishes the steps it was given.
const stepMarker = 'ETAPA CONCLUÍDA';

/// Steps listed in the **last** `ETAPA CONCLUÍDA: R1, R2` line of [text]
/// (accents and case tolerated; "R1 e R2" too). Empty = no marker.
Set<String> parseStepMarker(String? text) {
  if (text == null) return const {};
  final re = RegExp(
    r'ETAPAS?\s+CONCLU[IÍ]DAS?\s*:\s*([^\n]+)',
    caseSensitive: false,
  );
  final m = re.allMatches(text).lastOrNull;
  if (m == null) return const {};
  return {
    for (final r in RegExp(
      r'\bR\d+\b',
      caseSensitive: false,
    ).allMatches(m.group(1)!))
      r.group(0)!.toUpperCase(),
  };
}

/// `R1,R2` stored in `sessions.steps` → list.
List<String> parseSessionSteps(String? steps) => [
  for (final s in (steps ?? '').split(','))
    if (s.trim().isNotEmpty) s.trim(),
];

/// First message of a step session: the spec itself (the file may not be
/// committed, so it is not read from the worktree), what is done, what to do
/// now and how to finish.
String specStepPrompt({
  required Spec spec,
  required String specText,
  required List<StepView> steps,
  required List<String> todo,
}) {
  String line(StepView s) => '${s.id} · ${s.text}';
  final now = [
    for (final s in steps)
      if (todo.contains(s.id)) s,
  ];
  final done = [
    for (final s in steps)
      if (s.isDone) s,
  ];
  final later = [
    for (final s in steps)
      if (!s.isDone && !todo.contains(s.id)) s.id,
  ];
  final ids = todo.join(', ');
  final b = StringBuffer()
    ..writeln(
      todo.length == 1
          ? 'Implemente a etapa ${todo.single} da spec ${spec.code} — '
                '${spec.title}.'
          : 'Implemente as etapas $ids da spec ${spec.code} — ${spec.title}.',
    )
    ..writeln()
    ..writeln(todo.length == 1 ? 'Etapa de agora:' : 'Etapas de agora:');
  for (final s in now) {
    b.writeln('- ${line(s)}');
  }
  b.writeln();
  if (done.isEmpty) {
    b.writeln('Nenhuma etapa desta spec foi concluída ainda.');
  } else {
    b.writeln('Já concluídas (commits nesta branch):');
    for (final s in done) {
      b.writeln('- ${line(s)}');
    }
  }
  if (later.isNotEmpty) {
    b.writeln(
      'Ficam para as próximas sessões (não implemente agora): '
      '${later.join(', ')}.',
    );
  }
  b
    ..writeln()
    ..writeln('Spec (${spec.path}):')
    ..writeln('<spec>')
    ..writeln(specText.trimRight())
    ..writeln('</spec>')
    ..writeln()
    ..writeln('Ao terminar:')
    ..writeln('1. rode os testes do projeto;')
    ..writeln(
      '2. faça commit com a mensagem "${spec.code} $ids: <resumo do que '
      'mudou>";',
    )
    ..writeln('3. termine a resposta com a linha exata: $stepMarker: $ids')
    ..writeln()
    ..writeln(
      'Se faltar informação ou algo impedir a etapa, explique e pergunte, '
      'sem escrever essa linha.',
    );
  return b.toString().trimRight();
}

/// `SPEC-003 · R2 · Extrair PKs…` / `SPEC-003 · R1–R3 · Extração do schema`.
String specSessionTitle(Spec spec, List<StepView> steps, List<String> todo) {
  if (todo.length == 1) {
    final s = steps.where((s) => s.id == todo.single).firstOrNull;
    return '${spec.code} · ${todo.single} · ${s?.text ?? spec.title}';
  }
  return '${spec.code} · ${todo.first}–${todo.last} · ${spec.title}';
}

/// Runs a spec step by step: one session per step (or one for a small spec)
/// in the spec's own worktree, and moves the card / steps from the sessions'
/// events (called by `SessionManager`).
class SpecRunner {
  SpecRunner(this._ref);

  final Ref _ref;

  SessionManager get _manager => _ref.read(sessionManagerProvider.notifier);

  /// Opens the session of the next steps of [specId] and returns its id.
  /// [mode] / [model] / [effort] null = those of the spec's last session,
  /// else the defaults. [agent] is stored on the spec.
  Future<String> runNext(
    int specId, {
    ClaudePermissionMode? mode,
    String? model,
    String? effort,
    String? agent,
    bool ignoreBlockers = false,
  }) async {
    final specs = _ref.read(specsRepoProvider);
    var spec = await specs.getById(specId);
    if (spec == null) throw const SpecRunException('Spec não encontrada.');
    final ws = await _ref
        .read(workspacesRepoProvider)
        .getById(spec.workspaceId);
    if (ws == null) throw const SpecRunException('Workspace não encontrado.');
    final service = _ref.read(specServiceProvider);
    await service.sync(ws);
    spec = (await specs.getById(specId))!;
    final text = await service.read(ws, spec);
    if (text == null) {
      throw SpecRunException('O arquivo ${spec.path} não existe.');
    }

    if (!ignoreBlockers) {
      final all = await specs.watchByWorkspace(ws.id).first;
      final blockers = specBlockers(spec, specsByCode(all));
      if (blockers.isNotEmpty) {
        throw SpecRunException(
          '${spec.code} depende de ${blockers.join(', ')}, que ainda não '
          'estão em Feito.',
        );
      }
    }
    final sessions = await _ref.read(sessionsRepoProvider).bySpec(specId);
    final live = sessions.where(
      (s) =>
          _manager.isAlive(s.id) &&
          (s.status == SessionStatus.running ||
              s.status == SessionStatus.waitingApproval),
    );
    if (live.isNotEmpty) {
      throw SpecRunException(
        '${spec.code} já tem uma sessão rodando (${live.first.title}).',
      );
    }

    final rows = await _ref.read(specStepsRepoProvider).bySpec(specId);
    final steps = stepsOf(spec, rows);
    if (steps.isEmpty) {
      throw SpecRunException(
        '${spec.code} não tem requisitos (linhas "- R1 · …") para executar.',
      );
    }
    final prefs = _ref.read(runPrefsProvider);
    final todo = nextSteps(
      steps,
      singleSessionMax: prefs.singleSessionMaxSteps,
    );
    if (todo.isEmpty) {
      throw SpecRunException(
        'Todas as etapas de ${spec.code} já estão feitas.',
      );
    }

    if (agent != null) {
      await specs.setAgent(specId, agent);
      spec = (await specs.getById(specId))!;
    }
    final wt = await _worktree(ws, spec);
    final last = sessions.isEmpty ? null : sessions.last;
    final settings = _ref.read(appSettingsProvider.notifier);
    final id = await _manager.create(
      NewSessionRequest(
        workspace: ws,
        title: specSessionTitle(spec, steps, todo),
        prompt: specStepPrompt(
          spec: spec,
          specText: text,
          steps: steps,
          todo: todo,
        ),
        agent: spec.agentName,
        model: model ?? last?.model ?? prefs.model(RunKind.session),
        effort: effort ?? last?.effort,
        permissionMode:
            mode ??
            ClaudePermissionMode.fromCli(last?.permissionMode) ??
            ClaudePermissionMode.fromCli(settings.get(lastPermissionModeKey)) ??
            ClaudePermissionMode.defaultMode,
        specId: specId,
        steps: todo.join(','),
        worktreePath: wt.path,
        branch: wt.branch,
        baseBranch: wt.base,
      ),
    );
    return id;
  }

  /// The spec's worktree: the stored one when it still exists, else a new
  /// `pr/spec-003-<slug>-<tail>` from the root's current branch.
  Future<({String path, String branch, String? base})> _worktree(
    Workspace ws,
    Spec spec,
  ) async {
    final git = _ref.read(gitServiceFactoryProvider)(ws.path);
    if (spec.worktreePath != null && spec.branch != null) {
      final known = await git.listWorktrees();
      if (known.any((w) => w.path == spec.worktreePath && !w.prunable) &&
          await Directory(spec.worktreePath!).exists()) {
        return (
          path: spec.worktreePath!,
          branch: spec.branch!,
          base: spec.baseBranch,
        );
      }
    }
    try {
      final base = await git.currentBranch();
      final id = _ref.read(sessionIdGeneratorProvider)();
      final created = await git.addWorktree(
        sessionSlug(
          '${spec.code.toLowerCase()} ${slugify(spec.title, maxLength: 24)}',
          id,
        ),
      );
      await _ref
          .read(specsRepoProvider)
          .setWorktree(
            spec.id,
            path: created.path,
            branch: created.branch,
            baseBranch: base,
          );
      return (path: created.path, branch: created.branch, base: base);
    } on GitException catch (e) {
      throw SpecRunException('Falha ao criar o worktree da spec: $e');
    }
  }

  // --- session events (SessionManager) ---------------------------------------

  Future<Session?> _specSession(String id) async {
    final s = await _ref.read(sessionsRepoProvider).getById(id);
    return s?.specId == null ? null : s;
  }

  /// Running / waiting approval: its steps run, the card is in execution.
  Future<void> onActive(String sessionId) => _guard(sessionId, () async {
    final s = await _specSession(sessionId);
    if (s == null) return;
    final steps = _ref.read(specStepsRepoProvider);
    final rows = {for (final r in await steps.bySpec(s.specId!)) r.step: r};
    for (final step in parseSessionSteps(s.steps)) {
      if (rows[step]?.status == StepStatus.done) continue;
      await steps.set(
        s.specId!,
        step,
        StepStatus.running,
        sessionId: sessionId,
      );
    }
    final spec = await _ref.read(specsRepoProvider).getById(s.specId!);
    if (spec != null && spec.stage != SpecStage.running) {
      await _ref.read(specsRepoProvider).setStage(spec.id, SpecStage.running);
    }
  });

  /// End of a turn: steps named in `ETAPA CONCLUÍDA` are done, the others of
  /// the session wait for the user. All steps done → Review; this session's
  /// steps done and auto-advance on → next session.
  Future<void> onResult(String sessionId, Result r) => _guard(
    sessionId,
    () async {
      final s = await _specSession(sessionId);
      if (s == null) return;
      final specId = s.specId!;
      final mine = parseSessionSteps(s.steps);
      final marked = r.isSuccess ? parseStepMarker(r.result) : const <String>{};
      final repo = _ref.read(specStepsRepoProvider);
      final rows = {for (final x in await repo.bySpec(specId)) x.step: x};
      for (final step in mine) {
        if (rows[step]?.status == StepStatus.done) continue;
        await repo.set(
          specId,
          step,
          marked.contains(step) ? StepStatus.done : StepStatus.needsInput,
          sessionId: sessionId,
        );
      }
      final spec = await _ref.read(specsRepoProvider).getById(specId);
      if (spec == null) return;
      final steps = stepsOf(spec, await repo.bySpec(specId));
      if (steps.isNotEmpty && steps.every((x) => x.isDone)) {
        await _ref.read(specsRepoProvider).setStage(specId, SpecStage.review);
        return;
      }
      final mineDone = mine.every(
        (step) => steps.any((x) => x.id == step && x.isDone),
      );
      if (mineDone && spec.autoAdvance) {
        // Outside the session's event queue: releasing its process waits
        // for that queue.
        unawaited(Future<void>.microtask(() => _advance(s)));
      }
    },
  );

  /// Stopped by the user: its running steps go back to pending. Failed:
  /// they wait for the user.
  Future<void> onEnded(String sessionId, SessionStatus status) =>
      _guard(sessionId, () async {
        final s = await _specSession(sessionId);
        if (s == null) return;
        final repo = _ref.read(specStepsRepoProvider);
        final rows = {for (final x in await repo.bySpec(s.specId!)) x.step: x};
        for (final step in parseSessionSteps(s.steps)) {
          if (rows[step]?.status != StepStatus.running) continue;
          await repo.set(
            s.specId!,
            step,
            status == SessionStatus.stopped
                ? StepStatus.pending
                : StepStatus.needsInput,
          );
        }
      });

  /// Next session of the spec, with the same mode / model / effort; the
  /// finished one's idle process is closed first.
  Future<void> _advance(Session done) async {
    try {
      await _manager.release(done.id);
      await runNext(
        done.specId!,
        mode: ClaudePermissionMode.fromCli(done.permissionMode),
        model: done.model,
        effort: done.effort,
      );
    } catch (e) {
      debugPrint('spec ${done.specId}: próxima etapa não iniciada — $e');
    }
  }

  Future<void> _guard(String id, Future<void> Function() job) async {
    try {
      await job();
    } catch (e) {
      debugPrint('sessão $id: spec não atualizada — $e');
    }
  }
}

final specRunnerProvider = Provider(SpecRunner.new);
