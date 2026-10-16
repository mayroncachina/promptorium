import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/claude_event.dart';
import '../../core/providers/claude_code_provider.dart';
import '../../data/providers.dart';
import '../sessions/session_manager.dart' show sessionIdGeneratorProvider;
import '../../core/claude/readonly_run.dart'
    show PlannerException, runReadOnlyClaude, structuredOutput;
import 'project_plan.dart';

/// The planner of the Projeto screen: short, read-only `claude -p` runs with
/// `--json-schema` (like "Gerar tarefas"). The Visão conversation keeps one
/// Claude session (`--session-id`, then `--resume`); the stack and roadmap
/// runs get the plan in the prompt.

const _str = {'type': 'string'};
const _strList = {'type': 'array', 'items': _str};

Map<String, Object?> _object(Map<String, Object?> props) => {
  'type': 'object',
  'additionalProperties': false,
  'required': props.keys.toList(),
  'properties': props,
};

final visionSchema = _object({
  'reply': _str,
  'plan': _object({
    'name': _str,
    'summary': _str,
    'audience': _str,
    'mvp': _strList,
    'outOfScope': _strList,
    'openQuestions': _strList,
  }),
  'suggestions': _strList,
});

final stackSchema = _object({
  'decisions': {
    'type': 'array',
    'items': _object({
      'area': _str,
      'choice': _str,
      'why': _str,
      'alternatives': _strList,
    }),
  },
  'claudeMd': _str,
});

final _specSchema = _object({
  'code': _str,
  'title': _str,
  'phase': {
    'type': 'string',
    'enum': ['foundation', 'mvp'],
  },
  'objective': _str,
  'requirements': {
    'type': 'array',
    'items': _object({'id': _str, 'text': _str}),
  },
  'acceptance': _strList,
  'dependsOn': _strList,
});

final roadmapSchema = _object({
  'specs': {'type': 'array', 'items': _specSchema},
  'later': _strList,
});

/// One spec out of a "Depois" idea.
final ideaSpecSchema = _object({'spec': _specSchema});

const _base =
    'Você é o planner do Promptorium e está ajudando a planejar um projeto '
    'de software novo. Escreva em português do Brasil. Não altere arquivos. '
    'Responda somente com a saída estruturada pedida.';

const visionSystemPrompt =
    '$_base Etapa Visão: entenda o que o projeto é e para quem. A cada '
    'mensagem: em reply, responda de forma curta e faça no máximo duas '
    'perguntas por vez, começando pelas que mais mudam o plano; em plan, '
    'devolva o plano COMPLETO atualizado (name; summary em 1 ou 2 frases; '
    'audience; mvp com as funcionalidades essenciais; outOfScope; '
    'openQuestions com as dúvidas que ainda faltam); em suggestions, até 3 '
    'respostas curtas que o usuário poderia clicar para a sua pergunta '
    'principal (lista vazia se não houver pergunta). Não invente requisitos '
    'que o usuário não disse: quando faltar informação, pergunte e registre '
    'em openQuestions. Quando não houver mais dúvidas importantes, diga que a '
    'visão está pronta para a etapa de stack.';

const stackSystemPrompt =
    '$_base Etapa Stack: proponha as tecnologias do projeto. Em decisions, '
    'uma entrada por área relevante (ex.: Aplicação, Banco de dados, '
    'Autenticação, Testes, Deploy) com choice, why (uma frase ligando a '
    'escolha à visão) e até 2 alternatives. Se a escolha depender de '
    'informação que falta, use choice "${StackDecision.undecided}". Mantenha '
    'exatamente as escolhas indicadas como fixadas. Em claudeMd, escreva o '
    'CLAUDE.md do projeto em Markdown: título e resumo, stack, comandos '
    '(instalar, rodar, testar, lint — os que a stack terá) e convenções de '
    'código e de commits. Seja conciso: ele é lido no início de toda sessão '
    'de agente.';

