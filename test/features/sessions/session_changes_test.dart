import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/sessions/session_changes.dart';

import '../../core/git/git_test_utils.dart';

/// SPEC-111: what a session in a worktree changed, also after the work was
/// committed (by the app at the end of a Codex turn, or by the agent).
void main() {
  late Directory tmp;
  late String root;
  late String wt;
  late List<List<String>> calls;

  GitService gitAt(String dir) => GitService(
    dir,
    run: (exe, args) {
      calls.add(args);
      return Process.run(exe, args);
    },
  );

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('changes-111-');
    root = await createRepo(tmp);
    wt = '${tmp.path}/wt';
    await gitIn(root, ['worktree', 'add', '-q', wt, '-b', 'sessao']);
    calls = [];
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> commitIn(String dir, String msg) async {
    await gitIn(dir, ['add', '-A']);
    await gitIn(dir, ['commit', '-q', '-m', msg]);
  }

  test('R1, R5: a session that committed (Claude Code committing by itself, '
      "or the app's commit of a Codex turn) still lists the files and the "
      'diff lines', () async {
    File('$wt/a.txt').writeAsStringSync('nova\n', mode: FileMode.append);
    File('$wt/b.txt').writeAsStringSync('um\ndois\n');
    await commitIn(wt, 'turno');
    expect((await gitIn(wt, ['status', '--porcelain'])).trim(), isEmpty);

    final c = await loadSessionChanges(gitAt(wt), baseBranch: 'main');
    expect(c.error, isNull);
    expect(c.base, isNotNull);
    expect(c.entries.map((e) => e.path), ['a.txt', 'b.txt']);
    expect(c.entries.map((e) => e.x), ['M', 'A']);
    expect(c.entries.any((e) => e.isUntracked), isFalse);
    expect(c.count, 2);
    expect(c.numstat['a.txt'], (1, 0));
    expect(c.numstat['b.txt'], (2, 0));
    expect(c.files.map((f) => f.path), ['a.txt', 'b.txt']);
    final added = [
      for (final h in c.files.last.hunks)
        for (final l in h.lines) l.text,
    ];
    expect(added, containsAll(['um', 'dois']));
    expect(c.baseLabel, 'desde main');
  });

  test('R1: a commit, a loose change and a new untracked file after the '
      'commit all show up', () async {
    File('$wt/b.txt').writeAsStringSync('commitado\n');
    await commitIn(wt, 'turno 1');
    File('$wt/a.txt').writeAsStringSync('solta\n', mode: FileMode.append);
    File('$wt/novo.txt').writeAsStringSync('não rastreado\n');

    final c = await loadSessionChanges(gitAt(wt), baseBranch: 'main');
    expect(c.entries.map((e) => e.path), ['a.txt', 'b.txt', 'novo.txt']);
    expect(c.entries.last.isUntracked, isTrue);
    expect(c.numstat['a.txt'], (1, 0));
    expect(c.numstat['b.txt'], (1, 0));
    expect(c.files.map((f) => f.path), ['a.txt', 'b.txt']);
  });

  test('R1: the measure starts at the merge-base, not at the tip of the '
      'base branch (main moving on does not show up)', () async {
    File('$wt/b.txt').writeAsStringSync('sessão\n');
    await commitIn(wt, 'turno');
    File('$root/c.txt').writeAsStringSync('main andou\n');
    await commitIn(root, 'na main');

    final c = await loadSessionChanges(gitAt(wt), baseBranch: 'main');
    expect(c.entries.map((e) => e.path), ['b.txt']);
  });

  test('R2: a session without baseBranch (project root) measures from HEAD, '
      'as before', () async {
    File('$root/b.txt').writeAsStringSync('commitado\n');
    await commitIn(root, 'commit na raiz');
    File('$root/a.txt').writeAsStringSync('solta\n', mode: FileMode.append);
    File('$root/novo.txt').writeAsStringSync('x\n');

    final git = gitAt(root);
    final c = await loadSessionChanges(git);
    expect(c.base, isNull);
    expect(c.entries.map((e) => e.toString()), [' M a.txt', '?? novo.txt']);
    expect(c.numstat.keys, ['a.txt']);
    expect(c.files.map((f) => f.path), ['a.txt']);
    expect(c.baseLabel, 'git diff HEAD');
    expect(calls.any((a) => a.contains('merge-base')), isFalse);
  });

  test('R2: without a merge-base (deleted ref) it falls back to HEAD without '
      'an error', () async {
    File('$wt/b.txt').writeAsStringSync('commitado\n');
    await commitIn(wt, 'turno');
    File('$wt/a.txt').writeAsStringSync('solta\n', mode: FileMode.append);

    final c = await loadSessionChanges(gitAt(wt), baseBranch: 'apagada');
    expect(c.error, isNull);
    expect(c.base, isNull);
    expect(c.entries.map((e) => e.path), ['a.txt']);
    expect(c.baseLabel, 'git diff HEAD');
  });

  test(
    'R2: without a shared history (orphan branch) it falls back to HEAD',
    () async {
      await gitIn(root, ['checkout', '-q', '--orphan', 'solta']);
      await gitIn(root, ['rm', '-rq', '--cached', '.']);
      File('$root/z.txt').writeAsStringSync('z\n');
      await gitIn(root, ['add', 'z.txt']);
      await gitIn(root, ['commit', '-q', '-m', 'órfã']);

      final c = await loadSessionChanges(gitAt(wt), baseBranch: 'solta');
      expect(c.error, isNull);
      expect(c.base, isNull);
      expect(c.entries, isEmpty);
    },
  );

  test('R6: one merge-base per load and no git call per file', () async {
    for (var i = 0; i < 12; i++) {
      File('$wt/f$i.txt').writeAsStringSync('$i\n');
    }
    await commitIn(wt, 'muitos');
    for (var i = 0; i < 5; i++) {
      File('$wt/u$i.txt').writeAsStringSync('$i\n');
    }
    final c = await loadSessionChanges(gitAt(wt), baseBranch: 'main');
    expect(c.count, 17);
    expect(calls.where((a) => a.contains('merge-base')), hasLength(1));
    expect(calls, hasLength(5));
  });

  test('parseNameStatusZ reads letters and paths with spaces', () {
    expect(
      parseNameStatusZ('M\x00a b.txt\x00D\x00c.txt\x00')
          .map((e) => '${e.x} ${e.path}'),
      ['M a b.txt', 'D c.txt'],
    );
    expect(parseNameStatusZ(''), isEmpty);
  });
}
