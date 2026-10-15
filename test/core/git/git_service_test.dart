import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/core/git/git_service.dart';

import 'git_test_utils.dart';

void main() {
  late Directory tmp;
  late String repo;
  late GitService git;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-gitsvc-');
    repo = await createRepo(tmp);
    git = GitService(repo, worktreesBase: '${tmp.path}/worktrees');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('currentBranch, detached HEAD and log', () async {
    expect(await git.currentBranch(), 'main');
    final log = await git.log(5);
    expect(log, hasLength(1));
    expect(log.single.subject, 'inicial');
    expect(log.single.author, 'Teste');
    expect(log.single.sha, hasLength(40));

    await gitIn(repo, ['checkout', '-q', '--detach']);
    expect(await git.currentBranch(), isNull);
  });

  test(
    'status parses porcelain v1 (modified, untracked, staged, rename)',
    () async {
      File('$repo/a.txt').writeAsStringSync('mudou\n');
      File('$repo/novo arquivo.txt').writeAsStringSync('x\n');
      Directory('$repo/dir').createSync();
      File('$repo/dir/b.txt').writeAsStringSync('b\n');
      File('$repo/c.txt').writeAsStringSync('c\n');
      await gitIn(repo, ['add', 'c.txt']);
      await gitIn(repo, ['commit', '-q', '-m', 'c']);
      await gitIn(repo, ['mv', 'c.txt', 'd.txt']);

      final st = await git.status();
      final byPath = {for (final e in st) e.path: e};
      expect(byPath['a.txt']!.x, ' ');
      expect(byPath['a.txt']!.y, 'M');
      expect(byPath['novo arquivo.txt']!.isUntracked, isTrue);
      expect(byPath['dir/b.txt']!.isUntracked, isTrue);
      expect(byPath['d.txt']!.x, 'R');
      expect(byPath['d.txt']!.origPath, 'c.txt');
    },
  );

  test('addWorktree / listWorktrees / diff / merge / removeWorktree', () async {
    final wt = await git.addWorktree('spec-001-login');
    expect(wt.branch, 'pr/spec-001-login');
    expect(wt.path, '${tmp.path}/worktrees/repo-spec-001-login');
    expect(File('${wt.path}/a.txt').existsSync(), isTrue);

    final list = await git.listWorktrees();
    expect(list, hasLength(2));
    expect(list.first.branch, 'main');
    final created = list.firstWhere((w) => w.branch == 'pr/spec-001-login');
    expect(
      Directory(created.path).resolveSymbolicLinksSync(),
      Directory(wt.path).resolveSymbolicLinksSync(),
    );
    expect(created.head, hasLength(40));

    // Work in the worktree, then diff it against main.
    final wtGit = GitService(wt.path, worktreesBase: git.worktreesBase);
    expect(await wtGit.currentBranch(), 'pr/spec-001-login');
    File('${wt.path}/a.txt').writeAsStringSync(
      File('${wt.path}/a.txt')
          .readAsStringSync()
          .replaceFirst('linha 2\n', 'linha dois\n'),
    );
    final working = DiffParser.parse(await wtGit.diff());
    expect(working.single.path, 'a.txt');
    await gitIn(wt.path, ['commit', '-q', '-am', 'muda linha 2']);
    final vsMain = DiffParser.parse(
      await wtGit.diff(base: 'main', path: 'a.txt'),
    );
    expect(vsMain.single.status, DiffFileStatus.modified);
    expect(
      vsMain.single.hunks.single.lines
          .where((l) => l.kind == DiffLineKind.add)
          .single
          .text,
      'linha dois',
    );

    // Merge into main (fast-forward) and clean up.
    await git.merge('pr/spec-001-login');
    expect(File('$repo/a.txt').readAsStringSync(), contains('linha dois'));
    expect((await git.log(1)).single.subject, 'muda linha 2');

    await expectLater(
      git.addWorktree('spec-001-login'),
      throwsA(isA<GitException>()),
    );
    await expectLater(git.addWorktree('../fora'), throwsA(isA<GitException>()));

    await git.removeWorktree(wt.path);
    expect(Directory(wt.path).existsSync(), isFalse);
    expect(await git.listWorktrees(), hasLength(1));
    await git.deleteBranch('pr/spec-001-login');
  });

  test('worktree from a base branch; dirty remove needs force', () async {
    await gitIn(repo, ['branch', 'dev']);
    final wt = await git.addWorktree('x', baseBranch: 'dev');
    File('${wt.path}/sujo.txt').writeAsStringSync('?');
    await expectLater(
      git.removeWorktree(wt.path),
      throwsA(
        isA<GitException>().having((e) => e.stderr, 'stderr', isNotEmpty),
      ),
    );
    await git.removeWorktree(wt.path, force: true);
    expect(Directory(wt.path).existsSync(), isFalse);
  });

  test('merge conflict raises GitException with stderr/stdout info', () async {
    await gitIn(repo, ['checkout', '-q', '-b', 'outra']);
    File('$repo/a.txt').writeAsStringSync('outra\n');
    await gitIn(repo, ['commit', '-q', '-am', 'outra']);
    await gitIn(repo, ['checkout', '-q', 'main']);
    File('$repo/a.txt').writeAsStringSync('main\n');
    await gitIn(repo, ['commit', '-q', '-am', 'main']);
    await expectLater(
      git.merge('outra'),
      throwsA(
        isA<GitException>().having((e) => '$e', 'text', contains('a.txt')),
      ),
    );
    await git.mergeAbort();
    expect(await git.status(), isEmpty);
  });

  test('errors are typed', () async {
    final bad = GitService('${tmp.path}/nao-existe');
    await expectLater(bad.status(), throwsA(isA<GitException>()));
    await expectLater(bad.currentBranch(), throwsA(isA<GitException>()));
    final noGit = GitService(
      repo,
      run: (e, a) => throw const ProcessException('git', [], 'não encontrado'),
    );
    await expectLater(noGit.log(1), throwsA(isA<GitException>()));
  });

  test('parseWorktreeList handles detached / locked / bare blocks', () {
    const out =
        'worktree /r\nHEAD aaa\nbranch refs/heads/main\n\n'
        'worktree /w1\nHEAD bbb\ndetached\nlocked motivo\n\n'
        'worktree /w2\nbare\nprunable gitdir file points to non-existent location\n';
    final l = GitService.parseWorktreeList(out);
    expect(l.map((w) => w.path), ['/r', '/w1', '/w2']);
    expect(l[0].branch, 'main');
    expect(l[1].detached && l[1].locked, isTrue);
    expect(l[1].branch, isNull);
    expect(l[2].bare && l[2].prunable, isTrue);
  });

  test('refs that look like options are rejected before running git', () {
    expect(() => git.merge('--abort'), throwsA(isA<GitException>()));
    expect(() => git.diff(base: '-R'), throwsA(isA<GitException>()));
    expect(() => git.deleteBranch('-D'), throwsA(isA<GitException>()));
    expect(
      () => git.addWorktree('ok', baseBranch: '--orphan'),
      throwsA(isA<GitException>()),
    );
  });
}
