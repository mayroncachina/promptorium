import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';

import 'git_test_utils.dart';

/// SPEC-084 R2, R3, R4, R8: the restore point of a turn and the git steps
/// of the undo, always in temporary repositories.
void main() {
  late Directory tmp;
  late String repo;
  late GitService git;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-restore-git-');
    repo = await createRepo(tmp);
    git = GitService(repo);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  File f(String p) => File('$repo/$p');

  test('captureState keeps modified and untracked files, leaves the '
      'ignored and the big ones out, and touches neither the index, the '
      'stage nor the stash', () async {
    f('.gitignore').writeAsStringSync('.env\n');
    f('b.txt').writeAsStringSync('b\n');
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'b']);
    // Something in the stash, something staged, something untracked.
    f('b.txt').writeAsStringSync('stash\n');
    await gitIn(repo, ['stash', '-q']);
    f('a.txt').writeAsStringSync('staged\n');
    await gitIn(repo, ['add', 'a.txt']);
    f('b.txt').writeAsStringSync('modificado\n');
    f('novo.txt').writeAsStringSync('novo\n');
    f('.env').writeAsStringSync('SEGREDO=1\n');
    f('dump.sql').writeAsStringSync('x' * 2048);
    final statusBefore = await gitIn(repo, ['status', '--porcelain']);
    final stashBefore = await gitIn(repo, ['stash', 'list']);
    final indexBefore = await gitIn(repo, ['diff', '--cached']);

    final s = await git.captureState(maxUntrackedBytes: 1024);

    expect(s.branch, 'main');
    expect(s.head, (await gitIn(repo, ['rev-parse', 'HEAD'])).trim());
    expect(s.sha, isNot(s.head));
    expect(s.large, ['dump.sql']);
    expect(s.files, 3); // a.txt, b.txt, novo.txt
    final files = (await gitIn(repo, [
      'ls-tree',
      '-r',
      '--name-only',
      s.sha,
    ])).split('\n');
    expect(files, containsAll(['a.txt', 'b.txt', 'novo.txt', '.gitignore']));
    expect(files, isNot(contains('.env')));
    expect(files, isNot(contains('dump.sql')));
    expect(await gitIn(repo, ['show', '${s.sha}:b.txt']), 'modificado\n');
    expect(await gitIn(repo, ['status', '--porcelain']), statusBefore);
    expect(await gitIn(repo, ['stash', 'list']), stashBefore);
    expect(await gitIn(repo, ['diff', '--cached']), indexBefore);
  });

  test('a clean tree gives HEAD; no commit is an error', () async {
    final s = await git.captureState();
    expect(s.sha, s.head);
    expect(s.files, 0);
    final empty = Directory('${tmp.path}/vazio')..createSync();
    await gitIn(empty.path, ['init', '-q']);
    expect(
      () => GitService(empty.path).captureState(),
      throwsA(isA<GitException>()),
    );
  });

  test(
    'treeChanges lists modified, created and deleted with the lines',
    () async {
      f('b.txt').writeAsStringSync('b\n');
      await gitIn(repo, ['add', 'b.txt']);
      await gitIn(repo, ['commit', '-q', '-m', 'b']);
      final start = await git.captureState();
      f('a.txt').writeAsStringSync('x\n');
      f('c.txt').writeAsStringSync('c\nc\n');
      f('b.txt').deleteSync();
      final end = await git.captureState();
      final changes = await git.treeChanges(start.sha, end.sha);
      expect(changes.map((c) => '$c'), [
        'modified a.txt',
        'deleted b.txt',
        'created c.txt',
      ]);
      expect(changes.first.added, 1);
      expect(changes.first.removed, 30);
      expect(changes.last.added, 2);
    },
  );

  test('restorePaths brings back, deletes and leaves the rest alone', () async {
    f('b.txt').writeAsStringSync('da pessoa\n');
    f('pedido.ts').writeAsStringSync('pedido\n');
    await gitIn(repo, ['add', 'pedido.ts']);
    await gitIn(repo, ['commit', '-q', '-m', 'pedido']);
    final start = await git.captureState();
    // The turn: edit, create (in a new folder), delete.
    f('a.txt').writeAsStringSync('agente\n');
    Directory('$repo/src').createSync();
    f('src/order.ts').writeAsStringSync('order\n');
    f('pedido.ts').deleteSync();
    f('b.txt').writeAsStringSync('da pessoa e do agente\n');

    await git.restorePaths(start.sha, ['a.txt', 'src/order.ts', 'pedido.ts']);

    expect(f('a.txt').readAsStringSync(), startsWith('linha 1\n'));
    expect(f('src/order.ts').existsSync(), isFalse);
    expect(Directory('$repo/src').existsSync(), isFalse);
    expect(f('pedido.ts').readAsStringSync(), 'pedido\n');
    expect(f('b.txt').readAsStringSync(), 'da pessoa e do agente\n');
    expect(await gitIn(repo, ['diff', '--cached']), '');
  });

  test(
    'moveHead + restorePaths undo a commit with a staged new file',
    () async {
      final start = await git.captureState();
      f('a.txt').writeAsStringSync('agente\n');
      f('novo.ts').writeAsStringSync('novo\n');
      await gitIn(repo, ['add', '-A']);
      await gitIn(repo, ['commit', '-q', '-m', 'wip']);
      expect(
        (await git.commitsBetween(
          start.head,
          (await git.headSha())!,
        )).single.subject,
        'wip',
      );

      await git.moveHead(start.head, branch: 'main');
      await git.restorePaths(start.sha, ['a.txt', 'novo.ts']);

      expect((await git.headSha()), start.head);
      expect(await gitIn(repo, ['status', '--porcelain']), '');
      expect(f('novo.ts').existsSync(), isFalse);
    },
  );

  test(
    'moveHead goes back to the start branch and keeps the new one',
    () async {
      final start = await git.captureState();
      await gitIn(repo, ['switch', '-q', '-c', 'feat/order']);
      f('a.txt').writeAsStringSync('agente\n');
      await gitIn(repo, ['commit', '-q', '-am', 'order']);
      final featTip = (await git.headSha())!;

      await git.moveHead(start.head, branch: 'main');
      await git.restorePaths(start.sha, ['a.txt']);

      expect(await git.currentBranch(), 'main');
      expect(await git.resolveRef('feat/order'), featTip);
      expect(await gitIn(repo, ['status', '--porcelain']), '');
    },
  );

  test('pushedCommits finds the commits already on a remote branch', () async {
    final remote = Directory('${tmp.path}/remoto.git');
    await gitIn(tmp.path, ['init', '-q', '--bare', remote.path]);
    await gitIn(repo, ['remote', 'add', 'origin', remote.path]);
    final base = (await git.headSha())!;
    f('a.txt').writeAsStringSync('1\n');
    await gitIn(repo, ['commit', '-q', '-am', 'enviado']);
    await gitIn(repo, ['push', '-q', 'origin', 'main']);
    final sent = (await git.headSha())!;
    f('a.txt').writeAsStringSync('2\n');
    await gitIn(repo, ['commit', '-q', '-am', 'local']);

    final p = await git.pushedCommits(base, (await git.headSha())!);
    expect(p.commits, {sent});
    expect(p.remotes, ['origin/main']);
  });

  test(
    'refs under refs/promptorium/restore/ and the space they hold',
    () async {
      f('grande.bin').writeAsStringSync('y' * 4096);
      final s = await git.captureState();
      await git.updateRef('refs/promptorium/restore/s1/1-inicio', s.sha);
      expect(await git.refsUnder('refs/promptorium/restore/'), {
        'refs/promptorium/restore/s1/1-inicio': s.sha,
      });
      expect(
        await git.diskUsageOnly('refs/promptorium/restore/'),
        greaterThan(0),
      );
      // Hidden: not a branch, not in the log.
      expect(await gitIn(repo, ['branch', '--list']), contains('main'));
      expect(
        await gitIn(repo, ['branch', '--list']),
        isNot(contains('restore')),
      );
      expect(await gitIn(repo, ['log', '--oneline']), isNot(contains('ponto')));
      await git.deleteRefList(['refs/promptorium/restore/s1/1-inicio']);
      expect(await git.refsUnder('refs/promptorium/restore/'), isEmpty);
    },
  );

  test(
    'ignoredChangedSince lists the ignored files changed in the turn',
    () async {
      f('.gitignore').writeAsStringSync('.env\nbuild/\n');
      await gitIn(repo, ['add', '.']);
      await gitIn(repo, ['commit', '-q', '-m', 'ignore']);
      final since = DateTime.now().subtract(const Duration(seconds: 2));
      f('.env').writeAsStringSync('X=1\n');
      expect(await git.ignoredChangedSince(since), ['.env']);
      expect(
        await git.ignoredChangedSince(
          DateTime.now().add(const Duration(hours: 1)),
        ),
        isEmpty,
      );
    },
  );
}
