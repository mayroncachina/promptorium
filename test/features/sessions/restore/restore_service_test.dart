// Real git in temporary repositories: slow on a busy runner.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/restore/restore_service.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../../core/git/git_test_utils.dart';
import '../../../helpers/test_db.dart';
import '../session_test_utils.dart';

/// SPEC-084 R1–R4, R8, R11: recording the points of a turn and undoing it,
/// in temporary repositories only.
void main() {
  late Directory tmp;
  late String repo;
  late ProviderContainer c;
  late RestoreService restore;
  late int wsId;

  File f(String p) => File('$repo/$p');

  /// A long timeout by default: a busy machine must not turn the git work
  /// into "passou de 5 s" (the timeout test lowers it).
  Future<void> boot({
    List<Override> extra = const [],
    Duration timeout = const Duration(minutes: 1),
  }) async {
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        restoreTimeoutProvider.overrideWithValue(timeout),
        ...extra,
      ],
    );
    await c.read(appSettingsProvider.notifier).load();
    wsId =
        (await c.read(workspacesRepoProvider).add(path: repo, name: 'loja-api'))
            .id;
    await c
        .read(sessionsRepoProvider)
        .insert(
          id: 's1',
          workspaceId: wsId,
          worktreePath: repo,
          branch: 'main',
          model: 'opus',
        );
    restore = c.read(restoreServiceProvider);
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-restore-');
    repo = await createRepo(tmp, name: 'loja-api');
    Directory('$repo/src').createSync();
    for (var i = 1; i <= 40; i++) {
      f('src/m$i.ts').writeAsStringSync('import { Pedido } from "./pedido";\n');
    }
    f('src/pedido.ts').writeAsStringSync('export class Pedido {}\n');
    f('src/cupom.ts').writeAsStringSync('export const cupom = 0;\n');
    await gitIn(repo, ['add', '-A']);
    await gitIn(repo, ['commit', '-q', '-m', 'loja']);
  });

  tearDown(() {
    c.dispose();
    RestoreService.failAfterMoveForTest = false;
    tmp.deleteSync(recursive: true);
  });

  /// The turn of the example: `sed -i` in 40 files, creates order.ts,
  /// deletes pedido.ts and commits "wip".
  Future<void> agentTurn() async {
    for (var i = 1; i <= 40; i++) {
      f('src/m$i.ts').writeAsStringSync('import { Order } from "./order";\n');
    }
    f('src/order.ts').writeAsStringSync('export class Order {}\n');
    f('src/pedido.ts').deleteSync();
    await gitIn(repo, ['add', '-A']);
    await gitIn(repo, ['commit', '-q', '-m', 'wip: renomeia Pedido']);
  }

  Future<String> head() async =>
      (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();

  test('undoing the example brings back the 40 files, recreates the deleted '
      'one, deletes the created one, throws the commit away and keeps the '
      "person's file; Refazer goes back to the undone state", () async {
    await boot();
    // The person's work before the turn, not committed.
    f('src/cupom.ts').writeAsStringSync('export const cupom = 10; // à mão\n');
    final startHead = await head();

    final r = await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
      prompt: 'Renomeie Pedido para Order no projeto todo e faça um commit.',
    );
    expect(r.failure, isNull);
    final point = r.point!;
    expect(point.turn, 1);
    expect(point.startBranch, 'main');
    expect(point.files, 1);
    expect(
      await GitService(repo).resolveRef('refs/promptorium/restore/s1/1-inicio'),
      point.startSha,
    );

    await agentTurn();
    final agentHead = await head();
    await restore.end(sessionId: 's1');
    final ended = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    expect(ended.changedFiles, 42);
    expect(ended.commits, 1);

    final plan = await restore.plan(ended);
    expect(plan.restore, hasLength(42));
    expect(plan.changedAfter, isEmpty);
    expect(plan.commits.single.subject, 'wip: renomeia Pedido');
    expect(plan.filesOnly, isFalse);
    expect(plan.kept, ['src/cupom.ts']);

    final out = await restore.undo(ended, plan.defaultSelection);
    expect(out.files, 42);
    expect(out.commits, ['wip: renomeia Pedido']);
    expect(await head(), startHead);
    expect(await gitIn(repo, ['branch', '--show-current']), 'main\n');
    expect(f('src/m7.ts').readAsStringSync(), contains('Pedido'));
    expect(f('src/pedido.ts').existsSync(), isTrue);
    expect(f('src/order.ts').existsSync(), isFalse);
    expect(f('src/cupom.ts').readAsStringSync(), contains('à mão'));
    expect(await gitIn(repo, ['status', '--porcelain']), ' M src/cupom.ts\n');
    final undone = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    expect(undone.state, RestoreState.undone);
    expect(undone.undoneSha, isNotNull);

    final redoPlan = await restore.redoPlan(undone);
    expect(redoPlan.restore, hasLength(42));
    await restore.redo(undone, redoPlan.defaultSelection);
    expect(await head(), agentHead);
    expect(f('src/order.ts').existsSync(), isTrue);
    expect(f('src/pedido.ts').existsSync(), isFalse);
    expect(f('src/cupom.ts').readAsStringSync(), contains('à mão'));
    final redone = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    expect(redone.state, RestoreState.redone);
  });

  test(
    'a file the person changed after the turn stays out unless checked',
    () async {
      await boot();
      final point = (await restore.start(
        workspaceId: wsId,
        worktree: repo,
        sessionId: 's1',
      )).point!;
      f('src/m1.ts').writeAsStringSync('agente\n');
      f('src/m2.ts').writeAsStringSync('agente\n');
      await restore.end(sessionId: 's1');
      f('src/m2.ts').writeAsStringSync('agente e depois a pessoa\n');
      final p = (await c.read(restorePointsRepoProvider).byId(point.id))!;
      final plan = await restore.plan(p);
      expect(plan.restore.single.path, 'src/m1.ts');
      expect(plan.changedAfter.single.path, 'src/m2.ts');
      await restore.undo(p, plan.defaultSelection);
      expect(f('src/m1.ts').readAsStringSync(), contains('Pedido'));
      expect(f('src/m2.ts').readAsStringSync(), 'agente e depois a pessoa\n');
    },
  );

  test('a failure halfway goes back to "antes de desfazer"', () async {
    await boot();
    final point = (await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    )).point!;
    await agentTurn();
    final agentHead = await head();
    await restore.end(sessionId: 's1');
    final p = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    final plan = await restore.plan(p);
    RestoreService.failAfterMoveForTest = true;
    await expectLater(
      restore.undo(p, plan.defaultSelection),
      throwsA(isA<RestoreException>()),
    );
    expect(await head(), agentHead);
    expect(await gitIn(repo, ['status', '--porcelain']), '');
    expect(f('src/order.ts').existsSync(), isTrue);
    final after = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    expect(after.state, RestoreState.active);
  });

  test('a pushed commit: files only, the commit stays', () async {
    final remote = '${tmp.path}/remoto.git';
    await gitIn(tmp.path, ['init', '-q', '--bare', remote]);
    await gitIn(repo, ['remote', 'add', 'origin', remote]);
    await boot();
    final point = (await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    )).point!;
    await agentTurn();
    await gitIn(repo, ['push', '-q', 'origin', 'main']);
    final agentHead = await head();
    await restore.end(sessionId: 's1');
    final p = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    final plan = await restore.plan(p);
    expect(plan.filesOnly, isTrue);
    expect(plan.remotes, ['origin/main']);
    await restore.undo(p, plan.defaultSelection, filesOnly: true);
    expect(await head(), agentHead);
    expect(f('src/pedido.ts').existsSync(), isTrue);
    expect(f('src/order.ts').existsSync(), isFalse);
  });

  test('"Voltar a antes deste turno" sums the turns after it', () async {
    await boot();
    final first = (await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    )).point!;
    f('src/m1.ts').writeAsStringSync('turno 1\n');
    await restore.end(sessionId: 's1');
    final second = await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    );
    expect(second.failure, isNull);
    expect(second.point?.turn, 2);
    f('src/m2.ts').writeAsStringSync('turno 2\n');
    await restore.end(sessionId: 's1');
    final p = (await c.read(restorePointsRepoProvider).byId(first.id))!;
    final plan = await restore.plan(p);
    expect(plan.restore.map((x) => x.path).toSet(), {'src/m1.ts', 'src/m2.ts'});
    await restore.undo(p, plan.defaultSelection);
    final all = await c.read(restorePointsRepoProvider).list(sessionId: 's1');
    expect(all.map((x) => x.state), [RestoreState.undone, RestoreState.undone]);
    expect(await gitIn(repo, ['status', '--porcelain']), '');
  });

  test('more than the timeout: the turn goes on without a point', () async {
    await boot(
      timeout: const Duration(milliseconds: 50),
      extra: [
        gitServiceFactoryProvider.overrideWithValue(
          (root) => GitService(
            root,
            run: (exe, args) async {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              return Process.run(exe, args);
            },
          ),
        ),
      ],
    );
    final sw = Stopwatch()..start();
    final r = await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect(r.point, isNull);
    expect(r.failure, startsWith('passou de'));
    // The late git work does not leave a row behind.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(
      await c.read(restorePointsRepoProvider).list(sessionId: 's1'),
      isEmpty,
    );
  });

  test('a repository without commits and a folder without git', () async {
    final empty = Directory('${tmp.path}/vazio')..createSync();
    await gitIn(empty.path, ['init', '-q']);
    await boot();
    final r = await restore.start(
      workspaceId: wsId,
      worktree: empty.path,
      sessionId: 's1',
    );
    expect(r.failure, 'repositório sem commit');
    final plain = Directory('${tmp.path}/docs-antigos')..createSync();
    final r2 = await restore.start(
      workspaceId: wsId,
      worktree: plain.path,
      sessionId: 's1',
    );
    expect(r2.failure, 'docs-antigos não é um repositório git');
    // Said once.
    final r3 = await restore.start(
      workspaceId: wsId,
      worktree: plain.path,
      sessionId: 's1',
    );
    expect(r3.failure, isNull);
    expect(r3.point, isNull);
  });

  test('the switch off records nothing', () async {
    await boot();
    await c
        .read(appSettingsProvider.notifier)
        .set(RestoreSettingKeys.enabled, 'false');
    final r = await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    );
    expect(r.point, isNull);
    expect(r.failure, isNull);
  });

  group('SessionManager', () {
    late FakeCli cli;

    Future<String> newSession() async {
      cli = FakeCli();
      c.dispose();
      c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
          restorePoints: true,
        ),
        restoreTimeoutProvider.overrideWithValue(const Duration(minutes: 1)),
      ]);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      return c
          .read(sessionManagerProvider.notifier)
          .create(
            NewSessionRequest(
              workspace: ws,
              title: 'Renomear',
              prompt: 'Renomeie.',
              useWorktree: false,
            ),
          );
    }

    setUp(() async => boot());

    test('send records the start; the result records the end; a notice in '
        'the middle of the turn records nothing', () async {
      final id = await newSession();
      final repoP = c.read(restorePointsRepoProvider);
      var points = await repoP.list(sessionId: id);
      expect(points.single.turn, 1);
      expect(points.single.eventSeq, isNotNull);
      expect(points.single.prompt, 'Renomeie.');
      expect(points.single.endedAt, isNull);

      f('src/m1.ts').writeAsStringSync('agente\n');
      await c
          .read(sessionManagerProvider.notifier)
          .notifyUserEdit(id, 'src/m1.ts');
      await settle();
      expect(await repoP.list(sessionId: id), hasLength(1));

      cli.last.emit(fixtureLines().last); // result
      await until(
        () async => (await repoP.list(sessionId: id)).single.endedAt != null,
      );
      points = await repoP.list(sessionId: id);
      expect(points.single.changedFiles, 1);

      final plan = await c.read(restoreServiceProvider).plan(points.single);
      expect(plan.restore.single.userDuring, isTrue);
    });

    test('an undo notice waits for the next message', () async {
      final id = await newSession();
      cli.last.emit(fixtureLines().last);
      await settle();
      final m = c.read(sessionManagerProvider.notifier);
      await m.queueNotice(id, SessionManager.undoNotice(4));
      await settle();
      expect(m.pendingNotices(id), [SessionManager.undoNotice(4)]);
      await m.send(id, 'Agora só o checkout.');
      await settle();
      expect(m.pendingNotices(id), isEmpty);
      expect(
        '${cli.last.writtenJson.last}',
        contains('O usuário desfez o turno 4'),
      );
    });
  });

  test('the commit the app makes at the end of a Codex turn lands before the '
      'capture: the point counts the file and the commit, and undoing it '
      'takes the file away (SPEC-096 R10 with SPEC-084 R1)', () async {
    await boot();
    final startHead = await head();
    final point = (await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
      prompt: 'crie uma nota',
    )).point!;
    // The Codex writes and leaves it uncommitted; the app commits it.
    f('NOTA.md').writeAsStringSync('# Nota\n');
    var committed = false;
    await restore.end(
      sessionId: 's1',
      beforeEnd: () async {
        committed = await GitService(repo).commitAll('Nota pelo Codex');
      },
    );
    expect(committed, isTrue);
    final ended = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    expect(ended.endHead, await head());
    expect(ended.changedFiles, 1);
    expect(ended.commits, 1);

    final plan = await restore.plan(ended);
    expect(plan.changedAfter, isEmpty);
    expect(plan.restore, hasLength(1));
    await restore.undo(ended, plan.defaultSelection);
    expect(f('NOTA.md').existsSync(), isFalse);
    expect(await head(), startHead);
  });

  test('beforeEnd still runs when the turn has no open point', () async {
    await boot();
    var ran = false;
    await restore.end(sessionId: 's1', beforeEnd: () async => ran = true);
    expect(ran, isTrue);
  });
}