const roadmapSystemPrompt =
    '$_base Etapa Roadmap: transforme a visão e a stack em specs. Cada spec '
    'é uma unidade de trabalho do tamanho de um PR: uma branch, um review, um '
    'merge. Specs com phase "foundation" formam o esqueleto do projeto (criar '
    'o projeto com a stack escolhida, banco e migrations se houver, lint, '
    'testes e CI); a primeira não depende de nada. Specs com phase "mvp": '
    'uma por área funcional do MVP. Cada spec: code único em todo o roadmap '
    '(S1, S2, …), title, objective (1 ou 2 frases), requirements (ids R1, '
    'R2… dentro da spec, com text), acceptance (critérios verificáveis) e '
    'dependsOn (codes das specs que precisam estar concluídas antes). Cada '
    'requisito vira uma etapa que o agente implementa numa sessão própria: '
    'escreva-os pequenos, verificáveis e em ordem de execução (cada um pode '
    'usar o que os anteriores fizeram). No máximo ${Roadmap.maxRequirements} '
    'requisitos por spec: se uma área precisar de mais, divida em duas specs '
    'com dependsOn. Toda spec do mvp depende, direta ou indiretamente, da '
    'fundação. Itens fora do escopo vão em later e não viram specs.';

const ideaSystemPrompt =
    '$_base Etapa Roadmap: o usuário decidiu trazer para o roadmap uma ideia '
    'que estava fora do escopo. Escreva UMA spec para ela, na phase pedida: '
    'code (use o code novo indicado), title, objective (1 ou 2 frases), '
    'requirements (R1, R2…, pequenos, verificáveis e em ordem de execução; no '
    'máximo ${Roadmap.maxRequirements}), acceptance (critérios verificáveis) '
    'e dependsOn (codes de specs existentes listadas — toda spec do mvp '
    'depende, direta ou indiretamente, da fundação).';

String _json(Object? v) => const JsonEncoder.withIndent('  ').convert(v);

/// User message of a stack run.
String stackPrompt(
  VisionPlan vision, {
  List<StackDecision> fixed = const [],
  String? request,
}) {
  final b = StringBuffer()
    ..writeln('Visão do projeto (JSON):')
    ..writeln(_json(vision.toJson()));
  if (fixed.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Escolhas fixadas (mantenha exatamente):');
    for (final d in fixed) {
      b.writeln('- ${d.area}: ${d.choice}');
    }
  }
  if (request != null && request.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('Pedido do usuário: ${request.trim()}');
  }
  return b.toString().trimRight();
}

/// User message of a roadmap run.
String roadmapPrompt(VisionPlan vision, StackPlan stack, {String? request}) {
  final b = StringBuffer()
    ..writeln('Visão do projeto (JSON):')
    ..writeln(_json(vision.toJson()))
    ..writeln()
    ..writeln('Stack:');
  for (final d in stack.decisions) {
    b.writeln('- ${d.area}: ${d.choice}');
  }
  if (request != null && request.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('Pedido do usuário: ${request.trim()}');
  }
  return b.toString().trimRight();
}

/// User message of an idea run.
String ideaPrompt(String idea, RoadmapPhase phase, ProjectPlanData data) {
  final roadmap = data.roadmap;
  final b = StringBuffer()
    ..writeln('Ideia: $idea')
    ..writeln(
      'Phase: ${phase == RoadmapPhase.foundation ? 'foundation' : 'mvp'}',
    )
    ..writeln()
    ..writeln('Visão do projeto (JSON):')
    ..writeln(_json(data.vision.toJson()))
    ..writeln()
    ..writeln('Stack:');
  for (final d in data.stack.decisions) {
    b.writeln('- ${d.area}: ${d.choice}');
  }
  b
    ..writeln()
    ..writeln('Roadmap atual (specs existentes):');
  for (final s in roadmap.specs) {
    b.writeln('- ${s.code} · ${s.phase.label} · ${s.title}');
  }
  b
    ..writeln()
    ..writeln('Code novo: ${roadmap.nextSpecCode()}.');
  return b.toString().trimRight();
}

