import 'package:flutter/foundation.dart';

import '../../features/agents/agent_file.dart';
import '../providers/agent_provider.dart';
import '../providers/permission_policy.dart';
import 'codex_probe.dart' show CodexModelInfo;

/// SPEC-106: a `.claude/agents` agent translated to what the Codex takes in
/// one run — instructions, model, effort and sandbox — plus what was
/// adapted and what is ignored. Pure: nothing is written anywhere (R12).

/// Claude aliases of the table "Modelos equivalentes" (R6).
const codexAgentModelAliases = ['opus', 'sonnet', 'haiku', 'fable', 'inherit'];

/// Claude efforts of the table (R6).
const codexAgentEffortLevels = ['low', 'medium', 'high', 'xhigh', 'max'];

/// Effort value "o maior do modelo" (P2).
const codexHighestEffort = '@maior';

/// Effort value "padrão do modelo".
const codexModelDefaultEffort = 'default';

String codexAgentModelKey(String alias) => 'codex.agentModel.$alias';
String codexAgentEffortKey(String level) => 'codex.agentEffort.$level';

/// "Escolher um por um" hides the suggestion of P1 for good.
const codexAgentSuggestionKey = 'codex.agentModel.suggestion';

/// Tools that may write: without them the agent runs `read-only` (R4).
/// `Bash` counts as writing (P5).
const codexWriteTools = {'Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'Bash'};

/// Tools that call subagents (R5).
const _subagentTools = {'Task', 'Agent'};

/// Known effort ranks, to find the highest one of a model (P2).
const _effortRank = [
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
  'ultra',
];

/// The table "Modelos equivalentes" (R6), as stored in `app_settings`. It
/// starts empty: no Codex model name is ever fixed in the code.
@immutable
class CodexAgentTable {
  const CodexAgentTable({this.models = const {}, this.efforts = const {}});

  factory CodexAgentTable.fromSettings(Map<String, String> settings) =>
      CodexAgentTable(
        models: {
          for (final a in codexAgentModelAliases)
            if (settings[codexAgentModelKey(a)] case final v?
                when v.isNotEmpty && v != 'inherit')
              a: v,
        },
        efforts: {
          for (final l in codexAgentEffortLevels)
            if (settings[codexAgentEffortKey(l)] case final v?
                when v.isNotEmpty)
              l: v,
        },
      );

  /// Alias → Codex model id (absent = the model of the run kind).
  final Map<String, String> models;

  /// Level → Codex effort, [codexHighestEffort] or [codexModelDefaultEffort].
  final Map<String, String> efforts;

  /// Effort of [level]: the saved one, else the same name, and the highest
  /// of the model for `xhigh` and `max` (P2).
  String effortFor(String level) =>
      efforts[level] ??
      (level == 'xhigh' || level == 'max' ? codexHighestEffort : level);
}

/// Highest effort of [efforts] (P2): by the known ranks, else the last one.
String? codexHighestOf(List<String> efforts) {
  if (efforts.isEmpty) return null;
  String? best;
  var rank = -1;
  for (final e in efforts) {
    final r = _effortRank.indexOf(e);
    if (r > rank) {
      rank = r;
      best = e;
    }
  }
  return best ?? efforts.last;
}

/// P1: models suggested by their position in `model/list` — the first for
/// `opus`, the middle one for `sonnet`, the last for `haiku`. Never applied
/// without the person's confirmation.
Map<String, String> codexSuggestedModels(List<CodexModelInfo> models) {
  if (models.isEmpty) return const {};
  final n = models.length;
  return {
    'opus': models.first.id,
    'sonnet': models[n == 2 ? 0 : n ~/ 2].id,
    'haiku': models.last.id,
  };
}

/// State of one translated field (R7).
enum CodexFieldState {
  applied('aplicado'),
  adapted('adaptado'),
  ignored('ignorado no Codex');

  const CodexFieldState(this.label);

  final String label;
}

/// One row of the "No Codex" panel: field, value in the `.md`, what the
/// Codex gets and the state.
@immutable
class CodexAgentField {
  const CodexAgentField(this.key, this.value, this.target, this.state);

  factory CodexAgentField.fromJson(Map<String, dynamic> j) => CodexAgentField(
    '${j['key']}',
    '${j['value'] ?? ''}',
    '${j['target'] ?? ''}',
    CodexFieldState.values.asNameMap()[j['state']] ?? CodexFieldState.ignored,
  );

  final String key;
  final String value;
  final String target;
  final CodexFieldState state;

  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    'target': target,
    'state': state.name,
  };

  @override
  bool operator ==(Object other) =>
      other is CodexAgentField &&
      other.key == key &&
      other.value == value &&
      other.target == target &&
      other.state == state;

  @override
  int get hashCode => Object.hash(key, value, target, state);

  @override
  String toString() => '$key: $value → $target (${state.name})';
}

