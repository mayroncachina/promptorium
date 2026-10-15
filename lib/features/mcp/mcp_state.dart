import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_event.dart';
import '../../data/providers.dart';
import '../sessions/session_manager.dart';
import 'mcp_cli.dart';
import 'mcp_rules.dart';

/// Status of one server as last seen.
@immutable
class McpLiveStatus {
  const McpLiveStatus({required this.name, required this.state, this.detail});

  final String name;
  final McpConnState state;

  /// Error text (`CONNECTION_CLOSED: …`) when known.
  final String? detail;
}

enum McpStatusSource { list, get, init }

/// Latest MCP status picture (whole snapshot of the newest `claude mcp list`
/// or `system/init`; `get` updates one server). Feeds the list and the
/// footer.
@immutable
class McpStatusBoardState {
  const McpStatusBoardState({this.byName = const {}, this.source, this.at});

  final Map<String, McpLiveStatus> byName;
  final McpStatusSource? source;
  final DateTime? at;

  bool get isEmpty => byName.isEmpty;
  int get connected =>
      byName.values.where((s) => s.state == McpConnState.connected).length;
  int get failed =>
      byName.values.where((s) => s.state == McpConnState.failed).length;
  int get total => byName.length;
}

class McpStatusBoard extends Notifier<McpStatusBoardState> {
  @override
  McpStatusBoardState build() {
    // Every new system/init of a session (any screen) replaces the picture.
    ref.listen(sessionManagerProvider.select((s) => s.lastInit), (prev, next) {
      if (next != null && !identical(prev, next)) setFromInit(next);
    });
    final init = ref.read(sessionManagerProvider).lastInit;
    return init == null ? const McpStatusBoardState() : _fromInit(init);
  }

  static McpStatusBoardState _fromInit(SystemInit init) => McpStatusBoardState(
    byName: {
      for (final s in init.mcpServers)
        s.name: McpLiveStatus(
          name: s.name,
          state: McpConnState.fromInit(s.status),
        ),
    },
    source: McpStatusSource.init,
    at: DateTime.now(),
  );

  /// Keeps the error text of the previous picture when the state agrees
  /// (`system/init` has no error detail; `claude mcp list` has).
  void setFromInit(SystemInit init) {
    final next = _fromInit(init);
    state = McpStatusBoardState(
      byName: {
        for (final MapEntry(:key, :value) in next.byName.entries)
          key: state.byName[key]?.state == value.state
              ? McpLiveStatus(
                  name: key,
                  state: value.state,
                  detail: state.byName[key]?.detail,
                )
              : value,
      },
      source: next.source,
      at: next.at,
    );
  }