/// [roadmap] with the spec of an idea run added: a code already in use is
/// replaced, [idea] leaves "Depois" and the result is normalized and marked
/// as edited.
Roadmap addIdeaSpec(Roadmap roadmap, RoadmapSpec spec, String idea) {
  final used = {for (final s in roadmap.specs) s.code};
  final code = spec.code.isEmpty || used.contains(spec.code)
      ? roadmap.nextSpecCode()
      : spec.code;
  return roadmap
      .copyWith(
        specs: [
          ...roadmap.specs,
          spec.copyWith(
            code: code,
            dependsOn: [
              for (final d in spec.dependsOn)
                if (d != code) d,
            ],
          ),
        ],
        later: [
          for (final l in roadmap.later)
            if (l != idea) l,
        ],
      )
      .normalized()
      .copyWith(edited: true);
}

Map _map(Result r) {
  final data = structuredOutput(r);
  if (data is! Map) {
    throw const PlannerException(
      'O planner não devolveu a saída estruturada (structured_output).',
    );
  }
  return data;
}

/// `{reply, plan, suggestions}` of a Visão turn.
({String reply, VisionPlan plan, List<String> suggestions}) parseVisionResult(
  Result r,
) {
  final m = _map(r);
  final s = m['suggestions'];
  return (
    reply: '${m['reply'] ?? ''}'.trim(),
    plan: VisionPlan.fromJson(m['plan']),
    suggestions: [
      if (s is List)
        for (final x in s.take(3))
          if ('$x'.trim().isNotEmpty) '$x'.trim(),
    ],
  );
}

/// Stack proposal; decisions in [fixed] keep the user's choice.
StackPlan parseStackResult(Result r, {List<StackDecision> fixed = const []}) {
  final proposed = StackPlan.fromJson(_map(r));
  if (proposed.decisions.isEmpty) {
    throw const PlannerException('O planner não propôs nenhuma tecnologia.');
  }
  final byArea = {for (final d in fixed) d.area.toLowerCase(): d};
  final seen = <String>{};
  return proposed.copyWith(
    decisions: [
      for (final d in proposed.decisions)
        if (seen.add(d.area.toLowerCase())) byArea[d.area.toLowerCase()] ?? d,
      // Fixed choices the planner left out (e.g. renamed area) are kept.
      for (final d in fixed)
        if (!seen.contains(d.area.toLowerCase())) d,
    ],
    claudeMdStale: false,
  );
}

/// Roadmap ([Roadmap.normalized]).
Roadmap parseRoadmapResult(Result r) {
  final roadmap = Roadmap.fromJson(_map(r)).normalized();
  if (!roadmap.isReady) {
    throw const PlannerException('O planner não gerou nenhuma spec.');
  }
  return roadmap;
}

/// What the planner is doing for a workspace (null = idle).
@immutable
class PlannerActivity {
  const PlannerActivity({this.busy, this.error});

  /// "Pensando…", "Propondo a stack…" while a run is in flight.
  final String? busy;

  /// Last failure of a stack / roadmap run (Visão errors go to the chat).
  final String? error;

  bool get isBusy => busy != null;
}

/// Runs the planner and stores its output in `project_plans`, per workspace.
class ProjectPlanner extends Notifier<Map<int, PlannerActivity>> {
  @override
  Map<int, PlannerActivity> build() => const {};

  static const budgetUsd = 0.5;
  static const roadmapBudgetUsd = 1.0;

  ClaudeOptions _options(
    String systemPrompt,
    Map<String, Object?> schema, {
    double budget = budgetUsd,
    String? sessionId,
    String? resumeId,
  }) => ClaudeOptions(
    sessionId: sessionId,
    resumeId: resumeId,
    permissionMode: ClaudePermissionMode.defaultMode,
    disallowedTools: ClaudeCodeProvider.readOnlyDisallowedTools,
    appendSystemPrompt: systemPrompt,
    jsonSchema: jsonEncode(schema),
    maxBudgetUsd: budget,
    includePartialMessages: false,
  );

  void _set(int ws, PlannerActivity? a) {
    final next = Map.of(state);
    if (a == null) {
      next.remove(ws);
    } else {
      next[ws] = a;
    }
    state = next;
  }

  Future<(ProjectPlan, ProjectPlanData)> _load(Workspace ws) async {
    final row = await ref.read(projectPlansRepoProvider).start(ws.id);
    return (row, ProjectPlanData.decode(row.data));
  }

