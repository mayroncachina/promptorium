import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/claude_event.dart' show Result;
import '../../core/claude/readonly_run.dart';
import '../../core/providers/claude_code_provider.dart';
import '../../data/providers.dart';
import '../project/project_memory.dart';
import '../project/project_plan.dart' show Roadmap;
import 'spec_action.dart';
import 'spec_file.dart';

/// Instructions of "Planejar" (read-only run in the repository).
const designPrompt = '''
Você é o planner do Promptorium. Leia a spec abaixo e o repositório (somente
leitura) e escreva a seção Plano: como implementar cada requisito neste código —
componentes e arquivos que mudam ou nascem, decisões e alternativas descartadas,
riscos. Cite os requisitos (R1, R2…) em cada parte. Comece com a subseção
"### O que já existe": os arquivos, classes e funções do repositório que a
implementação reaproveita ou altera, com o caminho de cada um — as sessões de
execução partem dela em vez de explorar o código de novo. Depois, organize em
subseções "### R1 · …" quando houver mais de um requisito. Seja concreto e curto.

Em "etapas", para cada requisito liste ao menos um arquivo que a etapa toca e,
quando houver, um comando que verifica a etapa (ex.: um teste específico); deixe
vazio quando não houver.''';

final designSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['design', 'etapas'],
  'properties': {
    'design': {'type': 'string'},
    'etapas': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['requisito', 'arquivos', 'verificar'],
        'properties': {
          'requisito': {'type': 'string'},
          'arquivos': {
            'type': 'array',
            'minItems': 1,
            'items': {'type': 'string'},
          },
          'verificar': {'type': 'string'},
        },
      },
    },
  },
};

/// How "Refinar com IA" improves a spec, shared with the automatic round
/// (SPEC-037 R12).
const specRefineRules =
    'Melhore o objetivo, '
    'deixe os requisitos verificáveis (um por linha, no formato '
    '"- R1 · texto", de preferência no estilo EARS: "Quando <gatilho>, o '
    'sistema deve <resposta>"), complete os critérios de aceite (marque o '
    'requisito de cada um, ex.: [R2], e um "verificar: <comando>" quando '
    'houver), escreva a seção "Fora do escopo" com o que a spec não faz e '
    'deixe as dúvidas sem resposta como itens de "Perguntas em aberto", em '
    'vez de transformá-las em requisitos ($openQuestionsFormatHint; a '
    'sugestão nunca é um item próprio).';

/// Instructions of the automatic round: refine and plan at once (SPEC-037
/// R6, R12).
const autoPlanPrompt =
    '''
$designPrompt

Antes de planejar, refine a spec. $specRefineRules

Devolva a spec refinada nos campos "objetivo", "requisitos", "criterios",
"foraDoEscopo" e "perguntas", e o plano em "design" e "etapas". O plano parte da
spec já refinada. Ninguém revisa esta rodada, então siga estas regras:
- mantenha todo requisito existente, com o mesmo número: reescreva o texto se
  precisar e acrescente requisitos novos com o próximo número livre, mas não
  remova nenhum;
- no máximo ${Roadmap.maxRequirements} requisitos por spec;
- em "criterios", um critério por item, sem o "- [ ]";
- em "perguntas", só as dúvidas novas, com a sugestão de resposta quando houver
  (vazia quando não houver); nunca invente a resposta nem pare por causa delas;
- não escreva títulos "##" nos textos: use "###" dentro do plano;
- o frontmatter (id, status, depende-de) não muda e não faz parte da resposta.''';

/// [designSchema] plus the refined sections.
final autoPlanSchema = () {
  const text = {'type': 'string'};
  final props = designSchema['properties'] as Map<String, Object?>;
  return {
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'objetivo',
      'requisitos',
      'criterios',
      'foraDoEscopo',
      'perguntas',
      'design',
      'etapas',
    ],
    'properties': {
      'objetivo': text,
      'requisitos': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['id', 'texto'],
          'properties': {'id': text, 'texto': text},
        },
      },
      'criterios': {'type': 'array', 'items': text},
      'foraDoEscopo': text,
      'perguntas': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['pergunta', 'sugestao'],
          'properties': {'pergunta': text, 'sugestao': text},
        },
      },
      ...props,
    },
  };
}();

/// What an automatic round produced.
typedef AutoPlanAnswer = ({String text, int addedRequirements, int questions});

