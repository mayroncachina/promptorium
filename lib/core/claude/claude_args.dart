import 'package:flutter/foundation.dart';

/// Permission modes accepted by the app (plano, Fase 0.2).
///
/// [skipPermissions] is an opt-in exception to anti-padrão 0.5, chosen per
/// session by the user ("sem perguntar"): it is written as
/// `--dangerously-skip-permissions` (stored as `bypassPermissions`). The
/// planner, the Prompt conversations and the probes never use it.
enum ClaudePermissionMode {
  defaultMode('default'),
  acceptEdits('acceptEdits'),
  plan('plan'),
  auto('auto'),
  dontAsk('dontAsk'),
  skipPermissions('bypassPermissions');

  const ClaudePermissionMode(this.cliValue);

  /// Value passed to `--permission-mode`.
  final String cliValue;

  static ClaudePermissionMode? fromCli(String? value) {
    for (final m in values) {
      if (m.cliValue == value) return m;
    }
    return null;
  }
}

/// Immutable options of one `claude -p` stream-json session.
///
/// [toArgs] only emits flags listed in plano, Fase 0.2. The base flags
/// `-p --input-format stream-json --output-format stream-json --verbose
/// --permission-prompt-tool stdio` are always present.
@immutable
class ClaudeOptions {
  const ClaudeOptions({
    this.sessionId,
    this.resumeId,
    this.forkSession = false,
    this.model,
    this.agent,
    this.permissionMode,
    this.allowedTools = const [],
    this.disallowedTools = const [],
    this.appendSystemPrompt,
    this.mcpConfigs = const [],
    this.strictMcpConfig = false,
    this.agentsJson,
    this.maxBudgetUsd,
    this.maxTurns,
    this.jsonSchema,
    this.includePartialMessages = true,
    this.effort,
    this.autocompact,
    this.settingsFile,
    this.tools = const [],
  });

  /// New session id (`--session-id`, must be a UUID). Exclusive with
  /// [resumeId], except with [forkSession] (then it is the fork's id —
  /// verified on CLI 2.1.300, plano Fase 5).
  final String? sessionId;

  /// Session to resume (`--resume`).
  final String? resumeId;

  /// With [resumeId]: continue under a new id (`--fork-session`).
  final bool forkSession;

  /// `opus`, `sonnet`, `haiku`, `fable`, `inherit` or a full model id.
  final String? model;

  /// `--agent <name>`: runs the main thread as that subagent (its prompt,
  /// tools and model). Listed in `claude --help` 2.1.300; see plano Fase 5.
  final String? agent;
  final ClaudePermissionMode? permissionMode;

  /// Permission rules, e.g. `Read`, `Bash(git *)`, `mcp__srv__tool`.
  final List<String> allowedTools;
  final List<String> disallowedTools;
  final String? appendSystemPrompt;

  /// Files or JSON strings for `--mcp-config`.
  final List<String> mcpConfigs;
  final bool strictMcpConfig;

  /// JSON (or file path) for `--agents`.
  final String? agentsJson;
  final double? maxBudgetUsd;
  final int? maxTurns;

  /// `--json-schema <schema>`: structured output. Verified on CLI 2.1.300
  /// (plano, Fase 8): the model answers through a `StructuredOutput` tool and
  /// the `result` event carries the object in `structured_output` (and the
  /// same JSON as a string in `result`).
  final String? jsonSchema;

  /// `--include-partial-messages` (live `stream_event` deltas).
  final bool includePartialMessages;

  /// `--effort <level>` ([effortLevels]); null or empty = CLI default.
  /// An unknown value only makes the CLI warn and use its default (2.1.301).
  final String? effort;

  /// `--autocompact <auto|tokens>`: context size that triggers the automatic
  /// compaction (`auto`, or 100k–1M as `200k` / `200000`; 2.1.301 rejects
  /// smaller values before starting). Null or empty = CLI default.
  final String? autocompact;

  /// `--settings <file>`: settings added to the user's / project's ones
  /// (the app's managed hooks). Verified on CLI 2.1.302: hooks of every
  /// source run (docs/pesquisa/hooks-settings-stream-json.md).
  final String? settingsFile;

  /// `--tools a,b,c`: the only built-in tools available (an allow list).
  /// Verified on CLI 2.1.302: `system/init.tools` lists only them and the
  /// model says the others do not exist (docs/pesquisa/
  /// hooks-settings-stream-json.md §4). Empty = every tool.
  final List<String> tools;

  /// Values accepted by `--effort` (CLI 2.1.301).
  static const effortLevels = ['low', 'medium', 'high', 'xhigh', 'max'];

  static const baseArgs = [
    '-p',
    '--input-format',
    'stream-json',
    '--output-format',
    'stream-json',
    '--verbose',
    '--permission-prompt-tool',
    'stdio',
  ];