  Future<void> _save(Workspace ws, ProjectPlanData data, {String? sid}) => ref
      .read(projectPlansRepoProvider)
      .update(
        ws.id,
        ProjectPlansCompanion(
          data: Value(data.encode()),
          plannerSessionId: sid == null ? const Value.absent() : Value(sid),
        ),
      );

  Future<Result> _run(
    Workspace ws,
    ClaudeOptions options,
    String prompt,
  ) async {
    final r = await runReadOnlyClaude(
      ref,
      cwd: ws.path,
      options: options,
      prompt: prompt,
    );
    await ref.read(projectPlansRepoProvider).addCost(ws.id, r.totalCostUsd);
    return r;
  }

  /// One Visão turn: stores [text], asks the planner and stores its answer
  /// and the updated vision. Failures become a red message in the chat.
  Future<void> sendVision(Workspace ws, String text) async {
    final msg = text.trim();
    if (msg.isEmpty || (state[ws.id]?.isBusy ?? false)) return;
    _set(ws.id, const PlannerActivity(busy: 'Pensando…'));
    try {
      var (row, data) = await _load(ws);
      data = data.copyWith(
        messages: [
          ...data.messages,
          PlanMessage(fromUser: true, text: msg),
        ],
      );
      await _save(ws, data);
      final resume = row.plannerSessionId;
      final sid = resume ?? ref.read(sessionIdGeneratorProvider)();
      try {
        final r = await _run(
          ws,
          _options(
            visionSystemPrompt,
            visionSchema,
            sessionId: resume == null ? sid : null,
            resumeId: resume,
          ),
          msg,
        );
        final out = parseVisionResult(r);
        data = data.copyWith(
          vision: out.plan,
          messages: [
            ...data.messages,
            PlanMessage(
              fromUser: false,
              text: out.reply.isEmpty ? 'Plano atualizado.' : out.reply,
              suggestions: out.suggestions,
              note: visionChanges(data.vision, out.plan),
            ),
          ],
        );
        await _save(ws, data, sid: sid);
      } on PlannerException catch (e) {
        await _save(
          ws,
          data.copyWith(
            messages: [
              ...data.messages,
              PlanMessage(fromUser: false, text: e.message, error: true),
            ],
          ),
        );
      }
    } finally {
      _set(ws.id, null);
    }
  }

  /// Stack proposal. [keepChoices] = every current choice is fixed (only
  /// the CLAUDE.md is redone); otherwise only the user's picks are.
  Future<void> proposeStack(
    Workspace ws, {
    bool keepChoices = false,
    String? request,
  }) => _guarded(
    ws,
    keepChoices ? 'Atualizando o CLAUDE.md…' : 'Propondo a stack…',
    () async {
      final (_, data) = await _load(ws);
      final fixed = [
        for (final d in data.stack.decisions)
          if (keepChoices || d.pinned) d,
      ];
      final r = await _run(
        ws,
        _options(stackSystemPrompt, stackSchema),
        stackPrompt(data.vision, fixed: fixed, request: request),
      );
      final stack = parseStackResult(r, fixed: fixed);
      final (_, latest) = await _load(ws);
      await _save(ws, latest.copyWith(stack: stack));
    },
  );

  /// Roadmap of specs (replaces the previous one).
  Future<void> planRoadmap(Workspace ws, {String? request}) => _guarded(
    ws,
    'Montando o roadmap…',
    () async {
      final (_, data) = await _load(ws);
      final r = await _run(
        ws,
        _options(roadmapSystemPrompt, roadmapSchema, budget: roadmapBudgetUsd),
        roadmapPrompt(data.vision, data.stack, request: request),
      );
      final roadmap = parseRoadmapResult(r);
      final (_, latest) = await _load(ws);
      await _save(ws, latest.copyWith(roadmap: roadmap));
    },
  );

