import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Attempts of the steps (schema v19, SPEC-035 R17): one row at the end of
/// each attempt, read by the Histórico of the Orquestrador.
class StepRunsRepo {
  StepRunsRepo(this._db);

  final AppDatabase _db;

  $StepRunsTable get _t => _db.stepRuns;

  /// Records the end of an attempt of [step]; returns the row id.
  Future<int> add({
    required int specId,
    required String step,
    required String? kind,
    required String model,
    String? effort,
    String? sessionId,
    required StepRunResult result,
    double? costUsd,
    DateTime? at,
  }) => _db
      .into(_t)
      .insert(
        StepRunsCompanion.insert(
          specId: specId,
          step: step,
          kind: Value(kind),
          model: model,
          effort: Value(effort),
          sessionId: Value(sessionId),
          result: result,
          costUsd: Value(costUsd),
          createdAt: Value.absentIfNull(at),
        ),
      );

  SimpleSelectStatement<$StepRunsTable, StepRun> _since(
    DateTime from, [
    DateTime? to,
  ]) => _db.select(_t)
    ..where(
      (r) =>
          r.createdAt.isBiggerOrEqualValue(from) &
          (to == null
              ? const Constant(true)
              : r.createdAt.isSmallerThanValue(to)),
    )
    ..orderBy([
      (r) => OrderingTerm.asc(r.createdAt),
      (r) => OrderingTerm.asc(r.id),
    ]);

  /// Attempts from [from] (inclusive) to [to] (exclusive; null = now on),
  /// oldest first.
  Future<List<StepRun>> between(DateTime from, [DateTime? to]) =>
      _since(from, to).get();

  Stream<List<StepRun>> watchSince(DateTime from) => _since(from).watch();

  /// Attempts of [specId], oldest first.
  Future<List<StepRun>> bySpec(int specId) =>
      (_db.select(_t)
            ..where((r) => r.specId.equals(specId))
            ..orderBy([(r) => OrderingTerm.asc(r.id)]))
          .get();
}
