import 'dart:convert';
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
import 'package:promptorium/features/sessions/timeline.dart';

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

  /// The app's notes of [id]: (text, provider).
  Future<List<(String, String?)>> notes(String id) async => [
    for (final e in await c.read(sessionsRepoProvider).events(id))
      if (e.type == AppEventTypes.note)
        (() {
          final j = jsonDecode(e.json) as Map;
          return ('${j['text']}', j['provider'] as String?);
        })(),
  ];

  Map<String, dynamic> untrusted(String cmd) {
    final r = trusted(cmd, ['preToolUse', 'postToolUse', 'sessionEnd']);
    for (final h in (r['data'] as List).first['hooks'] as List) {
      (h as Map)['trustStatus'] = 'untrusted';
    }
    return r;
  }

  void approval(FakeCodex f, int id, String command) => f.emit(
    jsonEncode({
      'method': 'item/commandExecution/requestApproval',
      'id': id,
      'params': {
        'threadId': f.threadId,
        'turnId': 'turn-1',
        'itemId': 'exec-$id',
        'command': command,
        'cwd': root,
        'availableDecisions': ['accept', 'cancel'],
      },
    }),
  );

  /// Runs the session's script as the Codex would.
  Future<int> runScript(String id, Map<String, Object?> event) async {
    final p = await Process.start('python3', [
      '${hooks.dirOf(id)}/promptorium_hook.py',
      '--provedor',
      'codex',
    ]);
    p.stdin.write(jsonEncode(event));
    await p.stdin.close();
    await p.stdout.drain<void>();
    await p.stderr.drain<void>();
    return p.exitCode;
  }

  group('T4 · atividade e pós-turno (R6, R7, P2)', () {
    test('nativos: the push --force refused by the Codex hook becomes the '
        'same card, once, with the Codex badge; no post-turn notice', () async {
      listFor = (cmd) =>
          trusted(cmd, ['preToolUse', 'postToolUse', 'sessionEnd']);
      final id = await start();
      await wait();
      final f = servers.single;
      final s = (await c.read(sessionsRepoProvider).getById(id))!;
      // The Codex runs the hook before the command: refused (exit 2).
      expect(
        await runScript(id, {
          'hook_event_name': 'preToolUse',
          'tool_name': 'shell',
          'cwd': s.worktreePath,
          'tool_input': {
            'command': ['bash', '-lc', 'git push --force origin spec-031'],
          },
        }),
        2,
      );
      final run = {
        'id': 'h1',
        'eventName': 'preToolUse',
        'status': 'blocked',
        'source': 'sessionFlags',
        'sourcePath': '/<session-flags>/config.toml',
        'entries': [
          {'kind': 'feedback', 'text': 'Promptorium: comando bloqueado'},
        ],
      };
      f.emitHook(run);
      f.emitHook(run); // the same event again: no second card
      await wait();
      final cards = (await notes(id))
          .where((n) => n.$1.startsWith('Hook bloqueou'))
          .toList();
      expect(cards, [
        (
          'Hook bloqueou `git push --force origin spec-031` (git push --force)',
          'codex',
        ),
      ]);
      expect(
        c.read(hookActivityProvider)[ManagedHook.block]!.provider,
        'codex',
      );
      expect(
        (await notes(id)).where((n) => n.$1.contains('não ficaram ativos')),
        isEmpty,
      );
      // With the hook active, approvals are not filtered by the app.
      approval(f, 7, "/usr/bin/zsh -lc 'git push --force'");
      await wait();
      expect(c.read(sessionManagerProvider).live[id]!.approvals, hasLength(1));
    }, skip: hasPython ? false : 'python3 ausente');

    test('só pós-turno: one notice per session; a built-in rule refuses the '
        'approval before the balloon, the rest goes to the person', () async {
      listFor = untrusted;
      final id = await start();
      await wait();
      final f = servers.single;
      approval(f, 1, "/usr/bin/zsh -lc 'rm -rf ~'");
      approval(f, 2, "/usr/bin/zsh -lc 'flutter test test/pagamento/'");
      await wait();
      expect(
        f.writtenJson.firstWhere(
          (m) => m['id'] == 1 && m['method'] == null,
        )['result'],
        {'decision': 'decline'},
      );
      final live = c.read(sessionManagerProvider).live[id]!;
      expect(live.approvals, hasLength(1));
      expect(
        live.approvals.single.request.input['command'],
        contains('flutter test'),
      );
      final all = await notes(id);
      expect(
        all.where((n) => n.$1.startsWith('Recusado antes do balão')).single,
        (
          'Recusado antes do balão: `rm -rf ~` (rm -rf na raiz ou na home)',
          'codex',
        ),
      );
      final notice = all.where((n) => n.$1.contains('não ficaram ativos'));
      expect(notice, hasLength(1));
      expect(notice.single.$1, contains(codexUntrustedReason));
      expect(notice.single.$1, contains('regras aplicadas aos pedidos'));
      // A second turn does not repeat it.
      f.completeTurn();
      await wait();
      await c.read(sessionManagerProvider.notifier).send(id, 'De novo');
      await wait();
      expect(
        (await notes(id)).where((n) => n.$1.contains('não ficaram ativos')),
        hasLength(1),
      );
      // The Vigia's own "sem hook" line is covered by the notice.
      expect(
        (await notes(id))
            .where((n) => n.$1.startsWith('Vigia de segredos sem')),
        isEmpty,
      );
    }, skip: hasPython ? false : 'python3 ausente');

    test('YOLO without hooks: no prior block, said in the notice', () async {
      listFor = untrusted;
      final id = await start(ClaudePermissionMode.skipPermissions);
      await wait();
      final notice = (await notes(id))
          .firstWhere((n) => n.$1.contains('não ficaram ativos'));
      expect(notice.$1, contains('Bloquear comandos perigosos: indisponível'));
    }, skip: hasPython ? false : 'python3 ausente');

    test(
      'só pós-turno: formatar: runs on the files the turn left (not on a '
      'deleted one) before the commit; the end is recorded by the app',
      () async {
        Directory('$root/.promptorium').createSync();
        File('$root/.promptorium/config.yml')
            .writeAsStringSync('formatar: printf ok > {arquivo}.fmt\n');
        await gitIn(root, ['add', '-A']);
        await gitIn(root, ['commit', '-qm', 'config']);
        listFor = untrusted;
        final id = await start();
        await wait();
        final f = servers.single;
        // The first message's turn started (send() resets the turn's files).
        await until(
          () async => f.writtenJson.any((m) => m['method'] == 'turn/start'),
        );
        final wt = (await c.read(sessionsRepoProvider).getById(id))!
            .worktreePath;
        File('$wt/lib/a.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('void main() {}\n');
        f.emit(
          jsonEncode({
            'method': 'item/completed',
            'params': {
              'threadId': f.threadId,
              'item': {
                'type': 'fileChange',
                'id': 'p1',
                'status': 'completed',
                'changes': [
                  {
                    'path': '$wt/lib/a.dart',
                    'kind': {'type': 'add'},
                    'diff': 'void main() {}\n',
                  },
                  {
                    'path': '$wt/lib/velho.dart',
                    'kind': {'type': 'delete'},
                    'diff': 'x\n',
                  },
                ],
              },
            },
          }),
        );
        await wait();
        f.completeTurn();
        await until(
          () async =>
              (await notes(id)).any((n) => n.$1.startsWith('Formatado ao fim')),
        );
        expect(File('$wt/lib/a.dart.fmt').readAsStringSync(), 'ok');
        expect(File('$wt/lib/velho.dart.fmt').existsSync(), isFalse);
        expect(
          (await notes(id)).firstWhere((n) => n.$1.startsWith('Formatado')),
          ('Formatado ao fim do turno: lib/a.dart', 'codex'),
        );
        expect(
          c.read(hookActivityProvider)[ManagedHook.format]!.provider,
          'codex',
        );
        // The app's commit took the formatted file with it.
        final log = await gitIn(wt, [
          'show',
          '--name-only',
          '--format=',
          'HEAD',
        ]);
        expect(log, contains('lib/a.dart.fmt'));
        await c.read(sessionManagerProvider.notifier).stop(id);
        await until(
          () async =>
              (await notes(id)).any((n) => n.$1.startsWith('Sessão enc')),
        );
        expect(
          (await notes(id)).firstWhere((n) => n.$1.startsWith('Sessão enc')),
          ('Sessão encerrada (parada pelo usuário)', 'codex'),
        );
        expect(c.read(codexHookStatusProvider)[id], isNull);
      },
      skip: hasPython ? false : 'python3 ausente',
    );
  });
}
