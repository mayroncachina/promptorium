import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/claude_event.dart';
import '../../core/claude/readonly_run.dart'
    show PlannerException, runReadOnlyClaude, structuredOutput;
import '../../core/providers/claude_code_provider.dart';
import '../../data/providers.dart';
import '../project/project_planner.dart' show ProjectPlanner;
import '../sessions/session_manager.dart' show sessionIdGeneratorProvider;
import 'spec_draft.dart';
import 'spec_service.dart';

/// The planner of "Nova spec" (SPEC-039): the conversation of the Visão step
/// applied to one spec. Short, read-only `claude -p` runs with
/// `--json-schema`, in one Claude session (`--session-id`, then `--resume`).

const _str = {'type': 'string'};
const _strList = {'type': 'array', 'items': _str};

Map<String, Object?> _object(Map<String, Object?> props) => {
  'type': 'object',
  'additionalProperties': false,
  'required': props.keys.toList(),
  'properties': props,
};

final specPlannerSchema = _object({
  'reply': _str,
  'draft': _object({
    'title': _str,
    'objective': _str,
    'requirements': _strList,
    'outOfScope': _strList,
    'dependsOn': _strList,
    'openQuestions': {
      'type': 'array',
      'items': _object({'text': _str, 'suggestion': _str}),
    },
  }),
  'suggestions': _strList,
});

const specPlannerSystemPrompt =
    'Você é o planner do Promptorium e está ajudando a escrever UMA spec de '
    'um repositório que já existe. Escreva em português do Brasil. Leia o '
    'repositório quando ajudar. Não altere arquivos. Responda somente com a '
    'saída estruturada pedida. A cada mensagem: em reply, responda de forma '
    'curta e faça no máximo duas perguntas por vez, começando pelas que mais '
    'mudam a spec; em draft, devolva o rascunho COMPLETO atualizado (title '
    'curto; objective em 1 ou 2 frases; requirements sem numeração, pequenos, '
    'verificáveis e em ordem de execução, no estilo EARS: "Quando <gatilho>, '
    'o sistema deve <resposta>"; outOfScope; dependsOn com os códigos das '
    'specs listadas de que esta depende; openQuestions com text e, quando '
    'houver, suggestion); em suggestions, até 3 respostas curtas que o '
    'usuário poderia clicar para a sua pergunta principal (lista vazia se não '
    'houver pergunta). Não invente requisitos que o usuário não disse: uma '
    'dúvida sem resposta vira item de openQuestions. Uma dúvida que não '
    'impede começar não segura a criação: registre-a e diga em reply que a '
    'spec já pode ser criada. No máximo ${SpecDraftData.maxRequirements} '
    'requisitos: mantenha os que mais importam, mova o resto para outOfScope '
    'terminando com "$nextSpecHint", avise em reply e não divida a spec.';

/// User message of a turn. The specs of the workspace go in the first one,
/// where the planner learns what it may put in `dependsOn` (R5).
String specPlannerPrompt(
  String message, {
  List<Spec> specs = const [],
  bool first = false,
  String? fixedTitle,
}) {
  final b = StringBuffer()..writeln(message);
  if (first) {
    b
      ..writeln()
      ..writeln('Specs do workspace (código · título):');
    if (specs.isEmpty) b.writeln('Nenhuma.');
    for (final s in specs) {
      b.writeln('- ${s.code} · ${s.title}');
    }
  }
  if (fixedTitle != null) {
    b
      ..writeln()
      ..writeln('Título definido pela pessoa (mantenha): $fixedTitle');
  }
  return b.toString().trimRight();
}

/// `{reply, draft, suggestions}` of a turn.
({String reply, PlannerDraft draft, List<String> suggestions})
parseSpecPlannerResult(Result r) {
  final m = structuredOutput(r);
  if (m is! Map) {
    throw const PlannerException(
      'O planner não devolveu a saída estruturada (structured_output).',
    );
  }
  final s = m['suggestions'];
  return (
    reply: '${m['reply'] ?? ''}'.trim(),
    draft: PlannerDraft.fromJson(m['draft']),
    suggestions: [
      if (s is List)
        for (final x in s.take(3))
          if ('$x'.trim().isNotEmpty) '$x'.trim(),
    ],
  );
}

/// Markdown of the spec of [data] (R6): the template with what the draft has.
String specTextFromDraft(
  SpecDraftData data, {
  required String code,
  required String title,
}) => newSpecMarkdown(
  code: code,
  title: title,
  objective: data.objective,
  requirements: data.requirements,
  outOfScope: data.outOfScope,
  dependsOn: data.dependsOn,
  questions: [
    for (final q in data.openQuestions)
      (text: q.text, suggestion: q.suggestion),
  ],
);

