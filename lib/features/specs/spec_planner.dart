import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_event.dart';
import '../../core/claude/claude_process.dart' show ImagePart;
import '../../core/providers/structured_run.dart';
import '../../data/providers.dart';
import '../issues/issue_refine.dart';
import '../project/project_plan.dart' show PlanQuestion;
import '../project/project_planner.dart' show ProjectPlanner;
import '../project/project_config.dart';
import '../sessions/session_manager.dart' show sessionIdGeneratorProvider;
import 'prototype/prototype_files.dart' show mockupDir;
import 'spec_draft.dart';
import 'spec_prints.dart';
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
  'questions': {
    'type': 'array',
    'items': _object({'text': _str, 'options': _strList}),
  },
  // SPEC-083 R7: one item per print of the idea (empty without prints).
  'prints': {
    'type': 'array',
    'items': _object({'nome': _str, 'descricao': _str, 'marcas': _strList}),
  },
});

const specPlannerSystemPrompt =
    'Você é o planner do Promptorium e está ajudando a escrever UMA spec de '
    'um repositório que já existe. Escreva em português do Brasil. Leia o '
    'repositório quando ajudar. Não altere arquivos. Responda somente com a '
    'saída estruturada pedida. A cada mensagem: em reply, responda de forma '
    'curta, sem repetir as perguntas; em questions, faça até duas perguntas, '
    'começando pelas que mais mudam a spec, com até três respostas curtas '
    'em options para cada pergunta. Em draft, devolva o rascunho COMPLETO atualizado (title '
    'curto; objective em 1 ou 2 frases; requirements sem numeração, pequenos, '
    'verificáveis e em ordem de execução, no estilo EARS: "Quando <gatilho>, '
    'o sistema deve <resposta>"; outOfScope; dependsOn com os códigos das '
    'specs listadas de que esta depende; openQuestions com text e, quando '
    'houver, suggestion). Não invente requisitos que o usuário não disse: uma '
    'dúvida sem resposta vira item de openQuestions. Uma dúvida que não '
    'impede começar não segura a criação: registre-a e diga em reply que a '
    'spec já pode ser criada. No máximo ${SpecDraftData.maxRequirements} '
    'requisitos: mantenha os que mais importam, mova o resto para outOfScope '
    'terminando com "$nextSpecHint", avise em reply e não divida a spec. '
    '$specPlannerPrintRules';

/// SPEC-083 R7: what the planner does with each kind of print.
const specPlannerPrintRules =
    'Prints: a mensagem pode trazer capturas de tela (imagens), cada uma com '
    'nome e tipo. Em prints, devolva um item por print, na ordem, com nome, '
    'descricao (uma frase do que o print mostra, usada como texto '
    'alternativo) e marcas (os nomes de produto, empresa e marca que você lê '
    'no print; lista vazia quando não há); sem prints, devolva lista vazia. '
    'Print de BUG (tela deste projeto com defeito): descreva o defeito (o '
    'que está errado, onde, em que estado da tela), ache no repositório a '
    'tela e os arquivos prováveis e escreva requisitos de correção com '
    'critérios verificáveis. Print de REFERÊNCIA (tela de outro produto): '
    'extraia só a ideia (a função, a organização da tela, o fluxo), adapte '
    'ao projeto e ao visual dele (as cores, as fontes e os componentes do '
    'repositório) e escreva os requisitos como algo do projeto. É PROIBIDO '
    'pôr no título, no objetivo, nos requisitos, no fora do escopo ou nas '
    'descrições a marca, o nome do produto ou da empresa, o logotipo, os '
    'slogans e textos da interface, os ícones próprios e as cores de marca '
    'do outro produto; onde precisar se referir a ele, escreva "o app de '
    'referência".';