/// [specText] refined and planned by [data], checked against SPEC-037 R12.
/// Throws [PlannerException] with the reason when the answer breaks a rule:
/// the caller keeps the spec as it was.
AutoPlanAnswer applyAutoPlanAnswer(String specText, Object? data) {
  Never refuse(String why) =>
      throw PlannerException('$why A spec ficou como estava.');
  if (data is! Map) refuse('A resposta veio vazia.');
  final doc = SpecDocument.parse(specText);
  String field(String name) => '${data[name] ?? ''}'.trim();

  final requirements = <String, String>{};
  for (final r in (data['requisitos'] as List? ?? const [])) {
    final id = r is Map ? '${r['id'] ?? ''}'.trim() : '';
    final text = r is Map ? '${r['texto'] ?? ''}'.trim() : '';
    if (!RegExp(r'^R\d+$').hasMatch(id)) {
      refuse('A resposta trouxe um requisito sem número válido.');
    }
    if (text.isEmpty) refuse('A resposta deixou o requisito $id sem texto.');
    if (requirements.containsKey(id)) {
      refuse('A resposta repetiu o requisito $id.');
    }
    requirements[id] = text;
  }
  final before = [for (final r in doc.requirements) r.id];
  final removed = before.where((id) => !requirements.containsKey(id)).toList();
  if (removed.length == 1) {
    refuse('A resposta removeu o requisito ${removed.single}.');
  }
  if (removed.isNotEmpty) {
    refuse('A resposta removeu os requisitos ${removed.join(', ')}.');
  }
  if (requirements.length > Roadmap.maxRequirements) {
    refuse(
      'A resposta passou de ${Roadmap.maxRequirements} requisitos '
      '(${requirements.length}).',
    );
  }
  if (requirements.isEmpty) refuse('A resposta veio sem requisitos.');
  final criteria = [
    for (final c in (data['criterios'] as List? ?? const []))
      if ('$c'.replaceFirst(_itemPrefix, '').trim() case final t
          when t.isNotEmpty)
        t,
  ];
  if (criteria.isEmpty) refuse('A resposta veio sem critérios de aceite.');
  final objective = field('objetivo'), outOfScope = field('foraDoEscopo');
  if (objective.isEmpty) refuse('A resposta veio sem objetivo.');
  if (outOfScope.isEmpty) refuse('A resposta veio sem "Fora do escopo".');
  final questions = [
    for (final q in (data['perguntas'] as List? ?? const []))
      if (q is Map && '${q['pergunta'] ?? ''}'.trim().isNotEmpty)
        (
          text: '${q['pergunta']}'.trim(),
          suggestion: '${q['sugestao'] ?? ''}'.trim(),
        ),
  ];
  final bodies = [
    objective,
    outOfScope,
    field('design'),
    ...requirements.values,
    ...criteria,
    ...questions.map((q) => q.text),
  ];
  // Would open a section of its own, or close the frontmatter.
  if (bodies.any(RegExp(r'^(##\s|---\s*$)', multiLine: true).hasMatch)) {
    refuse('A resposta trouxe um título de seção dentro do texto.');
  }

  var out = doc.withSection('Objetivo', objective, after: 'Objetivo');
  out = SpecDocument.parse(out).withSection(
    'Requisitos',
    [for (final e in requirements.entries) '- ${e.key} · ${e.value}']
        .join('\n'),
    after: 'Objetivo',
  );
  try {
    out = applyDesignAnswer(out, data);
  } on PlannerException {
    refuse('A resposta veio sem plano.');
  }
  if (SpecDocument.parse(out).stepPlans.isEmpty) {
    refuse('A resposta veio sem etapas.');
  }
  out = SpecDocument.parse(out).withSection(
    SpecDocument.outOfScopeSection,
    outOfScope,
    after: 'Requisitos',
  );
  out = SpecDocument.parse(out).withSection(
    SpecDocument.criteriaSection,
    [for (final c in criteria) '- [ ] $c'].join('\n'),
    after: 'Etapas',
  );
  final existing = SpecDocument.parse(out).openQuestions;
  final known = {for (final q in existing) foldText(q.text)};
  final used = {for (final q in existing) q.id};
  var n = 0;
  final added = <OpenQuestion>[];
  for (final q in questions) {
    if (!known.add(foldText(q.text))) continue;
    do {
      n++;
    } while (used.contains('P$n'));
    added.add(
      OpenQuestion(
        id: 'P$n',
        text: q.text,
        suggestion: q.suggestion.isEmpty ? null : q.suggestion,
      ),
    );
  }
  if (added.isNotEmpty) {
    out = SpecDocument.parse(out).withOpenQuestions([...existing, ...added]);
  }

  final after = SpecDocument.parse(out);
  if (after.id != doc.id ||
      after.rawStatus != doc.rawStatus ||
      after.dependsOn.join(',') != doc.dependsOn.join(',')) {
    refuse('A resposta mudou o frontmatter.');
  }
  return (
    text: out,
    addedRequirements: requirements.length - before.length,
    questions: added.length,
  );
}

