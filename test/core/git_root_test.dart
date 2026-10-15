import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_root.dart';

Future<ProcessResult> realRun(String exe, List<String> args) =>
    Process.run(exe, args);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('promptorium-git-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('resolves the repository root from a subfolder (real git)', () async {
    final init = await Process.run('git', ['init', '-q', tmp.path]);
    expect(init.exitCode, 0, reason: '${init.stderr}');
    final sub = Directory('${tmp.path}/lib/src')..createSync(recursive: true);

    final root = await resolveGitRoot(sub.path, run: realRun);
    expect(
      Directory(root).resolveSymbolicLinksSync(),
      tmp.resolveSymbolicLinksSync(),
    );
    expect(folderName(root), folderName(tmp.path));
  });

  test('rejects missing, relative, empty and non-git folders', () async {
    Future<String> check(String p) => resolveGitRoot(p, run: realRun);
    final invalid = throwsA(isA<InvalidWorkspaceFolder>());

    await expectLater(check(''), invalid);
    await expectLater(check('relative/path'), invalid);
    await expectLater(check('${tmp.path}/missing'), invalid);
    // tmp is not a repository (assuming the system temp dir is not in one).
    await expectLater(
      check(tmp.path),
      throwsA(
        isA<InvalidWorkspaceFolder>().having(
          (e) => e.message,
          'message',
          contains('repositório git'),
        ),
      ),
    );
  });

  test('git missing from PATH is reported', () async {
    Future<ProcessResult> noGit(String e, List<String> a) async =>
        throw ProcessException(e, a, 'No such file or directory', 2);
    await expectLater(
      resolveGitRoot(tmp.path, run: noGit),
      throwsA(
        isA<InvalidWorkspaceFolder>().having(
          (e) => e.message,
          'message',
          'git não encontrado.',
        ),
      ),
    );
  });

  test('expandHome', () {
    expect(expandHome('~/x', home: '/home/u'), '/home/u/x');
    expect(expandHome('~', home: '/home/u'), '/home/u');
    expect(expandHome('/abs', home: '/home/u'), '/abs');
    expect(folderName('/a/b/'), 'b');
  });
}
