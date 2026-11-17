// Real git in temporary repositories: slow on a busy runner.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/repository/hygiene/hygiene_scan.dart';
import 'package:promptorium/features/sessions/restore/restore_service.dart';

import '../../../core/git/git_test_utils.dart';
import '../../../helpers/test_db.dart';

/// SPEC-084 R13–R15: how long the points stay and the hygiene.
void main() {
  late Directory tmp;
  late String repo;
  late ProviderContainer c;
  late RestoreService restore;
  late Workspace ws;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-restore-ret-');
    repo = await createRepo(tmp);
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        restoreTimeoutProvider.overrideWithValue(const Duration(minutes: 1)),
      ],
    );
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    for (final id in ['s1', 's2']) {
      await c
          .read(sessionsRepoProvider)
          .insert(
            id: id,
            workspaceId: ws.id,
            worktreePath: repo,
            branch: 'main',
            model: 'opus',
          );
    }
    restore = c.read(restoreServiceProvider);
  });

  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<Map<String, String>> refs() =>
      GitService(repo).refsUnder('refs/promptorium/restore/');

  Future<void> turn(String session) async {
    await restore.start(workspaceId: ws.id, worktree: repo, sessionId: session);
    File('$repo/a.txt').writeAsStringSync('${DateTime.now().microsecond}\n');
    await restore.end(sessionId: session);
  }

  test('the 21st turn deletes the 1st (points and refs)', () async {
    for (var i = 0; i < 21; i++) {
      await turn('s1');
    }
    final points = await c
        .read(restorePointsRepoProvider)
        .list(sessionId: 's1');
    expect(points, hasLength(20));
    expect(points.last.turn, 2);
    final names = (await refs()).keys;
    expect(names, isNot(contains('refs/promptorium/restore/s1/1-inicio')));
    expect(names, contains('refs/promptorium/restore/s1/2-inicio'));
    expect(names, contains('refs/promptorium/restore/s1/21-fim'));
  });

  test('the configured number of turns', () async {
    await c
        .read(appSettingsProvider.notifier)
        .set(RestoreSettingKeys.keepTurns, '2');
    for (var i = 0; i < 4; i++) {
      await turn('s1');
    }
    final points = await c
        .read(restorePointsRepoProvider)
        .list(sessionId: 's1');
    expect(points.map((p) => p.turn), [4, 3]);
  });

  test('the worktree going away (merge, discard) and a deleted session take '
      'every point of the session', () async {
    await turn('s1');
    await turn('s2');
    await restore.dropSession('s1');
    expect(
      await c.read(restorePointsRepoProvider).list(sessionId: 's1'),
      isEmpty,
    );
    expect((await refs()).keys.where((r) => r.contains('/s1/')), isEmpty);
    expect((await refs()).keys.where((r) => r.contains('/s2/')), isNotEmpty);

    await restore.dropWorktree(repo);
    expect(await c.read(restorePointsRepoProvider).all(), isEmpty);
    expect(await refs(), isEmpty);
  });

  test('opening the app: points unused for 14 days, of merged sessions and '
      'refs without a row go', () async {
    await turn('s1');
    await turn('s2');
    final repoP = c.read(restorePointsRepoProvider);
    final old = (await repoP.list(sessionId: 's1')).single;
    await repoP.update(
      old.id,
      RestorePointsCompanion(
        usedAt: Value(DateTime.now().subtract(const Duration(days: 15))),
      ),
    );
    await GitService(repo).updateRef(
      'refs/promptorium/restore/apagada/1-inicio',
      (await GitService(repo).headSha())!,
    );
    await restore.prune();
    expect(await repoP.list(sessionId: 's1'), isEmpty);
    expect(await repoP.list(sessionId: 's2'), hasLength(1));
    expect((await refs()).keys, everyElement(contains('/s2/')));

    await c.read(sessionsRepoProvider).setMerged('s2', 'abc');
    await restore.prune();
    expect(await repoP.all(), isEmpty);
    expect(await refs(), isEmpty);
  });

  test('the hygiene never offers the restore refs', () {
    expect(
      closedRefGroup(
        'restore',
        ['refs/promptorium/restore/s1/1-inicio'],
        known: const {},
        localBranches: {'main'},
      ),
      isNull,
    );
    expect(
      closedRefGroup(
        'SPEC-001',
        ['refs/promptorium/SPEC-001/R1-inicio'],
        known: const {},
        localBranches: {'main'},
      )?.deleted,
      isTrue,
    );
  });

  test('"Apagar todos os pontos deste workspace" and the space used', () async {
    File('$repo/grande.bin').writeAsStringSync('z' * 8192);
    await turn('s1');
    final usage = await restore.usage(ws);
    expect(usage.points, 1);
    expect(usage.sessions, 1);
    expect(usage.bytes, greaterThan(0));
    expect(await restore.dropWorkspace(ws), 1);
    expect(await refs(), isEmpty);
    expect((await restore.usage(ws)).points, 0);
  });
}
