import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../claude/run_extensions.dart' show runSettingsDirProvider;
import 'app_mcp_server.dart';
import 'app_mcp_tools.dart';

/// `--mcp-config` JSON of one run (SPEC-052 R1): the `promptorium` server
/// over HTTP, with the run's token in the `Authorization` header (the token
/// never goes on the command line).
Map<String, Object?> mcpConfigJson({
  required int port,
  required String token,
}) => {
  'mcpServers': {
    appMcpServerName: {
      'type': 'http',
      'url': 'http://127.0.0.1:$port${AppMcpServer.path}',
      'headers': {'Authorization': 'Bearer $token'},
    },
  },
};

/// Writes `<dir>/mcp-<sessão>-<token>.json` with permission 0600 and
/// returns its path. The token prefix keeps a quick resume from sharing the
/// file the previous process is about to delete.
Future<String> writeMcpConfig(
  String dir, {
  required int port,
  required McpGrant grant,
}) async {
  final safe = grant.sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final f = File('$dir/mcp-$safe-${grant.token.substring(0, 8)}.json');
  await f.parent.create(recursive: true);
  // Empty and 0600 before the token goes in.
  await f.writeAsString('');
  final chmod = await Process.run('chmod', ['600', f.path]);
  if (chmod.exitCode != 0) {
    await f.delete().catchError((Object _) => f);
    throw FileSystemException('chmod 600 falhou: ${chmod.stderr}', f.path);
  }
  await f.writeAsString(
    jsonEncode(mcpConfigJson(port: port, token: grant.token)),
    flush: true,
  );
  return f.path;
}

/// Removes a file of [writeMcpConfig] (missing = nothing to do).
Future<void> deleteMcpConfig(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (e) {
    debugPrint('servidor MCP: $path não removido — $e');
  }
}

/// The tools the server serves.
final appMcpToolsProvider = Provider<McpToolbox>((ref) => AppMcpTools());

/// The app's MCP server (null in tests: they override it). Bound on the
/// first run that needs it (or by the splash) and closed with the app.
final appMcpServerProvider = Provider<AppMcpServer?>((ref) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
  final server = AppMcpServer(ref.read(appMcpToolsProvider));
  ref.onDispose(server.stop);
  return server;
});

/// Files of a previous app session (its tokens died with it): removed once,
/// before the first run of this one writes its file.
final appMcpPurgeProvider = FutureProvider<void>((ref) async {
  final dir = Directory(ref.read(runSettingsDirProvider));
  try {
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.last;
      if (f is File && name.startsWith('mcp-') && name.endsWith('.json')) {
        await f.delete();
      }
    }
  } catch (e) {
    debugPrint('servidor MCP: arquivos antigos não removidos — $e');
  }
});

/// Configurações › Execução de specs: the server is on (R10, P2).
bool appMcpEnabled(Map<String, String> settings) =>
    settings[AppSettingKeys.mcpServer] != '0';

/// R9 limit of the settings (default 10; at least 1).
int appMcpCreationLimit(Map<String, String> settings) {
  final n = int.tryParse(settings[AppSettingKeys.mcpCreationLimit] ?? '');
  return n == null || n < 1 ? McpGrant.defaultCreationLimit : n;
}

/// What a run of the app gets from the server: the `--mcp-config` file and
/// the permission rules of its tools.
@immutable
class McpRunLink {
  const McpRunLink({
    required this.token,
    required this.configPath,
    required this.access,
  });

  final String token;
  final String configPath;
  final McpAccess access;

  /// `--allowedTools`: the reads never ask (R3).
  List<String> get allowedTools => appMcpReadToolIds;

  /// `--disallowedTools`: a read-only run does not even see the writes
  /// (R8; the server leaves them out of `tools/list` too).
  List<String> get disallowedTools =>
      access == McpAccess.read ? appMcpWriteToolIds : const [];
}

/// Links a new run to the server: a grant with a fresh token and its
/// `--mcp-config` file. Null when the server is off in Configurações (R10),
/// absent (tests) or fails to start: the run goes on without it.
Future<McpRunLink?> openMcpRun(
  Ref ref, {
  required int workspaceId,
  required String sessionId,
  required McpAccess access,
  int? conversationId,
  int? specId,
  String? steps,
  String? title,
  bool skipApproval = false,
}) async {
  final settings = ref.read(appSettingsProvider);
  if (!appMcpEnabled(settings)) return null;
  final server = ref.read(appMcpServerProvider);
  if (server == null) return null;
  try {
    await ref.read(appMcpPurgeProvider.future);
    final port = await server.start();
    final grant = McpGrant(
      token: server.newToken(),
      workspaceId: workspaceId,
      sessionId: sessionId,
      conversationId: conversationId,
      specId: specId,
      steps: steps,
      title: title,
      access: access,
      skipApproval: skipApproval,
      limit: appMcpCreationLimit(settings),
    );
    final path = await writeMcpConfig(
      ref.read(runSettingsDirProvider),
      port: port,
      grant: grant,
    );
    server.issue(grant);
    return McpRunLink(token: grant.token, configPath: path, access: access);
  } catch (e) {
    debugPrint('servidor MCP: execução sem o servidor — $e');
    return null;
  }
}

/// End of the process: the token stops working and the file goes away
/// (R2).
Future<void> closeMcpRun(AppMcpServer? server, McpRunLink? link) async {
  if (link == null) return;
  await deleteMcpConfig(link.configPath);
  server?.revoke(link.token);
}