  ClaudeOptions copyWith({
    String? sessionId,
    String? resumeId,
    bool? forkSession,
    String? model,
    String? agent,
    ClaudePermissionMode? permissionMode,
    List<String>? allowedTools,
    List<String>? disallowedTools,
    String? appendSystemPrompt,
    List<String>? mcpConfigs,
    bool? strictMcpConfig,
    String? agentsJson,
    double? maxBudgetUsd,
    int? maxTurns,
    String? jsonSchema,
    bool? includePartialMessages,
    String? effort,
    String? autocompact,
    String? settingsFile,
    List<String>? tools,
  }) => ClaudeOptions(
    sessionId: sessionId ?? this.sessionId,
    resumeId: resumeId ?? this.resumeId,
    forkSession: forkSession ?? this.forkSession,
    model: model ?? this.model,
    agent: agent ?? this.agent,
    permissionMode: permissionMode ?? this.permissionMode,
    allowedTools: allowedTools ?? this.allowedTools,
    disallowedTools: disallowedTools ?? this.disallowedTools,
    appendSystemPrompt: appendSystemPrompt ?? this.appendSystemPrompt,
    mcpConfigs: mcpConfigs ?? this.mcpConfigs,
    strictMcpConfig: strictMcpConfig ?? this.strictMcpConfig,
    agentsJson: agentsJson ?? this.agentsJson,
    maxBudgetUsd: maxBudgetUsd ?? this.maxBudgetUsd,
    maxTurns: maxTurns ?? this.maxTurns,
    jsonSchema: jsonSchema ?? this.jsonSchema,
    includePartialMessages:
        includePartialMessages ?? this.includePartialMessages,
    effort: effort ?? this.effort,
    autocompact: autocompact ?? this.autocompact,
    settingsFile: settingsFile ?? this.settingsFile,
    tools: tools ?? this.tools,
  );

  /// Command-line arguments (without the executable).
  ///
  /// Throws [ArgumentError] for contradictory options.
  List<String> toArgs() {
    if (sessionId != null && resumeId != null && !forkSession) {
      throw ArgumentError(
        'Use sessionId (nova sessão) OU resumeId, não ambos '
        '(exceto com forkSession).',
      );
    }
    if (forkSession && resumeId == null) {
      throw ArgumentError('forkSession exige resumeId.');
    }
    if (maxTurns != null && maxTurns! < 1) {
      throw ArgumentError.value(maxTurns, 'maxTurns', 'deve ser ≥ 1');
    }
    if (maxBudgetUsd != null && maxBudgetUsd! <= 0) {
      throw ArgumentError.value(maxBudgetUsd, 'maxBudgetUsd', 'deve ser > 0');
    }
    return [
      ...baseArgs,
      if (includePartialMessages) '--include-partial-messages',
      if (sessionId != null) ...['--session-id', sessionId!],
      if (resumeId != null) ...['--resume', resumeId!],
      if (forkSession) '--fork-session',
      if (model != null && model!.isNotEmpty) ...['--model', model!],
      if (agent != null && agent!.isNotEmpty) ...['--agent', agent!],
      if (effort != null && effort!.isNotEmpty) ...['--effort', effort!],
      if (autocompact != null && autocompact!.isNotEmpty) ...[
        '--autocompact',
        autocompact!,
      ],
      if (permissionMode == ClaudePermissionMode.skipPermissions)
        '--dangerously-skip-permissions'
      else if (permissionMode != null) ...[
        '--permission-mode',
        permissionMode!.cliValue,
      ],
      if (appendSystemPrompt != null && appendSystemPrompt!.isNotEmpty) ...[
        '--append-system-prompt',
        appendSystemPrompt!,
      ],
      for (final c in mcpConfigs) ...['--mcp-config', c],
      if (strictMcpConfig) '--strict-mcp-config',
      if (agentsJson != null && agentsJson!.isNotEmpty) ...[
        '--agents',
        agentsJson!,
      ],
      if (tools.isNotEmpty) ...['--tools', tools.join(',')],
      if (settingsFile != null && settingsFile!.isNotEmpty) ...[
        '--settings',
        settingsFile!,
      ],
      if (maxBudgetUsd != null) ...['--max-budget-usd', _num(maxBudgetUsd!)],
      if (maxTurns != null) ...['--max-turns', '$maxTurns'],
      if (jsonSchema != null && jsonSchema!.isNotEmpty) ...[
        '--json-schema',
        jsonSchema!,
      ],
      // Variadic flags: one value per argv entry (values may contain spaces).
      if (allowedTools.isNotEmpty) ...['--allowedTools', ...allowedTools],
      if (disallowedTools.isNotEmpty) ...[
        '--disallowedTools',
        ...disallowedTools,
      ],
    ];
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}
