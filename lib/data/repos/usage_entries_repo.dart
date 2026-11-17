import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// One entry per turn of the app (SPEC-081 R1).
class UsageEntriesRepo {
  UsageEntriesRepo(this._db);

  final AppDatabase _db;

  $UsageEntriesTable get _t => _db.usageEntries;

  Future<int> add(UsageEntriesCompanion entry) => _db.into(_t).insert(entry);

  /// Several at once (the history of before, R5).
  Future<void> addAll(List<UsageEntriesCompanion> entries) =>
      _db.batch((b) => b.insertAll(_t, entries));

  /// Every entry of [specId], newest first.
  Stream<List<UsageEntry>> bySpec(int specId) =>
      (_db.select(_t)
            ..where((e) => e.specId.equals(specId))
            ..orderBy([(e) => OrderingTerm.desc(e.at)]))
          .watch();

  /// Entries of [workspaceIds] (null = every workspace) since [since] (null
  /// = all), only those of a spec when [withSpec].
  Stream<List<UsageEntry>> byWorkspace(
    Iterable<int>? workspaceIds, {
    DateTime? since,
    bool withSpec = true,
  }) {
    final q = _db.select(_t);
    q.where((e) {
      Expression<bool> w = const Constant(true);
      if (workspaceIds != null) w = w & e.workspaceId.isIn(workspaceIds);
      if (since != null) w = w & e.at.isBiggerOrEqualValue(since);
      if (withSpec) w = w & e.specId.isNotNull();
      return w;
    });
    return q.watch();
  }

  /// Entries still without the weight of a window (R4).
  Future<List<UsageEntry>> pendingWeights() => (_db.select(
    _t,
  )..where((e) => e.fiveHourPct.isNull() | e.weekPct.isNull())).get();

  /// Fills the weights still missing of [id]; a weight already there never
  /// changes (R4).
  Future<void> setWeights(int id, {double? fiveHour, double? week}) =>
      _db.customUpdate(
        'UPDATE usage_entries SET '
        'five_hour_pct = COALESCE(five_hour_pct, ?), '
        'week_pct = COALESCE(week_pct, ?) WHERE id = ?',
        variables: [
          Variable<double>(fiveHour),
          Variable<double>(week),
          Variable.withInt(id),
        ],
        updates: {_t},
        updateKind: UpdateKind.update,
      );

  /// When the first entry recorded live was written (null = none yet): the
  /// history of before stops there (R5).
  Future<DateTime?> firstLiveAt() async {
    final first = _t.at.min();
    final row =
        await (_db.selectOnly(_t)
              ..addColumns([first])
              ..where(_t.estimated.equals(false)))
            .getSingle();
    return row.read(first);
  }
}