/// User message of a turn. The specs of the workspace go in the first one,
/// where the planner learns what it may put in `dependsOn` (R5).
String specPlannerPrompt(
  String message, {
  List<Spec> specs = const [],
  bool first = false,
  String? fixedTitle,
  List<SpecPrint> prints = const [],
}) {
  final b = StringBuffer()..writeln(message);
  if (prints.isNotEmpty) {
    // SPEC-083 R6: the name and the kind of each image sent with it.
    b
      ..writeln()
      ..writeln('Prints anexados (as imagens desta mensagem, na ordem):');
    for (final s in prints) {
      b.writeln(
        '- ${s.name} (${s.width} × ${s.height}): '
        '${s.kind == PrintKind.reference ? 'referência de outro app (só a ideia; não copie a marca)' : 'bug neste projeto'}',
      );
    }
  }
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

/// `{reply, draft, suggestions, prints}` of a turn.
({
  String reply,
  PlannerDraft draft,
  List<String> suggestions,
  List<PlanQuestion> questions,
  List<PrintNote> prints,
})
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
    questions: [
      if (m['questions'] case final List questions)
        for (final raw in questions.whereType<Map>().take(2))
          if (PlanQuestion.fromJson(raw) case final question
              when question.text.isNotEmpty)
            PlanQuestion(
              text: question.text,
              options: question.options.take(3).toList(),
            ),
    ],
    prints: [
      if (m['prints'] case final List l)
        for (final x in l) PrintNote.fromJson(x),
    ],
  );
}

/// Markdown of the spec of [data] (R6): the template with what the draft has.
/// With prints, the section "Referência visual" after the Objetivo, with
/// the images relative to the spec file in [specsDir] (SPEC-083 R11), and
/// `tipo: bug` when one of them is a bug (R7).
String specTextFromDraft(
  SpecDraftData data, {
  required String code,
  required String title,
  String specsDir = 'docs/specs',
}) => newSpecMarkdown(
  code: code,
  title: title,
  type: data.isBug ? 'bug' : null,
  visualReference: visualReferenceSection(data.prints, code, specsDir),
  objective: data.objective,
  requirements: data.requirements,
  outOfScope: data.outOfScope,
  dependsOn: data.dependsOn,
  questions: [
    for (final q in data.openQuestions)
      (text: q.text, suggestion: q.suggestion),
  ],
);

/// Body of "## Referência visual" (SPEC-083 R11); empty without prints.
String visualReferenceSection(
  List<SpecPrint> prints,
  String code,
  String specsDir,
) {
  if (prints.isEmpty) return '';
  final dir = mockupDir(code);
  final up = specsDir
      .split('/')
      .where((x) => x.isNotEmpty && x != '.')
      .map((_) => '..')
      .join('/');
  final b = StringBuffer();
  for (final (i, s) in renumberPrints(prints).indexed) {
    final alt = s.description.isEmpty
        ? 'Print ${i + 1}'
        : 'Print ${i + 1}: ${s.description.replaceAll(RegExp(r'[\[\]]'), '')}';
    if (i > 0) b.writeln();
    b
      ..writeln('![$alt](${up.isEmpty ? '' : '$up/'}$dir/${s.name})')
      ..writeln()
      ..writeln(
        '- ${s.name} · ${s.kind == PrintKind.reference ? 'Referência de outro app' : 'Bug neste projeto'}',
      );
    if (s.kind == PrintKind.reference) b.writeln(referenceNote);
  }
  return b.toString().trimRight();
}

/// The line of a reference print in the spec (SPEC-083 R11).
const referenceNote =
    '- Referência de outro app: só a ideia. A spec não copia a marca, o '
    'nome, os textos nem os ícones dele.';

