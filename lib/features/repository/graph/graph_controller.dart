import 'dart:async';

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

  GraphQuery _query = const GraphQuery();
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
    final c = sha == null ? null : _bySha[sha];
    if (c != null && !_details.containsKey(sha)) unawaited(loadDetails(sha!));
  }

  /// What to show (R6): a new query reads the log again.
  Future<void> setQuery(GraphQuery q) {
    if (q == _query) return Future.value();
    _query = q;
    return load();
  }

  Future<void> setScope(GraphScope scope) =>
      setQuery(_query.copyWith(scope: scope));

  Future<void> setRemoteOnly(bool on) =>
      setQuery(_query.copyWith(remoteOnly: on));

  /// Only the commits of [day] (null = every day). SPEC-046 opens the Grafo
  /// this way from the Atividade.
  Future<void> setDay(DateTime? day) => setQuery(
    _query.copyWith(
      day: () => day == null ? null : DateTime(day.year, day.month, day.day),
    ),
  );

  /// Reads the log again after HEAD, the refs or the tags changed (R7):
  /// as many commits as before, the selection kept.
  Future<void> refresh() => load(keep: _commits.length);

  // Search (R6).

  String _search = '';
  String get search => _search;
  List<int> _matches = const [];

  /// Rows (indexes in [rows]) that match the search.
  List<int> get matches => _matches;
  int _match = -1;

  /// Index in [matches] of the current result (-1 = none).
  int get currentMatch => _match;

  bool isMatch(int row) => _matchSet.contains(row);
  Set<int> _matchSet = const {};

  /// Searches the message, the SHA, the author or `SPEC-NNN` of the rows on
  /// screen; the first result becomes the current one.
  void setSearch(String text) {
    _search = text;
    _findMatches();
    _match = _matches.isEmpty ? -1 : 0;
    notifyListeners();
  }

  /// The next result (Enter), round to the first one; null = no result.
  int? nextMatch() {
    if (_matches.isEmpty) return null;
    _match = (_match + 1) % _matches.length;
    notifyListeners();
    return _matches[_match];
  }

  /// Row of the current result.
  int? get currentMatchRow =>
      _match < 0 || _match >= _matches.length ? null : _matches[_match];

  void _findMatches() {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) {
      _matches = const [];
      _matchSet = const {};
      return;
    }
    _matches = [
      for (final (i, r) in _rows.indexed)
        if (_matchesRow(r, q)) i,
    ];
    _matchSet = _matches.toSet();
    if (_match >= _matches.length) _match = _matches.isEmpty ? -1 : 0;
  }

  bool _matchesRow(LaneRow r, String q) {
    final spec = specOf(r);
    if (spec != null &&
        (spec.code.toLowerCase() == q || spec.label.toLowerCase() == q)) {
      return true;
    }
    if (r.kind == NodeKind.summary) return false;
    final c = _bySha[r.sha];
    if (c == null) return false;
    return c.subject.toLowerCase().contains(q) ||
        c.author.toLowerCase().contains(q) ||
        (q.length >= 4 && c.sha.startsWith(q));
  }

  // Details of the selected commit (R5).

  final Map<String, CommitDetails> _details = {};
  final Map<String, Object> _detailErrors = {};

  CommitDetails? details(String sha) => _details[sha];
  Object? detailsError(String sha) => _detailErrors[sha];

  Future<void> loadDetails(String sha) async {
    final c = _bySha[sha];
    if (c == null) return;
    try {
      _details[sha] = await log.details(c);
      _detailErrors.remove(sha);
    } on GitException catch (e) {
      _detailErrors[sha] = e;
    }
    notifyListeners();
  }

  Future<String> fileDiff(String sha, String path) {
    final c = _bySha[sha];
    if (c == null) return Future.value('');
    return log.fileDiff(c, path);
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
      // The refs changed: what contains each commit may have changed too.
      _details.clear();
      _detailErrors.clear();
      _relayout();
      if (_selected != null && !_bySha.containsKey(_selected)) {
        _selected = null;
      }
      if (_selected != null) unawaited(loadDetails(_selected!));
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
      _findMatches();
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
    _findMatches();
  }
}