/// The translation of one agent for one Codex run (R1–R5).
@immutable
class CodexAgentPlan {
  const CodexAgentPlan({
    required this.agent,
    required this.instructions,
    required this.model,
    required this.effort,
    required this.sandbox,
    required this.effectiveSandbox,
    required this.fields,
    this.warnings = const [],
  });

  /// Rebuilt from the record of a run (R11): the detail of a past run
  /// comes from here, never from the `.md` as it is now.
  static CodexAgentPlan? fromRecord(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.isEmpty) return null;
    return CodexAgentPlan(
      agent: name,
      instructions: null,
      model: '${raw['model'] ?? 'inherit'}',
      effort: raw['effort'] as String?,
      sandbox: null,
      effectiveSandbox: '${raw['sandbox'] ?? ''}',
      fields: [
        for (final f in raw['fields'] as List? ?? const [])
          if (f is Map<String, dynamic>) CodexAgentField.fromJson(f),
      ],
      warnings: [for (final w in raw['warnings'] as List? ?? const []) '$w'],
    );
  }

  final String agent;

  /// Header + body of the agent, for `developerInstructions` (R1); null =
  /// empty body.
  final String? instructions;

  /// Model to send (`inherit` = the CLI default); never an id outside
  /// `model/list` (R2).
  final String model;

  /// Effort to send; null = the model default (R3).
  final String? effort;

  /// Sandbox override (`read-only`), never above the mode (R4); null = the
  /// mode's.
  final String? sandbox;

  /// The sandbox the run ends up with, for the record.
  final String effectiveSandbox;
  final List<CodexAgentField> fields;

  /// Things the screen warns about (an effort the model lacks, a model
  /// that left the catalog).
  final List<String> warnings;

  /// Fields ignored in the Codex (R5).
  List<String> get ignored => [
    for (final f in fields)
      if (f.state == CodexFieldState.ignored) f.key,
  ];

  /// "adaptado" when something was not taken as is, else "aplicado".
  String get stateLabel => fields.any((f) => f.state != CodexFieldState.applied)
      ? 'adaptado'
      : 'aplicado';

  /// "adaptado · 2 campos ignorados" (R8).
  String get summary {
    final n = ignored.length;
    if (n == 0) return stateLabel;
    return '$stateLabel · $n ${n == 1 ? 'campo ignorado' : 'campos ignorados'}';
  }

  /// One line with the main translation (mock 3): "Instruções aplicadas ·
  /// sonnet → gpt-x · workspace-write · mcpServers e color ignorados no
  /// Codex".
  String get detail {
    final parts = <String>[];
    for (final f in fields) {
      if (f.state == CodexFieldState.ignored) continue;
      switch (f.key) {
        case 'prompt':
          parts.add('Instruções aplicadas');
        case 'model' || 'effort':
          if (f.state == CodexFieldState.adapted) {
            parts.add('${f.value} → ${f.target}');
          }
      }
    }
    parts.add(effectiveSandbox);
    final ig = ignored;
    if (ig.isNotEmpty) {
      final names = ig.length == 1
          ? ig.first
          : '${ig.sublist(0, ig.length - 1).join(', ')} e ${ig.last}';
      parts.add('$names ${ig.length == 1 ? 'ignorado' : 'ignorados'} no Codex');
    }
    return parts.join(' · ');
  }

  /// "agente `flutter-dev` · adaptado" (R11).
  String get label => '$agent · $stateLabel';

  /// What goes into the `promptorium_run` event (R11).
  Map<String, dynamic> toRecord() => {
    'v': 1,
    'name': agent,
    'state': stateLabel,
    'model': model,
    'effort': effort,
    'sandbox': effectiveSandbox,
    'ignored': ignored,
    'fields': [for (final f in fields) f.toJson()],
    if (warnings.isNotEmpty) 'warnings': warnings,
  };
}