/// The images of the first turn (SPEC-083 R6). A file that can no longer
/// be read is left out.
Future<List<ImagePart>> printImages(List<SpecPrint> prints) async => [
  for (final s in prints)
    if (await File(s.path).exists())
      ImagePart(
        mediaType: s.mediaType,
        base64: base64Encode(await File(s.path).readAsBytes()),
        name: s.name,
      ),
];

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

  /// "Planejar a spec": starts the draft with [idea] and its [prints]
  /// (SPEC-083). With prints and no text, the idea is what they show (R5).
  Future<void> begin(
    Workspace ws,
    String idea, {
    List<SpecPrint> prints = const [],
  }) async {
    final repo = ref.read(specDraftsRepoProvider);
    await repo.start(ws.id);
    if (prints.isNotEmpty) {
      await _change(ws.id, (d) => d.withPrints(renumberPrints(prints)));
    }
    final text = idea.trim().isEmpty && prints.isNotEmpty
        ? (prints.length == 1
              ? 'O que o print mostra.'
              : 'O que os prints mostram.')
        : idea;
    await send(ws, text);
  }

  /// The description of a print typed by the person (SPEC-083 R8).
  Future<void> editPrintDescription(Workspace ws, int index, String text) =>
      _change(ws.id, (d) => d.withPrintDescription(index, text));

  /// "Pedir ao planner para reescrever" (SPEC-083 R9).
  Future<void> rewriteBrands(Workspace ws, List<String> brands) => send(
    ws,
    'O rascunho cita ${brands.map((b) => '"$b"').join(', ')}, do app de '
    'referência. Reescreva o título, o objetivo, os requisitos, o fora do '
    'escopo e as descrições dos prints trocando essas citações por termos '
    'do projeto (ou "o app de referência"), sem mudar o que a spec pede.',
  );

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
      // R6: the images go once; a resumed session already has them.
      // SPEC-100 R6: "Enviar sem os prints" holds for this turn.
      final drop =
          ref
              .read(structuredRunsProvider.notifier)
              .peekOnce(specPlannerSlot(ws.id))
              ?.dropImages ??
          false;
      final withPrints = data.prints.isNotEmpty && !data.printsSent && !drop;
      final images = withPrints
          ? await printImages(data.prints)
          : const <ImagePart>[];
      final r = await runStructured(
        ref,
        StructuredIntent(
          workspaceId: ws.id,
          cwd: ws.path,
          sessionId: resume == null ? sid : null,
          resumeId: resume,
          instructions: specPlannerSystemPrompt,
          schema: specPlannerSchema,
          claude: const ClaudeStructuredExtras(
            maxBudgetUsd: ProjectPlanner.budgetUsd,
          ),
          slot: specPlannerSlot(ws.id),
          label: 'a Nova spec',
          prompt: specPlannerPrompt(
            pending.join('\n\n'),
            specs: specs,
            first: resume == null,
            fixedTitle: data.titleEdited ? data.title : null,
            prints: withPrints ? data.prints : const [],
          ),
          images: images,
        ),
      );
      await repo.addCost(ws.id, r.costUsd ?? 0);
      final out = parseSpecPlannerResult(r.raw);
      await _change(ws.id, (d) {
        final next = d.withAnswer(
          reply: out.reply,
          draft: out.draft,
          suggestions: out.suggestions,
          questions: out.questions,
          knownSpecs: {for (final s in specs) s.code},
          printNotes: out.prints,
        );
        return withPrints || drop ? next.withPrintsSent() : next;
      }, sessionId: sid);
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
    // SPEC-074 R6: refining a spec linked to an issue rewrites the same
    // spec (same code, same `issue:`), never a new one.
    final target = ref.read(issueRefineProvider)[ws.id];
    final linked = target == null
        ? null
        : await ref.read(specsRepoProvider).getById(target.specId);
    final specsDir = ProjectConfig.loadSync(ws.path).specsDir;
    if (target != null && linked != null) {
      // SPEC-083 R10: the prints first; a failed copy keeps everything.
      await copyPrintsToMockups(ws.path, linked.code, data.prints);
      final text = SpecDocument.parse(
        specTextFromDraft(
          data,
          code: linked.code,
          title: title.trim(),
          specsDir: specsDir,
        ),
      ).withIssue(target.issue);
      final spec = await ref.read(specServiceProvider).save(ws, linked, text);
      await repo.delete(ws.id);
      await deletePrintFiles(data.prints);
      ref.read(issueRefineProvider.notifier).clear(ws.id);
      return spec;
    }
    final spec = await ref
        .read(specServiceProvider)
        .create(
          ws,
          title: title,
          render: (code) => specTextFromDraft(
            data,
            code: code,
            title: title.trim(),
            specsDir: specsDir,
          ),
          // SPEC-083 R10: with the spec file; a failure creates nothing.
          attach: data.prints.isEmpty
              ? null
              : (code) => copyPrintsToMockups(ws.path, code, data.prints),
        );
    await repo.delete(ws.id);
    await deletePrintFiles(data.prints);
    return spec;
  }

  /// Removes the draft and the temporary prints (SPEC-083 R4).
  Future<void> discard(Workspace ws) async {
    ref.read(issueRefineProvider.notifier).clear(ws.id);
    final repo = ref.read(specDraftsRepoProvider);
    final row = await repo.get(ws.id);
    await repo.delete(ws.id);
    if (row != null) {
      await deletePrintFiles(SpecDraftData.decode(row.data).prints);
    }
  }
}

/// Slot of the Nova spec's provider line (SPEC-100 R10).
String specPlannerSlot(int workspaceId) => 'new-spec:$workspaceId';

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
