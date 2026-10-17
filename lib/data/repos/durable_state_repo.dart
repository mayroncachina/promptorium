import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// State that used to live only in memory and now survives closing the app
/// (schema v9): the Autopilot of each workspace, the Review drafts and the
/// notices waiting to be sent to a session.
class DurableStateRepo {
  DurableStateRepo(this._db);

  final AppDatabase _db;

  // --- autopilot -------------------------------------------------------------

  Future<Set<int>> autopilotOn() async => {
    for (final r in await _db.select(_db.autopilotStates).get()) r.workspaceId,
  };

  Future<void> setAutopilot(int workspaceId, bool on) => on
      ? _db
            .into(_db.autopilotStates)
            .insertOnConflictUpdate(
              AutopilotStatesCompanion.insert(workspaceId: Value(workspaceId)),
            )
      : (_db.delete(
          _db.autopilotStates,
        )..where((t) => t.workspaceId.equals(workspaceId))).go();

  // --- review drafts ---------------------------------------------------------

  Future<String?> reviewDraft(String sessionId) async => (await (_db.select(
    _db.reviewDrafts,
  )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull())?.data;

  /// [data] null removes the draft.
  Future<void> setReviewDraft(String sessionId, String? data) => data == null
      ? (_db.delete(
          _db.reviewDrafts,
        )..where((t) => t.sessionId.equals(sessionId))).go()
      : _db
            .into(_db.reviewDrafts)
            .insertOnConflictUpdate(
              ReviewDraftsCompanion.insert(
                sessionId: sessionId,
                data: data,
                updatedAt: Value(DateTime.now()),
              ),
            );

  // --- pending notices -------------------------------------------------------

  /// Every notice, by session, oldest first.
  Future<Map<String, List<String>>> notices() async {
    final rows = await (_db.select(
      _db.pendingNotices,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    final out = <String, List<String>>{};
    for (final r in rows) {
      out.putIfAbsent(r.sessionId, () => []).add(r.body);
    }
    return out;
  }

  Future<void> addNotice(String sessionId, String body) => _db
      .into(_db.pendingNotices)
      .insert(PendingNoticesCompanion.insert(sessionId: sessionId, body: body));

  Future<void> clearNotices(String sessionId) => (_db.delete(
    _db.pendingNotices,
  )..where((t) => t.sessionId.equals(sessionId))).go();
}
