import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/project/spec_auto_planner.dart';

import '../board/board_ops_test.dart' show spec;

/// Issue #313: a plan saved by hand is committed (only its file), so the
/// root stays clean for the merge.
void main() {
  late Directory tmp;
  late GitService git;
  final s = spec(1, 'SPEC-001', []);

  Future<String> run(List<String> args) => git.git(args);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-plan-commit-');
    git = GitService(tmp.path);
    Directory('${tmp.path}/specs').createSync();
    File('${tmp.path}/${s.path}').writeAsStringSync('# A\n');
    File('${tmp.path}/outro.txt').writeAsStringSync('a\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> initRepo() async {
    await run(['init', '-q', '-b', 'main']);
    await run(['config', 'user.email', 't@t']);
    await run(['config', 'user.name', 't']);
    await run(['add', '.']);
    await run(['commit', '-q', '-m', 'inicial']);
  }

  test('a tracked spec with a new plan is committed alone', () async {
    await initRepo();
    File('${tmp.path}/${s.path}').writeAsStringSync('# A\n\n## Plano\n\nX\n');
    File('${tmp.path}/outro.txt').writeAsStringSync('b\n');
    expect(await commitSavedPlan(git, s), isTrue);
    expect(
      (await run(['log', '-1', '--format=%s'])).trim(),
      'Plano atualizado: SPEC-001',
    );
    expect(
      (await run(['show', '--name-only', '--format=', 'HEAD'])).trim(),
      s.path,
    );
    // Only the spec: the other change stays for the person.
    expect((await run(['status', '--porcelain'])).trim(), 'M outro.txt');
  });

  test(
    'nothing changed, an untracked spec or no repository: skipped',
    () async {
      expect(await commitSavedPlan(git, s), isFalse); // not a repository
      await initRepo();
      expect(await commitSavedPlan(git, s), isFalse); // unchanged
      final other = spec(2, 'SPEC-002', []);
      File('${tmp.path}/${other.path}').writeAsStringSync('# B\n');
      expect(await commitSavedPlan(git, other), isFalse); // never committed
      expect((await run(['rev-list', '--count', 'HEAD'])).trim(), '1');
    },
  );
}
