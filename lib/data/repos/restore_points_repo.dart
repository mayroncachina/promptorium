import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// States of a restore point (SPEC-084 R9, R11).
abstract final class RestoreState {
  static const active = 'ativo';
  static const undone = 'desfeito';
  static const redone = 'refeito';
}

/// Rows of `restore_points` (SPEC-084 R3): one per turn of a session or of
/// the conversation of a VIBE.
class RestorePointsRepo {
  RestorePointsRepo(this._db);

  final AppDatabase _db;

  $RestorePointsTable get _t => _db.restorePoints;

  Expression<bool> _owner(
    $RestorePointsTable t, {
    String? sessionId,
    int? conversationId,
  }) => sessionId != null
      ? t.sessionId.equals(sessionId)
      : t.conversationId.equals(conversationId ?? -1);

  /// Points of a session (or conversation), newest turn first.
  Stream<List<RestorePoint>> watch({String? sessionId, int? conversationId}) =>
      (_db.select(_t)
            ..where(
              (t) => _owner(
                t,
                sessionId: sessionId,
                conversationId: conversationId,
              ),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.turn)]))
          .watch();

  Future<List<RestorePoint>> list({String? sessionId, int? conversationId}) =>
      (_db.select(_t)
            ..where(
              (t) => _owner(
                t,
                sessionId: sessionId,
                conversationId: conversationId,
              ),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.turn)]))
          .get();

  Future<List<RestorePoint>> byWorkspace(int workspaceId) =>
      (_db.select(_t)..where((t) => t.workspaceId.equals(workspaceId))).get();

  Future<List<RestorePoint>> all() => _db.select(_t).get();

  Future<RestorePoint?> byId(int id) =>
      (_db.select(_t)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Next turn number of the session (1 for the first).
  Future<int> nextTurn({String? sessionId, int? conversationId}) async {
    final max = _t.turn.max();
    final q = _db.selectOnly(_t)
      ..addColumns([max])
      ..where(_owner(_t, sessionId: sessionId, conversationId: conversationId));
    return ((await q.getSingle()).read(max) ?? 0) + 1;
  }

  Future<RestorePoint> insert(RestorePointsCompanion row) =>
      _db.into(_t).insertReturning(row);

  Future<void> update(int id, RestorePointsCompanion row) =>
      (_db.update(_t)..where((t) => t.id.equals(id))).write(row);

  Future<void> deleteIds(Iterable<int> ids) =>
      (_db.delete(_t)..where((t) => t.id.isIn(ids))).go();

  /// The redo of the undone points of a session goes away (a new turn
  /// moved history forward, R11).
  Future<void> dropRedo({String? sessionId, int? conversationId}) =>
      (_db.update(_t)..where(
            (t) =>
                _owner(
                  t,
                  sessionId: sessionId,
                  conversationId: conversationId,
                ) &
                t.undoneSha.isNotNull(),
          ))
          .write(
            const RestorePointsCompanion(
              undoneSha: Value(null),
              undoneHead: Value(null),
            ),
          );
}

/// Untracked files over the limit kept out of [p] (R4).
List<String> largeFilesOf(RestorePoint p) {
  try {
    final v = jsonDecode(p.largeFiles);
    return v is List ? [for (final e in v) '$e'] : const [];
  } on FormatException {
    return const [];
  }
}
