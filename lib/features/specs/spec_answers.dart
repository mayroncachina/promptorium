import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/readonly_run.dart';
import '../../core/providers/claude_code_provider.dart';
import '../../data/providers.dart';
import '../project/project_memory.dart';
import 'spec_action.dart';
import 'spec_file.dart';

/// Which option of a question was picked (SPEC-028 R7).
enum AnswerOption {
  /// "Sugestão da spec".
  suggestion,

  /// First alternative of the Claude.
  alternative1,

  /// Second alternative of the Claude.
  alternative2,

  /// Third alternative of the Claude (SPEC-061 R1).
  alternative3,

  /// "Outra resposta", with its own text.
  other,
}

/// The answer to one question in the session (SPEC-028 R8): the option, the
/// text that goes to `## Decisões`, or "Deixar para depois".
@immutable
class Answer {
  const Answer({required this.option, this.text = '', this.deferred = false});

  const Answer.deferred()
    : option = AnswerOption.suggestion,
      text = '',
      deferred = true;

  final AnswerOption option;

  /// Summary of the answer (empty = not answered yet).
  final String text;
  final bool deferred;

  bool get answered => !deferred && text.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is Answer &&
      other.option == option &&
      other.text == text &&
      other.deferred == deferred;

  @override
  int get hashCode => Object.hash(option, text, deferred);
}

/// Answers of the session per spec id, then per question id (SPEC-028 R8):
/// kept while the app is open (closing the panel keeps them; P2 of the spec:
/// nothing is stored), dropped when they are saved into the spec.
class SpecAnswers extends Notifier<Map<int, Map<String, Answer>>> {
  @override
  Map<int, Map<String, Answer>> build() => const {};

  Map<String, Answer> of(int specId) => state[specId] ?? const {};

  void set(int specId, String questionId, Answer answer) => state = {
    ...state,
    specId: {...of(specId), questionId: answer},
  };

  void clear(int specId) {
    if (!state.containsKey(specId)) return;
    state = {...state}..remove(specId);
  }
}

final specAnswersProvider =
    NotifierProvider<SpecAnswers, Map<int, Map<String, Answer>>>(
      SpecAnswers.new,
    );

/// The Claude's alternatives in the order shown (SPEC-061 R1: three).
const alternativeOptions = [
  AnswerOption.alternative1,
  AnswerOption.alternative2,
  AnswerOption.alternative3,
];

/// How many alternatives the Claude proposes for each question.
const alternativesPerQuestion = 3;

/// One alternative of the Claude for a question (SPEC-028 R7).
@immutable
class QuestionAlternative {
  const QuestionAlternative({required this.title, required this.consequence});

  final String title;
  final String consequence;
}

const questionOptionsPrompt = '''
Você ajuda a responder uma pergunta em aberto de uma spec do Promptorium. Leia a
spec abaixo (e o repositório, somente leitura, se precisar) e proponha três
respostas para a pergunta indicada, diferentes da sugestão que a spec já traz.
Para cada uma, dê um título curto (a resposta em si, no máximo 8 palavras) e a
consequência para quem usa ou para a implementação, numa frase. Não repita a
sugestão da spec. Responda em português.''';

final questionOptionsSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['options'],
  'properties': {
    'options': {
      'type': 'array',
      'maxItems': alternativesPerQuestion,
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['title', 'consequence'],
        'properties': {
          'title': {'type': 'string'},
          'consequence': {'type': 'string'},
        },
      },
    },
  },
};

/// Alternatives of the structured answer (at most three, empty titles out).
List<QuestionAlternative> parseQuestionOptions(Object? data) {
  final list = data is Map ? data['options'] : null;
  return [
    if (list is List)
      for (final o in list)
        if (o is Map && '${o['title'] ?? ''}'.trim().isNotEmpty)
          QuestionAlternative(
            title: '${o['title']}'.trim(),
            consequence: '${o['consequence'] ?? ''}'.trim(),
          ),
  ].take(alternativesPerQuestion).toList();
}

String _norm(String s) => s.trim().toLowerCase();