final _itemPrefix = RegExp(r'^\s*[-*+]\s+(\[[ xX]\]\s+)?');

/// Text of the spec with the generated `## Plano` / `## Etapas` (F7).
String applyDesignAnswer(String specText, Object? data) {
  if (data is! Map || '${data['design'] ?? ''}'.trim().isEmpty) {
    throw const PlannerException('O planner não devolveu um plano.');
  }
  final plans = <String, StepPlan>{
    for (final e in (data['etapas'] as List? ?? const []))
      if (e is Map &&
          RegExp(r'^(REV|R)\d+$').hasMatch('${e['requisito'] ?? ''}'.trim()))
        '${e['requisito']}'.trim(): StepPlan(
          files: [
            for (final f in (e['arquivos'] as List? ?? const []))
              if ('$f'.trim().isNotEmpty) '$f'.trim(),
          ],
          verify: '${e['verificar'] ?? ''}'.trim().isEmpty
              ? null
              : '${e['verificar']}'.trim(),
        ),
  };
  return SpecDocument.parse(specText)
      .withDesign('${data['design']}'.trim(), plans: plans);
}

/// "Planejar" of the Specs screen.
class SpecDesigner {
  SpecDesigner(this._ref);

  final Ref _ref;

  static const budgetUsd = 1.0;

  /// Limit of an automatic round: the same as Planejar (SPEC-037 R6, D12).
  static const autoPlanBudgetUsd = budgetUsd;

  /// Returns [specText] with the generated plan (not saved: the user
  /// reviews it in the editor). Completing [cancelled] stops the agent and
  /// throws [SpecActionCancelled] (SPEC-025 R5).
  Future<String> generate(
    Workspace ws,
    String specText, {
    Future<void>? cancelled,
  }) async => applyDesignAnswer(
    specText,
    await _run(
      ws,
      'Spec:\n<spec>\n${specText.trimRight()}\n</spec>',
      systemPrompt: designPrompt,
      schema: designSchema,
      budgetUsd: budgetUsd,
      cancelled: cancelled,
    ),
  );

  /// One read-only round that refines and plans [specText] (SPEC-037 R6,
  /// R12), not saved here. [dependencyPlans] (code → plan) stands for code
  /// the repository does not have yet. Throws [PlannerException] when the
  /// answer breaks R12, [SpecActionCancelled] as [generate].
  Future<AutoPlanAnswer> refineAndPlan(
    Workspace ws,
    String specText, {
    Map<String, String> dependencyPlans = const {},
    Future<void>? cancelled,
  }) async => applyAutoPlanAnswer(
    specText,
    await _run(
      ws,
      [
        if (dependencyPlans.isNotEmpty)
          'Planos das specs de que esta depende (o código delas ainda não '
              'existe no repositório; conte com ele):\n'
              '${[for (final e in dependencyPlans.entries) '<plano spec="${e.key}">\n${e.value.trim()}\n</plano>'].join('\n')}\n',
        'Spec:\n<spec>\n${specText.trimRight()}\n</spec>',
      ].join('\n'),
      systemPrompt: autoPlanPrompt,
      schema: autoPlanSchema,
      budgetUsd: autoPlanBudgetUsd,
      cancelled: cancelled,
    ),
  );

  Future<Object?> _run(
    Workspace ws,
    String request, {
    required String systemPrompt,
    required Map<String, Object?> schema,
    required double budgetUsd,
    Future<void>? cancelled,
  }) async {
    var stopped = false;
    // Registered before the run's own listener: the flag is set by the time
    // the run fails with "cancelada".
    cancelled?.then((_) => stopped = true);
    final Result r;
    try {
      r = await runReadOnlyClaude(
        _ref,
        workspaceId: ws.id,
        cancelled: cancelled,
        cwd: ws.path,
        options: ClaudeOptions(
          permissionMode: ClaudePermissionMode.defaultMode,
          disallowedTools: ClaudeCodeProvider.readOnlyDisallowedTools,
          appendSystemPrompt: systemPrompt,
          jsonSchema: jsonEncode(schema),
          maxBudgetUsd: budgetUsd,
          includePartialMessages: false,
        ),
        prompt: [
          if (ProjectMemory.loadSync(ws.path) case final m when !m.isEmpty)
            'Memória do projeto:\n${m.toPrompt()}\n',
          request,
        ].join('\n'),
      );
    } on PlannerException {
      if (stopped) throw const SpecActionCancelled();
      rethrow;
    }
    if (stopped) throw const SpecActionCancelled();
    return structuredOutput(r);
  }
}

final specDesignerProvider = Provider(SpecDesigner.new);
