import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/structured_run.dart';
import '../../core/providers/workspace_assets.dart';
import '../../data/providers.dart';
import '../sessions/session_manager.dart' show sessionIdGeneratorProvider;
import 'interview_data.dart';

export 'interview_data.dart';

/// The interview of "Melhorar com IA" (SPEC-113 R13–R18): read-only rounds
/// of [runStructured] on the provider of "Planner e assistentes" (SPEC-100),
/// one thread per interview, kept in `instruction_interviews` so it survives
/// closing the app. It ends with a proposal of trechos (R19) that the app
/// applies (T6): the AI never writes a file.

// --- Schemas --------------------------------------------------------------------

const _str = {'type': 'string'};
const _strList = {'type': 'array', 'items': _str};

Map<String, Object?> _object(Map<String, Object?> props) => {
  'type': 'object',
  'additionalProperties': false,
  'required': props.keys.toList(),
  'properties': props,
};

/// The answer of each round (R13, R14, R16).
final interviewRoundSchema = _object({
  'findings': {
    'type': 'array',
    'items': _object({'text': _str, 'path': _str}),
  },
  'questions': {
    'type': 'array',
    'items': _object({
      'id': _str,
      'title': _str,
      'text': _str,
      'reason': _str,
      'options': _strList,
      'recommended': _str,
      'requires': _strList,
      'onlyClaude': {'type': 'boolean'},
      'target': _str,
    }),
  },
  'draft': _str,
  'summary': _str,
  'done': {'type': 'boolean'},
});

/// The proposal at the end (R19): trechos by file and section.
final interviewProposalSchema = _object({
  'summary': _str,
  'hunks': {
    'type': 'array',
    'items': _object({
      'file': _str,
      'section': _str,
      'oldText': _str,
      'newText': _str,
      'questions': _strList,
    }),
  },
});

/// The app's own instructions (grill-me style, in rounds): the same on both
/// providers, never the person's `grill-me` skill (Fora do escopo).
const interviewSystemPrompt =
    'Você conduz a entrevista "Melhorar com IA" do Promptorium, que melhora '
    'as instruções dos agentes deste repositório: o AGENTS.md (a fonte, lida '
    'pelo Claude Code e pelo Codex) e o CLAUDE.md (a linha @AGENTS.md e o que '
    'vale só para o Claude Code). Escreva em português do Brasil. Você está '
    'em SOMENTE LEITURA: leia o código e os arquivos, mas nunca crie, altere '
    'ou apague arquivos nem rode comandos que gravem; o app aplica as '
    'mudanças depois, com a aprovação da pessoa. Entreviste como um revisor '
    'exigente, em rodadas: em cada rodada faça TODAS as perguntas cujos '
    'pré-requisitos já estão respondidos, de uma vez, e nenhuma cujo '
    'pré-requisito ainda está aberto (ela vem numa rodada seguinte). Fato é '
    'seu, decisão é da pessoa: o que o código responde (comandos, pastas, '
    'ferramentas, convenções visíveis) não vira pergunta; vai em findings, '
    'com text curto e path, o caminho onde você leu. Pergunte só o que muda '
    'as instruções e só a pessoa pode decidir. Cada pergunta tem: id (Q1, '
    'Q2…, continuando a numeração indicada), title (até cinco palavras), '
    'text, reason (o que você viu no projeto que motiva a pergunta), até '
    'três options curtas, recommended (a resposta que você recomenda), '
    'requires (os ids das perguntas que precisam estar respondidas antes; '
    'lista vazia quando não há), onlyClaude (true quando a regra vale só '
    'para o Claude Code e vai para o CLAUDE.md) e target (arquivo › seção '
    'onde a resposta entra, como "AGENTS.md › Regras"). Em draft, devolva o '
    'rascunho COMPLETO do AGENTS.md com o que já foi entendido, em Markdown '
    'curto e direto. Uma pergunta pulada não vira regra. Quando não houver '
    'mais nada a perguntar, devolva questions vazia, done true e, em summary, '
    'o resumo do que foi entendido, em tópicos curtos; enquanto houver '
    'perguntas, done false e summary vazio.';

/// Limits of a round: it reads the project, so longer than a planner turn.
const interviewTimeout = Duration(minutes: 10);
const interviewBudgetUsd = 1.0;

/// Slot of the interview's provider line (SPEC-100 R10).
String interviewSlot(int workspaceId) => 'instructions-interview:$workspaceId';