/// Alternatives of the Claude for each question (SPEC-028 R7): a read-only
/// run with `--json-schema`, cached by (spec, question, text) while the app
/// is open.
class SpecQuestionOptions {
  SpecQuestionOptions(this._ref);

  final Ref _ref;

  static const budgetUsd = 0.3;

  final _cache = <String, Future<List<QuestionAlternative>>>{};

  /// Every alternative already shown for a question (SPEC-061 R4: "Outras
  /// sugestões" never repeats them).
  final _shown = <String, List<QuestionAlternative>>{};

  String _key(int specId, OpenQuestion q) =>
      '$specId|${q.id}|${Object.hash(q.text, q.suggestion)}';

  /// Cached [generate] of [q]; a failure is not cached (asked again on the
  /// next visit).
  Future<List<QuestionAlternative>> forQuestion(
    Workspace ws,
    int specId,
    String specText,
    OpenQuestion q,
  ) {
    final key = _key(specId, q);
    return _cache[key] ??=
        generate(ws, specText, q).then((v) {
          _shown.putIfAbsent(key, () => []).addAll(v);
          return v;
        })..catchError((Object _) {
          _cache.remove(key);
          return const <QuestionAlternative>[];
        });
  }

  /// "Outras sugestões" (SPEC-061 R4): a new set for [q] in place of
  /// [current], without any alternative shown before. The one at [keep]
  /// (the chosen one) stays where it is. The new set replaces the cached
  /// one; a failure throws and leaves the cache as it was.
  Future<List<QuestionAlternative>> more(
    Workspace ws,
    int specId,
    String specText,
    OpenQuestion q, {
    required List<QuestionAlternative> current,
    int? keep,
  }) async {
    final key = _key(specId, q);
    final shown = _shown.putIfAbsent(key, () => [...current]);
    final kept = keep != null && keep < current.length ? current[keep] : null;
    final want = alternativesPerQuestion - (kept == null ? 0 : 1);
    final seen = {
      for (final a in [...shown, ...current]) _norm(a.title),
    };
    final fresh = [
      for (final a in await generate(
        ws,
        specText,
        q,
        avoid: [...shown, ...current.where((a) => !shown.contains(a))],
        count: want,
      ))
        if (seen.add(_norm(a.title))) a,
    ].take(want).toList();
    if (fresh.isEmpty) throw StateError('Nenhuma sugestão nova.');
    shown.addAll(fresh);
    final next = [...fresh];
    if (kept != null) next.insert(keep!.clamp(0, next.length), kept);
    _cache[key] = Future.value(next);
    return next;
  }

  /// Alternatives for [q] (never written anywhere): [count] of them, none
  /// like the ones in [avoid].
  Future<List<QuestionAlternative>> generate(
    Workspace ws,
    String specText,
    OpenQuestion q, {
    List<QuestionAlternative> avoid = const [],
    int count = alternativesPerQuestion,
  }) async {
    final r = await runReadOnlyClaude(
      _ref,
      workspaceId: ws.id,
      cwd: ws.path,
      options: ClaudeOptions(
        permissionMode: ClaudePermissionMode.defaultMode,
        disallowedTools: ClaudeCodeProvider.readOnlyDisallowedTools,
        appendSystemPrompt: questionOptionsPrompt,
        jsonSchema: jsonEncode(questionOptionsSchema),
        maxBudgetUsd: budgetUsd,
        includePartialMessages: false,
      ),
      prompt: [
        'Spec:\n<spec>\n${specText.trimRight()}\n</spec>',
        'Pergunta ${q.id}: ${q.text}',
        if (q.suggestion != null) 'Sugestão da spec: ${q.suggestion}',
        if (avoid.isNotEmpty)
          'Já mostradas (não repita nem reformule):\n'
              '${[for (final a in avoid) '- ${a.title}: ${a.consequence}'].join('\n')}',
        if (count != alternativesPerQuestion)
          'Proponha só $count ${count == 1 ? 'resposta' : 'respostas'}.',
      ].join('\n\n'),
    );
    return parseQuestionOptions(structuredOutput(r));
  }
}

