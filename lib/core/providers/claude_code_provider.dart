import '../../ui/widgets/app_icon.dart';
import '../claude/claude_args.dart';
import '../claude/claude_event.dart';
import '../claude/claude_process.dart';
import 'agent_provider.dart';

/// Claude Code CLI as an [AgentProvider] (reuses [ClaudeProcess]).
class ClaudeCodeProvider implements AgentProvider {
  ClaudeCodeProvider({this.executable = 'claude', this.starter});

  final String executable;

  /// Injected `Process.start` (tests).
  final ProcessStarter? starter;

  static const providerId = 'claude';

  /// Tools removed in the "Perguntar" mode (`--disallowedTools`, bare names
  /// remove the tool — plano 0.2). Verified on CLI 2.1.300 (plano, Fase 6):
  /// with these removed and every permission prompt auto-approved, the model
  /// could not write ("No such tool available … disabled in subagents as
  /// well"). `--permission-mode plan` alone is **not** read-only: it wrote a
  /// plan file under `~/.claude/plans` and asked for `ExitPlanMode`, whose
  /// approval leaves plan mode.
  ///
  /// `Edit`/`Write`/`NotebookEdit`/`Bash` were tested; the others are listed in
  /// `system/init.tools` of 2.1.300 and also run commands or change state
  /// (`Monitor` runs shell commands, `EnterWorktree` creates a git worktree,
  /// `Cron*`/`RemoteTrigger`/`Workflow` schedule or run work).
  static const readOnlyDisallowedTools = [
    'Edit',
    'Write',
    'NotebookEdit',
    'Bash',
    'Monitor',
    'EnterWorktree',
    'CronCreate',
    'CronDelete',
    'RemoteTrigger',
    'Workflow',
  ];

  @override
  String get id => providerId;

  @override
  String get displayName => 'Claude Code';

  @override
  AppIconData get icon => AppIcons.sparkle;

  @override
  bool get enabled => true;

  @override
  List<String> get models => const [
    'inherit',
    'opus',
    'sonnet',
    'haiku',
    'fable',
  ];

  /// Modes that never auto-approve MCP tools ("Permitido" keeps asking).
  static bool ignoresMcpAllow(PromptMode m) =>
      m == PromptMode.ask || m == PromptMode.refine;

  /// CLI options for [o] (pure; tested).
  static ClaudeOptions optionsFor(AgentStartOptions o) {
    final model = o.model == null || o.model!.isEmpty || o.model == 'inherit'
        ? null
        : o.model;
    return ClaudeOptions(
      sessionId: o.sessionId,
      resumeId: o.resumeId,
      forkSession: o.forkSession,
      model: model,
      maxBudgetUsd: o.maxBudgetUsd,
      permissionMode: switch (o.mode) {
        PromptMode.ask => ClaudePermissionMode.defaultMode,
        PromptMode.plan => ClaudePermissionMode.plan,
        PromptMode.edit => ClaudePermissionMode.acceptEdits,
        PromptMode.refine => ClaudePermissionMode.defaultMode,
      },
      // MCP rules (Fase 11): "Perguntar" / "Refinar" ignore "Permitido" (an
      // MCP tool may write; it keeps asking) and respect "Bloqueado".
      allowedTools: ignoresMcpAllow(o.mode) ? const [] : o.mcpAllowedTools,
      disallowedTools: [
        if (o.mode == PromptMode.ask) ...readOnlyDisallowedTools,
        ...o.mcpDisallowedTools,
      ],
    );
  }

  @override
  Future<AgentRun> start(AgentStartOptions options) async {
    final p = await ClaudeProcess.start(
      optionsFor(options),
      workingDirectory: options.workingDirectory,
      executable: executable,
      starter: starter,
    );
    return _ClaudeRun(p);
  }
}

class _ClaudeRun implements AgentRun {
  _ClaudeRun(this._p);

  final ClaudeProcess _p;

  @override
  Stream<ClaudeEvent> get events => _p.events;

  @override
  Stream<String> get logs => _p.logs;

  @override
  bool get isRunning => _p.isRunning;

  @override
  Future<int> get exitCode => _p.exitCode;

  @override
  List<String> get args => _p.args;

  @override
  Future<void> send(String text) => _p.send(text);

  @override
  Future<void> approve(String requestId, {List<Object?>? updatedPermissions}) =>
      _p.allow(requestId, updatedPermissions: updatedPermissions);

  @override
  Future<void> deny(String requestId, String message) =>
      _p.deny(requestId, message);

  @override
  Future<int> stop({Duration timeout = const Duration(seconds: 5)}) =>
      _p.stop(timeout: timeout);
}
