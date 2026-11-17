import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// How long the journal keeps what finished (SPEC-080 P6).
const activityJournalDays = 14;

/// The journal of what finished, by workspace (SPEC-080 R6).
class ActivityEventsRepo {
  ActivityEventsRepo(this._db);

  final AppDatabase _db;

  $ActivityEventsTable get _t => _db.activityEvents;

  Future<int> add(ActivityEventsCompanion row) => _db.into(_t).insert(row);

  /// Events after [at] (every workspace), newest first.
  Future<List<ActivityEvent>> since(DateTime at) =>
      (_db.select(_t)
            ..where((e) => e.at.isBiggerThanValue(at))
            ..orderBy([(e) => OrderingTerm.desc(e.at)]))
          .get();

  /// The same, live (the card follows what keeps finishing).
  Stream<List<ActivityEvent>> watchSince(DateTime at) =>
      (_db.select(_t)
            ..where((e) => e.at.isBiggerThanValue(at))
            ..orderBy([(e) => OrderingTerm.desc(e.at)]))
          .watch();

  /// Whether [groupKey] already has an event at [at] (the GitHub catch-up
  /// never writes the same merge twice, R7).
  Future<bool> has(String groupKey, String kind, DateTime at) async =>
      (await (_db.select(_t)
                ..where(
                  (e) =>
                      e.groupKey.equals(groupKey) &
                      e.kind.equals(kind) &
                      e.at.equals(at),
                )
                ..limit(1))
              .get())
          .isNotEmpty;

  /// The newest event of [groupKey] of [kind] (null = none).
  Future<ActivityEvent?> latestOf(String groupKey, String kind) =>
      (_db.select(_t)
            ..where((e) => e.groupKey.equals(groupKey) & e.kind.equals(kind))
            ..orderBy([(e) => OrderingTerm.desc(e.at)])
            ..limit(1))
          .getSingleOrNull();

  /// Deletes what is older than [days] (on opening the app, P6).
  Future<int> purgeOlderThan({int days = activityJournalDays, DateTime? now}) {
    final limit = (now ?? DateTime.now()).subtract(Duration(days: days));
    return (_db.delete(_t)..where((e) => e.at.isSmallerThanValue(limit))).go();
  }

  /// How many events the journal keeps (Configurações, R14).
  Stream<int> watchCount() {
    final n = _t.id.count();
    return (_db.selectOnly(_t)..addColumns([n]))
        .watchSingle()
        .map((r) => r.read(n) ?? 0);
  }

  /// "Limpar o diário" (R14).
  Future<int> clear() => _db.delete(_t).go();
}
