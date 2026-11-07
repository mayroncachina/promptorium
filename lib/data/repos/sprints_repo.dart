import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Sprints of a workspace (SPEC-042): at most one active at a time.
class SprintsRepo {
  SprintsRepo(this._db);

  final AppDatabase _db;

  $SprintsTable get _t => _db.sprints;

  Stream<List<Sprint>> watchByWorkspace(int workspaceId) =>
      (_db.select(_t)
            ..where((s) => s.workspaceId.equals(workspaceId))
            ..orderBy([
              (s) => OrderingTerm.asc(s.position),
              (s) => OrderingTerm.asc(s.id),
            ]))
          .watch();

  Future<List<Sprint>> byWorkspace(int workspaceId) =>
      watchByWorkspace(workspaceId).first;

  Future<Sprint?> active(int workspaceId) =>
      (_db.select(_t)..where(
            (s) =>
                s.workspaceId.equals(workspaceId) &
                s.state.equalsValue(SprintState.active),
          ))
          .getSingleOrNull();

  /// New sprint at the end of the list. The first of the workspace is active;
  /// the next ones are planned (R4).
  Future<Sprint> create({
    required int workspaceId,
    required String name,
    String? goal,
  }) => _db.transaction(() async {
    final all = await byWorkspace(workspaceId);
    final last = all.fold(0, (m, s) => s.position > m ? s.position : m);
    return _db
        .into(_t)
        .insertReturning(
          SprintsCompanion.insert(
            workspaceId: workspaceId,
            name: name,
            goal: Value(goal),
            state: Value(
              all.isEmpty ? SprintState.active : SprintState.planned,
            ),
            position: Value(last + 1),
          ),
        );
  });

  Future<void> rename(int id, {required String name, String? goal}) =>
      (_db.update(_t)..where((s) => s.id.equals(id))).write(
        SprintsCompanion(name: Value(name), goal: Value(goal)),
      );

  /// Makes [id] the active sprint; the previous one goes back to planned.
  Future<void> activate(int id) => _db.transaction(() async {
    final sprint = await (_db.select(
      _t,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (sprint == null || sprint.state == SprintState.done) return;
    await (_db.update(_t)..where(
          (s) =>
              s.workspaceId.equals(sprint.workspaceId) &
              s.state.equalsValue(SprintState.active),
        ))
        .write(const SprintsCompanion(state: Value(SprintState.planned)));
    await (_db.update(_t)..where((s) => s.id.equals(id))).write(
      const SprintsCompanion(state: Value(SprintState.active)),
    );
  });

  /// Its specs stay, in "Sem sprint" (`ON DELETE SET NULL`).
  Future<int> delete(int id) =>
      (_db.delete(_t)..where((s) => s.id.equals(id))).go();

  /// Moves [specIds] to [sprintId] (null = "Sem sprint"). Column, steps and
  /// runs are not touched (R5).
  Future<void> moveSpecs(Iterable<int> specIds, int? sprintId) =>
      (_db.update(_db.specs)..where((s) => s.id.isIn(specIds))).write(
        SpecsCompanion(sprintId: Value(sprintId)),
      );

  /// Closes [id] (R10): what is not in Feito goes to [moveTo] (null = "Sem
  /// sprint"), and [activate] becomes the active sprint, if given.
  Future<void> complete(int id, {int? moveTo, int? activate}) =>
      _db.transaction(() async {
        await (_db.update(_db.specs)..where(
              (s) =>
                  s.sprintId.equals(id) &
                  s.stage.equalsValue(SpecStage.done).not(),
            ))
            .write(SpecsCompanion(sprintId: Value(moveTo)));
        await (_db.update(_t)..where((s) => s.id.equals(id))).write(
          SprintsCompanion(
            state: const Value(SprintState.done),
            closedAt: Value(DateTime.now()),
          ),
        );
        if (activate != null) await this.activate(activate);
      });
}
