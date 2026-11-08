import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'spec_branch.dart';

/// What the layout needs of a commit (SPEC-045 R1): the commit log rows
/// implement it, and the tests build their own.
abstract interface class LaneCommit {
  String get sha;

  /// Parents, the first one first (`%P`).
  List<String> get parents;

  /// Branches whose tip is this commit: the local ones, then the remote
  /// ones (`origin/x`).
  List<String> get branches;

  /// First line of the message.
  String get subject;
}

/// How a piece of a lane crosses a row.
enum SegmentKind {
  /// Top to bottom, beside the commit.
  pass,

  /// From the top of [LaneSegment.column] to the commit (a child that left
  /// from here: the straight line on the commit's own lane, a curve from
  /// another lane).
  into,

  /// From the commit to the bottom of [LaneSegment.column] (the first
  /// parent on the commit's lane, the other parents of a merge on theirs).
  outOf,
}

/// A piece of a lane in a row, with the branch whose colour it takes.
@immutable
class LaneSegment {
  const LaneSegment(this.kind, this.column, this.track);

  final SegmentKind kind;
  final int column;

  /// Branch of the lane (`main`, `spec/042-sprints`); null = unknown.
  final String? track;

  @override
  bool operator ==(Object other) =>
      other is LaneSegment &&
      other.kind == kind &&
      other.column == column &&
      other.track == track;

  @override
  int get hashCode => Object.hash(kind, column, track);

  @override
  String toString() => '${kind.name}($column${track == null ? '' : ' $track'})';
}

enum NodeKind { commit, merge, summary }

/// One row of the graph: where the commit goes and the pieces of lane that
/// cross its row.
@immutable
class LaneRow {
  const LaneRow({
    required this.sha,
    required this.column,
    required this.track,
    required this.kind,
    required this.segments,
    this.group,
  });

  final String sha;
  final int column;

  /// Branch the commit belongs to (its lane's colour).
  final String? track;
  final NodeKind kind;
  final List<LaneSegment> segments;

  /// Number of the collapsed spec this row stands for (summary rows, R3).
  final int? group;

  /// Lanes the row draws (the widest column + 1).
  int get width =>
      segments.fold(column + 1, (w, s) => math.max(w, s.column + 1));

  @override
  bool operator ==(Object other) =>
      other is LaneRow &&
      other.sha == sha &&
      other.column == column &&
      other.track == track &&
      other.kind == kind &&
      other.group == group &&
      listEquals(other.segments, segments);

  @override
  int get hashCode =>
      Object.hash(sha, column, track, kind, group, Object.hashAll(segments));

  @override
  String toString() => '$sha@$column[${segments.join(' ')}]';
}

/// What the rows of a spec (mother and daughters) add up to, for the
/// collapsed row and the lane's balloon (R3, R8).
class GroupStats {
  int commits = 0;

  /// Tasks seen (`-tN-` branches and their merges).
  final Set<int> tasks = {};

  /// Tasks whose merge into the mother was seen.
  final Set<int> mergedTasks = {};

  /// Sha of the first (newest) row of the spec.
  String? first;

  GroupStats copy() => GroupStats()
    ..commits = commits
    ..tasks.addAll(tasks)
    ..mergedTasks.addAll(mergedTasks)
    ..first = first;
}

/// What a branch's lane adds up to (R8).
class TrackStats {
  int commits = 0;

  /// Merge commit that brought the branch in, and the branch it went to.
  String? mergedAt;
  String? mergedInto;
  int? pr;

  TrackStats copy() => TrackStats()
    ..commits = commits
    ..mergedAt = mergedAt
    ..mergedInto = mergedInto
    ..pr = pr;
}

class _Lane {
  _Lane(this.sha, this.track);

  String sha;
  final String? track;
}

/// Where the layout stopped: the open lanes and what the rows added up to,
/// so the next page continues without laying out the previous ones again
/// (R7).
class LaneState {
  LaneState._(this._lanes, this._ghosts, this._shown, this.groups, this.tracks);

  LaneState.empty() : this._([], {}, {}, {}, {});

