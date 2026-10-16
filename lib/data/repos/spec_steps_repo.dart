import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// State of the steps of each spec (schema v8). Rows are created on demand:
/// a step without a row is `pending`.
class SpecStepsRepo {
  SpecStepsRepo(this._db);

  final AppDatabase _db;

  $SpecStepsTable get _t => _db.specSteps;

  Stream<List<SpecStep>> watchBySpec(int specId) =>
      (_db.select(_t)..where((s) => s.specId.equals(specId))).watch();

  Future<List<SpecStep>> bySpec(int specId) =>
      (_db.select(_t)..where((s) => s.specId.equals(specId))).get();

  /// Every step row of the specs of [workspaceId] (Quadro).
  Stream<List<SpecStep>> watchByWorkspace(int workspaceId) {
    final q = _db.select(_t).join([
      innerJoin(_db.specs, _db.specs.id.equalsExp(_t.specId)),
    ])..where(_db.specs.workspaceId.equals(workspaceId));
    return q.watch().map((rows) => [for (final r in rows) r.readTable(_t)]);
  }

  /// Sets the state of [step]; `done` stamps `doneAt`, the others clear it.
  /// [sessionId] null keeps the stored one.
  Future<void> set(
    int specId,
    String step,
    StepStatus status, {
    String? sessionId,
    DateTime? at,
  }) => _db
      .into(_t)
      .insert(
        SpecStepsCompanion.insert(
          specId: specId,
          step: step,
          status: Value(status),
          sessionId: Value.absentIfNull(sessionId),
          doneAt: Value(
            status == StepStatus.done ? (at ?? DateTime.now()) : null,
          ),
        ),
        onConflict: DoUpdate(
          (old) => SpecStepsCompanion(
            status: Value(status),
            sessionId: Value.absentIfNull(sessionId),
            doneAt: Value(
              status == StepStatus.done ? (at ?? DateTime.now()) : null,
            ),
          ),
        ),
      );

  /// Every step of [specId] in [steps] → [status] (merge: all `done`).
  Future<void> setAll(int specId, Iterable<String> steps, StepStatus status) =>
      _db.transaction(() async {
        for (final s in steps) {
          await set(specId, s, status);
        }
      });
}
