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

  /// A session starts [steps]: where they start from (`HEAD` and the stash
  /// of the uncommitted changes) and a fresh gate.
  Future<void> markStart(
    int specId,
    Iterable<String> steps, {
    required String? sha,
    String? stash,
  }) => _db.transaction(() async {
    for (final step in steps) {
      await _db
          .into(_t)
          .insert(
            SpecStepsCompanion.insert(
              specId: specId,
              step: step,
              startSha: Value(sha),
              startStash: Value(stash),
              gateAttempts: const Value(0),
            ),
            onConflict: DoUpdate(
              (old) => SpecStepsCompanion(
                startSha: Value(sha),
                startStash: Value(stash),
                gateAttempts: const Value(0),
              ),
            ),
          );
    }
  });

  /// Stores the gate's [report] (JSON) and the resends made so far.
  Future<void> setGate(
    int specId,
    Iterable<String> steps, {
    required String? report,
    int? attempts,
  }) => _db.transaction(() async {
    for (final step in steps) {
      await (_db.update(_t)
            ..where((s) => s.specId.equals(specId) & s.step.equals(step)))
          .write(
            SpecStepsCompanion(
              gateReport: Value(report),
              gateAttempts: Value.absentIfNull(attempts),
            ),
          );
    }
  });

  /// Back to the start of the step: pending, no gate.
  Future<void> reset(int specId, Iterable<String> steps) =>
      _db.transaction(() async {
        for (final step in steps) {
          await (_db.update(_t)
                ..where((s) => s.specId.equals(specId) & s.step.equals(step)))
              .write(
                const SpecStepsCompanion(
                  status: Value(StepStatus.pending),
                  doneAt: Value(null),
                  gateReport: Value(null),
                  gateAttempts: Value(0),
                ),
              );
        }
      });
}
