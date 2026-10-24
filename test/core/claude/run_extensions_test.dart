import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/claude/readonly_run.dart';
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../features/prompt/prompt_test_utils.dart';
import '../../features/sessions/session_test_utils.dart';
import '../../helpers/test_db.dart';
import '../git/git_test_utils.dart';

/// `system/init` of CLI 2.1.308 (trimmed): one user plugin, three
/// built-in, a plugin MCP server, two of the user and a claude.ai one.
Map<String, dynamic> init() => {
  'type': 'system',
  'subtype': 'init',
  'tools': [
    'Bash',
    'mcp__plugin_claude-mem_mcp-search__search',
    'mcp__plugin_claude-mem_mcp-search__timeline',
  ],
  'plugins': [
    {
      'name': 'claude-mem',
      'source': 'claude-mem@thedotmack',
      'version': '13.9.2',
    },
    {'name': 'cc-plugin-telemetry', 'source': 'cc-plugin-telemetry@builtin'},
  ],
  'mcp_servers': [
    {
      'name': 'plugin:claude-mem:mcp-search',
      'status': 'connected',
      'source': 'plugin',
    },
    {'name': 'youtrack', 'status': 'pending', 'source': 'user'},
    {'name': 'context7', 'status': 'pending', 'source': 'user'},
    {
      'name': 'claude.ai Claude Docs',
      'status': 'pending',
      'source': 'claudeai',
    },
  ],
};

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('promptorium-ext-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('settings JSON: enabledPlugins false and deniedMcpServers; empty when '
      'nothing is off', () {
    expect(disabledExtensionsJson((plugins: {}, mcpServers: {})), isEmpty);
    expect(
      disabledExtensionsJson((
        plugins: {'claude-mem@thedotmack'},
        mcpServers: {'youtrack'},
      )),
      {
        'enabledPlugins': {'claude-mem@thedotmack': false},
        'deniedMcpServers': [
          {'serverName': 'youtrack'},
        ],
      },
    );
  });

  test('known plugins and servers come from system/init, without the '
      '@builtin plugins and the plugin servers', () {
    final k = knownExtensionsFromInit(init());
    expect(k.plugins.map((p) => (p.id, p.version, p.tools)), [
      ('claude-mem@thedotmack', '13.9.2', 2),
    ]);
    expect(k.servers.map((s) => (s.name, s.source)), [
      ('youtrack', 'user'),
      ('context7', 'user'),
      ('claude.ai Claude Docs', 'claudeai'),
    ]);
    final back = decodeKnownExtensions(encodeKnownExtensions(k));
    expect(back.plugins.single.id, 'claude-mem@thedotmack');
    expect(back.servers, hasLength(3));
    expect(decodeKnownExtensions('lixo').plugins, isEmpty);
  });

  test('the file: same content, same path; nothing when empty', () async {
    expect(await writeRunSettings(tmp.path, const {}), isNull);
    final a = await writeRunSettings(tmp.path, {'x': 1});
    final b = await writeRunSettings(tmp.path, {'x': 1});
    final c = await writeRunSettings(tmp.path, {'x': 2});
    expect(a, b);
    expect(a, isNot(c));
    expect(jsonDecode(File(a!).readAsStringSync()), {'x': 1});
  });

  test('managed hooks: the extensions go into the same settings.json, also '
      'with no hook on', () async {
    final hooks = ManagedHooks(runBase: tmp.path);
    final off = {
      'enabledPlugins': {'claude-mem@thedotmack': false},
    };
    final only = await hooks.prepare(
      's1',
      enabled: const {},
      rules: const [],
      extra: off,
    );
    expect(jsonDecode(File(only!).readAsStringSync()), off);
    final both = await hooks.prepare(
      's2',
      enabled: {ManagedHook.block},
      rules: builtinBlockRules,
      extra: off,
    );
    final j = jsonDecode(File(both!).readAsStringSync()) as Map;
    expect(j['enabledPlugins'], {'claude-mem@thedotmack': false});
    expect((j['hooks'] as Map).keys, ['PreToolUse']);
    expect(
      await hooks.prepare('s3', enabled: const {}, rules: const []),
      isNull,
    );
  });

  test('a session gets --settings with what is off and records what its '
      'init lists', () async {
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
    ]);
    addTearDown(c.dispose);
    final settings = c.read(appSettingsProvider.notifier);
    await settings.load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    final m = c.read(sessionManagerProvider.notifier);

    await m.create(NewSessionRequest(workspace: ws, title: 'A', prompt: 'oi'));
    expect(cli.args.last, isNot(contains('--settings')));
    cli.last.emit(jsonEncode(init()));
    await settle();
    final known = decodeKnownExtensions(
      settings.get(AppSettingKeys.knownExtensions),
    );
    expect(known.plugins.single.id, 'claude-mem@thedotmack');

    await settings.set(
      AppSettingKeys.disabledPlugins,
      jsonEncode(['claude-mem@thedotmack']),
    );
    await settings.set(
      AppSettingKeys.disabledMcpServers,
      jsonEncode(['youtrack']),
    );
    await m.create(NewSessionRequest(workspace: ws, title: 'B', prompt: 'oi'));
    final args = cli.args.last;
    final path = args[args.indexOf('--settings') + 1];
    expect(path, startsWith('${tmp.path}/run/'));
    expect(jsonDecode(File(path).readAsStringSync()), {
      'enabledPlugins': {'claude-mem@thedotmack': false},
      'deniedMcpServers': [
        {'serverName': 'youtrack'},
      ],
    });

    // Turned off, the plugin is not in the next init: it stays listed.
    final without = init()
      ..['plugins'] = [
        {
          'name': 'cc-plugin-telemetry',
          'source': 'cc-plugin-telemetry@builtin',
        },
      ];
    cli.last.emit(jsonEncode(without));
    await settle();
    expect(
      decodeKnownExtensions(settings.get(AppSettingKeys.knownExtensions))
          .plugins
          .single
          .id,
      'claude-mem@thedotmack',
    );
  });

  test('a Claude conversation gets the same --settings', () async {
    final db = memoryDatabase();
    final provider = FakeAgentProvider();
    final c = ProviderContainer(
      overrides: [
        databaseOverride(db),
        ...fakeProviderOverrides(provider),
        runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
      ],
    );
    addTearDown(c.dispose);
    c.listen(conversationManagerProvider, (_, _) {});
    final ws = await addWorkspace(db, '/work/repo');
    final settings = c.read(appSettingsProvider.notifier);
    await settings.load();
    final m = c.read(conversationManagerProvider.notifier);

    await m.create(workspace: ws, text: 'oi');
    expect(provider.last.options.settingsFile, isNull);

    await settings.set(
      AppSettingKeys.disabledPlugins,
      jsonEncode(['claude-mem@thedotmack']),
    );
    await m.create(workspace: ws, text: 'oi de novo');
    final path = provider.last.options.settingsFile!;
    expect(jsonDecode(File(path).readAsStringSync()), {
      'enabledPlugins': {'claude-mem@thedotmack': false},
    });
  });

  test(
    'a read-only Claude run ("Gerar design", reviewer) gets it too',
    () async {
      final cli = FakeCli();
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          claudeProcessStarterProvider.overrideWithValue(cli.start),
          runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
        ],
      );
      addTearDown(c.dispose);
      final settings = c.read(appSettingsProvider.notifier);
      await settings.load();
      await settings.set(
        AppSettingKeys.disabledMcpServers,
        jsonEncode(['youtrack']),
      );
      final run = Provider(
        (ref) =>
            () => runReadOnlyClaude(
              ref,
              cwd: tmp.path,
              options: const ClaudeOptions(sessionId: 'design-1'),
              prompt: 'Leia e responda',
            ),
      );
      final done = c.read(run)();
      await until(() async => cli.args.isNotEmpty);
      final args = cli.args.single;
      final path = args[args.indexOf('--settings') + 1];
      expect(jsonDecode(File(path).readAsStringSync()), {
        'deniedMcpServers': [
          {'serverName': 'youtrack'},
        ],
      });
      cli.last.emit(
        jsonEncode({
          'type': 'result',
          'subtype': 'success',
          'result': 'ok',
          'session_id': 'design-1',
          'total_cost_usd': 0,
        }),
      );
      await done;
    },
  );
}
