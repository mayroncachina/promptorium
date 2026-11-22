import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/git/worktree_roots.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/session_changes.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';

import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

/// SPEC-096 T3: Codex sessions in a worktree — writable roots, the app's
/// commit at the end of the turn, Interromper, Retomar, fork with the
/// parent link and the access per turn.
void main() {
  late Directory tmp;
  late String root;
  late List<FakeCodex> servers;
  late ProviderContainer c;
  late Workspace ws;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('codex-096-');
    root = await createRepo(tmp);
    servers = [];
    c = sessionContainer([
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: FakeCli(),
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      // The sandbox check would start one more App Server (R10a).
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
        final fake = FakeCodex(threadId: 'thread-${servers.length}');
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

  Future<void> settle([int ms = 60]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  void complete(FakeCodex f, String status, {String? answer}) {
    if (answer != null) {
      f.emit(
        jsonEncode({
          'method': 'item/completed',
          'params': {
            'threadId': f.threadId,
            'item': {'type': 'agentMessage', 'id': 'm1', 'text': answer},
          },
        }),
      );
    }
    f.emit(
      jsonEncode({
        'method': 'turn/completed',
        'params': {
          'threadId': f.threadId,
          'turn': {'id': 'turn-1', 'status': status},
        },
      }),
    );
  }

  Future<String> start(ClaudePermissionMode mode) => c
      .read(sessionManagerProvider.notifier)
      .create(
        NewSessionRequest(
          workspace: ws,
          title: 'Ledger com provedor',
          prompt: 'Grave o provedor',
          permissionMode: mode,
        ),
      );

  test('R10: worktreeWritableRoots is the slice of the git common dir '
      '(never the whole .git) and empty in the project root', () async {
    await gitIn(root, ['worktree', 'add', '-q', '${tmp.path}/w1', '-b', 'w1']);
    final roots = worktreeWritableRoots('${tmp.path}/w1');
    expect(roots, [
      '$root/.git/worktrees/w1',
      '$root/.git/objects',
      '$root/.git/refs',
      '$root/.git/logs',
    ]);
    expect(roots, isNot(contains('$root/.git')));
    expect(worktreeWritableRoots(root), isEmpty);
  });

  test('R10: a session in a worktree sends the roots on turn/start, the '
      'thread opens read-only, and the app commits what was left with the '
      "agent's message", () async {
    final id = await start(ClaudePermissionMode.acceptEdits);
    await settle();
    final s = (await c.read(sessionsRepoProvider).getById(id))!;
    expect(s.worktreePath, isNot(root));
    final f = servers.single;
    final thread = f.writtenJson.firstWhere(
      (m) => m['method'] == 'thread/start',
    )['params'];
    expect(thread['sandbox'], 'read-only');
    final turn = f.writtenJson.lastWhere(
      (m) => m['method'] == 'turn/start',
    )['params'];
    expect(turn['sandboxPolicy']['type'], 'workspaceWrite');
    expect(
      turn['sandboxPolicy']['writableRoots'],
      worktreeWritableRoots(s.worktreePath),
    );
    // The Codex wrote and did not commit.
    File('${s.worktreePath}/ledger.txt').writeAsStringSync('provider\n');
    complete(f, 'completed', answer: 'Gravei o provedor no ledger.');
    // The app's commit runs after the turn (git is slow under load).
    var log = '';
    for (var i = 0; i < 100 && !log.contains('Ledger com provedor'); i++) {
      await settle(100);
      log = await gitIn(s.worktreePath, ['log', '-1', '--format=%B']);
    }
    expect(log, contains('Ledger com provedor'));
    expect(log, contains('Gravei o provedor no ledger.'));
    final status = await gitIn(s.worktreePath, ['status', '--porcelain']);
    expect(status.trim(), isEmpty);
  });

  test("SPEC-111 R1, R4: after the app's commit of the turn the changes "
      'still list the files of the turn, and the provider reloads by itself '
      'once the commit is done', () async {
    final id = await start(ClaudePermissionMode.acceptEdits);
    await settle();
    final s = (await c.read(sessionsRepoProvider).getById(id))!;
    expect(s.baseBranch, isNotNull);
    final seen = <SessionChanges>[];
    final sub = c.listen(
      sessionChangesProvider(id),
      (_, next) => next.whenData(seen.add),
      fireImmediately: true,
    );
    addTearDown(sub.close);
    File('${s.worktreePath}/ledger.txt').writeAsStringSync('provider\n');
    complete(servers.single, 'completed', answer: 'Gravei.');
    // Nobody invalidates by hand: the last value must be the committed file.
    bool committedSeen() =>
        seen.isNotEmpty &&
        seen.last.entries.any((e) => e.path == 'ledger.txt' && !e.isUntracked);
    for (var i = 0; i < 100 && !committedSeen(); i++) {
      await settle(100);
    }
    final status = await gitIn(s.worktreePath, ['status', '--porcelain']);
    expect(status.trim(), isEmpty);
    expect(committedSeen(), isTrue);
    final last = seen.last;
    expect(last.base, isNotNull);
    expect(last.numstat['ledger.txt'], (1, 0));
    expect(last.files.map((f) => f.path), ['ledger.txt']);
  });

  test('R12, P3: Interromper leaves the session interrupted by you (not '
      'failed); Retomar continues on the same process', () async {
    final id = await start(ClaudePermissionMode.acceptEdits);
    await settle();
    final m = c.read(sessionManagerProvider.notifier);
    expect(m.canInterrupt(id), isTrue);
    await m.interrupt(id);
    final f = servers.single;
    expect(f.writtenJson.any((x) => x['method'] == 'turn/interrupt'), isTrue);
    complete(f, 'interrupted');
    await settle(200);
    final s = (await c.read(sessionsRepoProvider).getById(id))!;
    expect(s.status, SessionStatus.interrupted);
    expect(interruptedByUser(s), isTrue);
    expect(
      sessionStatusLabel(s, SessionLook.of(s.status, alive: true)),
      'Interrompida por você',
    );
    expect(m.isAlive(id), isTrue);
    await m.continueSession(id);
    expect(
      f.writtenJson.where((x) => x['method'] == 'turn/start'),
      hasLength(2),
    );
    expect(servers, hasLength(1));
  });

  test('R12, R16: Retomar after closing uses thread/resume with the stored '
      'thread; fork uses thread/fork and stores parentSessionId', () async {
    final id = await start(ClaudePermissionMode.acceptEdits);
    await settle();
    complete(servers.single, 'completed');
    await settle(200);
    final m = c.read(sessionManagerProvider.notifier);
    await m.release(id);
    await m.resume(id);
    final resume = servers.last.writtenJson.singleWhere(
      (x) => x['method'] == 'thread/resume',
    )['params'];
    expect(resume['threadId'], 'thread-0');
    expect(resume['sandbox'], 'read-only');
    final child = await m.fork(id, prompt: 'Continue noutro rumo');
    await settle();
    final fork = (await c.read(sessionsRepoProvider).getById(child))!;
    expect(fork.parentSessionId, id);
    expect(fork.provider, 'codex');
    expect(
      servers.last.writtenJson.singleWhere(
        (x) => x['method'] == 'thread/fork',
      )['params']['threadId'],
      'thread-1',
    );
    final forks = await c.read(sessionsRepoProvider).forksOf(id);
    expect(forks.map((f) => f.id), [child]);
  });

  test('R14: with the turn stopped, a new access goes on the next '
      'turn/start without restarting the process', () async {
    final id = await start(ClaudePermissionMode.acceptEdits);
    await settle();
    final m = c.read(sessionManagerProvider.notifier);
    final f = servers.single;
    complete(f, 'completed');
    await settle(200);
    await m.setPermissionMode(id, ClaudePermissionMode.plan);
    expect(m.isAlive(id), isTrue);
    await m.send(id, 'Leia só');
    expect(
      f.writtenJson.lastWhere(
        (x) => x['method'] == 'turn/start',
      )['params']['sandboxPolicy']['type'],
      'readOnly',
    );
    expect(servers, hasLength(1));
  });

  test('R11: YOLO in the project root is refused, also when switching the '
      'stopped session', () async {
    await expectLater(
      c
          .read(sessionManagerProvider.notifier)
          .create(
            NewSessionRequest(
              workspace: ws,
              title: 'YOLO',
              prompt: 'Olá',
              useWorktree: false,
              permissionMode: ClaudePermissionMode.skipPermissions,
            ),
          ),
      throwsA(isA<SessionException>()),
    );
    final id = await c
        .read(sessionManagerProvider.notifier)
        .create(
          NewSessionRequest(
            workspace: ws,
            title: 'Raiz',
            prompt: 'Olá',
            useWorktree: false,
            permissionMode: ClaudePermissionMode.acceptEdits,
          ),
        );
    await expectLater(
      c
          .read(sessionManagerProvider.notifier)
          .setPermissionMode(id, ClaudePermissionMode.skipPermissions),
      throwsA(isA<SessionException>()),
    );
  });
}
