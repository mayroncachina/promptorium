import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// The draft of "Nova spec" (SPEC-039 R8), one per workspace.
class SpecDraftsRepo {
  SpecDraftsRepo(this._db);

  final AppDatabase _db;

  $SpecDraftsTable get _t => _db.specDrafts;

  SimpleSelectStatement<$SpecDraftsTable, SpecDraft> _of(int workspaceId) =>
      _db.select(_t)..where((d) => d.workspaceId.equals(workspaceId));

  Future<SpecDraft?> get(int workspaceId) => _of(workspaceId).getSingleOrNull();

  Stream<SpecDraft?> watch(int workspaceId) =>
      _of(workspaceId).watchSingleOrNull();

  /// Creates an empty draft (or returns the existing one).
  Future<SpecDraft> start(int workspaceId) async {
    final existing = await get(workspaceId);
    if (existing != null) return existing;
    return _db
        .into(_t)
        .insertReturning(
          SpecDraftsCompanion.insert(workspaceId: Value(workspaceId)),
        );
  }

  /// Writes [changes] and bumps `updatedAt`. A discarded draft stays gone.
  Future<void> update(int workspaceId, SpecDraftsCompanion changes) =>
      (_db.update(_t)..where((d) => d.workspaceId.equals(workspaceId))).write(
        changes.copyWith(updatedAt: Value(DateTime.now())),
      );

  /// Adds [delta] to the planner cost.
  Future<void> addCost(int workspaceId, double delta) async {
    if (delta <= 0) return;
    final d = await get(workspaceId);
    if (d == null) return;
    await update(
      workspaceId,
      SpecDraftsCompanion(costUsd: Value(d.costUsd + delta)),
    );
  }

  Future<int> delete(int workspaceId) =>
      (_db.delete(_t)..where((d) => d.workspaceId.equals(workspaceId))).go();
}
