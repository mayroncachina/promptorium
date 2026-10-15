@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/mcp/mcp_cli.dart';
import 'package:promptorium/features/mcp/mcp_config.dart';
import 'package:promptorium/features/mcp/mcp_state.dart';

/// Real `claude mcp add/list/remove` + inventory (plano, Fase 11), **no model
/// call and no cost**. Isolated: `CLAUDE_CONFIG_DIR` points to a temporary
/// directory (verified to redirect `~/.claude.json` on 2.1.300) and the
/// server is added with scope `project` in a temporary folder — the user's
/// `~/.claude.json` / `.mcp.json` are never touched.
///   flutter test --run-skipped -t integration test/integration/mcp_cli_integration_test.dart
void main() {
  test('McpCli com o CLI real (config temporária)', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-mcp-it-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final config = Directory('${tmp.path}/config')..createSync();
    final ws = Directory('${tmp.path}/ws')..createSync();
    final server = File('${tmp.path}/fake_mcp.py')
      ..writeAsStringSync(_fakeServer);

    Future<ProcessResult> run(
      String exe,
      List<String> args, {
      String? workingDirectory,
      Duration? timeout,
    }) {
      // Never run against the user's configuration.
      expect(workingDirectory, ws.path);
      return Process.run(
        exe,
        args,
        workingDirectory: workingDirectory,
        environment: {'CLAUDE_CONFIG_DIR': config.path},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    }

    final home = Platform.environment['HOME'] ?? '';
    final exe = File('$home/.local/bin/claude').existsSync()
        ? '$home/.local/bin/claude'
        : 'claude';
    final cli = McpCli(executable: exe, run: run);
    const name = 'promptorium-it';

    final added = await cli.add(
      McpAddRequest(
        name: name,
        scope: McpScope.project,
        transport: McpTransport.stdio,
        command: 'python3',
        args: ['-I', server.path],
        env: const {'IT_TOKEN': 'valor-secreto-it'},
      ),
      ws.path,
    );
    expect(added, contains('Added stdio MCP server $name'));
    expect(added, isNot(contains('valor-secreto-it')));

    final mcpJson = jsonDecode(File('${ws.path}/.mcp.json').readAsStringSync());
    expect((mcpJson['mcpServers'] as Map).keys, [name]);

    // The registry reads it back (env value masked).
    final snap = await McpRegistry(
      claudeJsonPath: '${config.path}/.claude.json',
      workspacePath: ws.path,
    ).read();
    final c = snap.servers.single;
    expect((c.name, c.scope), (name, McpScope.project));
    expect(c.envKeys, ['IT_TOKEN']);
    expect(c.maskedJson(), isNot(contains('valor-secreto-it')));

    final list = await cli.list(ws.path);
    final e = list.singleWhere((x) => x.name == name);
    // Unapproved .mcp.json server (no interactive approval here).
    expect(e.state, McpConnState.pending);
    // ignore: avoid_print
    print('mcp list: ${e.name} → ${e.state} (${e.statusText})');

    // Inventory (unknown model ⇒ init only, cost 0).
    final r = await run(exe, mcpInventoryArgs, workingDirectory: ws.path);
    final init = firstInit('${r.stdout}');
    expect(init, isNotNull);
    final inv = McpInventory.fromInit(init!);
    // ignore: avoid_print
    print(
      'init: ${[for (final s in inv.servers) '${s.name}=${s.status}']} '
      'tools=${inv.toolsByServer}',
    );

    final removed = await cli.remove(name, McpScope.project, ws.path);
    expect(removed, contains('Removed MCP server $name'));
    expect((await cli.list(ws.path)).where((x) => x.name == name), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));
}

const _fakeServer = r'''
import sys, json
for line in sys.stdin:
    try:
        m = json.loads(line)
    except Exception:
        continue
    i = m.get("id")
    if i is None:
        continue
    meth = m.get("method")
    if meth == "initialize":
        r = {"protocolVersion": m["params"].get("protocolVersion", "2024-11-05"),
             "capabilities": {"tools": {}}, "serverInfo": {"name": "it", "version": "1"}}
    elif meth == "tools/list":
        r = {"tools": [{"name": "echo", "description": "eco",
                        "inputSchema": {"type": "object"}}]}
    else:
        r = {}
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": i, "result": r}) + "\n")
    sys.stdout.flush()
''';
