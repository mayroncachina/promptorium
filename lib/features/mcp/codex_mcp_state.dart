import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/codex/codex_cli.dart' show codexExecutableProvider;
import '../../core/providers/provider_preferences.dart'
    show activeAgentProvider;
import '../../data/providers.dart';
import 'codex_mcp_cli.dart';
import 'mcp_cli.dart';
import 'mcp_state.dart';

/// Provider of a tab of the MCP screen (SPEC-105 R1).
enum McpProviderTab {
  claude('claude', 'Claude Code'),
  codex('codex', 'Codex');

  const McpProviderTab(this.id, this.label);

  final String id;
  final String label;

  static McpProviderTab? parse(String? id) =>
      values.where((t) => t.id == id).firstOrNull;
}

/// `app_settings` key of the tab chosen in a workspace (no migration).
String mcpProviderTabKey(int? workspaceId) =>
    'mcp.provider.workspace.${workspaceId ?? 0}';

/// Tab of the MCP screen: the one chosen in this workspace, else the
/// provider active in the footer (R1).
final mcpProviderTabProvider = Provider<McpProviderTab>((ref) {
  final ws = ref.watch(activeWorkspaceProvider);
  final saved = ref.watch(
    appSettingsProvider.select((s) => s[mcpProviderTabKey(ws?.id)]),
  );
  return McpProviderTab.parse(saved) ??
      (ref.watch(activeAgentProvider) == McpProviderTab.codex.id
          ? McpProviderTab.codex
          : McpProviderTab.claude);
});

/// Remembers the tab of the active workspace.
Future<void> selectMcpProviderTab(WidgetRef ref, McpProviderTab tab) => ref
    .read(appSettingsProvider.notifier)
    .set(mcpProviderTabKey(ref.read(activeWorkspaceProvider)?.id), tab.id);

/// Configured Codex servers (`codex mcp list --json`, R2). Invalidate after
/// add / remove.
final codexMcpListProvider =
    FutureProvider.family<List<CodexMcpServer>, String?>(
      (ref, cwd) => ref.read(codexMcpCliProvider).list(cwd),
    );

/// Status of every Codex server (`mcpServerStatus/list` with
/// `toolsAndAuthOnly`, a short App Server connection without a turn, R2).
/// Feeds [codexMcpBoardProvider] (footer, R11).
final codexMcpStatusProvider =
    FutureProvider.family<List<CodexMcpStatus>, String?>((ref, cwd) async {
      final list = await readCodexMcpStatus(
        executable: ref.read(codexExecutableProvider),
        starter: ref.read(codexMcpStarterProvider),
        workingDirectory: cwd,
      );
      if (ref.mounted) {
        ref.read(codexMcpBoardProvider.notifier).setFromStatus(list);
      }
      return list;
    });

/// Latest status picture of the Codex servers (R11): the footer counts
/// these when the Codex is the provider in focus.
class CodexMcpBoard extends Notifier<McpStatusBoardState> {
  @override
  McpStatusBoardState build() => const McpStatusBoardState();

  void setFromStatus(List<CodexMcpStatus> list) => state = McpStatusBoardState(
    byName: {
      for (final s in list)
        s.name: McpLiveStatus(
          name: s.name,
          state: s.state,
          detail: s.toolsError,
        ),
    },
    source: McpStatusSource.list,
    at: DateTime.now(),
  );

  void setOne(String name, McpConnState s, {String? detail}) =>
      state = McpStatusBoardState(
        byName: {
          ...state.byName,
          name: McpLiveStatus(name: name, state: s, detail: detail),
        },
        source: state.source ?? McpStatusSource.get,
        at: DateTime.now(),
      );

  void remove(String name) => state = McpStatusBoardState(
    byName: {...state.byName}..remove(name),
    source: state.source,
    at: state.at,
  );
}

final codexMcpBoardProvider =
    NotifierProvider<CodexMcpBoard, McpStatusBoardState>(CodexMcpBoard.new);

/// One row of the Codex tab: a configured server and / or a status entry
/// (plugin servers only appear in the status, R3).
@immutable
class CodexMcpRow {
  const CodexMcpRow({required this.name, this.config, this.status});

  final String name;
  final CodexMcpServer? config;
  final CodexMcpStatus? status;

  bool get fromPlugin => config == null && status?.pluginId != null;
  String get key => 'codex:$name';

  McpConnState? get state {
    if (config != null && !config!.enabled) return McpConnState.disabled;
    return status?.state;
  }
}

/// Rows of the Codex tab: configured servers (global group), then plugin
/// servers seen only in `mcpServerStatus/list`.
List<CodexMcpRow> buildCodexMcpRows(
  List<CodexMcpServer> servers,
  List<CodexMcpStatus> status,
) {
  final byName = {for (final s in status) s.name: s};
  final names = {for (final c in servers) c.name};
  return [
    for (final c in servers)
      CodexMcpRow(name: c.name, config: c, status: byName[c.name]),
    for (final s in status)
      if (!names.contains(s.name)) CodexMcpRow(name: s.name, status: s),
  ];
}

/// Server selected on the Codex tab (its row key).
class SelectedCodexMcpServer extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? key) => state = key;
}

final selectedCodexMcpServerProvider =
    NotifierProvider<SelectedCodexMcpServer, String?>(
      SelectedCodexMcpServer.new,
    );
