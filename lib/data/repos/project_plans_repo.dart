import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// `project_plans`: the planning draft of each workspace (Projeto screen).
class ProjectPlansRepo {
  ProjectPlansRepo(this._db);

  final AppDatabase _db;

  $ProjectPlansTable get _t => _db.projectPlans;

  SimpleSelectStatement<$ProjectPlansTable, ProjectPlan> _of(int workspaceId) =>
      _db.select(_t)..where((p) => p.workspaceId.equals(workspaceId));

  Future<ProjectPlan?> get(int workspaceId) =>
      _of(workspaceId).getSingleOrNull();

  Stream<ProjectPlan?> watch(int workspaceId) =>
      _of(workspaceId).watchSingleOrNull();

  /// Creates an empty plan (or returns the existing one).
  Future<ProjectPlan> start(int workspaceId) async {
    final existing = await get(workspaceId);
    if (existing != null) return existing;
    return _db
        .into(_t)
        .insertReturning(
          ProjectPlansCompanion.insert(workspaceId: Value(workspaceId)),
        );
  }

  /// Writes [changes] and bumps `updatedAt`.
  Future<void> update(int workspaceId, ProjectPlansCompanion changes) =>
      (_db.update(_t)..where((p) => p.workspaceId.equals(workspaceId))).write(
        changes.copyWith(updatedAt: Value(DateTime.now())),
      );

  /// Adds [delta] to the planner cost.
  Future<void> addCost(int workspaceId, double delta) async {
    if (delta <= 0) return;
    final p = await get(workspaceId);
    if (p == null) return;
    await update(
      workspaceId,
      ProjectPlansCompanion(costUsd: Value(p.costUsd + delta)),
    );
  }

  Future<int> delete(int workspaceId) =>
      (_db.delete(_t)..where((p) => p.workspaceId.equals(workspaceId))).go();
}
