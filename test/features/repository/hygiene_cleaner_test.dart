import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/repository/hygiene/hygiene_cleaner.dart';
import 'package:promptorium/features/repository/hygiene/hygiene_scan.dart';

import '../../core/git/git_test_utils.dart';
import 'fake_gh.dart';
import 'hygiene_fixture.dart';

void main() {
  late Directory tmp;
  late HygieneFixture f;
  late List<List<String>> calls;
  late GitService git;
  late HygieneReport report;
  var now = DateTime(2026, 11, 7, 10);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-limpeza-');
    f = await HygieneFixture.create(tmp);
    calls = [];
    git = GitService(
      f.repo,
      run: (exe, args) {
        if (exe == 'git') calls.add(args);
        return Process.run(exe, args);
      },
    );
    report = await scanHygiene(
      git: GitService(f.repo),
      repoPath: f.repo,
      defaultBranch: 'main',
      remote: 'origin',
      gh: GhCli((FakeGh()..mergedPrs = f.mergedPrs).call, cwd: f.repo),
      context: const HygieneContext(
        refKeys: {
          'SPEC-001': RefKeyInfo(closed: true),
          'SPEC-002': RefKeyInfo(closed: false),
        },
      ),
    );
    now = DateTime(2026, 11, 7, 10);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  HygieneCleaner cleaner() =>
      HygieneCleaner(git, remote: 'origin', clock: () => now);
  MergedBranch branch(String name) =>
      report.merged.firstWhere((b) => b.name == name);
  WorktreeItem worktree(String name) =>
      report.worktrees.firstWhere((w) => w.path == f.wt(name));
  Future<bool> localExists(String b) async =>
      await GitService(f.repo).resolveRef('refs/heads/$b') != null;
  Future<bool> remoteExists(String b) async =>
      await GitService(f.origin).resolveRef('refs/heads/$b') != null;
  int indexOf(bool Function(List<String> a) test) => calls.indexWhere(test);

  test('order: worktree, local branch, remote, refs; never -D nor '
      '--force', () async {
    final o = await cleaner().clean(
      CleanupRequest(
        worktrees: [worktree('wt-fechado')],
        branches: [branch('wt/fechado'), branch('feat/mergeada')],
        remoteBranches: [branch('feat/mergeada')],
        refs: [report.refs.firstWhere((g) => g.key == 'SPEC-001')],
        deleteRemote: true,
      ),
    );
    expect(o.errors, isEmpty);
    final wt = indexOf((a) => a.contains('worktree') && a.contains('remove'));
    final local = indexOf((a) => a.contains('branch') && a.contains('-d'));
    final remote = indexOf((a) => a.contains('push') && a.contains('--delete'));
    final refs = indexOf((a) => a.contains('update-ref') && a.contains('-d'));
    expect([wt, local, remote, refs].every((i) => i >= 0), isTrue);
    expect(wt < local && local < remote && remote < refs, isTrue);
    expect(
      calls.any((a) => a.contains('-D') || a.contains('--force')),
      isFalse,
    );

    expect(Directory(f.wt('wt-fechado')).existsSync(), isFalse);
    expect(await localExists('wt/fechado'), isFalse);
    expect(await localExists('feat/mergeada'), isFalse);
    expect(await remoteExists('feat/mergeada'), isFalse);
    expect(o.remoteBranches, ['origin/feat/mergeada']);
    expect(
      await GitService(f.repo)
          .resolveRef('refs/promptorium/SPEC-001/R1-inicio'),
      isNull,
    );
    expect(
      await GitService(f.repo)
          .resolveRef('refs/promptorium/SPEC-003/R1-inicio'),
      isNotNull,
      reason: 'only the chosen spec',
    );
  });

  test('a refused -d is not forced: the item keeps the error', () async {
    final b = branch('feat/sem-upstream-squash');
    expect(b.bySquash, isTrue);
    final o = await cleaner().clean(CleanupRequest(branches: [b]));
    expect(o.errors[b.id], isNotEmpty);
    expect(o.branches, isEmpty);
    expect(await localExists('feat/sem-upstream-squash'), isTrue);
    expect(calls.any((a) => a.contains('-D')), isFalse);
  });

  test('the squash branch with its upstream goes with -d', () async {
    final o = await cleaner().clean(
      CleanupRequest(branches: [branch('feat/squash')]),
    );
    expect(o.errors, isEmpty);
    expect(await localExists('feat/squash'), isFalse);
  });

  test('the remote only leaves with the box checked', () async {
    final b = branch('feat/mergeada');
    await cleaner().clean(CleanupRequest(branches: [b], remoteBranches: [b]));
    expect(await localExists('feat/mergeada'), isFalse);
    expect(await remoteExists('feat/mergeada'), isTrue);
    expect(calls.any((a) => a.contains('push')), isFalse);
  });

  test('a protected item is never touched, even if asked', () async {
    final sujo = worktree('wt-sujo');
    expect(sujo.protection, isNotNull);
    final held = branch('wt/sujo');
    final o = await cleaner().clean(
      CleanupRequest(worktrees: [sujo], branches: [held]),
    );
    expect(o.errors.keys, containsAll([sujo.id, held.id]));
    expect(File('${f.wt('wt-sujo')}/rascunho.txt').existsSync(), isTrue);
    expect(await localExists('wt/sujo'), isTrue);
    expect(calls.any((a) => a.contains('remove')), isFalse);
  });

  test('Desfazer brings back the local branches at their commits, the '
      'upstream and the worktrees, within 15 s', () async {
    final squashSha = branch('feat/squash').sha;
    final fechadoSha = branch('wt/fechado').sha;
    final c = cleaner();
    final o = await c.clean(
      CleanupRequest(
        worktrees: [worktree('wt-fechado'), worktree('wt-orfao')],
        branches: [branch('wt/fechado'), branch('feat/squash')],
      ),
    );
    expect(o.errors, isEmpty);
    expect(o.undoable, isTrue);
    now = now.add(const Duration(seconds: 12));
    final u = await c.undo(o);
    expect(u.errors, isEmpty);
    expect(u.branches, containsAll(['wt/fechado', 'feat/squash']));
    expect(u.worktrees, [f.wt('wt-fechado')]);
    expect(
      await GitService(f.repo).resolveRef('refs/heads/feat/squash'),
      squashSha,
    );
    expect(
      await GitService(f.repo).resolveRef('refs/heads/wt/fechado'),
      fechadoSha,
    );
    expect(
      (await gitIn(f.repo, [
        'rev-parse',
        '--abbrev-ref',
        'feat/squash@{u}',
      ])).trim(),
      'origin/feat/squash',
    );
    expect(Directory(f.wt('wt-fechado')).existsSync(), isTrue);
    expect(
      (await gitIn(f.wt('wt-fechado'), ['branch', '--show-current'])).trim(),
      'wt/fechado',
    );
    // The orphan's folder was already gone: it doesn't come back.
    expect(Directory(f.wt('wt-orfao')).existsSync(), isFalse);
  });

  test('after 15 s there is no undo', () async {
    final c = cleaner();
    final o = await c.clean(
      CleanupRequest(branches: [branch('feat/mergeada')]),
    );
    now = now.add(const Duration(seconds: 16));
    expect(() => c.undo(o), throwsA(isA<UndoExpiredException>()));
    expect(await localExists('feat/mergeada'), isFalse);
  });

  test('refs of a closed spec are cleaned by spec', () async {
    expect(report.refs.map((g) => g.key), ['SPEC-001', 'SPEC-003']);
    final o = await cleaner().clean(CleanupRequest(refs: [report.refs.last]));
    expect(o.refs, ['SPEC-003']);
    final left = await gitIn(f.repo, [
      'for-each-ref',
      '--format=%(refname)',
      'refs/promptorium/',
    ]);
    expect(left, contains('SPEC-001'));
    expect(left, contains('SPEC-002'));
    expect(left, isNot(contains('SPEC-003')));
  });
}
