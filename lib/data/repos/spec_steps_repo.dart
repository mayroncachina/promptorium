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
      await (_db.update(
        _t,
      )..where((s) => s.specId.equals(specId) & s.step.equals(step))).write(
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
          await (_db.update(
            _t,
          )..where((s) => s.specId.equals(specId) & s.step.equals(step))).write(
            const SpecStepsCompanion(
              status: Value(StepStatus.pending),
              doneAt: Value(null),
              gateReport: Value(null),
              gateAttempts: Value(0),
            ),
          );
        }
      });

  /// Splits the execution of [parent] (SPEC-033 R16): one pending row per
  /// text of [bodies] (`R3.1`, `R3.2`…, returned in order), in place of any
  /// earlier split. The requirement's row stays, pending and without gate.
  Future<List<String>> addSubSteps(
    int specId,
    String parent,
    List<String> bodies,
  ) => _db.transaction(() async {
    await _deleteSubSteps(specId, parent);
    await set(specId, parent, StepStatus.pending);
    await reset(specId, [parent]);
    final ids = [for (var i = 1; i <= bodies.length; i++) '$parent.$i'];
    for (final (i, id) in ids.indexed) {
      await addExtra(specId, id, bodies[i]);
    }
    return ids;
  });

  /// Undoes [addSubSteps]: the sub-step rows of [parent] go away and, with
  /// [previous] (its row before the split), the requirement is as it was.
  Future<void> removeSubSteps(
    int specId,
    String parent, {
    SpecStep? previous,
  }) => _db.transaction(() async {
    await _deleteSubSteps(specId, parent);
    if (previous == null) return;
    await (_db.update(_t)
          ..where((s) => s.specId.equals(specId) & s.step.equals(parent)))
        .write(previous.toCompanion(false));
  });

  /// The steps of [specId] are exactly [rows] again, as read by [bySpec]:
  /// the rows written since then go away ("Desfazer", SPEC-033 R10).
  Future<void> restore(int specId, List<SpecStep> rows) =>
      _db.transaction(() async {
        await (_db.delete(_t)..where((s) => s.specId.equals(specId))).go();
        for (final row in rows) {
          await _db.into(_t).insert(row.toCompanion(false));
        }
      });

  Future<void> _deleteSubSteps(int specId, String parent) => (_db.delete(
    _t,
  )..where((s) => s.specId.equals(specId) & s.step.like('$parent.%'))).go();

  /// A step that is not in the file ([body] = its text): pending.
  Future<void> addExtra(int specId, String step, String body) => _db
      .into(_t)
      .insertOnConflictUpdate(
        SpecStepsCompanion.insert(
          specId: specId,
          step: step,
          status: const Value(StepStatus.pending),
          body: Value(body),
        ),
      );

  /// The row of [step] (null = no row yet: pending, no plan).
  Future<SpecStep?> byStep(int specId, String step) =>
      (_db.select(_t)
            ..where((s) => s.specId.equals(specId) & s.step.equals(step)))
          .getSingleOrNull();

  /// Stores the Orquestrador's plan of [step] (SPEC-035): [kind]
  /// (`StepKind.name`), the model and effort copied from the rules, the
  /// [hash] of the classified text and whether the user picked the model.
  /// The status and the gate of the step do not change.
  Future<void> setPlan(
    int specId,
    String step, {
    required String? kind,
    required String model,
    required String? effort,
    String? hash,
    bool userPicked = false,
  }) {
    final plan = SpecStepsCompanion(
      kind: Value(kind),
      planModel: Value(model),
      planEffort: Value(effort),
      planHash: Value(hash),
      userPicked: Value(userPicked),
    );
    return _db
        .into(_t)
        .insert(
          plan.copyWith(specId: Value(specId), step: Value(step)),
          onConflict: DoUpdate((old) => plan),
        );
  }

  /// Removes the plan of [steps]: they run with the model of the form again
  /// (Manual).
  Future<void> clearPlan(int specId, Iterable<String> steps) =>
      _db.transaction(() async {
        for (final step in steps) {
          await (_db.update(
            _t,
          )..where((s) => s.specId.equals(specId) & s.step.equals(step))).write(
            const SpecStepsCompanion(
              kind: Value(null),
              planModel: Value(null),
              planEffort: Value(null),
              planHash: Value(null),
              userPicked: Value(false),
              escalations: Value(0),
            ),
          );
        }
      });

  /// One more rung climbed by [step] (R9); returns the new count.
  Future<int> incrementEscalations(int specId, String step) =>
      _db.transaction(() async {
        final now = (await byStep(specId, step))?.escalations ?? 0;
        await _db
            .into(_t)
            .insert(
              SpecStepsCompanion.insert(
                specId: specId,
                step: step,
                escalations: Value(now + 1),
              ),
              onConflict: DoUpdate(
                (old) => SpecStepsCompanion(escalations: Value(now + 1)),
              ),
            );
        return now + 1;
      });

  /// A new execution of [steps] starts from the bottom of the ladder.
  Future<void> resetEscalations(int specId, Iterable<String> steps) =>
      _db.transaction(() async {
        for (final step in steps) {
          await (_db.update(_t)
                ..where((s) => s.specId.equals(specId) & s.step.equals(step)))
              .write(const SpecStepsCompanion(escalations: Value(0)));
        }
      });
}
