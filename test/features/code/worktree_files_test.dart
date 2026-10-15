import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/code/worktree_files.dart';

import '../../core/git/git_test_utils.dart';

void main() {
  late Directory tmp;
  late String repo;
  late WorktreeFiles files;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-code-');
    repo = await createRepo(tmp);
    File('$repo/.gitignore').writeAsStringSync('build/\n*.log\n');
    Directory('$repo/lib/ui').createSync(recursive: true);
    File('$repo/lib/main.dart').writeAsStringSync('void main() {}\n');
    File('$repo/lib/ui/app.dart').writeAsStringSync('class App {}\n');
    File('$repo/b.txt').writeAsStringSync('b\n');
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'mais']);
    // Ignored, untracked, modified, deleted, added.
    Directory('$repo/build').createSync();
    File('$repo/build/out.bin').writeAsStringSync('x');
    File('$repo/debug.log').writeAsStringSync('x');
    File('$repo/novo.dart').writeAsStringSync('// novo\n');
    File('$repo/lib/main.dart')
        .writeAsStringSync('void main() { print(1); }\n');
    File('$repo/b.txt').deleteSync();
    File('$repo/lib/ui/added.dart').writeAsStringSync('x\n');
    await gitIn(repo, ['add', 'lib/ui/added.dart']);
    files = WorktreeFiles(repo);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'tree lists files respecting .gitignore, hides .git, marks A/M/D/?',
    () async {
      final index = await files.index();
      expect(index.files, contains('lib/ui/app.dart'));
      expect(index.files, contains('novo.dart'));
      expect(index.files, isNot(contains('debug.log')));
      expect(index.files.where((f) => f.startsWith('build/')), isEmpty);
      expect(index.files.where((f) => f.startsWith('.git/')), isEmpty);
      final root = index.children('');
      expect(root.first.path, 'lib'); // folders first
      expect(root.first.isDir, isTrue);
      expect(root.map((e) => e.path), isNot(contains('build')));
      expect(root.map((e) => e.path), isNot(contains('.git')));
      final lib = index.children('lib');
      expect(lib.map((e) => e.path), ['lib/ui', 'lib/main.dart']);
      expect(lib.first.changedInside, isTrue);
      expect(index.marks['lib/main.dart'], FileMark.modified);
      expect(index.marks['novo.dart'], FileMark.untracked);
      expect(index.marks['b.txt'], FileMark.deleted);
      expect(index.marks['lib/ui/added.dart'], FileMark.added);
    },
  );

  test('create / rename / delete inside the worktree', () async {
    expect(await files.createFile('lib/core/x.dart'), 'lib/core/x.dart');
    expect(File('$repo/lib/core/x.dart').existsSync(), isTrue);
    await expectLater(
      files.createFile('lib/core/x.dart'),
      throwsA(isA<CodeFileException>()),
    );
    await files.createFolder('docs/vazia');
    expect(Directory('$repo/docs/vazia').existsSync(), isTrue);
    final idx = await files.index(extraDirs: {'docs/vazia'});
    expect(idx.isDir('docs/vazia'), isTrue);

    await files.rename('lib/core/x.dart', 'lib/y.dart');
    expect(File('$repo/lib/y.dart').existsSync(), isTrue);
    expect(File('$repo/lib/core/x.dart').existsSync(), isFalse);
    await files.rename('lib/core', 'lib/nucleo');
    expect(Directory('$repo/lib/nucleo').existsSync(), isTrue);

    await files.delete('lib/y.dart');
    expect(File('$repo/lib/y.dart').existsSync(), isFalse);
    await files.delete('lib/nucleo');
    expect(Directory('$repo/lib/nucleo').existsSync(), isFalse);
  });

  test('rejects path traversal and .git', () async {
    final outside = Directory('${tmp.path}/fora')..createSync();
    Link('$repo/link-fora').createSync(outside.path);
    for (final bad in [
      '../fora/x.txt',
      'lib/../../fora/x.txt',
      '/etc/passwd',
      '~/x',
      '.git/config',
      'lib//x',
      './x',
      '',
      'link-fora/x.txt',
    ]) {
      await expectLater(
        files.createFile(bad),
        throwsA(isA<CodeFileException>()),
        reason: bad,
      );
    }
    await expectLater(
      files.rename('a.txt', '../fora/a.txt'),
      throwsA(isA<CodeFileException>()),
    );
    await expectLater(
      files.delete('../fora'),
      throwsA(isA<CodeFileException>()),
    );
    await expectLater(
      files.read('../repo/a.txt'),
      throwsA(isA<CodeFileException>()),
    );
    expect(outside.listSync(), isEmpty);
    expect(File('$repo/a.txt').existsSync(), isTrue);
    expect(Directory(repo).existsSync(), isTrue);
  });

  test(
    'symlinks leaving the worktree are refused on every operation',
    () async {
      final outside = Directory('${tmp.path}/fora2')..createSync();
      File('${outside.path}/segredo.txt').writeAsStringSync('x');
      // File link to an existing outside file + dangling link to an outside
      // path that does not exist yet.
      Link('$repo/link-arquivo').createSync('${outside.path}/segredo.txt');
      Link('$repo/link-solto').createSync('${outside.path}/novo.txt');
      for (final op in <Future<Object?> Function()>[
        () => files.read('link-arquivo'),
        () => files.write('link-arquivo', 'y'),
        () => files.write('link-solto', 'y'),
        () => files.read('link-solto'),
        () => files.createFile('link-solto'),
        () => files.delete('link-arquivo'),
        () => files.rename('a.txt', 'link-solto'),
        () => files.stat('link-solto'),
      ]) {
        await expectLater(op(), throwsA(isA<CodeFileException>()));
      }
      expect(File('${outside.path}/novo.txt').existsSync(), isFalse);
      expect(File('${outside.path}/segredo.txt').readAsStringSync(), 'x');
      expect(File('$repo/a.txt').existsSync(), isTrue);
    },
  );

  test('binary and > 2 MB files are not opened', () async {
    File('$repo/img.png').writeAsBytesSync([0x89, 0x50, 0, 1, 2]);
    File('$repo/big.txt').writeAsStringSync('a' * (2 * 1024 * 1024 + 1));
    expect(await files.read('img.png'), isA<UnsupportedFileContent>());
    expect(await files.read('big.txt'), isA<UnsupportedFileContent>());
    final ok = await files.read('a.txt');
    expect(ok, isA<TextFileContent>());
    expect((ok as TextFileContent).text, startsWith('linha 1\n'));
    expect(ok.crlf, isFalse);
  });

  test('changed lines against the merge-base of a session worktree', () async {
    final git = GitService(repo, worktreesBase: '${tmp.path}/wt');
    final wt = await git.addWorktree('s1');
    final lines = File('${wt.path}/a.txt').readAsLinesSync();
    lines[2] = 'linha 3 (agente)';
    lines.insert(10, 'nova');
    File('${wt.path}/a.txt').writeAsStringSync('${lines.join('\n')}\n');
    await gitIn(wt.path, ['commit', '-q', '-am', 'agente']);
    File('${wt.path}/a.txt')
        .writeAsStringSync('${lines.join('\n')}\nfim (nao commitado)\n');
    final wf = WorktreeFiles(wt.path);
    final base = await wf.marksBase('main');
    expect(base, isNot('HEAD'));
    expect(await wf.changedLines('a.txt', base: base), {2, 10, 31});
    File('${wt.path}/u.txt').writeAsStringSync('1\n2\n');
    expect(await wf.changedLines('u.txt', base: base), {0, 1});
  });

  test('gutter marks: agent lines shift with the unsaved edit', () {
    final saved = ['a', 'b', 'c', 'd', 'e'];
    final current = ['a', 'X', 'Y', 'b', 'c', 'd', 'e'];
    final m = lineMarks(
      saved: saved,
      current: current,
      agentLines: {0, 3},
      agent: 'g',
      user: 'u',
    );
    expect(m, {0: 'g', 1: 'u', 2: 'u', 5: 'g'});
    expect(editedRange(saved, saved), isNull);
    expect(
      lineMarks(
        saved: saved,
        current: saved,
        agentLines: {4},
        agent: 'g',
        user: 'u',
      ),
      {4: 'g'},
    );
    // Deletion marks the line where it happened.
    expect(
      lineMarks(
        saved: saved,
        current: ['a', 'b', 'd', 'e'],
        agentLines: const {},
        agent: 'g',
        user: 'u',
      ),
      {2: 'u'},
    );
  });

  test('fuzzy file search', () {
    final list = [
      'lib/ui/shell/app_shell.dart',
      'lib/features/code/code_screen.dart',
      'test/ui/app_shell_test.dart',
      'README.md',
    ];
    expect(fuzzyFilter(list, 'appsh').first, 'lib/ui/shell/app_shell.dart');
    expect(fuzzyFilter(list, 'cscr'), ['lib/features/code/code_screen.dart']);
    expect(fuzzyFilter(list, 'zzz'), isEmpty);
    expect(fuzzyFilter(list, '').length, 4);
  });
}
