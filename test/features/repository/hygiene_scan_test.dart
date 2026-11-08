import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/repository/hygiene/hygiene_scan.dart';

import '../../core/git/git_test_utils.dart';
import 'fake_gh.dart';
import 'hygiene_fixture.dart';

void main() {
  late Directory tmp;
  late HygieneFixture f;
  late FakeGh gh;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-higiene-');
    f = await HygieneFixture.create(tmp);
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() {
    gh = FakeGh()..mergedPrs = f.mergedPrs;
  });

  HygieneContext context() => HygieneContext(
    liveBranches: {'wt/vivo'},
    liveWorktrees: {f.wt('wt-vivo')},
    sessionByBranch: {'feat/conflito': 'sessao-1'},
    specByBranch: {'feat/mergeada': 'SPEC-009'},
    refKeys: {
      'SPEC-001': RefKeyInfo(closed: true, mergedAt: DateTime(2026, 10, 24)),
      'SPEC-002': const RefKeyInfo(closed: false),
    },
  );

  Future<HygieneReport> scan({bool withGh = true, bool light = false}) =>
      scanHygiene(
        git: GitService(f.repo),
        repoPath: f.repo,
        defaultBranch: 'main',
        remote: 'origin',
        gh: withGh ? GhCli(gh.call, cwd: f.repo) : null,
        context: context(),
        light: light,
      );

  group('R2 · branches mergeadas', () {
    test('by merge and by squash (the PR says so), with the remote in its '
        'own field', () async {
      final r = await scan();
      final byName = {for (final b in r.merged) b.name: b};
      expect(
        byName.keys,
        containsAll([
          'feat/mergeada',
          'feat/squash',
          'feat/sem-upstream-squash',
          'wt/fechado',
        ]),
      );
      expect(byName.keys, isNot(contains('main')));
      expect(byName.keys, isNot(contains('feat/aberta')));
      expect(byName.keys, isNot(contains('wt/parado')));

      final merge = byName['feat/mergeada']!;
      expect(merge.bySquash, isFalse);
      expect(merge.remoteRef, 'origin/feat/mergeada');
      expect(merge.spec, 'SPEC-009');
      expect(merge.pr, 1);
      expect(merge.date, isNotNull);

      final squash = byName['feat/squash']!;
      expect(squash.bySquash, isTrue);
      expect(squash.pr, 2);
      expect(squash.remoteRef, 'origin/feat/squash');
      expect(squash.upstream, 'origin/feat/squash');

      expect(byName['feat/sem-upstream-squash']!.remoteRef, isNull);
    });

    test('without gh, squash merges are not guessed', () async {
      final r = await scan(withGh: false);
      final names = r.merged.map((b) => b.name);
      expect(names, contains('feat/mergeada'));
      expect(names, isNot(contains('feat/squash')));
      expect(r.ghAvailable, isFalse);
    });

    test('a branch with commits after the merged PR is not merged', () async {
      gh.mergedPrs = [
        {...f.mergedPrs.first, 'headRefOid': 'f' * 40},
      ];
      final r = await scan();
      expect(r.merged.map((b) => b.name), isNot(contains('feat/squash')));
    });

    test('spec read from the branch name', () {
      expect(specOfBranchName('spec/042-t1-dados'), 'SPEC-042 T1');
      expect(specOfBranchName('pr/spec-020-icone-na-bandeja'), 'SPEC-020');
      expect(specOfBranchName('docs/spec-014-marcar-criterios'), 'SPEC-014');
      expect(specOfBranchName('chore/remover-hook'), isNull);
    });
  });

  group('R3 · worktrees', () {
    test('orphan, closed spec and stale, with the disk size and the '
        'uncommitted changes', () async {
      final r = await scan();
      final byPath = {for (final w in r.worktrees) w.path: w};
      expect(byPath[f.wt('wt-orfao')]!.kind, WorktreeKind.orphan);
      expect(byPath[f.wt('wt-orfao')]!.sizeBytes, isNull);
      expect(byPath[f.wt('wt-fechado')]!.kind, WorktreeKind.closed);
      expect(byPath[f.wt('wt-fechado')]!.branch, 'wt/fechado');
      expect(byPath[f.wt('wt-fechado')]!.sizeBytes, greaterThan(0));
      expect(byPath[f.wt('wt-fechado')]!.dirty, isFalse);
      expect(byPath[f.wt('wt-parado')]!.kind, WorktreeKind.stale);
      expect(byPath[f.wt('wt-sujo')]!.kind, WorktreeKind.closed);
      expect(byPath[f.wt('wt-sujo')]!.dirty, isTrue);
      // Old, but with a live session: in use, not listed.
      expect(byPath.containsKey(f.wt('wt-vivo')), isFalse);
      // The main repository never.
      expect(byPath.containsKey(f.repo), isFalse);
      expect(r.worktreeBytes, greaterThan(0));
    });

    test('pruneDryRun finds the orphan without removing it', () async {
      final git = GitService(f.repo);
      expect(await git.pruneDryRun(), {f.wt('wt-orfao')});
      expect(
        (await git.listWorktrees()).map((w) => w.path),
        contains(f.wt('wt-orfao')),
      );
    });

    test('classifyWorktree', () {
      final now = DateTime(2026, 11, 7);
      WorktreeKind? c({
        bool missing = false,
        String? branch = 'b',
        bool exists = true,
        bool merged = false,
        int days = 1,
        bool live = false,
      }) => classifyWorktree(
        missing: missing,
        branch: branch,
        branchExists: exists,
        branchMerged: merged,
        lastCommit: now.subtract(Duration(days: days)),
        now: now,
        live: live,
      );
      expect(c(missing: true), WorktreeKind.orphan);
      expect(c(exists: false), WorktreeKind.closed);
      expect(c(merged: true), WorktreeKind.closed);
      expect(c(days: 15), WorktreeKind.stale);
      expect(c(days: 14), isNull);
      expect(c(days: 30, live: true), isNull);
      expect(c(), isNull);
    });
  });

  group('R4 · atrás da base', () {
    test('behind and ahead, most behind first, with the conflict', () async {
      final r = await scan();
      final byName = {for (final b in r.behind) b.name: b};
      expect(byName.keys, containsAll(['feat/aberta', 'feat/conflito']));
      expect(byName.keys, isNot(contains('feat/mergeada')));
      final aberta = byName['feat/aberta']!;
      expect(aberta.ahead, 1);
      expect(aberta.behind, greaterThan(1));
      expect(aberta.conflict!.files, isEmpty);
      final conflito = byName['feat/conflito']!;
      expect(conflito.conflict!.files, ['a.txt']);
      expect(conflito.sessionId, 'sessao-1');
      for (var i = 1; i < r.behind.length; i++) {
        expect(
          r.behind[i - 1].behind,
          greaterThanOrEqualTo(r.behind[i].behind),
        );
      }
    });

    test('aheadBehind', () async {
      final ab = await GitService(f.repo).aheadBehind('feat/aberta', 'main');
      expect(ab.ahead, 1);
      expect(ab.behind, greaterThan(0));
    });

    test('the light scan skips the conflict and the disk', () async {
      final r = await scan(light: true);
      expect(r.behind.every((b) => b.conflict == null), isTrue);
      expect(r.worktrees.every((w) => w.sizeBytes == null), isTrue);
      expect(r.cleanable, greaterThan(0));
    });
  });

  group('R5 · refs internas', () {
    test('grouped by spec, only closed (done) and unknown (deleted)', () async {
      final r = await scan();
      expect(r.refs.map((g) => g.key), ['SPEC-001', 'SPEC-003']);
      expect(r.refs.first.refs, hasLength(2));
      expect(r.refs.first.mergedAt, DateTime(2026, 10, 24));
      expect(r.refs.last.deleted, isTrue);
    });

    test('a session key is closed when its branch is gone', () {
      expect(
        closedRefGroup(
          's1',
          ['refs/promptorium/s1/pre-rebase'],
          known: {'s1': const RefKeyInfo(closed: false, branch: 'pr/x')},
          localBranches: {'main'},
        )?.deleted,
        isTrue,
      );
      expect(
        closedRefGroup(
          's1',
          ['refs/promptorium/s1/pre-rebase'],
          known: {'s1': const RefKeyInfo(closed: false, branch: 'pr/x')},
          localBranches: {'pr/x'},
        ),
        isNull,
      );
    });
  });

  group('R6 · proteções', () {
    test('default branch, current branch of any worktree, live session and '
        'dirty worktree are never selectable', () async {
      final r = await scan();
      final byName = {for (final b in r.merged) b.name: b};
      expect(
        byName['wt/fechado']!.protection?.reason,
        'worktree em ${shortWorktree(f.wt('wt-fechado'))}',
      );
      expect(
        byName['wt/fechado']!.protection?.worktreePath,
        f.wt('wt-fechado'),
      );
      expect(byName['wt/sujo']!.protection, isNotNull);
      expect(byName['feat/mergeada']!.protection, isNull);
      final sujo = r.worktrees.firstWhere((w) => w.path == f.wt('wt-sujo'));
      expect(sujo.protection?.reason, 'alterações não commitadas');
      final fechado = r.worktrees.firstWhere(
        (w) => w.path == f.wt('wt-fechado'),
      );
      expect(fechado.protection, isNull);
    });

    test('branchProtection', () {
      Protection? p(String b) => branchProtection(
        b,
        defaultBranch: 'main',
        mainPath: '/r',
        checkedOut: {'atual': '/r', 'outra': '/w/x/outra'},
        liveBranches: {'viva'},
      );
      expect(p('main')?.reason, 'branch padrão');
      expect(p('atual')?.reason, 'branch atual');
      expect(p('viva')?.reason, 'sessão viva');
      expect(p('outra')?.reason, 'worktree em x/outra');
      expect(p('outra')?.worktreePath, '/w/x/outra');
      expect(p('livre'), isNull);
    });

    test('worktreeProtection', () {
      expect(worktreeProtection(live: true)?.reason, 'sessão viva');
      expect(
        worktreeProtection(dirty: true)?.reason,
        'alterações não commitadas',
      );
      expect(worktreeProtection(locked: true)?.reason, 'bloqueado');
      expect(worktreeProtection(), isNull);
    });

    test('the current branch of the main repository is protected', () async {
      await gitIn(f.repo, ['switch', '-q', 'feat/mergeada']);
      addTearDown(() => gitIn(f.repo, ['switch', '-q', 'main']));
      final r = await scan();
      final b = r.merged.firstWhere((b) => b.name == 'feat/mergeada');
      expect(b.protection?.reason, 'branch atual');
    });
  });
}
