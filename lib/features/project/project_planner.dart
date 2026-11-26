import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_event.dart';
import '../../data/providers.dart';
import '../sessions/session_manager.dart' show sessionIdGeneratorProvider;
import '../../core/providers/structured_run.dart';
import 'cost_estimate.dart';
import 'project_plan.dart';
import 'project_templates.dart' show CustomStack, templateClaudeMd;

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
  // The commands of the CLAUDE.md, for the config.yml (SPEC-072 R11).
  'commands': _object({for (final k in StackCommands.keys) k: _str}),
});

/// The "Outro…" modal (SPEC-072 R17): the stack schema plus a short name
/// and the skeleton command.
final customStackSchema = _object({
  'name': _str,
  ...(stackSchema['properties'] as Map<String, Object?>),
  'scaffold': _str,
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
    'exatamente as escolhas indicadas como fixadas. Em claudeMd, escreva as '
    'instruções do projeto em Markdown, que vão para o AGENTS.md (o Codex o '
    'lê, e o CLAUDE.md o importa com @AGENTS.md para o Claude Code): título '
    'e resumo, stack, comandos '
    '(instalar, rodar, testar, lint — os que a stack terá) e convenções de '
    'código e de commits. Seja conciso: ele é lido no início de toda sessão '
    'de agente. Em commands, os mesmos comandos que as instruções listam, para '
    'o .promptorium/config.yml: install (dependências; protegido pela '
    'existência do manifesto, porque o projeto começa vazio, ex.: '
    '"test ! -f pubspec.yaml || flutter pub get"), run (roda o app), dev '
    '(servidor de desenvolvimento), test, lint e format (formata um arquivo; '
    'use {arquivo} no lugar do caminho). Texto vazio quando o comando não se '
    'aplica (ex.: dev num app de desktop). Mantenha exatamente os comandos '
    'indicados como fixados.';

/// The "Outro…" modal: a stack from a free description (SPEC-072 R17).
const customStackSystemPrompt =
    '$_base Defina a stack de um projeto novo a partir da descrição do '
    'usuário, que é a fonte da verdade: não troque o que ele pediu. Em name, '
    'um nome curto da stack para um botão (ex.: "Go · Fiber"). Em decisions, '
    'uma entrada por área relevante (Linguagem, Framework, Banco, '
    'Migrations, Testes…) com choice, why (uma frase) e até 2 alternatives. '
    'Em commands: install (dependências, protegido pela existência do '
    'manifesto, porque o projeto começa vazio, ex.: "test ! -f go.mod || go '
    'mod download"), run, dev, test, lint e format (formata um arquivo, com '
    '{arquivo} no lugar do caminho); texto vazio quando não se aplica. Em '
    'scaffold, o comando que cria o esqueleto do projeto (vazio se não '
    'houver). Em claudeMd, instruções base concisas em Markdown (vão para o '
    'AGENTS.md, que o CLAUDE.md importa): título, '
    'stack, uma seção "## Comandos" com os comandos e o scaffold, e '
    'convenções de código e de commits. Num pedido de ajuste, devolva a '
    'proposta COMPLETA atualizada.';

/// User message of the "Outro…" modal: the description, or an adjustment
/// of the same conversation.
String customStackPrompt(String text, {bool adjust = false}) => adjust
    ? 'Ajuste pedido: ${text.trim()}'
    : 'Descrição da stack: ${text.trim()}';

const roadmapSystemPrompt =
    '$_base Etapa Roadmap: transforme a visão e a stack em specs. Cada spec '
    'é uma unidade de trabalho do tamanho de um PR: uma branch, um review, um '
    'merge. Specs com phase "foundation" formam o esqueleto do projeto (criar '
    'o projeto com a stack escolhida, banco e migrations se houver, lint, '
    'testes e CI); a primeira não depende de nada. Specs com phase "mvp": '
    'uma por área funcional do MVP. Cada spec: code único em todo o roadmap '
    '(S1, S2, …), title, objective (1 ou 2 frases), requirements (ids R1, '
    'R2… dentro da spec, com text, no estilo EARS quando couber: "Quando '
    '<gatilho>, o sistema deve <resposta>"), acceptance (critérios '
    'verificáveis, cada um terminando com o requisito entre colchetes, ex.: '
    '[R2]) e '
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
    'máximo ${Roadmap.maxRequirements}; estilo EARS quando couber), '
    'acceptance (critérios verificáveis, cada um com o requisito entre '
    'colchetes, ex.: [R2]) '
    'e dependsOn (codes de specs existentes listadas — toda spec do mvp '
    'depende, direta ou indiretamente, da fundação).';

String _json(Object? v) => const JsonEncoder.withIndent('  ').convert(v);

/// User message of a stack run.
String stackPrompt(
  VisionPlan vision, {
  List<StackDecision> fixed = const [],
  String? request,
  String? baseClaudeMd,
  StackCommands commands = const StackCommands(),
}) {
  final b = StringBuffer()
    ..writeln('Visão do projeto (JSON):')
    ..writeln(_json(vision.toJson()));
  final base = baseClaudeMd?.trim();
  if (base != null && base.isNotEmpty) {
    // The template's minimal instructions (R23): the plan's replace them.
    b
      ..writeln()
      ..writeln(
        'Instruções mínimas do modelo de partida, no AGENTS.md (use como '
        'base e amplie; o seu claudeMd vai substituí-las):',
      )
      ..writeln(base);
  }
  if (fixed.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Escolhas fixadas (mantenha exatamente):');
    for (final d in fixed) {
      b.writeln('- ${d.area}: ${d.choice}');
    }
  }
  final pinned = [
    for (final k in StackCommands.keys)
      if (commands.pinned.contains(k)) k,
  ];
  if (pinned.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Comandos fixados (mantenha exatamente em commands):');
    for (final k in pinned) {
      b.writeln('- $k: ${commands[k].isEmpty ? '(vazio)' : commands[k]}');
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
  if (stack.scaffold.trim().isNotEmpty) {
    // The "Outro…" stack (SPEC-072 R18): the base of the first Fundação spec.
    b
      ..writeln()
      ..writeln(
        'Comando que cria o esqueleto (scaffold): ${stack.scaffold.trim()} '
        '— use-o como base da primeira spec da Fundação.',
      );
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

/// Stack proposal; decisions in [fixed] keep the user's choice, and the
/// pinned commands of [commands] stay as they are (SPEC-072 R11).
StackPlan parseStackResult(
  Result r, {
  List<StackDecision> fixed = const [],
  StackCommands commands = const StackCommands(),
}) {
  final proposed = StackPlan.fromJson(_map(r));
  if (proposed.decisions.isEmpty) {
    throw const PlannerException('O planner não propôs nenhuma tecnologia.');
  }
  // A fixed choice matches the planner's by area, synonyms included
  // ("App" / "Aplicação"), or by the same technology under another area
  // name: either way it is one decision, not two (SPEC-071 R26).
  final byArea = {for (final d in fixed) stackAreaKey(d.area): d};
  final byChoice = {
    for (final d in fixed)
      if (d.choice.trim().isNotEmpty) d.choice.trim().toLowerCase(): d,
  };
  final seen = <String>{};
  final decisions = <StackDecision>[];
  for (final d in proposed.decisions) {
    final f =
        byArea[stackAreaKey(d.area)] ?? byChoice[d.choice.trim().toLowerCase()];
    if (seen.add(stackAreaKey((f ?? d).area))) decisions.add(f ?? d);
  }
  // Fixed choices the planner left out are kept.
  for (final d in fixed) {
    if (seen.add(stackAreaKey(d.area))) decisions.add(d);
  }
  var cmds = proposed.commands;
  for (final k in commands.pinned) {
    cmds = cmds.withValue(k, commands[k], pin: true);
  }
  return proposed.copyWith(
    decisions: decisions,
    claudeMdStale: false,
    commands: cmds,
  );
}

/// The answer of the "Outro…" modal (SPEC-072 R17).
CustomStack parseCustomStackResult(Result r) {
  final m = _map(r);
  final stack = StackPlan.fromJson(m);
  final name = m['name'] is String ? (m['name'] as String).trim() : '';
  if (stack.decisions.isEmpty || name.isEmpty) {
    throw const PlannerException('O Claude não propôs uma stack.');
  }
  return CustomStack(
    name: name,
    decisions: stack.decisions,
    commands: stack.commands,
    scaffold: m['scaffold'] is String ? (m['scaffold'] as String).trim() : '',
    claudeMd: stack.claudeMd,
  );
}

/// Area of a stack decision, compared without case, accents and synonyms
/// ("Aplicação", "aplicativo" → "app").
String stackAreaKey(String area) {
  const plain = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e', //
    'í': 'i', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ç': 'c',
  };
  final k = area
      .trim()
      .toLowerCase()
      .split('')
      .map((ch) => plain[ch] ?? ch)
      .join();
  const synonyms = {
    'aplicacao': 'app',
    'aplicativo': 'app',
    'app mobile': 'app',
    'aplicativo mobile': 'app',
    'mobile': 'app',
    'gerenciamento de estado': 'estado',
    'gerencia de estado': 'estado',
    'state management': 'estado',
    'linguagem de programacao': 'linguagem',
    'framework web': 'web',
    'backend': 'api',
  };
  return synonyms[k] ?? k;
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
/// One planner question: what [ProjectPlanner._run] asks (SPEC-100 R1).
typedef _PlannerAsk = ({
  String instructions,
  Map<String, Object?> schema,
  double budget,
  String? sessionId,
  String? resumeId,
});

/// Slot of the Projeto's provider line (SPEC-100 R10).
String projectPlannerSlot(int workspaceId) => 'project:$workspaceId';

class ProjectPlanner extends Notifier<Map<int, PlannerActivity>> {
  @override
  Map<int, PlannerActivity> build() => const {};

  static const budgetUsd = 0.5;
  static const roadmapBudgetUsd = 1.0;

  _PlannerAsk _options(
    String systemPrompt,
    Map<String, Object?> schema, {
    double budget = budgetUsd,
    String? sessionId,
    String? resumeId,
  }) => (
    instructions: systemPrompt,
    schema: schema,
    budget: budget,
    sessionId: sessionId,
    resumeId: resumeId,
  );

  /// Workspaces running "Gerar proposta completa" ([proposeAll]).
  final _chains = <int>{};

  /// The next step of a chain may start while the chain keeps "busy".
  final _handoff = <int>{};

  /// Whether a new run must wait (consumes the chain's handoff).
  bool _busyFor(int ws) => !_handoff.remove(ws) && (state[ws]?.isBusy ?? false);

  void _set(int ws, PlannerActivity? a) {
    // Between the steps of a chain the buttons stay busy (R26).
    if (a == null && _chains.contains(ws)) {
      a = PlannerActivity(busy: state[ws]?.busy ?? 'Pensando…');
    }
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

  /// One planner call; [kind] counts it for "Planner · N chamadas"
  /// (SPEC-072 R8, R10), also when it fails.
  Future<Result> _run(
    Workspace ws,
    _PlannerAsk ask,
    String prompt, {
    required String kind,
  }) async {
    try {
      final r = await runStructured(
        ref,
        StructuredIntent(
          workspaceId: ws.id,
          cwd: ws.path,
          sessionId: ask.sessionId,
          resumeId: ask.resumeId,
          instructions: ask.instructions,
          schema: ask.schema,
          claude: ClaudeStructuredExtras(maxBudgetUsd: ask.budget),
          slot: projectPlannerSlot(ws.id),
          label: 'o planner do Projeto',
          prompt: prompt,
        ),
      );
      await ref.read(projectPlansRepoProvider).addCost(ws.id, r.costUsd ?? 0);
      return r.raw;
    } finally {
      await recordPlannerCalls(ref, ws.id, kind);
    }
  }

  /// One Visão turn: stores [text], asks the planner and stores its answer
  /// and the updated vision. Failures become a red message in the chat.
  Future<void> sendVision(Workspace ws, String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _busyFor(ws.id)) return;
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
          kind: 'visao',
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
    keepChoices ? 'Atualizando as instruções…' : 'Propondo a stack…',
    () async {
      final (_, data) = await _load(ws);
      final fixed = [
        for (final d in data.stack.decisions)
          if (keepChoices || d.pinned) d,
      ];
      // keepChoices (refresh the CLAUDE.md): the commands edited by hand
      // stay too.
      final cmds = keepChoices
          ? data.stack.commands.copyWithAllPinned()
          : data.stack.commands;
      final r = await _run(
        ws,
        _options(stackSystemPrompt, stackSchema),
        stackPrompt(
          data.vision,
          fixed: fixed,
          request: request,
          baseClaudeMd: templateClaudeMd(ws.path),
          commands: cmds,
        ),
        kind: 'stack',
      );
      var stack = parseStackResult(r, fixed: fixed, commands: cmds);
      // Edited by hand: not pinned for the next proposal.
      if (keepChoices) {
        stack = stack.copyWith(
          commands: stack.commands.withPinned(data.stack.commands.pinned),
        );
      }
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
        kind: 'roadmap',
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
          kind: 'ideia',
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
    if (_busyFor(ws.id)) return;
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

  /// Edits one command of the "Comandos" block; the CLAUDE.md goes stale
  /// (SPEC-072 R12).
  Future<void> editCommand(Workspace ws, String key, String value) =>
      _edit(ws, (d) {
        if (d.stack.commands[key] == value.trim()) return d;
        return d.copyWith(
          stack: d.stack.copyWith(
            commands: d.stack.commands.withValue(key, value),
            claudeMdStale: d.stack.claudeMd.isNotEmpty,
          ),
        );
      });

  /// "Detectar do repositório": fills the empty commands (R14).
  Future<void> fillCommands(Workspace ws, StackCommands detected) =>
      _edit(ws, (d) {
        final next = d.stack.commands.fillEmpty(detected);
        if (next == d.stack.commands) return d;
        return d.copyWith(
          stack: d.stack.copyWith(
            commands: next,
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

  /// "Gerar proposta completa" (UX v2, U7): one idea → vision, stack and
  /// roadmap in sequence, landing on "Revisar e criar". Stops at the first
  /// failure (the error is in the chat / activity as usual).
  Future<void> proposeAll(Workspace ws, String idea) async {
    if (idea.trim().isEmpty || (state[ws.id]?.isBusy ?? false)) return;
    _chains.add(ws.id);
    try {
      await sendVision(ws, idea);
      final (_, afterVision) = await _load(ws);
      if (state[ws.id]?.error != null || !afterVision.vision.isReady) return;
      _handoff.add(ws.id);
      await proposeStack(ws);
      if (state[ws.id]?.error != null) return;
      final (_, afterStack) = await _load(ws);
      if (afterStack.stack.decisions.isEmpty) return;
      _handoff.add(ws.id);
      await planRoadmap(ws);
      if (state[ws.id]?.error != null) return;
      await goTo(ws, ProjectStep.create);
    } finally {
      _chains.remove(ws.id);
      _handoff.remove(ws.id);
      if (state[ws.id]?.error == null) _set(ws.id, null);
    }
  }

  Future<void> goTo(Workspace ws, ProjectStep step) => ref
      .read(projectPlansRepoProvider)
      .update(ws.id, ProjectPlansCompanion(step: Value(step.name)));

  /// Starts planning [ws] (creates the empty plan).
  Future<void> start(Workspace ws) =>
      ref.read(projectPlansRepoProvider).start(ws.id);

  /// Discards the plan (files, specs and tasks already created stay).
  Future<void> discard(Workspace ws) async {
    await ref.read(projectPlansRepoProvider).delete(ws.id);
    await ref
        .read(appSettingsProvider.notifier)
        .remove(AppSettingKeys.plannerCalls(ws.id));
  }
}

final projectPlannerProvider =
    NotifierProvider<ProjectPlanner, Map<int, PlannerActivity>>(
      ProjectPlanner.new,
    );
