import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/codex/codex_hooks.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

/// SPEC-103: the app's hooks in Codex sessions — injection by `-c`, the
/// state from `hooks/list`, the activity and the post-turn substitutes.
void main() {
  final hasPython = Process.runSync('which', ['python3']).exitCode == 0;
  late Directory tmp;
  late String root;
  late List<FakeCodex> servers;
  late List<List<String>> argsSeen;
  late List<Map<String, String>?> envSeen;
  late ProviderContainer c;
  late Workspace ws;
  late ManagedHooks hooks;

  /// `hooks/list` of each new App Server, given the command it got.
  late Map<String, dynamic>? Function(String command) listFor;
  String? listError;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('codex-103-');
    root = await createRepo(tmp);
    servers = [];
    argsSeen = [];
    envSeen = [];
    listError = null;
    listFor = (_) => null;
    hooks = ManagedHooks(runBase: '${tmp.path}/run');
    c = sessionContainer([
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: FakeCli(),
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      managedHooksProvider.overrideWithValue(hooks),
      providerAvailabilityProvider.overrideWith(
        (ref, id) async =>
            const ProviderAvailability(ProviderStatus.ready, 'ok'),
      ),
      codexProcessStarterProvider.overrideWithValue((
        exe,
        args, {
        workingDirectory,
        environment,
      }) async {
        argsSeen.add(args);
        envSeen.add(environment);
        final fake = FakeCodex(threadId: 'thread-${servers.length}');
        final pre = args.firstWhere(
          (a) => a.startsWith('hooks.'),
          orElse: () => '',
        );
        final m = RegExp(r'command="((?:[^"\\]|\\.)*)"').firstMatch(pre);
        if (m != null) fake.hooksList = listFor(m.group(1)!);
        fake.hooksListError = listError;
        servers.add(fake);
        return fake;
      }),
    ]);
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: root, name: 'r');
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(ws.id), 'codex');
  });

  tearDown(() async {
    await c.read(sessionManagerProvider.notifier).shutdown();
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> wait([int ms = 80]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<String> start([
    ClaudePermissionMode mode = ClaudePermissionMode.acceptEdits,
  ]) => c
      .read(sessionManagerProvider.notifier)
      .create(
        NewSessionRequest(
          workspace: ws,
          title: 'SPEC-031 · Pagamento com Stripe',
          prompt: 'Integre o Stripe',
          permissionMode: mode,
        ),
      );

  Map<String, dynamic> trusted(String command, Iterable<String> events) => {
    'data': [
      {
        'cwd': root,
        'hooks': [
          for (final e in events)
            {
              'key': '/<session-flags>/config.toml:$e:0:0',
              'eventName': e,
              'command': command,
              'source': 'sessionFlags',
              'enabled': true,
              'trustStatus': 'trusted',
            },
        ],
        'warnings': [],
        'errors': [],
      },
    ],
  };

  group('T3 · injeção e conferência (R3–R5)', () {
    test('the hooks go by -c with the script as the Codex; never --trust, '
        '~/.codex or CODEX_HOME', () async {
      final id = await start();
      await wait();
      final args = argsSeen.single;
      expect(args.first, 'app-server');
      final overrides = [
        for (var i = 0; i + 1 < args.length; i++)
          if (args[i] == '-c' && args[i + 1].startsWith('hooks.')) args[i + 1],
      ];
      expect(overrides.map((o) => o.split('=').first), [
        // No `formatar:` in the project: no PostToolUse.
        'hooks.PreToolUse',
        'hooks.SessionEnd',
      ]);
      expect(
        overrides.first,
        contains('${hooks.dirOf(id)}/promptorium_hook.py'),
      );
      expect(overrides.first, contains('--provedor codex'));
      final all = args.join(' ');
      expect(all, isNot(contains('--trust')));
      expect(all, isNot(contains('bypass')));
      expect(all, isNot(contains('/.codex')));
      expect(envSeen.single?.containsKey('CODEX_HOME') ?? false, isFalse);
      // The session's files live in the app's folder, as with the Claude.
      expect(File('${hooks.dirOf(id)}/hooks-config.json').existsSync(), isTrue);
      final listed = servers.single.writtenJson.firstWhere(
        (m) => m['method'] == 'hooks/list',
      );
      expect(listed['params'], {'threadId': 'thread-0'});
    }, skip: hasPython ? false : 'python3 ausente');

    test('state from hooks/list: all trusted = nativos', () async {
      listFor = (cmd) =>
          trusted(cmd, ['preToolUse', 'postToolUse', 'sessionEnd']);
      final id = await start();
      await wait();
      final s = c.read(codexHookStatusProvider)[id]!;
      expect(s.mode, CodexHookMode.native);
      expect(s.active, contains(ManagedHook.secrets));
    }, skip: hasPython ? false : 'python3 ausente');

    test('a hook missing from hooks/list = parciais (what was sent does not '
        'count)', () async {
      listFor = (cmd) => trusted(cmd, ['preToolUse']);
      final id = await start();
      await wait();
      final s = c.read(codexHookStatusProvider)[id]!;
      expect(s.mode, CodexHookMode.partial);
      expect(s.inactive, {ManagedHook.end});
    }, skip: hasPython ? false : 'python3 ausente');

    test('untrusted (the 0.170) = só pós-turno, with the reason', () async {
      listFor = (cmd) {
        final r = trusted(cmd, ['preToolUse', 'postToolUse', 'sessionEnd']);
        for (final h in (r['data'] as List).first['hooks'] as List) {
          (h as Map)['trustStatus'] = 'untrusted';
        }
        return r;
      };
      final id = await start();
      await wait();
      final s = c.read(codexHookStatusProvider)[id]!;
      expect(s.mode, CodexHookMode.postTurn);
      expect(s.reason, codexUntrustedReason);
    }, skip: hasPython ? false : 'python3 ausente');

    test('hooks/list failing = só pós-turno', () async {
      listError = 'indisponível';
      final id = await start();
      await wait();
      final s = c.read(codexHookStatusProvider)[id]!;
      expect(s.mode, CodexHookMode.postTurn);
      expect(s.problems.single, contains('indisponível'));
    }, skip: hasPython ? false : 'python3 ausente');

    test('every hook off = no -c and state desligados', () async {
      final settings = c.read(appSettingsProvider.notifier);
      for (final h in ManagedHook.values) {
        await settings.set(h.settingKey, '0');
      }
      final id = await start();
      await wait();
      expect(argsSeen.single.any((a) => a.startsWith('hooks.')), isFalse);
      expect(c.read(codexHookStatusProvider)[id]!.mode, CodexHookMode.off);
    }, skip: hasPython ? false : 'python3 ausente');
  });
}