  /// Turns a "Depois" idea into a spec written by the planner.
  Future<void> planIdea(Workspace ws, String idea, RoadmapPhase phase) =>
      _guarded(ws, 'Planejando “$idea”…', () async {
        final (_, data) = await _load(ws);
        final r = await _run(
          ws,
          _options(ideaSystemPrompt, ideaSpecSchema),
          ideaPrompt(idea, phase, data),
        );
        final m = _map(r);
        final spec = m['spec'] is Map
            ? RoadmapSpec.fromJson(m['spec'] as Map)
            : null;
        if (spec == null || spec.title.isEmpty || spec.requirements.isEmpty) {
          throw const PlannerException(
            'O planner não gerou a spec com requisitos.',
          );
        }
        final (_, latest) = await _load(ws);
        await _save(
          ws,
          latest.copyWith(
            roadmap: addIdeaSpec(
              latest.roadmap,
              spec.copyWith(phase: phase),
              idea,
            ),
          ),
        );
      });

  /// Turns a "Depois" idea into an empty spec (requirements by hand).
  Future<void> ideaToSpec(Workspace ws, String idea, RoadmapPhase phase) =>
      editRoadmap(
        ws,
        (r) => r.copyWith(
          specs: [
            ...r.specs,
            RoadmapSpec(code: r.nextSpecCode(), title: idea, phase: phase),
          ],
          later: [
            for (final l in r.later)
              if (l != idea) l,
          ],
        ),
      );

  Future<void> removeIdea(Workspace ws, String idea) => editRoadmap(
    ws,
    (r) => r.copyWith(
      later: [
        for (final l in r.later)
          if (l != idea) l,
      ],
    ),
  );

  Future<void> _guarded(
    Workspace ws,
    String label,
    Future<void> Function() job,
  ) async {
    if (state[ws.id]?.isBusy ?? false) return;
    _set(ws.id, PlannerActivity(busy: label));
    try {
      await job();
      _set(ws.id, null);
    } on PlannerException catch (e) {
      _set(ws.id, PlannerActivity(error: e.message));
    } catch (e) {
      _set(ws.id, PlannerActivity(error: '$e'));
    }
  }

  void clearError(int workspaceId) {
    if (state[workspaceId]?.error != null) _set(workspaceId, null);
  }

  // --- edits that do not call the planner -----------------------------------

  Future<void> _edit(
    Workspace ws,
    ProjectPlanData Function(ProjectPlanData) change,
  ) async {
    final (_, data) = await _load(ws);
    await _save(ws, change(data));
  }

  /// Picks an alternative of a stack decision (the CLAUDE.md goes stale).
  Future<void> chooseStack(Workspace ws, String area, String option) =>
      _edit(ws, (d) {
        final decisions = [
          for (final x in d.stack.decisions)
            x.area == area ? x.choose(option) : x,
        ];
        return d.copyWith(
          stack: d.stack.copyWith(
            decisions: decisions,
            claudeMdStale: d.stack.claudeMd.isNotEmpty,
          ),
        );
      });

  Future<void> editClaudeMd(Workspace ws, String text) =>
      _edit(ws, (d) => d.copyWith(stack: d.stack.copyWith(claudeMd: text)));

  /// A change made by hand in the Roadmap step; the result is
  /// [Roadmap.normalized] (same rules as the planner output) and marked as
  /// edited.
  Future<void> editRoadmap(Workspace ws, Roadmap Function(Roadmap) change) =>
      _edit(
        ws,
        (d) => d.copyWith(
          roadmap: change(d.roadmap).normalized().copyWith(edited: true),
        ),
      );

  Future<void> goTo(Workspace ws, ProjectStep step) => ref
      .read(projectPlansRepoProvider)
      .update(ws.id, ProjectPlansCompanion(step: Value(step.name)));

  /// Starts planning [ws] (creates the empty plan).
  Future<void> start(Workspace ws) =>
      ref.read(projectPlansRepoProvider).start(ws.id);

  /// Discards the plan (files, specs and tasks already created stay).
  Future<void> discard(Workspace ws) =>
      ref.read(projectPlansRepoProvider).delete(ws.id);
}

final projectPlannerProvider =
    NotifierProvider<ProjectPlanner, Map<int, PlannerActivity>>(
      ProjectPlanner.new,
    );
