import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/repository/graph/lane_layout.dart';
import 'package:promptorium/features/repository/graph/spec_branch.dart';

class C implements LaneCommit {
  C(this.sha, this.parents, {this.branches = const [], this.subject = ''});

  @override
  final String sha;
  @override
  final List<String> parents;
  @override
  final List<String> branches;
  @override
  final String subject;
}

LaneSegment pass(int c, [String? t]) => LaneSegment(SegmentKind.pass, c, t);
LaneSegment into(int c, [String? t]) => LaneSegment(SegmentKind.into, c, t);
LaneSegment out(int c, [String? t]) => LaneSegment(SegmentKind.outOf, c, t);

LaneLayout lay(List<C> commits, {Set<int> collapsed = const {}}) =>
    layoutLanes(commits, defaultBranch: 'main', collapsed: collapsed.contains);

/// The history of SPEC-042 (a mother with two daughters), merged into main.
List<C> spec042() => [
  C(
    'M94',
    ['B0', 'P3'],
    branches: ['main'],
    subject: 'Merge pull request #94 from o/spec/042-sprints',
  ),
  C('P3', [
    'P2',
    'T4b',
  ], subject: 'Merge pull request #98 from o/spec/042-t4-conclusao'),
  C('T4b', ['T4a'], subject: 'fix(sprints): singular'),
  C('T4a', ['P2'], subject: 'feat(sprints): concluir sprint'),
  C('P2', [
    'P1',
    'T3a',
  ], subject: 'Merge pull request #97 from o/spec/042-t3-visoes'),
  C('T3a', ['P1'], subject: 'feat(sprints): Grafo e Foco'),
  C('P1', ['B0'], subject: 'docs: SPEC-042, sprints no Quadro'),
  C('B0', [], subject: 'inicial'),
];

