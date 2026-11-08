import 'package:flutter/foundation.dart';

import '../../../core/git/git_service.dart';
import 'commit_log.dart';
import 'lane_layout.dart';
import 'spec_branch.dart';
import 'spec_of_commit.dart';

/// State of the Grafo tab (SPEC-045): the commits read so far, their lanes,
/// the collapsed specs and the selected commit.
class GraphController extends ChangeNotifier {
  GraphController(this.log);

  final CommitLog log;

  String get defaultBranch => log.defaultBranch;

  final GraphQuery _query = const GraphQuery();
  GraphQuery get query => _query;

  RepoRefs _refs = const RepoRefs();
  RepoRefs get refs => _refs;
  List<String> _revs = const [];

  final List<CommitRow> _commits = [];

  /// Commits read, in the log order (hidden ones included).
  List<CommitRow> get commits => List.unmodifiable(_commits);
  final Map<String, CommitRow> _bySha = {};

  CommitRow? commit(String sha) => _bySha[sha];

  List<LaneRow> _rows = const [];

  /// Rows on screen (the collapsed specs folded).
  List<LaneRow> get rows => _rows;
  LaneState _state = LaneState.empty();
  LaneState get laneState => _state;

  int _total = 0;

  /// Commits of the query (`300 de 1.284 commits`).
  int get total => _total;

  bool _more = false;
  bool get hasMore => _more;
  bool _loading = false;
  bool get loading => _loading;
  bool _loaded = false;
  bool get loaded => _loaded;
  Object? _error;
  Object? get error => _error;

  /// Bumped by every load: an answer of an older one is dropped.
  int _generation = 0;

  final Map<int, bool> _collapse = {};

  /// Whether spec [number] shows as one row (R3): the open ones start
  /// expanded, the merged ones collapsed, until the person changes it.
  bool isCollapsed(int number) =>
      _collapse[number] ?? !_refs.openSpecNumbers.contains(number);

  void toggleGroup(int number) {
    _collapse[number] = !isCollapsed(number);
    _relayout();
    notifyListeners();
  }

  String? _selected;
  String? get selected => _selected;

  void select(String? sha) {
    if (_selected == sha) return;
    _selected = sha;
    notifyListeners();
  }

  /// Widest row (lanes) read so far.
  int get width => _rows.fold(1, (w, r) => r.width > w ? r.width : w);

  /// The spec of a row (R2).
  SpecBranch? specOf(LaneRow row) {
    if (row.group != null) return SpecBranch(row.group!);
    final c = _bySha[row.sha];
    return c == null
        ? null
        : specOfCommit(track: row.track, subject: c.subject);
  }

  /// (Re)reads the log: the refs, the count and as many commits as were on
  /// screen ([keep]; one page at least).
  Future<void> load({int keep = 0}) async {
    final gen = ++_generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final refs = await log.refs();
      final revs = log.revisions(_query, refs);
      final limit = keep > CommitLog.pageSize ? keep : CommitLog.pageSize;
      final results = await Future.wait([
        log.count(_query, revs),
        log.page(_query, revs, limit: limit),
      ]);
      if (gen != _generation) return;
      final page = results[1] as CommitPage;
      _refs = refs;
      _revs = revs;
      _total = results[0] as int;
      _more = page.more;
      _commits
        ..clear()
        ..addAll(page.rows);
      _bySha
        ..clear()
        ..addEntries(page.rows.map((c) => MapEntry(c.sha, c)));
      _relayout();
      if (_selected != null && !_bySha.containsKey(_selected)) {
        _selected = null;
      }
    } on GitException catch (e) {
      if (gen != _generation) return;
      _error = e;
    } finally {
      if (gen == _generation) {
        _loading = false;
        _loaded = true;
        notifyListeners();
      }
    }
  }

  /// The next page (R7): its lanes continue from the last row, the rows on
  /// screen stay as they are.
  Future<void> loadMore() async {
    if (_loading || !_more) return;
    final gen = ++_generation;
    _loading = true;
    notifyListeners();
    try {
      final page = await log.page(_query, _revs, skip: _commits.length);
      if (gen != _generation) return;
      _more = page.more;
      final fresh = [
        for (final c in page.rows)
          if (!_bySha.containsKey(c.sha)) c,
      ];
      _commits.addAll(fresh);
      _bySha.addEntries(fresh.map((c) => MapEntry(c.sha, c)));
      final next = layoutLanes(
        fresh,
        defaultBranch: defaultBranch,
        from: _state,
        collapsed: isCollapsed,
      );
      _rows = [..._rows, ...next.rows];
      _state = next.state;
    } on GitException catch (e) {
      if (gen != _generation) return;
      _error = e;
    } finally {
      if (gen == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _relayout() {
    final l = layoutLanes(
      _commits,
      defaultBranch: defaultBranch,
      collapsed: isCollapsed,
    );
    _rows = l.rows;
    _state = l.state;
  }
}