final _questionId = RegExp(r'^Q\d+$');

/// The round the AI answered, numbered by the app: a missing or repeated id
/// gets the next free number, and a question whose prerequisite is still
/// open waits for a later round (R13).
InterviewRound parseInterviewRound(Object? out, InterviewData before) {
  if (out is! Map) {
    throw const PlannerException(
      'A entrevista não devolveu a saída estruturada.',
    );
  }
  final answers = before.answers;
  final known = {for (final q in before.questions) q.id};
  var next = before.nextNumber;
  final ids = <String, String>{};
  final used = {...known};
  final raw = [
    if (out['questions'] case final List l)
      for (final x in l) ?InterviewQuestion.fromJson(x),
  ];
  final numbered = <InterviewQuestion>[];
  for (final q in raw) {
    var id = q.id;
    if (!_questionId.hasMatch(id) || used.contains(id)) id = 'Q$next';
    final n = int.parse(id.substring(1));
    if (n >= next) next = n + 1;
    used.add(id);
    // A repeated id of an earlier round still names that question in the
    // prerequisites of this one.
    if (!known.contains(q.id)) ids[q.id] = id;
    numbered.add(q.withId(id, q.requires));
  }
  final questions = <InterviewQuestion>[];
  for (final q in numbered) {
    final requires = [for (final r in q.requires) ids[r] ?? r];
    // R13: only questions whose prerequisites are answered (or skipped);
    // one that depends on a question of this round waits for the next.
    final ready = requires.every(
      (r) => !used.contains(r) || (answers[r]?.complete ?? false),
    );
    if (!ready) continue;
    questions.add(
      q.withId(q.id, [
        for (final r in requires)
          if (known.contains(r)) r,
      ]),
    );
  }
  return InterviewRound(
    number: before.rounds.length + 1,
    findings: [
      if (out['findings'] case final List l)
        for (final x in l) ?InterviewFinding.fromJson(x),
    ],
    questions: questions,
    draft: '${out['draft'] ?? ''}'.trim(),
  );
}

/// The trechos of the proposal (R19): only the two root files.
InstructionProposal parseInterviewProposal(
  Object? out, {
  required InterviewData data,
  required String provider,
  String? model,
}) {
  if (out is! Map) {
    throw const PlannerException('A proposta não veio na saída estruturada.');
  }
  return InstructionProposal(
    hunks: [
      if (out['hunks'] case final List l)
        for (final x in l)
          if (InstructionProposalHunk.fromJson(x) case final h?
              when h.file == agentsMdName || h.file == claudeMdName)
            h,
    ],
    provider: provider,
    model: model,
    summary: '${out['summary'] ?? ''}'.trim(),
    endedEarly: data.endedEarly,
    questions: {for (final q in data.questions) q.id: q.title},
  );
}

/// The Q&A lines of [round] the AI reads.
String _answersOf(InterviewRound round) {
  final b = StringBuffer();
  for (final q in round.questions) {
    final a = round.answers[q.id];
    b.writeln(
      '- ${q.id} · ${q.text}: '
      '${a == null || !a.complete ? 'sem resposta (não vira regra)' : a.spoken}',
    );
  }
  return b.toString().trimRight();
}

/// What a new thread needs to continue (R18): every round asked and
/// answered, and the draft.
String interviewHistory(InterviewData data) {
  final b = StringBuffer()
    ..writeln(
      'Esta entrevista começou em outra conversa, que não existe mais. O que '
      'já foi perguntado e respondido:',
    );
  for (final r in data.rounds) {
    if (r.questions.isEmpty) continue;
    b
      ..writeln()
      ..writeln('Rodada ${r.number}:')
      ..writeln(_answersOf(r));
  }
  final findings = data.findings;
  if (findings.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Achados no código:');
    for (final f in findings) {
      b.writeln('- ${f.text} ${f.path}'.trimRight());
    }
  }
  if (data.draft.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Rascunho até agora:')
      ..writeln(data.draft);
  }
  return b.toString().trimRight();
}

