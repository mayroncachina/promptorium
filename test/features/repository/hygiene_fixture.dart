import 'dart:io';

import '../../core/git/git_test_utils.dart';

/// Runs git in [dir] with [env] (old commit dates).
Future<String> gitEnv(
  String dir,
  List<String> args,
  Map<String, String> env,
) async {
  final r = await Process.run('git', ['-C', dir, ...args], environment: env);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} falhou: ${r.stderr}');
  }
  return '${r.stdout}';
}

/// Writes [file] in [dir] and commits it (with an old date when [date]).
Future<String> commitFile(
  String dir,
  String file,
  String content, {
  DateTime? date,
}) async {
  File('$dir/$file').writeAsStringSync(content);
  await gitIn(dir, ['add', file]);
  final d = date?.toIso8601String();
  await gitEnv(
    dir,
    ['commit', '-q', '-m', 'muda $file'],
    {'GIT_COMMITTER_DATE': ?d, 'GIT_AUTHOR_DATE': ?d},
  );
  return (await gitIn(dir, ['rev-parse', 'HEAD'])).trim();
}

/// A repository with every case of the Higiene tab, all inside [tmp]:
///
/// - `origin`: a local bare remote;
/// - `feat/mergeada`: merged into main by a merge commit, pushed;
/// - `feat/squash`: merged by squash (only the PR knows), pushed with
///   upstream;
/// - `feat/sem-upstream-squash`: merged by squash, never pushed;
/// - `feat/aberta`: behind main, no conflict;
/// - `feat/conflito`: behind main, conflicts in `a.txt`;
/// - worktrees: `wt-orfao` (folder deleted), `wt-fechado` (branch merged),
///   `wt-parado` (last commit 30 days ago), `wt-sujo` (merged branch with
///   uncommitted changes), `wt-vivo` (a live session, also old);
/// - refs of SPEC-001 (done), SPEC-002 (open) and SPEC-003 (unknown).
class HygieneFixture {
  HygieneFixture._(this.tmp, this.repo, this.origin);

  final Directory tmp;
  final String repo;
  final String origin;
  late String squashSha;
  late String noUpstreamSquashSha;

  String wt(String name) => '${tmp.path}/$name';

  static Future<HygieneFixture> create(Directory tmp) async {
    final repo = await createRepo(tmp);
    final origin = '${tmp.path}/origin.git';
    await gitIn(tmp.path, ['init', '-q', '--bare', '-b', 'main', origin]);
    await gitIn(repo, ['remote', 'add', 'origin', origin]);
    await gitIn(repo, ['push', '-q', '-u', 'origin', 'main']);
    final f = HygieneFixture._(tmp, repo, origin);
    final old = DateTime.now().subtract(const Duration(days: 30));

    // Open branches start here, before main moves.
    await gitIn(repo, ['branch', 'feat/aberta']);
    await gitIn(repo, ['branch', 'feat/conflito']);

    // Merged by a merge commit.
    await gitIn(repo, ['switch', '-q', '-c', 'feat/mergeada']);
    await commitFile(repo, 'm.txt', 'm\n');
    await gitIn(repo, ['push', '-q', '-u', 'origin', 'feat/mergeada']);
    await gitIn(repo, ['switch', '-q', 'main']);
    await gitIn(repo, ['merge', '-q', '--no-ff', '--no-edit', 'feat/mergeada']);

    // Merged by squash, pushed with upstream.
    await gitIn(repo, ['switch', '-q', '-c', 'feat/squash']);
    f.squashSha = await commitFile(repo, 's.txt', 's\n');
    await gitIn(repo, ['push', '-q', '-u', 'origin', 'feat/squash']);
    await gitIn(repo, ['switch', '-q', 'main']);
    await gitIn(repo, ['merge', '-q', '--squash', 'feat/squash']);
    await gitIn(repo, ['commit', '-q', '-m', 'squash (#2)']);

    // Merged by squash, never pushed: `git branch -d` refuses it.
    await gitIn(repo, ['switch', '-q', '-c', 'feat/sem-upstream-squash']);
    f.noUpstreamSquashSha = await commitFile(repo, 'n.txt', 'n\n');
    await gitIn(repo, ['switch', '-q', 'main']);
    await gitIn(repo, ['merge', '-q', '--squash', 'feat/sem-upstream-squash']);
    await gitIn(repo, ['commit', '-q', '-m', 'squash (#3)']);

    // Main changes a.txt: feat/conflito changes the same line.
    await commitFile(repo, 'a.txt', 'main mudou\n');
    await gitIn(repo, ['push', '-q', 'origin', 'main']);
    await gitIn(repo, ['switch', '-q', 'feat/conflito']);
    await commitFile(repo, 'a.txt', 'conflito\n');
    await gitIn(repo, ['switch', '-q', 'feat/aberta']);
    await commitFile(repo, 'b.txt', 'b\n');
    await gitIn(repo, ['switch', '-q', 'main']);

    // Worktrees.
    await gitIn(repo, [
      'worktree',
      'add',
      '-q',
      '-b',
      'wt/orfao',
      f.wt('wt-orfao'),
    ]);
    Directory(f.wt('wt-orfao')).deleteSync(recursive: true);

    await gitIn(repo, ['branch', 'wt/fechado', 'main']);
    await gitIn(repo, [
      'worktree',
      'add',
      '-q',
      f.wt('wt-fechado'),
      'wt/fechado',
    ]);

    await gitIn(repo, [
      'worktree',
      'add',
      '-q',
      '-b',
      'wt/parado',
      f.wt('wt-parado'),
      'main',
    ]);
    await commitFile(f.wt('wt-parado'), 'p.txt', 'p\n', date: old);

    await gitIn(repo, ['branch', 'wt/sujo', 'main']);
    await gitIn(repo, ['worktree', 'add', '-q', f.wt('wt-sujo'), 'wt/sujo']);
    File('${f.wt('wt-sujo')}/rascunho.txt').writeAsStringSync('não salvo\n');

    await gitIn(repo, [
      'worktree',
      'add',
      '-q',
      '-b',
      'wt/vivo',
      f.wt('wt-vivo'),
      'main',
    ]);
    await commitFile(f.wt('wt-vivo'), 'v.txt', 'v\n', date: old);

    // Internal refs.
    final head = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
    for (final r in [
      'refs/promptorium/SPEC-001/R1-inicio',
      'refs/promptorium/SPEC-001/R2-inicio',
      'refs/promptorium/SPEC-002/R1-inicio',
      'refs/promptorium/SPEC-003/R1-inicio',
    ]) {
      await gitIn(repo, ['update-ref', r, head]);
    }
    return f;
  }

  /// The merged PRs `gh` would list.
  List<Map<String, Object?>> get mergedPrs => [
    {
      'number': 2,
      'url': 'https://github.com/o/r/pull/2',
      'title': 'squash',
      'headRefName': 'feat/squash',
      'headRefOid': squashSha,
      'state': 'MERGED',
      'mergedAt': '2026-11-01T10:00:00Z',
    },
    {
      'number': 3,
      'url': 'https://github.com/o/r/pull/3',
      'title': 'sem upstream',
      'headRefName': 'feat/sem-upstream-squash',
      'headRefOid': noUpstreamSquashSha,
      'state': 'MERGED',
      'mergedAt': '2026-11-01T11:00:00Z',
    },
    {
      'number': 1,
      'url': 'https://github.com/o/r/pull/1',
      'title': 'mergeada',
      'headRefName': 'feat/mergeada',
      'headRefOid': '',
      'state': 'MERGED',
      'mergedAt': '2026-10-30T10:00:00Z',
    },
  ];
}
