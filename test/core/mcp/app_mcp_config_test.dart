import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/core/mcp/app_mcp_config.dart';
import 'package:promptorium/core/mcp/app_mcp_server.dart';
import 'package:promptorium/core/mcp/app_mcp_tools.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/core/providers/claude_code_provider.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../features/prompt/prompt_test_utils.dart';
import '../../features/sessions/session_test_utils.dart';
import '../../helpers/test_db.dart';
import '../git/git_test_utils.dart';
import 'mcp_test_utils.dart';

void main() {
  late Directory tmp;
  late AppMcpServer server;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-mcp-cfg-');
    server = AppMcpServer(RecordingToolbox());
  });
  tearDown(() async {
    await server.stop();
    tmp.deleteSync(recursive: true);
  });

  test('writeMcpConfig: the promptorium server over HTTP with the token in '
      'the header, in a 0600 file', () async {
    const g = McpGrant(
      token: 'abcdef0123456789',
      workspaceId: 1,
      sessionId: 'sessao-1',
      access: McpAccess.write,
    );
    final path = await writeMcpConfig('${tmp.path}/run', port: 4321, grant: g);
    expect(path, '${tmp.path}/run/mcp-sessao-1-abcdef01.json');
    expect(jsonDecode(File(path).readAsStringSync()), {
      'mcpServers': {
        'promptorium': {
          'type': 'http',
          'url': 'http://127.0.0.1:4321/mcp',
          'headers': {'Authorization': 'Bearer abcdef0123456789'},
        },
      },
    });
    // rw------- (0600).
    expect(File(path).statSync().mode & 0x1ff, 0x180);
    await deleteMcpConfig(path);
    expect(File(path).existsSync(), isFalse);
  });

  group('R1 · sessions', () {
    late String repo;
    late FakeCli cli;
    late ProviderContainer c;

    setUp(() async {
      repo = await createRepo(tmp);
      cli = FakeCli();
      c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
        runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
        appMcpServerProvider.overrideWithValue(server),
      ]);
      await c.read(appSettingsProvider.notifier).load();
    });
    tearDown(() => c.dispose());

    test('a session gets --mcp-config with the promptorium server, the '
        'reads allowed, and no file of the user changes', () async {
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      final before = _tree(repo);
      await c
          .read(sessionManagerProvider.notifier)
          .create(NewSessionRequest(workspace: ws, title: 'A', prompt: 'oi'));
      final args = cli.args.last;
      final path = args[args.indexOf('--mcp-config') + 1];
      expect(path, startsWith('${tmp.path}/run/mcp-'));
      final cfg = jsonDecode(File(path).readAsStringSync()) as Map;
      expect((cfg['mcpServers'] as Map).keys, ['promptorium']);
      final allowed = args.sublist(args.indexOf('--allowedTools') + 1);
      for (final id in appMcpReadToolIds) {
        expect(allowed, contains(id));
      }
      for (final id in appMcpWriteToolIds) {
        expect(allowed, isNot(contains(id)));
      }
      // Nothing in the workspace (no .mcp.json) nor --strict-mcp-config.
      expect(_tree(repo), before);
      expect(File('$repo/.mcp.json').existsSync(), isFalse);
      expect(args, isNot(contains('--strict-mcp-config')));
    });

    test('with the server off in Configurações no run gets the file '
        '(R10)', () async {
      await c
          .read(appSettingsProvider.notifier)
          .set(AppSettingKeys.mcpServer, '0');
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      await c
          .read(sessionManagerProvider.notifier)
          .create(NewSessionRequest(workspace: ws, title: 'A', prompt: 'oi'));
      expect(cli.args.last, isNot(contains('--mcp-config')));
      expect(server.grants, isEmpty);
    });

    test('the limit of Configurações goes into the grant (R9)', () async {
      await c
          .read(appSettingsProvider.notifier)
          .set(AppSettingKeys.mcpCreationLimit, '3');
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      await c
          .read(sessionManagerProvider.notifier)
          .create(NewSessionRequest(workspace: ws, title: 'A', prompt: 'oi'));
      expect(server.grants.single.limit, 3);
    });
  });

  group('R1, R8 · Prompt conversations', () {
    late FakeAgentProvider provider;
    late ProviderContainer c;
    late Workspace ws;

    setUp(() async {
      final db = memoryDatabase();
      provider = FakeAgentProvider();
      c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          ...fakeProviderOverrides(provider),
          runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
          appMcpServerProvider.overrideWithValue(server),
        ],
      );
      c.listen(conversationManagerProvider, (_, _) {});
      ws = await addWorkspace(db, '/work/repo');
      await c.read(appSettingsProvider.notifier).load();
    });
    tearDown(() => c.dispose());

    test('Perguntar: the server reads only (writes disallowed)', () async {
      await c
          .read(conversationManagerProvider.notifier)
          .create(workspace: ws, text: 'oi', mode: PromptMode.ask);
      final o = provider.last.options;
      expect(o.mcpConfigs.single, startsWith('${tmp.path}/run/mcp-'));
      expect(o.appAllowedTools, appMcpReadToolIds);
      expect(o.mcpDisallowedTools, containsAll(appMcpWriteToolIds));
      expect(server.grants.single.access, McpAccess.read);
      // The CLI options keep the reads even where "Permitido" is ignored.
      final cli = ClaudeCodeProvider.optionsFor(o);
      expect(cli.allowedTools, appMcpReadToolIds);
      expect(cli.strictMcpConfig, isTrue);
      expect(cli.mcpConfigs, o.mcpConfigs);
    });

    test('Planejar and Editar: reads and writes', () async {
      final m = c.read(conversationManagerProvider.notifier);
      await m.create(workspace: ws, text: 'oi', mode: PromptMode.plan);
      expect(provider.last.options.mcpDisallowedTools, isEmpty);
      expect(server.grants.last.access, McpAccess.write);
      await m.create(workspace: ws, text: 'oi', mode: PromptMode.edit);
      expect(provider.last.options.mcpConfigs, hasLength(1));
      expect(server.grants.last.access, McpAccess.write);
    });

    test('Refinar (an internal run) does not get the server', () async {
      await c
          .read(conversationManagerProvider.notifier)
          .create(workspace: ws, text: 'oi', mode: PromptMode.refine);
      expect(provider.last.options.mcpConfigs, isEmpty);
      expect(server.grants, isEmpty);
    });

    test('the grant is revoked when the process ends', () async {
      await c
          .read(conversationManagerProvider.notifier)
          .create(workspace: ws, text: 'oi', mode: PromptMode.ask);
      final path = provider.last.options.mcpConfigs.single;
      await provider.last.finish(0);
      await until(() async => server.grants.isEmpty);
      expect(File(path).existsSync(), isFalse);
    });
  });
}

/// Every path under [dir] but `.git`.
List<String> _tree(String dir) => [
  for (final e in Directory(dir).listSync(recursive: true))
    if (!e.path.contains('/.git/') && !e.path.endsWith('/.git')) e.path,
]..sort();
