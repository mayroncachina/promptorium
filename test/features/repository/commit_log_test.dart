import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/repository/graph/commit_log.dart';
import 'package:promptorium/features/repository/graph/lane_layout.dart';

import '../../core/git/git_test_utils.dart';

/// Commits [message] on the current branch (a file per commit).
Future<String> commitIn(String repo, String message) async {
  final f = File('$repo/f-${message.hashCode}.txt')..writeAsStringSync(message);
  await gitIn(repo, ['add', f.path]);
  await gitIn(repo, ['commit', '-q', '-m', message]);
  return (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
}

/// main ─ SPEC-042 (merged, with a daughter) ─ v0.1.0 ─ SPEC-043 open.
Future<void> buildHistory(String repo) async {
  await gitIn(repo, ['checkout', '-q', '-b', 'spec/042-sprints']);
  await commitIn(repo, 'docs: SPEC-042, sprints');
  await gitIn(repo, ['checkout', '-q', '-b', 'spec/042-t1-dados']);
  await commitIn(repo, 'feat(sprints): dados');
  await gitIn(repo, ['checkout', '-q', 'spec/042-sprints']);
  await gitIn(repo, [
    'merge',
    '-q',
    '--no-ff',
    '-m',
    'Merge pull request #95 from o/spec/042-t1-dados',
    'spec/042-t1-dados',
  ]);
  await gitIn(repo, ['checkout', '-q', 'main']);
  await commitIn(repo, 'fix: na main');
  await gitIn(repo, [
    'merge',
    '-q',
    '--no-ff',
    '-m',
    'Merge pull request #94 from o/spec/042-sprints',
    'spec/042-sprints',
  ]);
  await gitIn(repo, ['branch', '-q', '-D', 'spec/042-t1-dados']);
  await gitIn(repo, ['tag', 'v0.1.0']);
  await gitIn(repo, ['checkout', '-q', '-b', 'spec/043-conflito']);
  await commitIn(repo, 'docs: SPEC-043, conflito');
  await gitIn(repo, ['checkout', '-q', 'main']);
}

void main() {
  late Directory tmp;
  late String repo;
  late CommitLog log;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-graph-');
    repo = await createRepo(tmp);
    await buildHistory(repo);
    log = CommitLog(GitService(repo), defaultBranch: 'main', remote: 'origin');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('decorations: HEAD, local, remote, tag; stash and internal refs '
      'left out', () {
    expect(
      parseDecorations(
        'HEAD -> refs/heads/main, tag: refs/tags/v1, '
        'refs/remotes/origin/main, refs/remotes/origin/HEAD, refs/stash, '
        'refs/promptorium/SPEC-1/x',
      ),
      const [
        CommitRef(RefKind.head, 'HEAD'),
        CommitRef(RefKind.local, 'main'),
        CommitRef(RefKind.tag, 'v1'),
        CommitRef(RefKind.remote, 'origin/main'),
      ],
    );
  });

  test('a remote label only when its local copy is elsewhere', () {
    final row = CommitRow(
      sha: 'a',
      parents: const [],
      author: '',
      time: DateTime(2026),
      subject: '',
      refs: const [
        CommitRef(RefKind.local, 'main'),
        CommitRef(RefKind.remote, 'origin/main'),
        CommitRef(RefKind.remote, 'origin/spec/043-x'),
      ],
    );
    expect(row.branchLabels.map((r) => r.name), ['main', 'origin/spec/043-x']);
    expect(row.branches, ['main', 'origin/main', 'origin/spec/043-x']);
  });

  test('R1 · the log in topological order with refs and parents', () async {
    final refs = await log.refs();
    const q = GraphQuery();
    final page = await log.page(q, log.revisions(q, refs));
    expect(page.more, isFalse);
    final subjects = page.rows.map((r) => r.subject).toList();
    expect(subjects.first, 'docs: SPEC-043, conflito');
    expect(subjects.last, 'inicial');
    expect(subjects, hasLength(7));
    final merge = page.rows.firstWhere((r) => r.subject.contains('#94'));
    expect(merge.isMerge, isTrue);
    expect(merge.tags, ['v0.1.0']);
    expect(merge.branches, ['main']);
    expect(merge.isHead, isTrue);
    expect(merge.author, 'Teste');
    expect(await log.count(q, log.revisions(q, refs)), 7);
  });

  test('R7 · pages of N commits continue where the last one stopped', () async {
    final refs = await log.refs();
    const q = GraphQuery();
    final revs = log.revisions(q, refs);
    final whole = await log.page(q, revs);
    final a = await log.page(q, revs, limit: 3);
    final b = await log.page(q, revs, skip: 3, limit: 3);
    final c = await log.page(q, revs, skip: 6, limit: 3);
    expect(a.more, isTrue);
    expect(c.more, isFalse);
    expect([...a.rows, ...b.rows, ...c.rows], whole.rows);
    // And the lanes continue across the pages.
    final l1 = layoutLanes(a.rows, defaultBranch: 'main');
    final l2 = layoutLanes(b.rows, defaultBranch: 'main', from: l1.state);
    final l3 = layoutLanes(c.rows, defaultBranch: 'main', from: l2.state);
    expect([
      ...l1.rows,
      ...l2.rows,
      ...l3.rows,
    ], layoutLanes(whole.rows, defaultBranch: 'main').rows);
    expect(l3.state.openLanes, 0);
  });

  test('R6 · only the default branch: one commit per merge', () async {
    final refs = await log.refs();
    const q = GraphQuery(scope: GraphScope.defaultBranch);
    final page = await log.page(q, log.revisions(q, refs));
    expect(page.rows.map((r) => r.subject), [
      'Merge pull request #94 from o/spec/042-sprints',
      'fix: na main',
      'inicial',
    ]);
  });

  test('R6 · open specs: the default branch and the spec branches not '
      'merged', () async {
    await gitIn(repo, ['branch', 'spec/042-sprints-copia', 'spec/042-sprints']);
    final refs = await log.refs();
    expect(refs.unmergedSpecs, ['spec/043-conflito']);
    expect(refs.openSpecNumbers, {43});
    const q = GraphQuery(scope: GraphScope.openSpecs);
    expect(log.revisions(q, refs), ['main', 'refs/heads/spec/043-conflito']);
    final page = await log.page(q, log.revisions(q, refs));
    expect(page.rows.first.subject, 'docs: SPEC-043, conflito');
  });

  test('R6 · remote branches without a local copy only when asked', () async {
    final main = (await gitIn(repo, ['rev-parse', 'main~1'])).trim();
    await gitIn(repo, ['update-ref', 'refs/remotes/origin/main', main]);
    await gitIn(repo, ['update-ref', 'refs/remotes/origin/feat-remota', main]);
    await gitIn(repo, ['update-ref', 'refs/promptorium/SPEC-001/x', main]);
    final refs = await log.refs();
    expect(refs.remoteOnly, ['origin/feat-remota']);
    final without = log.revisions(const GraphQuery(), refs);
    expect(without, contains('refs/remotes/origin/main'));
    expect(without, isNot(contains('refs/remotes/origin/feat-remota')));
    final withRemote = log.revisions(const GraphQuery(remoteOnly: true), refs);
    expect(withRemote, contains('refs/remotes/origin/feat-remota'));
    final page = await log.page(const GraphQuery(remoteOnly: true), withRemote);
    final row = page.rows.firstWhere((r) => r.sha == main);
    expect(row.refs.map((r) => r.name).toSet(), {
      'origin/feat-remota',
      'origin/main',
    });
  });
}
