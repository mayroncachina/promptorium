import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/core/mcp/app_mcp_config.dart';
import 'package:promptorium/core/mcp/app_mcp_server.dart';
import 'package:promptorium/core/mcp/app_mcp_tools.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../features/sessions/session_test_utils.dart';
import '../../helpers/test_db.dart';
import '../git/git_test_utils.dart';
import 'mcp_test_utils.dart';

McpGrant grant(
  String token, {
  int workspaceId = 1,
  McpAccess access = McpAccess.write,
}) => McpGrant(
  token: token,
  workspaceId: workspaceId,
  sessionId: 's-$token',
  access: access,
);

const _readNames = [
  'listar_specs',
  'ler_spec',
  'estado_do_quadro',
  'spec_atual',
];
const _writeNames = ['criar_spec', 'criar_filhas', 'anotar_andamento'];

void main() {
  late RecordingToolbox box;
  late AppMcpServer server;
  late int port;

  setUp(() async {
    box = RecordingToolbox();
    server = AppMcpServer(box);
    port = await server.start();
  });
  tearDown(() => server.stop());

  Map<String, Object?> rpc(String method, [Map<String, Object?>? params]) => {
    'jsonrpc': '2.0',
    'id': 7,
    'method': method,
    'params': ?params,
  };

  group('R2 · token', () {
    test('a call without a token is refused (401)', () async {
      final r = await mcpPost(port, rpc('tools/list'));
      expect(r.status, 401);
      expect(box.calls, isEmpty);
    });

    test('an unknown token is refused (401)', () async {
      server.issue(grant('bom'));
      final r = await mcpPost(port, rpc('tools/list'), token: 'outro');
      expect(r.status, 401);
    });

    test('a revoked token is refused (401)', () async {
      server.issue(grant('bom'));
      expect((await mcpPost(port, rpc('ping'), token: 'bom')).status, 200);
      server.revoke('bom');
      final r = await mcpPost(
        port,
        rpc('tools/call', {'name': 'listar_specs', 'arguments': {}}),
        token: 'bom',
      );
      expect(r.status, 401);
      expect(box.calls, isEmpty);
    });

    test('another host name is refused (DNS rebinding)', () async {
      server.issue(grant('bom'));
      final r = await mcpPost(
        port,
        rpc('ping'),
        token: 'bom',
        host: 'evil.example',
      );
      expect(r.status, 403);
    });

    test('the token only sees the workspace of its run', () async {
      server
        ..issue(grant('a', workspaceId: 1))
        ..issue(grant('b', workspaceId: 2));
      final ra = await mcpCall(port, 'a', 'listar_specs');
      final rb = await mcpCall(port, 'b', 'listar_specs');
      expect((ra['content'] as List).single['text'], contains('workspace 1'));
      expect((rb['content'] as List).single['text'], contains('workspace 2'));
      expect([for (final c in box.calls) c.$1.workspaceId], [1, 2]);
    });

    test('tokens are random and long', () {
      final a = server.newToken(), b = server.newToken();
      expect(a, hasLength(64));
      expect(a, isNot(b));
    });
  });

  group('transport', () {
    test(
      'initialize answers with the server and the tools capability',
      () async {
        server.issue(grant('t'));
        final r = await mcpPost(
          port,
          rpc('initialize', {
            'protocolVersion': '2025-06-18',
            'capabilities': {},
            'clientInfo': {'name': 'claude-code', 'version': '2.1.325'},
          }),
          token: 't',
        );
        final res = (r.body as Map)['result'] as Map;
        expect(res['protocolVersion'], '2025-06-18');
        expect((res['serverInfo'] as Map)['name'], 'promptorium');
        expect(res['capabilities'], contains('tools'));
      },
    );

    test('a notification gets 202 and no body; GET gets 405', () async {
      server.issue(grant('t'));
      final n = await mcpPost(port, {
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      }, token: 't');
      expect(n.status, 202);
      expect(n.body, isNull);
      final g = await mcpPost(port, null, token: 't', method: 'GET');
      expect(g.status, 405);
    });

    test('an unknown method is a JSON-RPC error (server/discover)', () async {
      server.issue(grant('t'));
      final r = await mcpPost(port, rpc('server/discover'), token: 't');
      expect(((r.body as Map)['error'] as Map)['code'], -32601);
    });

    test('the reads say readOnlyHint (else Planejar asks for each)', () async {
      server.issue(grant('t'));
      final r = await mcpPost(port, rpc('tools/list'), token: 't');
      final tools = ((r.body as Map)['result'] as Map)['tools'] as List;
      for (final t in tools.cast<Map>()) {
        final hint = (t['annotations'] as Map)['readOnlyHint'];
        expect(hint, _readNames.contains(t['name']), reason: '${t['name']}');
      }
    });
  });

  group('R8 · tools by mode', () {
    test('Perguntar (read access) lists only the reads', () async {
      server.issue(grant('p', access: McpAccess.read));
      expect(await mcpToolNames(port, 'p'), _readNames);
    });

    test('Planejar / Editar (write access) list reads and writes', () async {
      server.issue(grant('e'));
      expect(await mcpToolNames(port, 'e'), [..._readNames, ..._writeNames]);
    });

    test('a write called with read access is refused, not run', () async {
      server.issue(grant('p', access: McpAccess.read));
      final r = await mcpCall(port, 'p', 'criar_spec', {'texto': '# X'});
      expect(r['isError'], isTrue);
      expect(box.calls, isEmpty);
    });

    test('the permission rules follow the access', () {
      const w = McpRunLink(
        token: 't',
        configPath: 'x',
        access: McpAccess.write,
      );
      const r = McpRunLink(token: 't', configPath: 'x', access: McpAccess.read);
      expect(w.allowedTools, [for (final n in _readNames) appMcpToolId(n)]);
      expect(w.disallowedTools, isEmpty);
      expect(r.disallowedTools, [for (final n in _writeNames) appMcpToolId(n)]);
    });
  });

  group('R2 · end of the process', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('promptorium-mcp-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a session gets a grant of its workspace, revoked with its file '
        'when the process ends', () async {
      final repo = await createRepo(tmp);
      final cli = FakeCli();
      final c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
        runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
        appMcpServerProvider.overrideWithValue(server),
      ]);
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      final m = c.read(sessionManagerProvider.notifier);
      final id = await m.create(
        NewSessionRequest(workspace: ws, title: 'A', prompt: 'oi'),
      );

      final g = server.grants.single;
      expect(g.workspaceId, ws.id);
      expect(g.sessionId, id);
      expect(g.access, McpAccess.write);
      final args = cli.args.last;
      final file = args[args.indexOf('--mcp-config') + 1];
      final cfg = jsonDecode(File(file).readAsStringSync()) as Map;
      final headers =
          ((cfg['mcpServers'] as Map)['promptorium'] as Map)['headers'] as Map;
      expect(headers['Authorization'], 'Bearer ${g.token}');
      expect((await mcpPost(port, rpc('ping'), token: g.token)).status, 200);

      await cli.last.finish(0);
      await until(() async => server.grants.isEmpty);
      expect(File(file).existsSync(), isFalse);
      expect((await mcpPost(port, rpc('ping'), token: g.token)).status, 401);
    });
  });
}
