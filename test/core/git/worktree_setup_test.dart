import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/git/worktree_setup.dart';
import 'package:promptorium/core/process/shell_runner.dart';

import 'git_test_utils.dart';

void main() {
  late Directory tmp;
  late String repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-wtsetup-');
    repo = await createRepo(tmp);
    File('$repo/.gitignore').writeAsStringSync('.env\nconfig/local.json\n');
    await gitIn(repo, ['add', '.gitignore']);
    await gitIn(repo, ['commit', '-q', '-m', 'ignore']);
    File('$repo/.env').writeAsStringSync('SEGREDO=1\n');
    Directory('$repo/config').createSync();
    File('$repo/config/local.json').writeAsStringSync('{}');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('copies only ignored files that exist; runs preparar with the '
      'worktree variables', () async {
    final git = GitService(repo, worktreesBase: '${tmp.path}/wt');
    final wt = await git.addWorktree('x');
    final setup = WorktreeSetup(root: git, shell: runShell);
    final r = await setup.run(
      wt.path,
      copy: ['.env', 'config/local.json', 'a.txt', 'nao-existe'],
      prepare: r'echo "porta=$PROMPTORIUM_PORT" > preparado.txt',
      environment: worktreeEnvironment(
        root: repo,
        worktree: wt.path,
        specCode: 'SPEC-001',
        port: 4002,
      ),
    );
    expect(r.ok, isTrue);
    expect(r.copied, ['.env', 'config/local.json']);
    expect(File('${wt.path}/.env').readAsStringSync(), 'SEGREDO=1\n');
    expect(File('${wt.path}/preparado.txt').readAsStringSync(), 'porta=4002\n');
    // Already there: not copied again.
    expect(await setup.copyFiles(wt.path, ['.env']), isEmpty);

    final bad = await setup.run(wt.path, prepare: 'echo quebrou; exit 4');
    expect(bad.ok, isFalse);
    expect(bad.prepare!.output, contains('quebrou'));
  });

  test('index: smallest free from 1; environment', () {
    expect(nextWorktreeIndex([]), 1);
    expect(nextWorktreeIndex([1, 2, 4, null]), 3);
    expect(worktreeEnvironment(root: '/r', worktree: '/w'), {
      'PROMPTORIUM_ROOT': '/r',
      'PROMPTORIUM_WORKTREE': '/w',
    });
    expect(
      worktreeEnvironment(root: '/r', worktree: '/w', specCode: 'S', port: 1),
      containsPair('PROMPTORIUM_PORT', '1'),
    );
  });
}