void main() {
  group('spec branches', () {
    test('mother, daughter and the other branches', () {
      expect(parseSpecBranch('spec/042-sprints'), const SpecBranch(42));
      expect(
        parseSpecBranch('spec/042-t4-conclusao'),
        const SpecBranch(42, task: 4),
      );
      expect(parseSpecBranch('origin/spec/045-t1-raias')?.label, 'SPEC-045 T1');
      expect(parseSpecBranch('spec/040-wt'), const SpecBranch(40));
      expect(parseSpecBranch('feat/spec-x'), isNull);
      expect(parseSpecBranch('main'), isNull);
    });

    test('the branch and the PR of a merge subject', () {
      const pr = 'Merge pull request #94 from mayroncachina/spec/042-sprints';
      expect(branchFromMergeSubject(pr), 'spec/042-sprints');
      expect(prFromMergeSubject(pr), 94);
      expect(
        branchFromMergeSubject("Merge branch 'spec/039-x' into spec/040-wt"),
        'spec/039-x',
      );
      expect(
        branchFromMergeSubject(
          "Merge remote-tracking branch 'origin/spec/044-releases' into x",
        ),
        'spec/044-releases',
      );
      expect(branchFromMergeSubject('feat: x'), isNull);
    });
  });

  group('R1 · lanes', () {
    test('linear history stays on column 0', () {
      final l = lay([
        C('c', ['b'], branches: ['main']),
        C('b', ['a']),
        C('a', []),
      ]);
      expect(l.rows.map((r) => r.column), [0, 0, 0]);
      expect(l.rows.map((r) => r.track), ['main', 'main', 'main']);
      expect(l.rows[0].segments, [out(0, 'main')]);
      expect(l.rows[1].segments, [into(0, 'main'), out(0, 'main')]);
      expect(l.rows[2].segments, [into(0, 'main')]);
      expect(l.state.openLanes, 0);
    });

    test('branch and merge: the merge opens a lane, the branch joins where '
        'it left from', () {
      final l = lay([
        C('M', ['A', 'F'], branches: ['main'], subject: "Merge branch 'feat'"),
        C('F', ['B'], subject: 'feat: f'),
        C('A', ['B']),
        C('B', []),
      ]);
      final [m, f, a, b] = l.rows;
      expect(m.kind, NodeKind.merge);
      expect(m.segments, [out(0, 'main'), out(1, 'feat')]);
      expect(f.column, 1);
      expect(f.track, 'feat');
      expect(f.segments, [pass(0, 'main'), into(1, 'feat'), out(1, 'feat')]);
      expect(a.column, 0);
      expect(a.segments, [pass(1, 'feat'), into(0, 'main'), out(0, 'main')]);
      expect(b.column, 0);
      expect(b.segments, [into(0, 'main'), into(1, 'feat')]);
      expect(l.state.tracks['feat']!.mergedAt, 'M');
      expect(l.state.tracks['feat']!.mergedInto, 'main');
    });

    test('a merge with several parents opens one lane per parent', () {
      final l = lay([
        C('M', ['A', 'X', 'Y'], branches: ['main']),
        C('Y', ['A']),
        C('X', ['A']),
        C('A', []),
      ]);
      expect(l.rows[0].segments, [out(0, 'main'), out(1), out(2)]);
      expect(l.rows[1].column, 2);
      expect(l.rows[2].column, 1);
      expect(l.rows[3].segments, [into(0, 'main'), into(1), into(2)]);
      expect(l.rows.map((r) => r.width), [3, 3, 3, 3]);
    });

    test('a lane that ends is free for the next branch', () {
      final l = lay([
        C('M2', ['M1', 'G'], branches: ['main'], subject: "Merge branch 'g'"),
        C('G', ['M1']),
        C('M1', ['A', 'F'], subject: "Merge branch 'f'"),
        C('F', ['A']),
        C('A', []),
      ]);
      expect(l.rows[1].column, 1);
      expect(l.rows[2].segments, [
        into(0, 'main'),
        into(1, 'g'),
        out(0, 'main'),
        out(1, 'f'),
      ]);
      expect(l.rows[3].column, 1);
      expect(l.rows[3].track, 'f');
    });

    test('the default branch keeps column 0 even below a newer branch', () {
      final l = lay([
        C('S', ['A'], branches: ['spec/050-x']),
        C('A', ['Z'], branches: ['main']),
        C('Z', []),
      ]);
      expect(l.rows[0].column, 1);
      expect(l.rows[0].track, 'spec/050-x');
      expect(l.rows[1].column, 0);
      expect(l.rows[1].track, 'main');
      expect(l.rows[1].segments, [into(1, 'spec/050-x'), out(0, 'main')]);
    });

    test('a spec stacked on another: the tip belongs to the branch below', () {
      final l = lay([
        C('B2', ['B1'], branches: ['spec/045-grafo']),
        C('B1', ['A1'], branches: ['spec/044-releases']),
        C('A1', ['Z'], branches: ['main']),
        C('Z', []),
      ]);
      expect(l.rows.map((r) => r.track), [
        'spec/045-grafo',
        'spec/044-releases',
        'main',
        'main',
      ]);
      expect(l.rows[1].column, 1);
    });

    test(
      'the mother and a task on the same tip: the line is the mother\'s',
      () {
        final l = lay([
          C('T', ['P'], branches: ['spec/045-t2-aba']),
          C(
            'P',
            ['A'],
            branches: [
              'spec/045-t2-aba-old',
              'spec/045-t1-x',
              'spec/045-grafo',
            ],
          ),
          C('A', [], branches: ['main']),
        ]);
        expect(l.rows[1].track, 'spec/045-grafo');
      },
    );

    test('a task merged by fast-forward does not take the mother\'s line', () {
      final l = lay([
        C('P2', ['P1'], branches: ['spec/045-grafo']),
        C('P1', ['A'], branches: ['spec/045-t1-raias']),
        C('A', [], branches: ['main']),
      ]);
      expect(l.rows[1].track, 'spec/045-grafo');
    });

    test('a stale non-spec branch does not take a spec lane', () {
      final l = lay([
        C('S2', ['S1'], branches: ['spec/050-x']),
        C('S1', ['A'], branches: ['backup/old']),
        C('A', [], branches: ['main']),
      ]);
      expect(l.rows[1].track, 'spec/050-x');
    });
  });

  group('R7 · pages', () {
    test('two pages give the rows of one, without laying out the first '
        'again', () {
      final all = spec042();
      final whole = lay(all);
      for (var cut = 1; cut < all.length; cut++) {
        final a = layoutLanes(all.sublist(0, cut), defaultBranch: 'main');
        final b = layoutLanes(
          all.sublist(cut),
          defaultBranch: 'main',
          from: a.state,
        );
        expect([...a.rows, ...b.rows], whole.rows, reason: 'cut at $cut');
      }
    });

    test('the state of a page is not changed by the next one', () {
      final all = spec042();
      final a = layoutLanes(all.sublist(0, 3), defaultBranch: 'main');
      final waiting = a.state.waiting;
      layoutLanes(all.sublist(3), defaultBranch: 'main', from: a.state);
      expect(a.state.waiting, waiting);
    });

    test('a collapsed spec across the page break', () {
      final all = spec042();
      final whole = lay(all, collapsed: {42});
      final a = layoutLanes(
        all.sublist(0, 4),
        defaultBranch: 'main',
        collapsed: {42}.contains,
      );
      final b = layoutLanes(
        all.sublist(4),
        defaultBranch: 'main',
        from: a.state,
        collapsed: {42}.contains,
      );
      expect([...a.rows, ...b.rows], whole.rows);
      expect(b.state.groups[42]!.commits, 6);
    });
  });

  group('R3 · mother and daughters', () {
    test('expanded: the daughters beside the mother, in their own lane', () {
      final l = lay(spec042());
      final byId = {for (final r in l.rows) r.sha: r};
      expect(byId['M94']!.column, 0);
      expect(byId['P3']!.column, 1);
      expect(byId['P3']!.track, 'spec/042-sprints');
      expect(byId['T4b']!.column, 2);
      expect(byId['T4b']!.track, 'spec/042-t4-conclusao');
      expect(byId['T3a']!.column, 2);
      expect(byId['T3a']!.track, 'spec/042-t3-visoes');
      expect(byId['P1']!.track, 'spec/042-sprints');
      expect(byId['B0']!.segments, [
        into(0, 'main'),
        into(1, 'spec/042-sprints'),
      ]);
      final g = l.state.groups[42]!;
      expect(g.commits, 6);
      expect(g.tasks, {3, 4});
      expect(g.mergedTasks, {3, 4});
    });

    test('collapsed: one row on the mother lane, the daughters hidden', () {
      final l = lay(spec042(), collapsed: {42});
      expect(l.rows.map((r) => r.sha), ['M94', 'P3', 'B0']);
      final summary = l.rows[1];
      expect(summary.kind, NodeKind.summary);
      expect(summary.group, 42);
      expect(summary.column, 1);
      expect(summary.segments, [
        pass(0, 'main'),
        into(1, 'spec/042-sprints'),
        out(1, 'spec/042-sprints'),
      ]);
      expect(l.rows[2].segments, [
        into(0, 'main'),
        into(1, 'spec/042-sprints'),
      ]);
      expect(l.rows.every((r) => r.width <= 2), isTrue);
      final g = l.state.groups[42]!;
      expect(g.commits, 6);
      expect(g.tasks, {3, 4});
      expect(g.mergedTasks, {3, 4});
      expect(l.state.openLanes, 0);
    });

    test('other specs stay as they are when one collapses', () {
      final l = lay(
        [
          C(
            'M2',
            ['M1', 'Q1'],
            branches: ['main'],
            subject: 'Merge pull request #2 from o/spec/043-x',
          ),
          C('Q1', ['M1'], subject: 'docs: SPEC-043'),
          ...spec042().map(
            (c) => c.sha == 'M94' ? C('M1', c.parents, subject: c.subject) : c,
          ),
        ],
        collapsed: {42},
      );
      expect(l.rows.map((r) => r.sha), ['M2', 'Q1', 'M1', 'P3', 'B0']);
      expect(l.rows[1].track, 'spec/043-x');
    });
  });
}