/// Translates [agent] for a Codex run (R1–R5).
///
/// [access] is the mode chosen for the run; [runModel] and [runEffort] are
/// what the run kind would use without an agent. [catalog] is the cached
/// `model/list` (null = not read yet: no model of the table is sent).
/// [sandboxAvailable] = the OS sandbox works on this machine (decision 15).
CodexAgentPlan codexAgentPlan(
  AgentFile agent, {
  required String name,
  required AgentAccess access,
  CodexAgentTable table = const CodexAgentTable(),
  List<CodexModelInfo>? catalog,
  String runModel = 'inherit',
  String? runEffort,
  bool sandboxAvailable = true,
}) {
  final fields = <CodexAgentField>[];
  final warnings = <String>[];
  CodexModelInfo? find(String id) =>
      catalog?.where((m) => m.id == id).firstOrNull;
  String show(String model) => model == 'inherit' ? 'padrão do Codex' : model;

  // R1: the body becomes developer instructions.
  final body = agent.body.trim();
  String? instructions;
  if (body.isNotEmpty) {
    instructions = '# Agente `$name` (Promptorium)\n\n$body';
    final lines = body.split('\n').length;
    fields.add(
      CodexAgentField(
        'prompt',
        '$lines ${lines == 1 ? 'linha' : 'linhas'}',
        'developerInstructions',
        CodexFieldState.applied,
      ),
    );
  }

  // R2: the model through the table; never an id outside `model/list`.
  var model = runModel;
  final rawModel = agent.model?.trim();
  if (rawModel != null && rawModel.isNotEmpty) {
    final alias = rawModel;
    if (codexAgentModelAliases.contains(alias)) {
      final mapped = table.models[alias];
      if (mapped != null && find(mapped) != null) {
        model = mapped;
        fields.add(
          CodexAgentField('model', alias, mapped, CodexFieldState.adapted),
        );
      } else {
        if (mapped != null) {
          warnings.add(
            '$mapped saiu do model/list: $alias usa o modelo do tipo de '
            'execução.',
          );
        }
        fields.add(
          CodexAgentField(
            'model',
            alias,
            alias == 'inherit' && mapped == null
                ? 'modelo do tipo de execução'
                : 'padrão do Codex',
            alias == 'inherit' && mapped == null
                ? CodexFieldState.applied
                : CodexFieldState.adapted,
          ),
        );
      }
    } else if (find(alias) != null) {
      model = alias;
      fields.add(
        CodexAgentField('model', alias, alias, CodexFieldState.applied),
      );
    } else {
      fields.add(
        CodexAgentField(
          'model',
          alias,
          'padrão do Codex',
          CodexFieldState.adapted,
        ),
      );
    }
  }

  // R3: the effort must be in the efforts of the chosen model.
  final efforts = model == 'inherit' ? null : find(model)?.efforts;
  String? effort;
  bool offered(String? e) =>
      e != null && efforts != null && efforts.contains(e);
  final rawEffort = agent.effort?.trim();
  if (rawEffort != null && rawEffort.isNotEmpty) {
    final wanted = table.effortFor(rawEffort);
    String? target = switch (wanted) {
      codexHighestEffort => efforts == null ? null : codexHighestOf(efforts),
      codexModelDefaultEffort => null,
      _ => wanted,
    };
    if (target != null && !offered(target)) {
      warnings.add(
        'Esforço $target indisponível em ${show(model)}: vale o padrão do '
        'modelo.',
      );
      target = null;
    }
    effort = target;
    fields.add(
      CodexAgentField(
        'effort',
        rawEffort,
        target ?? 'padrão do modelo',
        target == rawEffort ? CodexFieldState.applied : CodexFieldState.adapted,
      ),
    );
    if (target == 'ultra') warnings.add('ultra gasta mais cota.');
  } else {
    final e = runEffort;
    // The run's effort goes on only when the (new) model offers it.
    effort = e == null || e == codexModelDefaultEffort
        ? null
        : model == runModel || offered(e)
        ? e
        : null;
  }

  // R4: tools only restrict, never above the mode.
  final policy = codexAccessPolicy(access);
  String base(String t) {
    final i = t.indexOf('(');
    return (i < 0 ? t : t.substring(0, i)).trim();
  }

  final tools = agent.tools;
  final denied = {for (final t in agent.disallowedTools) base(t)};
  final allowed = tools.isEmpty
      ? codexWriteTools
      : {for (final t in tools) base(t)};
  final writes = {
    for (final t in allowed)
      if (codexWriteTools.contains(t) && !denied.contains(t)) t,
  };
  final planMode = agent.permissionMode?.trim() == 'plan';
  final readOnlyAgent = writes.isEmpty || planMode;
  final modeReadOnly = policy.sandbox == 'read-only';
  String? sandbox;
  var enforced = true;
  if (readOnlyAgent && !modeReadOnly) {
    if (sandboxAvailable) {
      sandbox = 'read-only';
    } else {
      enforced = false;
      warnings.add(
        'Sem o sandbox do Codex nesta máquina, o só leitura do agente não é '
        'imposto: vale o modo da execução.',
      );
    }
  }
  final effectiveSandbox = sandbox ?? policy.sandbox;
  String modeTarget() => switch (access) {
    AgentAccess.ask || AgentAccess.plan => 'read-only (modo da execução)',
    AgentAccess.edit => '${policy.sandbox} · confirma edições',
    AgentAccess.refine => '${policy.sandbox} · cada comando pede aprovação',
    AgentAccess.yolo => '${policy.sandbox} · YOLO, só em worktree',
  };
  if (agent.has('tools') || agent.has('disallowedTools')) {
    final listed = [
      for (final t in tools)
        if (!t.startsWith('mcp__')) t,
    ];
    final value = [
      if (listed.isNotEmpty) listed.join(', ') else 'todas',
      if (denied.isNotEmpty) 'menos ${denied.join(', ')}',
    ].join(' ');
    fields.add(
      CodexAgentField(
        'tools',
        value,
        !readOnlyAgent || planMode
            ? modeTarget()
            : !enforced
            ? 'só leitura não imposta (sem sandbox) · ${modeTarget()}'
            : modeReadOnly
            ? 'read-only (modo da execução)'
            : 'só leitura · read-only',
        readOnlyAgent && !enforced
            ? CodexFieldState.ignored
            : CodexFieldState.adapted,
      ),
    );
  }
  final perm = agent.permissionMode?.trim();
  if (perm != null && perm.isNotEmpty) {
    fields.add(
      planMode
          ? CodexAgentField(
              'permissionMode',
              perm,
              !enforced
                  ? 'só leitura não imposta (sem sandbox)'
                  : 'só leitura · read-only',
              enforced ? CodexFieldState.adapted : CodexFieldState.ignored,
            )
          : CodexAgentField(
              'permissionMode',
              perm,
              'vale o modo da execução',
              CodexFieldState.ignored,
            ),
    );
  }
  final mcpTools = [
    for (final t in tools)
      if (t.startsWith('mcp__')) t,
  ];
  if (mcpTools.isNotEmpty) {
    fields.add(
      CodexAgentField(
        'tools (MCP)',
        mcpTools.join(', '),
        'não liberam nada no Codex',
        CodexFieldState.ignored,
      ),
    );
  }
  final subagents = [
    for (final t in tools)
      if (_subagentTools.contains(base(t))) base(t),
  ];
  if (subagents.isNotEmpty) {
    fields.add(
      CodexAgentField(
        'subagentes',
        subagents.toSet().join(', '),
        'a sessão principal faz o trabalho',
        CodexFieldState.ignored,
      ),
    );
  }

  // R5: what does not apply is said, and never blocks the run.
  if (agent.maxTurns case final turns?) {
    fields.add(
      CodexAgentField(
        'maxTurns',
        '$turns',
        'sem limite de turnos no Codex',
        CodexFieldState.ignored,
      ),
    );
  }
  if (agent.has('mcpServers')) {
    final names = agent.mcpServerNames;
    fields.add(
      CodexAgentField(
        'mcpServers',
        names.isEmpty ? 'definidos no arquivo' : names.join(', '),
        'servidores do Codex',
        CodexFieldState.ignored,
      ),
    );
  }
  if (agent.has('hooks')) {
    fields.add(
      const CodexAgentField(
        'hooks',
        'definidos no arquivo',
        'hooks do app (SPEC-103)',
        CodexFieldState.ignored,
      ),
    );
  }
  if (agent.color case final c? when c.isNotEmpty) {
    fields.add(
      CodexAgentField('color', c, 'só visual', CodexFieldState.ignored),
    );
  }

  return CodexAgentPlan(
    agent: name,
    instructions: instructions,
    model: model,
    effort: effort,
    sandbox: sandbox,
    effectiveSandbox: effectiveSandbox,
    fields: List.unmodifiable(fields),
    warnings: List.unmodifiable(warnings),
  );
}

