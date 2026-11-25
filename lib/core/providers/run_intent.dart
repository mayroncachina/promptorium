import 'package:flutter/foundation.dart';

import '../claude/claude_args.dart';
import 'capabilities.dart';

/// Access intent of one run (SPEC-094 R4, R7): the app's own modes, which
/// each adapter translates to its permission policy.
enum AgentAccess {
  /// Perguntar: read-only, enforced by the runtime.
  ask,

  /// Planejar: read-only, proposes a plan.
  plan,

  /// Editar: writes with confirmation.
  edit,

  /// Refinar: every edit or command asks for approval.
  refine,

  /// YOLO: no approvals, no sandbox. Worktree only.
  yolo;

  bool get readOnly => this == ask || this == plan;

  /// Legacy session mode stored in `sessions.permissionMode`. `auto` and
  /// `dontAsk` are Claude-only and have no app access (null).
  static AgentAccess? fromClaudeMode(ClaudePermissionMode? mode) =>
      switch (mode) {
        null || ClaudePermissionMode.defaultMode => refine,
        ClaudePermissionMode.acceptEdits => edit,
        ClaudePermissionMode.plan => plan,
        ClaudePermissionMode.skipPermissions => yolo,
        ClaudePermissionMode.auto || ClaudePermissionMode.dontAsk => null,
      };

  /// Legacy mode reported in the `system/init` of non-Claude runs.
  ClaudePermissionMode get legacyMode => switch (this) {
    ask || plan => ClaudePermissionMode.plan,
    edit => ClaudePermissionMode.acceptEdits,
    refine => ClaudePermissionMode.defaultMode,
    yolo => ClaudePermissionMode.skipPermissions,
  };
}

/// Options that belong to one provider (R4). Delivering extras of one
/// provider to another adapter is a programming error (R6).
@immutable
sealed class ProviderExtras {
  const ProviderExtras();

  /// Provider id these extras belong to.
  String get providerId;
}

/// Claude Code only: budget, turns, agents, settings, tools and MCP rules.
@immutable
class ClaudeExtras extends ProviderExtras {
  const ClaudeExtras({
    this.maxBudgetUsd,
    this.maxTurns,
    this.agent,
    this.agentsJson,
    this.settingsFile,
    this.tools = const [],
    this.mcpConfigs = const [],
    this.strictMcpConfig = false,
    this.mcpAllowedTools = const [],
    this.mcpDisallowedTools = const [],
    this.autocompact,
    this.permissionMode,
  });

  @override
  String get providerId => 'claude';

  final double? maxBudgetUsd;
  final int? maxTurns;
  final String? agent;
  final String? agentsJson;
  final String? settingsFile;
  final List<String> tools;

  /// `--mcp-config` files (the app's own server included).
  final List<String> mcpConfigs;
  final bool strictMcpConfig;

  /// MCP tools marked "Permitido" (`mcp__srv__tool`, Fase 11). Ignored by
  /// the read-only modes ([AgentAccess.ask], [AgentAccess.refine]).
  final List<String> mcpAllowedTools;

  /// MCP tools marked "Bloqueado" (always applied).
  final List<String> mcpDisallowedTools;

  /// `--autocompact` (null = provider default).
  final String? autocompact;

  /// Exact `--permission-mode` (sessions); null = from the access intent.
  final ClaudePermissionMode? permissionMode;

  bool get isEmpty =>
      maxBudgetUsd == null &&
      maxTurns == null &&
      agent == null &&
      agentsJson == null &&
      settingsFile == null &&
      tools.isEmpty &&
      mcpConfigs.isEmpty &&
      !strictMcpConfig &&
      mcpAllowedTools.isEmpty &&
      mcpDisallowedTools.isEmpty &&
      autocompact == null &&
      permissionMode == null;
}

/// Codex only: policy overrides, extra writable roots, `-c` overrides and
/// the compaction limit.
@immutable
class CodexExtras extends ProviderExtras {
  const CodexExtras({
    this.sandbox,
    this.approval,
    this.writableRoots = const [],
    this.configOverrides = const {},
    this.compactLimit,
    this.mcpDisallowedTools = const [],
  });

  @override
  String get providerId => 'codex';

  /// Overrides the sandbox of the access policy (`read-only`, …).
  final String? sandbox;

  /// Overrides the approval of the access policy (`never`, `on-request`).
  final String? approval;
  final List<String> writableRoots;

  /// `-c key=value` of `codex app-server`.
  final Map<String, String> configOverrides;

  /// `model_auto_compact_token_limit` (`200k`, `1m`, raw number).
  final String? compactLimit;

  /// "Bloqueado" MCP rules (`mcp__srv__tool`): `disabled_tools` of each
  /// server by override of the run (SPEC-105 R9).
  final List<String> mcpDisallowedTools;
}

/// The extras of the provider [caps] describes, built only with what it
/// supports (R5): no budget without `budgetUsd`, no agent without
/// `agentFiles`, no MCP rules without `mcpConfig`. Other providers get
/// none — services never hand one provider's extras to another.
ProviderExtras? extrasFor(
  ProviderCapabilities caps, {
  ClaudeExtras? claude,
  CodexExtras? codex,
}) {
  if (claude != null && caps.providerId == claude.providerId) {
    bool has(ProviderCapability c) => caps.supports(c);
    return ClaudeExtras(
      maxBudgetUsd: has(ProviderCapability.budgetUsd)
          ? claude.maxBudgetUsd
          : null,
      maxTurns: has(ProviderCapability.maxTurns) ? claude.maxTurns : null,
      agent: has(ProviderCapability.agentFiles) ? claude.agent : null,
      agentsJson: has(ProviderCapability.subagents) ? claude.agentsJson : null,
      settingsFile: has(ProviderCapability.managedHooks)
          ? claude.settingsFile
          : null,
      tools: claude.tools,
      mcpConfigs: has(ProviderCapability.mcpConfig)
          ? claude.mcpConfigs
          : const [],
      strictMcpConfig: claude.strictMcpConfig,
      mcpAllowedTools: has(ProviderCapability.mcpConfig)
          ? claude.mcpAllowedTools
          : const [],
      mcpDisallowedTools: has(ProviderCapability.mcpConfig)
          ? claude.mcpDisallowedTools
          : const [],
      autocompact: claude.autocompact,
      permissionMode: claude.permissionMode,
    );
  }
  if (codex != null && caps.providerId == codex.providerId) return codex;
  return null;
}

/// Throws when [extras] belong to another provider than [providerId]:
/// a programming error, never a user setting (R6).
void checkExtras(String providerId, ProviderExtras? extras) {
  if (extras != null && extras.providerId != providerId) {
    throw ArgumentError.value(
      extras.runtimeType,
      'extras',
      'opções de ${extras.providerId} entregues ao adaptador $providerId '
          '(SPEC-094 R6)',
    );
  }
}