final specQuestionOptionsProvider = Provider(SpecQuestionOptions.new);

const applyAnswersPrompt = '''
Você atualiza uma spec do Promptorium com as respostas dadas às perguntas em
aberto. A spec abaixo já traz as respostas em "## Decisões". Reescreva só o
necessário para refletir essas decisões nos requisitos (formato "- R<n> · …",
no estilo "Quando <gatilho>, o sistema deve <resposta>") e nos critérios de
aceite (com o requisito, ex.: [R2], e "verificar: <comando>" quando houver):
ajuste os requisitos existentes ou acrescente novos ao fim da lista. Não mude o
frontmatter, o título, a seção "## Decisões" nem as perguntas que continuam em
"## Perguntas em aberto". Não grave arquivos: devolva em "markdown" o texto
completo da spec atualizada.''';

final applyAnswersSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['markdown'],
  'properties': {
    'markdown': {'type': 'string'},
  },
};

/// "Atualizar requisitos e critérios com as respostas" (SPEC-028 R10): the
/// Claude gets the spec text with the decisions and returns the final text
/// by structured output. It runs read-only: nothing is written here, only
/// "Salvar na spec" saves (R11).
class SpecAnswerApplier {
  SpecAnswerApplier(this._ref);

  final Ref _ref;

  static const budgetUsd = 1.0;

  /// The final text of the spec, from [withDecisions] (the editor text with
  /// `## Decisões` written). The frontmatter `id` and `status` of
  /// [withDecisions] are kept whatever the agent returns. Completing
  /// [cancelled] stops the agent and throws [SpecActionCancelled].
  Future<String> apply(
    Workspace ws,
    String withDecisions,
    Map<OpenQuestion, Answer> answers, {
    Future<void>? cancelled,
  }) async {
    var stopped = false;
    cancelled?.then((_) => stopped = true);
    final Object? data;
    try {
      final r = await runReadOnlyClaude(
        _ref,
        workspaceId: ws.id,
        cancelled: cancelled,
        cwd: ws.path,
        options: ClaudeOptions(
          permissionMode: ClaudePermissionMode.defaultMode,
          disallowedTools: ClaudeCodeProvider.readOnlyDisallowedTools,
          appendSystemPrompt: applyAnswersPrompt,
          jsonSchema: jsonEncode(applyAnswersSchema),
          maxBudgetUsd: budgetUsd,
          includePartialMessages: false,
        ),
        prompt: [
          if (ProjectMemory.loadSync(ws.path) case final m when !m.isEmpty)
            'Memória do projeto:\n${m.toPrompt()}\n',
          'Respostas:',
          for (final MapEntry(key: q, value: a) in answers.entries)
            if (a.answered) '- ${q.id} · ${q.text} → ${a.text}',
          '',
          'Spec:\n<spec>\n${withDecisions.trimRight()}\n</spec>',
        ].join('\n'),
      );
      if (stopped) throw const SpecActionCancelled();
      data = structuredOutput(r);
    } on PlannerException {
      if (stopped) throw const SpecActionCancelled();
      rethrow;
    }
    return answeredSpecText(withDecisions, data);
  }
}

/// The markdown of the structured answer, with the `id` / `status` of
/// [base] (R11: saving does not change the status).
String answeredSpecText(String base, Object? data) {
  final md = data is Map ? '${data['markdown'] ?? ''}' : '';
  if (md.trim().isEmpty) {
    throw const PlannerException('O Claude não devolveu a spec atualizada.');
  }
  final before = SpecDocument.parse(base);
  var out = md.endsWith('\n') || !base.endsWith('\n') ? md : '$md\n';
  final doc = SpecDocument.parse(out);
  if (before.hasFrontmatter &&
      (doc.id != before.id || doc.rawStatus != before.rawStatus)) {
    out = doc.withMeta(id: before.id, status: before.status);
  }
  return out;
}

final specAnswerApplierProvider = Provider(SpecAnswerApplier.new);