/// Runs the conversation of "Nova spec" and keeps it in `spec_drafts`. The
/// state is the workspaces with a turn on the way.
class SpecPlanner extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  /// Writes of the draft, one at a time: what the person types while a turn
  /// ends is not lost.
  Future<void> _writes = Future.value();

  Future<void> _change(
    int workspaceId,
    SpecDraftData Function(SpecDraftData) change, {
    String? sessionId,
  }) {
    final repo = ref.read(specDraftsRepoProvider);
    final write = _writes.then((_) async {
      final row = await repo.get(workspaceId);
      if (row == null) return; // discarded on the way
      await repo.update(
        workspaceId,
        SpecDraftsCompanion(
          data: Value(change(SpecDraftData.decode(row.data)).encode()),
          plannerSessionId: sessionId == null
              ? const Value.absent()
              : Value(sessionId),
        ),
      );
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  void _busy(int workspaceId, bool busy) => state = busy
      ? {...state, workspaceId}
      : ({...state}..remove(workspaceId));

  /// "Planejar a spec": starts the draft with [idea].
  Future<void> begin(Workspace ws, String idea) async {
    await ref.read(specDraftsRepoProvider).start(ws.id);
    await send(ws, idea);
  }

  /// One turn. What did not get an answer goes along, so the session sees
  /// everything the person said (R9).
  Future<void> send(Workspace ws, String text) async {
    final msg = text.trim();
    if (msg.isEmpty || state.contains(ws.id)) return;
    _busy(ws.id, true);
    try {
      await _change(ws.id, (d) => d.withUserMessage(msg));
      await _turn(ws);
    } finally {
      _busy(ws.id, false);
    }
  }

  /// "Tentar de novo": sends what failed again, with no new message (R9).
  Future<void> retry(Workspace ws) async {
    if (state.contains(ws.id)) return;
    _busy(ws.id, true);
    try {
      await _turn(ws);
    } finally {
      _busy(ws.id, false);
    }
  }

  /// A failure leaves the person's message without an answer, which is what
  /// the screen shows as "O planner não respondeu".
  Future<void> _turn(Workspace ws) async {
    final repo = ref.read(specDraftsRepoProvider);
    try {
      final row = await repo.get(ws.id);
      if (row == null) return;
      final data = SpecDraftData.decode(row.data);
      final pending = data.unanswered;
      if (pending.isEmpty) return;
      final specs = await ref
          .read(specsRepoProvider)
          .watchByWorkspace(ws.id)
          .first;
      final resume = row.plannerSessionId;
      final sid = resume ?? ref.read(sessionIdGeneratorProvider)();
      final r = await runReadOnlyClaude(
        ref,
        workspaceId: ws.id,
        cwd: ws.path,
        options: ClaudeOptions(
          sessionId: resume == null ? sid : null,
          resumeId: resume,
          permissionMode: ClaudePermissionMode.defaultMode,
          disallowedTools: ClaudeCodeProvider.readOnlyDisallowedTools,
          appendSystemPrompt: specPlannerSystemPrompt,
          jsonSchema: jsonEncode(specPlannerSchema),
          maxBudgetUsd: ProjectPlanner.budgetUsd,
          includePartialMessages: false,
        ),
        prompt: specPlannerPrompt(
          pending.join('\n\n'),
          specs: specs,
          first: resume == null,
          fixedTitle: data.titleEdited ? data.title : null,
        ),
      );
      await repo.addCost(ws.id, r.totalCostUsd);
      final out = parseSpecPlannerResult(r);
      await _change(
        ws.id,
        (d) => d.withAnswer(
          reply: out.reply,
          draft: out.draft,
          suggestions: out.suggestions,
          knownSpecs: {for (final s in specs) s.code},
        ),
        sessionId: sid,
      );
    } catch (e) {
      debugPrint('Planner da nova spec: $e');
    }
  }

  /// The title typed by hand (R5).
  Future<void> editTitle(Workspace ws, String title) =>
      _change(ws.id, (d) => d.withTitle(title));

  /// "Criar spec" (R6): writes the spec with the code free now and only then
  /// removes the draft. A failure throws and keeps everything.
  Future<Spec> create(Workspace ws, {required String title}) async {
    final repo = ref.read(specDraftsRepoProvider);
    final row = await repo.get(ws.id);
    final data = SpecDraftData.decode(row?.data ?? '{}');
    final spec = await ref
        .read(specServiceProvider)
        .create(
          ws,
          title: title,
          render: (code) =>
              specTextFromDraft(data, code: code, title: title.trim()),
        );
    await repo.delete(ws.id);
    return spec;
  }

  Future<void> discard(Workspace ws) =>
      ref.read(specDraftsRepoProvider).delete(ws.id);
}

final specPlannerProvider = NotifierProvider<SpecPlanner, Set<int>>(
  SpecPlanner.new,
);

/// Where "Nova spec" is on the Specs screen (R1, R3).
enum NewSpecStage { closed, idea, conversation }

class NewSpecFlow extends Notifier<NewSpecStage> {
  @override
  NewSpecStage build() => NewSpecStage.closed;

  /// "Nova spec": back to the conversation when it is already open.
  void open() {
    if (state == NewSpecStage.closed) state = NewSpecStage.idea;
  }

  void converse() => state = NewSpecStage.conversation;

  void close() => state = NewSpecStage.closed;
}

final newSpecFlowProvider = NotifierProvider<NewSpecFlow, NewSpecStage>(
  NewSpecFlow.new,
);

/// Code the draft would get now (R5).
final nextSpecCodeProvider = FutureProvider.autoDispose
    .family<String, Workspace>(
      (ref, ws) => nextSpecCode(ref.watch(specsRepoProvider), ws),
    );
