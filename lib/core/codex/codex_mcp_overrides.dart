import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../mcp/app_mcp_tools.dart' show appMcpCatalog, appMcpServerName;

/// MCP of a Codex run by `-c` overrides of the App Server (SPEC-105 R7–R9).
/// Nothing is written to `~/.codex`.

/// Every `mcpServer/startupStatus/updated` of every Codex run (the params):
/// the MCP status board of the Codex follows them (R11).
final codexMcpStartupUpdates =
    StreamController<Map<String, dynamic>>.broadcast();

/// Variable that carries the token of the app's server to the App Server:
/// the token never goes on the command line.
const codexAppMcpTokenVar = 'PROMPTORIUM_MCP_TOKEN';

/// Names of the Codex servers a run may override (`codex mcp list --json`):
/// an override of a server that does not exist breaks the configuration
/// ("invalid transport", SPEC-105 sondagem).
typedef CodexMcpLister = Future<List<String>> Function(String exe, String cwd);

/// Keys accepted as a bare TOML key in a dotted `-c` path.
final _bareKey = RegExp(r'^[A-Za-z0-9_-]+$');

/// `codex mcp list --json` → names of the configured servers.
List<String> codexMcpServerNames(String stdout) {
  final start = stdout.indexOf('[');
  if (start < 0) throw const FormatException('codex mcp list sem lista');
  final j = jsonDecode(stdout.substring(start));
  if (j is! List) throw const FormatException('codex mcp list sem lista');
  return [
    for (final e in j)
      if (e is Map && e['name'] is String) e['name'] as String,
  ];
}

/// The real lister. Under `flutter test` it never runs the CLI (no servers).
Future<List<String>> defaultCodexMcpLister(String exe, String cwd) async {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return const [];
  final r = await Process.run(exe, const [
    'mcp',
    'list',
    '--json',
  ], workingDirectory: cwd).timeout(const Duration(seconds: 15));
  if (r.exitCode != 0) {
    throw ProcessException(exe, const ['mcp', 'list'], 'código ${r.exitCode}');
  }
  return codexMcpServerNames('${r.stdout}');
}

/// The app's server for one run: URL and token of its `--mcp-config` file
/// (SPEC-052), read by the adapter.
typedef CodexAppMcp = ({String url, String token});

/// Reads the `promptorium` entry of a `--mcp-config` file of the app.
CodexAppMcp? readAppMcpConfig(String path) {
  try {
    final j = jsonDecode(File(path).readAsStringSync());
    final s = (j is Map ? j['mcpServers'] : null);
    final e = s is Map ? s[appMcpServerName] : null;
    if (e is! Map || e['url'] is! String) return null;
    final auth = (e['headers'] as Map?)?['Authorization'];
    final token = auth is String && auth.startsWith('Bearer ')
        ? auth.substring(7)
        : null;
    if (token == null || token.isEmpty) return null;
    return (url: e['url'] as String, token: token);
  } catch (_) {
    return null;
  }
}

/// Read tools of the app's server: the only ones a Codex run gets (R7: a
/// per-tool approval in the Codex is not proven, so writes stay out).
List<String> get codexAppMcpTools => [
  for (final t in appMcpCatalog)
    if (!t.write) t.name,
];

String _toml(String s) => jsonEncode(s);
String _tomlList(Iterable<String> l) => '[${l.map(_toml).join(', ')}]';

/// The `-c` overrides of a run:
/// - [readOnly] (Perguntar, Planejar, execuções estruturadas, R8): every
///   configured server off (`enabled=false`) and `features.apps=false` —
///   `mcp_servers={}` does not turn them off (SPEC-093 D2);
/// - [disallowed] (`mcp__srv__tool`, the "Bloqueado" rules, R9):
///   `disabled_tools` of each configured server that has some;
/// - [app]: the Promptorium server by URL, its token read from
///   [codexAppMcpTokenVar], with only its read tools.
List<String> codexMcpOverrides({
  required List<String> servers,
  required bool readOnly,
  List<String> disallowed = const [],
  CodexAppMcp? app,
}) {
  final out = <String>[];
  final known = [
    for (final s in servers)
      if (s != appMcpServerName && _bareKey.hasMatch(s)) s,
  ];
  if (readOnly) {
    for (final s in known) {
      out.addAll(['-c', 'mcp_servers.$s.enabled=false']);
    }
    out.addAll(['-c', 'features.apps=false']);
  } else if (disallowed.isNotEmpty) {
    final byServer = <String, List<String>>{};
    for (final id in disallowed) {
      if (!id.startsWith('mcp__')) continue;
      final rest = id.substring(5);
      // Longest server name that prefixes the id wins (names with `__`).
      String? server;
      for (final s in known) {
        final key = s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
        if (rest.startsWith('${key}__') &&
            (server == null || s.length > server.length)) {
          server = s;
        }
      }
      if (server == null) continue;
      byServer
          .putIfAbsent(server, () => [])
          .add(rest.substring(server.length + 2));
    }
    for (final MapEntry(:key, :value) in byServer.entries) {
      out.addAll([
        '-c',
        'mcp_servers.$key.disabled_tools=${_tomlList(value..sort())}',
      ]);
    }
  }
  if (app != null) {
    const p = 'mcp_servers.$appMcpServerName';
    out.addAll([
      '-c',
      '$p.url=${_toml(app.url)}',
      '-c',
      '$p.bearer_token_env_var=${_toml(codexAppMcpTokenVar)}',
      '-c',
      '$p.enabled_tools=${_tomlList(codexAppMcpTools)}',
    ]);
  }
  return out;
}
