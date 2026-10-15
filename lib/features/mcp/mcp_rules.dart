import 'package:flutter/foundation.dart';

import '../../data/db/app_database.dart' show McpToolRule;
import '../../data/db/enums.dart';
import '../../data/repos/mcp_tool_rules_repo.dart';

/// Server segment of a tool id as the CLI builds it: characters outside
/// `[A-Za-z0-9_-]` become `_` (e.g. `claude.ai Docs` → `claude_ai_Docs`).
String mcpServerKey(String serverName) =>
    serverName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

/// `mcp__<server>__<tool>` (permission rule / tool name in `system/init`).
String mcpToolId(String server, String tool) =>
    'mcp__${mcpServerKey(server)}__$tool';

/// Splits `mcp__<server>__<tool>`. [knownServers] (server keys) resolve
/// names that contain `__`; the longest matching prefix wins, else the
/// first `__` after `mcp__` separates. Null for non-MCP names.
({String server, String tool})? splitMcpToolId(
  String id, [
  Iterable<String> knownServers = const [],
]) {
  if (!id.startsWith('mcp__')) return null;
  final rest = id.substring(5);
  String? best;
  for (final s in knownServers) {
    final k = mcpServerKey(s);
    if (rest.startsWith('${k}__') &&
        rest.length > k.length + 2 &&
        (best == null || k.length > best.length)) {
      best = k;
    }
  }
  if (best != null) {
    return (server: best, tool: rest.substring(best.length + 2));
  }
  final i = rest.indexOf('__');
  if (i <= 0 || i + 2 >= rest.length) return null;
  return (server: rest.substring(0, i), tool: rest.substring(i + 2));
}

/// Permission flags derived from `mcp_tool_rules`.
@immutable
class McpRuleArgs {
  const McpRuleArgs({this.allowed = const [], this.disallowed = const []});

  static const empty = McpRuleArgs();

  /// "Permitido" → `--allowedTools mcp__srv__tool` (auto-approved).
  final List<String> allowed;

  /// "Bloqueado" → `--disallowedTools mcp__srv__tool` (removed from
  /// `system/init.tools`, verified on 2.1.300).
  final List<String> disallowed;
}

/// Rules → flags. "Pedir aprovação" adds nothing (the default asks via
/// `--permission-prompt-tool stdio`). [ignoreAllow]: read-only modes
/// (Prompt "Perguntar" and the internal "Refinar") never auto-approve an MCP
/// tool — it could write — so "Permitido" keeps asking there; "Bloqueado"
/// is always respected.
McpRuleArgs mcpRuleArgs(
  Iterable<McpToolRule> rules, {
  bool ignoreAllow = false,
}) {
  final allowed = <String>[], disallowed = <String>[];
  for (final r in rules) {
    final id = mcpToolId(r.server, r.tool);
    switch (r.rule) {
      case McpRule.allow:
        if (!ignoreAllow) allowed.add(id);
      case McpRule.block:
        disallowed.add(id);
      case McpRule.ask:
        break;
    }
  }
  allowed.sort();
  disallowed.sort();
  return McpRuleArgs(allowed: allowed, disallowed: disallowed);
}

/// Reads every rule; errors = no rules (sessions still start).
Future<McpRuleArgs> readMcpRuleArgs(
  McpToolRulesRepo repo, {
  bool ignoreAllow = false,
}) async {
  try {
    return mcpRuleArgs(await repo.getAll(), ignoreAllow: ignoreAllow);
  } catch (e) {
    debugPrint('regras MCP não lidas — $e');
    return McpRuleArgs.empty;
  }
}