/// `developerInstructions` of a run with an agent (R1): the agent first,
/// under its header, then what the app already sends.
String? codexAgentInstructions(String? agent, String? app) {
  if (agent == null) return app;
  if (app == null || app.trim().isEmpty) return agent;
  return '$agent\n\n---\n\n$app';
}

/// [o] with the plan applied (R1–R4): instructions, model, effort and the
/// sandbox override. Only by `thread/start` and `turn/start` (R12).
AgentStartOptions withCodexAgent(AgentStartOptions o, CodexAgentPlan plan) {
  final c = o.codex;
  return AgentStartOptions(
    workingDirectory: o.workingDirectory,
    mode: o.mode,
    yolo: o.yolo,
    sessionId: o.sessionId,
    resumeId: o.resumeId,
    forkSession: o.forkSession,
    model: plan.model,
    effort: plan.effort,
    appendSystemPrompt: codexAgentInstructions(
      plan.instructions,
      o.appendSystemPrompt,
    ),
    jsonSchema: o.jsonSchema,
    environment: o.environment,
    appMcpConfigs: o.appMcpConfigs,
    appAllowedTools: o.appAllowedTools,
    extras: CodexExtras(
      sandbox: plan.sandbox ?? c.sandbox,
      approval: c.approval,
      writableRoots: c.writableRoots,
      configOverrides: c.configOverrides,
      compactLimit: c.compactLimit,
    ),
  );
}