/// The message of a round.
String interviewRoundPrompt(
  InterviewData data, {
  required bool filesChanged,
  bool hasAgents = true,
  bool hasClaude = true,
}) {
  final b = StringBuffer();
  final last = data.current;
  if (last == null) {
    b.writeln(
      'Comece a entrevista. Leia o AGENTS.md e o CLAUDE.md da raiz e o código '
      'que ajudar.',
    );
    if (!hasAgents) b.writeln('Este projeto ainda não tem AGENTS.md.');
    if (!hasClaude) b.writeln('Este projeto ainda não tem CLAUDE.md.');
  } else {
    b
      ..writeln('Respostas da rodada ${last.number}:')
      ..writeln(_answersOf(last));
  }
  if (filesChanged) {
    b
      ..writeln()
      ..writeln(
        'Os arquivos de instruções mudaram desde a última leitura: releia o '
        'AGENTS.md e o CLAUDE.md da raiz antes de continuar. As respostas já '
        'dadas continuam valendo.',
      );
  }
  b
    ..writeln()
    ..writeln('A próxima pergunta nova é Q${data.nextNumber}.');
  return b.toString().trimRight();
}

/// The message that asks for the proposal (R16, R19), with the current
/// text of both files: `oldText` must be an exact excerpt of them.
String interviewProposalPrompt(
  InterviewData data, {
  String? agents,
  String? claude,
}) {
  final b = StringBuffer();
  final pending = data.current;
  if (pending != null && !pending.sent && pending.questions.isNotEmpty) {
    b
      ..writeln('Respostas da rodada ${pending.number}:')
      ..writeln(_answersOf(pending))
      ..writeln();
  }
  if (data.endedEarly) {
    final open = [
      for (final q in data.questions)
        if (!(data.answers[q.id]?.complete ?? false)) q.id,
    ];
    b.writeln(
      'A pessoa encerrou a entrevista antes do fim. '
      '${open.isEmpty ? '' : 'As perguntas ${open.join(', ')} ficaram abertas e não viram regra. '}'
      'Use só o que foi respondido.',
    );
  } else {
    b.writeln('A pessoa confirmou o resumo. A entrevista terminou.');
  }
  b
    ..writeln()
    ..writeln(
      'Proponha as mudanças como trechos, sem gravar nada: o app mostra cada '
      'trecho e aplica só os aceitos. Para cada trecho: file ("AGENTS.md" ou '
      '"CLAUDE.md"), section (a seção onde ele fica), oldText (o trecho EXATO '
      'do arquivo atual que ele substitui, copiado caractere por caractere; '
      'vazio para um texto novo no fim da seção), newText (o texto novo) e '
      'questions (os ids das perguntas de origem). Trechos pequenos, um por '
      'mudança. O que vale para os dois provedores vai no AGENTS.md; o que '
      'vale só para o Claude Code vai no CLAUDE.md. Nunca tire a linha '
      '@AGENTS.md do CLAUDE.md. Em summary, uma frase do que muda.',
    )
    ..writeln()
    ..writeln(
      agents == null
          ? 'AGENTS.md: não existe (proponha o arquivo inteiro com oldText '
                'vazio).'
          : 'AGENTS.md atual:\n<<<\n$agents\n>>>',
    )
    ..writeln()
    ..writeln(
      claude == null
          ? 'CLAUDE.md: não existe.'
          : 'CLAUDE.md atual:\n<<<\n$claude\n>>>',
    );
  return b.toString().trimRight();
}

/// The text of the root instruction files and their hash (R18).
typedef InterviewFiles = ({String hash, String? agents, String? claude});

Future<InterviewFiles> readInterviewFiles(String root) async {
  final inv = await scanInstructions(root, depth: 0);
  final key =
      '$agentsMdName\u0000${inv.agentsText ?? ''}\u0000'
      '$claudeMdName\u0000${inv.claudeText ?? ''}';
  return (
    hash: claudeMdHash(key),
    agents: inv.agentsText,
    claude: inv.claudeText,
  );
}

/// A resumed round whose thread is gone (R18): the start failed (Codex
/// `thread/resume`), or the CLI ended without an answer (Claude `--resume`
/// of a session that no longer exists).
bool interviewThreadGone(Object e) {
  if (e is StructuredCancelled) return false;
  if (e is StructuredProviderFailure) return true;
  final text = '$e'.toLowerCase();
  return text.contains('encerrou antes de responder') ||
      text.contains('no conversation found') ||
      text.contains('thread not found') ||
      text.contains('no rollout found');
}

// --- Estado ---------------------------------------------------------------------

