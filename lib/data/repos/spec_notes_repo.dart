import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Progress notes of the agent (`spec_notes`, SPEC-052 R7).
class SpecNotesRepo {
  SpecNotesRepo(this._db);

  final AppDatabase _db;

  $SpecNotesTable get _t => _db.specNotes;

  Future<SpecNote> add({
    required int specId,
    required String note,
    String? sessionId,
    String? steps,
    DateTime? at,
  }) => _db
      .into(_t)
      .insertReturning(
        SpecNotesCompanion.insert(
          specId: specId,
          note: note,
          sessionId: Value(sessionId),
          steps: Value(steps),
          createdAt: at == null ? const Value.absent() : Value(at),
        ),
      );

  /// Every note of [specId], newest first (the history of the spec).
  Stream<List<SpecNote>> watchBySpec(int specId) =>
      (_db.select(_t)
            ..where((n) => n.specId.equals(specId))
            ..orderBy([
              (n) => OrderingTerm.desc(n.createdAt),
              (n) => OrderingTerm.desc(n.id),
            ]))
          .watch();

  Future<List<SpecNote>> bySpec(int specId) => watchBySpec(specId).first;

  /// The newest note of each spec of [workspaceId] (cards of the Quadro).
  Stream<Map<int, SpecNote>> watchLatestByWorkspace(int workspaceId) {
    final q =
        _db.select(_t).join([
            innerJoin(_db.specs, _db.specs.id.equalsExp(_t.specId)),
          ])
          ..where(_db.specs.workspaceId.equals(workspaceId))
          ..orderBy([OrderingTerm.asc(_t.createdAt), OrderingTerm.asc(_t.id)]);
    return q.watch().map(
      (rows) => {for (final r in rows) r.readTable(_t).specId: r.readTable(_t)},
    );
  }
}