  /// Column → the commit the lane waits for (null = free). Column 0 is the
  /// default branch's.
  final List<_Lane?> _lanes;

  /// Commits of collapsed specs reached without a lane on screen (the
  /// daughters behind a collapsed mother) → their branch.
  final Map<String, String?> _ghosts;

  /// Collapsed specs whose row was already drawn.
  final Set<int> _shown;

  /// Spec number → its rows (R3).
  final Map<int, GroupStats> groups;

  /// Branch → its rows (R8).
  final Map<String, TrackStats> tracks;

  /// Lanes still open (waiting for a commit below).
  int get openLanes => _lanes.where((l) => l != null).length;

  /// Commits the open lanes wait for, by column.
  List<String?> get waiting => [for (final l in _lanes) l?.sha];

  LaneState copy() => LaneState._(
    [for (final l in _lanes) l == null ? null : _Lane(l.sha, l.track)],
    Map.of(_ghosts),
    Set.of(_shown),
    {for (final e in groups.entries) e.key: e.value.copy()},
    {for (final e in tracks.entries) e.key: e.value.copy()},
  );
}

/// The rows laid out and where the layout stopped.
typedef LaneLayout = ({List<LaneRow> rows, LaneState state});

bool _never(int _) => false;

/// Lays out [commits] (in topological order, newest first) in lanes
/// (SPEC-045 R1, R3, R7). A pure function: [from] (the state of the
/// previous page) is not changed, and laying out two pages one after the
/// other gives the same rows as laying out both at once.
///
/// - The [defaultBranch] stays on column 0.
/// - A commit takes the lane of its first child; the other children that
///   wait for it join with a curve (where their branch left from).
/// - The first parent continues on the commit's lane; the other parents of
///   a merge open a lane to the right (a free one next to it, so the
///   daughters stay beside the mother), or join the lane that already
///   waits for them.
/// - Each commit belongs to a branch (its track): the default branch first,
///   then a spec branch whose tip it is, then the lane it came down (the
///   mother before a daughter), whose name came from a tip or from the
///   subject of the merge that opened it, then any branch whose tip it is.
/// - The spec of a [collapsed] number (the mother and its daughters) shows
///   only its first row, as a [NodeKind.summary]; the others are counted in
///   [LaneState.groups] and hidden, their lanes going on to the parents.
LaneLayout layoutLanes(
  List<LaneCommit> commits, {
  required String defaultBranch,
  LaneState? from,
  bool Function(int spec) collapsed = _never,
}) {
  final st = (from ?? LaneState.empty()).copy();
  final lanes = st._lanes;
  final rows = <LaneRow>[];

  bool isDefault(String? name) =>
      name != null &&
      (name == defaultBranch ||
          (name.endsWith('/$defaultBranch') &&
              parseSpecBranch(name) == null &&
              name.indexOf('/') == name.length - defaultBranch.length - 1));

  // Lower wins; a tip only takes the commit from a lane it beats.
  int rank(String? name, {bool tip = false}) {
    if (name == null) return 5;
    if (isDefault(name)) return 0;
    final spec = parseSpecBranch(name);
    if (spec == null) return 4;
    if (tip) return 1;
    return spec.isTask ? 3 : 2;
  }

  int free(int after) {
    for (var i = math.max(1, after + 1); i < lanes.length; i++) {
      if (lanes[i] == null) return i;
    }
    if (lanes.isEmpty) lanes.add(null);
    lanes.add(null);
    return lanes.length - 1;
  }

  void put(int column, _Lane lane) {
    while (lanes.length <= column) {
      lanes.add(null);
    }
    lanes[column] = lane;
  }

  void trim() {
    while (lanes.isNotEmpty && lanes.last == null) {
      lanes.removeLast();
    }
  }

  for (final c in commits) {
    final idxs = <int>[
      for (var i = 0; i < lanes.length; i++)
        if (lanes[i]?.sha == c.sha) i,
    ];

    // The branch of the commit and the lane it came down.
    int? bestLane;
    for (final i in idxs) {
      if (bestLane == null ||
          rank(lanes[i]!.track) < rank(lanes[bestLane]!.track)) {
        bestLane = i;
      }
    }
    String? name = bestLane == null ? null : lanes[bestLane]!.track;
    var nameRank = rank(name);
    if (bestLane == null && st._ghosts.containsKey(c.sha)) {
      name = st._ghosts[c.sha];
      nameRank = rank(name);
    }
    for (final b in c.branches) {
      final r = rank(b, tip: true);
      if (r < nameRank) {
        name = b;
        nameRank = r;
      }
    }
    st._ghosts.remove(c.sha);

    final spec = isDefault(name) ? null : parseSpecBranch(name);
    final group = spec?.number;
    final groupStats = group == null
        ? null
        : st.groups.putIfAbsent(group, GroupStats.new);
    final isCollapsed = group != null && collapsed(group);
    final mergedBranch = c.parents.length > 1
        ? branchFromMergeSubject(c.subject)
        : null;

    void countGroup() {
      if (groupStats == null) return;
      groupStats.commits++;
      groupStats.first ??= c.sha;
      if (spec!.task != null) groupStats.tasks.add(spec.task!);
      final merged = parseSpecBranch(mergedBranch);
      if (merged != null && merged.number == group && merged.isTask) {
        groupStats.tasks.add(merged.task!);
        groupStats.mergedTasks.add(merged.task!);
      }
    }

    // A hidden row of a collapsed spec: its lanes go on to the parents.
    if (isCollapsed && st._shown.contains(group)) {
      countGroup();
      for (final i in idxs) {
        if (c.parents.isEmpty) {
          lanes[i] = null;
        } else {
          lanes[i]!.sha = c.parents.first;
        }
      }
      for (final (k, p) in c.parents.indexed) {
        st._ghosts.putIfAbsent(p, () => k == 0 ? name : mergedBranch ?? name);
      }
      trim();
      continue;
    }
    final summary = isCollapsed;
    if (summary) st._shown.add(group);

    final column =
        isDefault(name) &&
            (lanes.isEmpty || lanes[0] == null || lanes[0]!.sha == c.sha)
        ? 0
        : bestLane ?? free(0);

    final segments = <LaneSegment>[
      for (var i = 0; i < lanes.length; i++)
        if (lanes[i] != null && !idxs.contains(i))
          LaneSegment(SegmentKind.pass, i, lanes[i]!.track),
      for (final i in idxs) LaneSegment(SegmentKind.into, i, lanes[i]!.track),
    ];
    for (final i in idxs) {
      lanes[i] = null;
    }
    if (c.parents.isNotEmpty) {
      put(column, _Lane(c.parents.first, name));
      segments.add(LaneSegment(SegmentKind.outOf, column, name));
    }
    for (final p in c.parents.skip(1)) {
      final track = mergedBranch;
      final pSpec = parseSpecBranch(track);
      if (summary && pSpec != null && pSpec.number == group) {
        // A daughter merged into the collapsed mother: hidden with it.
        st._ghosts.putIfAbsent(p, () => track);
        continue;
      }
      final waiting = lanes.indexWhere((l) => l?.sha == p);
      if (waiting >= 0) {
        segments.add(
          LaneSegment(SegmentKind.outOf, waiting, lanes[waiting]!.track),
        );
      } else {
        final j = free(column);
        put(j, _Lane(p, track));
        segments.add(LaneSegment(SegmentKind.outOf, j, track));
      }
      if (track != null) {
        final t = st.tracks.putIfAbsent(track, TrackStats.new);
        t.mergedAt ??= c.sha;
        t.mergedInto ??= name;
        t.pr ??= prFromMergeSubject(c.subject);
      }
    }
    trim();

    countGroup();
    if (name != null) st.tracks.putIfAbsent(name, TrackStats.new).commits++;
    rows.add(
      LaneRow(
        sha: c.sha,
        column: column,
        track: name,
        kind: summary
            ? NodeKind.summary
            : c.parents.length > 1
            ? NodeKind.merge
            : NodeKind.commit,
        segments: segments,
        group: summary ? group : null,
      ),
    );
  }
  return (rows: rows, state: st);
}