/// The interview of one workspace as the screen sees it.
@immutable
class InterviewState {
  const InterviewState({
    this.loaded = false,
    this.exists = false,
    this.data = const InterviewData(),
    this.provider,
    this.model,
    this.tokens = 0,
    this.pausedAt,
    this.updatedAt,
    this.busy = false,
    this.error,
    this.filesChanged = false,
  });

  final bool loaded;

  /// There is an interview (open or paused) for the workspace.
  final bool exists;
  final InterviewData data;

  /// Fixed when it started (R17).
  final String? provider;
  final String? model;
  final int tokens;

  /// "Pausar" (R18); null = open.
  final DateTime? pausedAt;
  final DateTime? updatedAt;

  /// A round (or the proposal) is on the way.
  final bool busy;

  /// Why the last round did not come ("Tentar de novo").
  final String? error;

  /// The instruction files changed after the AI read them (R18): the next
  /// round reads them again.
  final bool filesChanged;

  bool get paused => pausedAt != null;

  InterviewState copyWith({
    bool? loaded,
    bool? exists,
    InterviewData? data,
    String? provider,
    String? model,
    int? tokens,
    DateTime? pausedAt,
    bool clearPaused = false,
    DateTime? updatedAt,
    bool? busy,
    String? error,
    bool clearError = false,
    bool? filesChanged,
  }) => InterviewState(
    loaded: loaded ?? this.loaded,
    exists: exists ?? this.exists,
    data: data ?? this.data,
    provider: provider ?? this.provider,
    model: model ?? this.model,
    tokens: tokens ?? this.tokens,
    pausedAt: clearPaused ? null : (pausedAt ?? this.pausedAt),
    updatedAt: updatedAt ?? this.updatedAt,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    filesChanged: filesChanged ?? this.filesChanged,
  );
}

/// Runs the interview of one workspace (the family argument is its id).
class InterviewController extends Notifier<InterviewState> {
  InterviewController(this.workspaceId);

  final int workspaceId;

  @override
  InterviewState build() => const InterviewState();

  /// Writes, one at a time: an answer typed while a round ends is not lost.
  Future<void> _writes = Future.value();
  Completer<void>? _cancel;

  void _set(InterviewState s) {
    if (ref.mounted) state = s;
  }