  void setFromList(List<McpListEntry> entries) => state = McpStatusBoardState(
    byName: {
      for (final e in entries)
        e.name: McpLiveStatus(name: e.name, state: e.state, detail: e.detail),
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
}

final mcpStatusBoardProvider =
    NotifierProvider<McpStatusBoard, McpStatusBoardState>(McpStatusBoard.new);

/// Runs `claude mcp list` in the workspace (cwd) once per app session and
/// pushes the result to [mcpStatusBoardProvider]. Invalidate to re-test.
final mcpListProvider = FutureProvider.family<List<McpListEntry>, String?>((
  ref,
  cwd,
) async {
  final entries = await ref.read(mcpCliProvider).list(cwd);
  if (ref.mounted) {
    ref.read(mcpStatusBoardProvider.notifier).setFromList(entries);
  }
  return entries;
});

// --- tool inventory ------------------------------------------------------------

/// Tools of each server from one `system/init` (no model call).
@immutable
class McpInventory {
  const McpInventory({
    required this.toolsByServer,
    required this.servers,
    required this.at,
  });

  /// Server key ([mcpServerKey]) → tool names (without `mcp__srv__`).
  final Map<String, List<String>> toolsByServer;
  final List<McpServerStatus> servers;
  final DateTime at;

  static McpInventory fromInit(SystemInit init) {
    final keys = [for (final s in init.mcpServers) mcpServerKey(s.name)];
    final by = <String, List<String>>{};
    for (final t in init.tools) {
      final p = splitMcpToolId(t, keys);
      if (p == null) continue;
      by.putIfAbsent(p.server, () => []).add(p.tool);
    }
    for (final l in by.values) {
      l.sort();
    }
    return McpInventory(
      toolsByServer: by,
      servers: init.mcpServers,
      at: DateTime.now(),
    );
  }
}

/// `claude -p` that only emits `system/init` (plano Fase 7 trick, confirmed
/// for MCP on 2.1.300 in Fase 11): an unknown `--model` fails before any API
/// call (`result` with `total_cost_usd: 0`), but the init lists every
/// `mcp__<srv>__<tool>` and `mcp_servers[].status`.
/// `--no-session-persistence` keeps it out of `~/.claude/projects`;
/// `--max-budget-usd`/`--max-turns` are a safety net.
const mcpInventoryArgs = [
  '-p',
  '--output-format',
  'stream-json',
  '--verbose',
  '--model',
  'promptorium-inventario-sem-modelo',
  '--no-session-persistence',
  '--permission-mode',
  'default',
  '--max-budget-usd',
  '0.01',
  '--max-turns',
  '1',
  '--',
  '.',
];

/// First `system/init` of a stream-json output (null when absent).
SystemInit? firstInit(String stdout) {
  for (final line in const LineSplitter().convert(stdout)) {
    if (!line.startsWith('{')) continue;
    for (final e in ClaudeEvent.parseLine(line)) {
      if (e is SystemInit) return e;
    }
  }
  return null;
}

/// Inventory of a workspace, cached for the app session (invalidate =
/// "Atualizar ferramentas" / Reiniciar). Also refreshes the status board.
final mcpInventoryProvider = FutureProvider.family<McpInventory, String?>((
  ref,
  cwd,
) async {
  final cli = ref.read(mcpCliProvider);
  final r = await cli
      .run(
        cli.executable,
        mcpInventoryArgs,
        workingDirectory: cwd,
        timeout: McpCli.listTimeout,
      )
      .timeout(McpCli.listTimeout + const Duration(seconds: 5));
  final init = firstInit('${r.stdout}');
  if (init == null) {
    throw const McpException(
      'O Claude Code não emitiu system/init (inventário de ferramentas).',
    );
  }
  if (ref.mounted) ref.read(mcpStatusBoardProvider.notifier).setFromInit(init);
  return McpInventory.fromInit(init);
});

// --- log -----------------------------------------------------------------------

enum McpLogStatus { ok, error, waiting, running, noResult }

@immutable
class McpLogEntry {
  const McpLogEntry({
    required this.at,
    required this.tool,
    required this.status,
    required this.sessionTitle,
    this.agent,
    this.duration,
  });

  final DateTime at;

  /// Tool name without `mcp__srv__`.
  final String tool;
  final McpLogStatus status;
  final String sessionTitle;
  final String? agent;
  final Duration? duration;
}

/// Recent calls of [serverKey]'s tools in the workspace's sessions
/// (`session_events`): `tool_use` blocks → status from the matching
/// `tool_result` (ok / erro) or a pending `control_request` (aguardando
/// aprovação). Newest first, at most [limit].
Future<List<McpLogEntry>> loadMcpLog(
  Ref ref, {
  required int workspaceId,
  required String serverKey,
  int limit = 12,
}) async {
  final repo = ref.read(sessionsRepoProvider);
  final prefix = 'mcp__${serverKey}__';
  final rows = await repo.recentEventsContaining(workspaceId, [prefix]);
  final uses =
      <
        String,
        ({DateTime at, String tool, String title, String? agent, String sid})
      >{};
  final asked = <String>{};
  for (final (ev, s) in rows) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(ev.json) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    final e = ClaudeEvent.fromJson(json);
    if (e is AssistantMessage) {
      for (final b in e.blocks) {
        if (b is ToolUseBlock && b.name.startsWith(prefix)) {
          uses[b.id] = (
            at: ev.createdAt,
            tool: b.name.substring(prefix.length),
            title: sessionTitle(s),
            agent: s.agentName,
            sid: s.id,
          );
        }
      }
    } else if (e is PermissionRequest && e.toolName.startsWith(prefix)) {
      if (e.toolUseId != null) asked.add(e.toolUseId!);
    }
  }
  final ids = uses.keys.toList()
    ..sort((a, b) => uses[b]!.at.compareTo(uses[a]!.at));
  final top = ids.take(limit).toList();
  final results = <String, (bool, DateTime)>{};
  if (top.isNotEmpty) {
    final rr = await repo.recentEventsContaining(workspaceId, [
      for (final id in top) '"tool_use_id":"$id"',
    ], limit: top.length * 4);
    for (final (ev, _) in rr) {
      try {
        final json = jsonDecode(ev.json) as Map<String, dynamic>;
        for (final e in ClaudeEvent.expand(json)) {
          if (e is ToolResult && top.contains(e.toolUseId)) {
            results[e.toolUseId] = (e.isError, ev.createdAt);
          }
        }
      } catch (_) {}
    }
  }
  final live = ref.read(sessionManagerProvider);
  return [
    for (final id in top)
      () {
        final u = uses[id]!;
        final res = results[id];
        final McpLogStatus st;
        if (res != null) {
          st = res.$1 ? McpLogStatus.error : McpLogStatus.ok;
        } else if (asked.contains(id) && live.isAlive(u.sid)) {
          st = McpLogStatus.waiting;
        } else if (live.isAlive(u.sid)) {
          st = McpLogStatus.running;
        } else {
          st = McpLogStatus.noResult;
        }
        return McpLogEntry(
          at: u.at,
          tool: u.tool,
          status: st,
          sessionTitle: u.title,
          agent: u.agent,
          duration: res?.$2.difference(u.at),
        );
      }(),
  ];
}

final mcpLogProvider = FutureProvider.autoDispose
    .family<List<McpLogEntry>, (int, String)>((ref, key) {
      // Refresh when sessions start / stop or approvals change.
      ref.watch(
        sessionManagerProvider.select(
          (s) => (s.live.length, s.approvals.length, s.lastInit),
        ),
      );
      return loadMcpLog(ref, workspaceId: key.$1, serverKey: key.$2);
    });

/// Rules of one server key. A future (not a drift stream) so nothing stays
/// subscribed after the screen closes; invalidated after each change.
final mcpServerRulesProvider = FutureProvider.autoDispose
    .family<List<McpToolRule>, String>(
      (ref, server) => ref.watch(mcpToolRulesRepoProvider).getForServer(server),
    );

/// Server selected on the MCP screen (registry name or server key).
class SelectedMcpServer extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? name) => state = name;
}

final selectedMcpServerProvider = NotifierProvider<SelectedMcpServer, String?>(
  SelectedMcpServer.new,
);