  Future<void> _save(InstructionInterviewsCompanion changes) {
    final repo = ref.read(instructionInterviewsRepoProvider);
    final write = _writes.then((_) => repo.update(workspaceId, changes));
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> _saveData(InterviewData data) {
    _set(state.copyWith(data: data));
    return _save(InstructionInterviewsCompanion(data: Value(data.encode())));
  }

  /// Reads the stored interview (R18) and whether the files changed since
  /// the AI read them.
  Future<void> load(Workspace ws) async {
    final row = await ref.read(instructionInterviewsRepoProvider).get(ws.id);
    if (row == null) {
      _set(const InterviewState(loaded: true));
      return;
    }
    var changed = false;
    if (row.filesHash case final h?) {
      changed = (await readInterviewFiles(ws.path)).hash != h;
    }
    _set(
      InterviewState(
        loaded: true,
        exists: true,
        data: InterviewData.decode(row.data),
        provider: row.provider,
        model: row.model,
        tokens: row.tokens,
        pausedAt: row.pausedAt,
        updatedAt: row.updatedAt,
        busy: state.busy,
        filesChanged: changed,
      ),
    );
  }

  /// "Melhorar com IA": a new interview on the provider of "Planner e
  /// assistentes", fixed until the end (R17). An old one is replaced.
  Future<void> start(Workspace ws) async {
    if (state.busy) return;
    final provider = providerForKind(
      ref.read(appSettingsProvider),
      ProviderKind.planner,
      workspaceId: ws.id,
      flows: ref.read(providerFlowsProvider),
    );
    final row = await ref
        .read(instructionInterviewsRepoProvider)
        .start(ws.id, provider: provider);
    _set(
      InterviewState(
        loaded: true,
        exists: true,
        provider: provider,
        updatedAt: row.updatedAt,
      ),
    );
    await _round(ws);
  }

  /// R15: an option, a text, the recommended answer or "Pular". Kept at
  /// once; nothing is sent.
  Future<void> answer(String questionId, InterviewAnswer? answer) async {
    final round = state.data.current;
    if (round == null || round.sent) return;
    if (!round.questions.any((q) => q.id == questionId)) return;
    final answers = {...round.answers};
    if (answer == null) {
      answers.remove(questionId);
    } else {
      answers[questionId] = answer;
    }
    await _saveData(state.data.withCurrent(round.copyWith(answers: answers)));
  }

  /// "Aceitar as recomendadas que faltam" (R15): fills the round, without
  /// sending.
  Future<void> acceptRemainingRecommended() async {
    final round = state.data.current;
    if (round == null || round.sent) return;
    final answers = {...round.answers};
    for (final q in round.questions) {
      if (answers[q.id]?.complete ?? false) continue;
      answers[q.id] = InterviewAnswer(
        InterviewAnswerKind.recommended,
        q.recommended,
      );
    }
    await _saveData(state.data.withCurrent(round.copyWith(answers: answers)));
  }

  /// "Enviar rodada": the answers open the next round (R13).
  Future<void> sendRound(Workspace ws) async {
    final round = state.data.current;
    if (state.busy || round == null || round.sent || !round.complete) return;
    await _saveData(state.data.withCurrent(round.copyWith(sent: true)));
    await _round(ws);
  }

  /// "Tentar de novo": the round, or the proposal, that did not come.
  Future<InstructionProposal?> retry(Workspace ws) async {
    if (state.busy) return null;
    final data = state.data;
    // The proposal failed (after the summary or "Encerrar"): ask again.
    if (data.endedEarly || data.stage != InterviewStage.asking) {
      return propose(ws);
    }
    if (data.needsRun) await _round(ws);
    return null;
  }

  /// "Pausar" (R18): everything is already stored; a round on the way is
  /// interrupted and runs again on "Continuar".
  Future<void> pause() async {
    final now = DateTime.now();
    _cancel?.complete();
    _cancel = null;
    _set(state.copyWith(pausedAt: now));
    await _save(InstructionInterviewsCompanion(pausedAt: Value(now)));
  }

  /// "Continuar" (R18): on the same provider and thread; the round that did
  /// not come runs now, reading the files again when they changed.
  Future<void> resume(Workspace ws) async {
    if (!state.loaded) await load(ws);
    if (!state.exists) return;
    _set(state.copyWith(clearPaused: true));
    await _save(const InstructionInterviewsCompanion(pausedAt: Value(null)));
    if (state.data.needsRun) await _round(ws);
  }

  /// "Descartar e começar outra": the interview goes; the files never
  /// changed.
  Future<void> discard() async {
    _cancel?.complete();
    _cancel = null;
    await _writes;
    await ref.read(instructionInterviewsRepoProvider).delete(workspaceId);
    _set(const InterviewState(loaded: true));
  }

  /// One round on the interview's thread (R13, R18).
  Future<void> _round(Workspace ws) async {
    _set(state.copyWith(busy: true, clearError: true));
    final cancel = _cancel = Completer<void>();
    try {
      final repo = ref.read(instructionInterviewsRepoProvider);
      await _writes;
      final row = await repo.get(ws.id);
      if (row == null) return;
      final files = await readInterviewFiles(ws.path);
      final changed = row.filesHash != null && row.filesHash != files.hash;
      final before = InterviewData.decode(row.data);
      final prompt = interviewRoundPrompt(
        before,
        filesChanged: changed,
        hasAgents: files.agents != null,
        hasClaude: files.claude != null,
      );
      final (r, thread) = await _run(
        ws,
        row,
        before,
        prompt: prompt,
        schema: interviewRoundSchema,
        cancel: cancel,
      );
      final out = r.data;
      final round = parseInterviewRound(out, before);
      final done =
          (out is Map && out['done'] == true) || round.questions.isEmpty;
      final summary = out is Map ? '${out['summary'] ?? ''}'.trim() : '';
      final data = before.copyWith(
        rounds: [...before.rounds, round],
        stage: done ? InterviewStage.summary : InterviewStage.asking,
        summary: done ? summary : '',
      );
      await _finishRun(ws, r, thread, data, files.hash);
    } on StructuredCancelled {
      // Paused: the round runs again on "Continuar".
    } catch (e) {
      debugPrint('Entrevista das instruções: $e');
      _set(state.copyWith(error: '$e'));
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      _set(state.copyWith(busy: false));
    }
  }

  Future<void> _finishRun(
    Workspace ws,
    StructuredResult r,
    String thread,
    InterviewData data,
    String hash,
  ) async {
    final tokens = state.tokens + r.usage.total;
    _set(
      state.copyWith(
        data: data,
        model: r.model,
        tokens: tokens,
        filesChanged: false,
        updatedAt: DateTime.now(),
      ),
    );
    await _save(
      InstructionInterviewsCompanion(
        data: Value(data.encode()),
        model: r.model == null ? const Value.absent() : Value(r.model),
        threadId: Value(thread),
        filesHash: Value(hash),
        tokens: Value(tokens),
      ),
    );
    await _writes;
  }

  /// Runs on the stored thread; when it is gone, starts another with the
  /// stored answers (R18). The provider stays the one it started on (R17).
  Future<(StructuredResult, String)> _run(
    Workspace ws,
    InstructionInterview row,
    InterviewData data, {
    required String prompt,
    required Map<String, Object?> schema,
    required Completer<void> cancel,
  }) async {
    StructuredIntent intent({
      String? sessionId,
      String? resumeId,
      required String prompt,
    }) => StructuredIntent(
      workspaceId: ws.id,
      cwd: ws.path,
      prompt: prompt,
      schema: schema,
      instructions: interviewSystemPrompt,
      sessionId: sessionId,
      resumeId: resumeId,
      providerId: row.provider,
      timeout: interviewTimeout,
      cancelled: cancel.future,
      claude: const ClaudeStructuredExtras(maxBudgetUsd: interviewBudgetUsd),
      slot: interviewSlot(ws.id),
      label: 'a entrevista das instruções',
      denyMessage: 'A entrevista das instruções é somente leitura.',
    );
    final thread = row.threadId;
    if (thread != null) {
      try {
        final r = await runStructured(
          ref,
          intent(resumeId: thread, prompt: prompt),
        );
        return (r, thread);
      } catch (e) {
        if (!interviewThreadGone(e)) rethrow;
        debugPrint('Entrevista: a conversa $thread não voltou ($e).');
      }
    }
    final sid = ref.read(sessionIdGeneratorProvider)();
    final history = thread == null || data.rounds.isEmpty
        ? ''
        : '${interviewHistory(data)}\n\n';
    final r = await runStructured(
      ref,
      intent(sessionId: sid, prompt: '$history$prompt'),
    );
    return (r, sid);
  }

  /// "Encerrar e ver a proposta" (R16): what stayed open does not become a
  /// rule.
  Future<InstructionProposal?> finishEarly(Workspace ws) async {
    if (state.busy) return null;
    await _saveData(state.data.copyWith(endedEarly: true));
    return propose(ws);
  }

  /// "Confirmar e ver a proposta" (R16) — and the proposal of
  /// [finishEarly]: the trechos by file and section (R19). Null when it
  /// failed ([InterviewState.error]).
  Future<InstructionProposal?> propose(Workspace ws) async {
    if (state.busy) return null;
    _set(state.copyWith(busy: true, clearError: true));
    final cancel = _cancel = Completer<void>();
    try {
      final repo = ref.read(instructionInterviewsRepoProvider);
      await _writes;
      final row = await repo.get(ws.id);
      if (row == null) return null;
      final files = await readInterviewFiles(ws.path);
      final before = InterviewData.decode(row.data);
      final (r, thread) = await _run(
        ws,
        row,
        before,
        prompt: interviewProposalPrompt(
          before,
          agents: files.agents,
          claude: files.claude,
        ),
        schema: interviewProposalSchema,
        cancel: cancel,
      );
      final proposal = parseInterviewProposal(
        r.data,
        data: before,
        provider: row.provider,
        model: r.model ?? row.model,
      );
      final current = before.current;
      final data = before.copyWith(
        rounds: current == null || current.sent
            ? before.rounds
            : [
                ...before.rounds.take(before.rounds.length - 1),
                current.copyWith(sent: true),
              ],
        stage: InterviewStage.proposal,
        proposal: proposal,
      );
      await _finishRun(ws, r, thread, data, files.hash);
      return proposal;
    } on StructuredCancelled {
      return null;
    } catch (e) {
      debugPrint('Proposta das instruções: $e');
      _set(state.copyWith(error: '$e'));
      return null;
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      _set(state.copyWith(busy: false));
    }
  }
}

/// The interview of a workspace (by id). Kept while the app runs, so a
/// round goes on when the screen closes.
final instructionInterviewProvider =
    NotifierProvider.family<InterviewController, InterviewState, int>(
      InterviewController.new,
    );
