import 'package:drift/drift.dart';

import '../db/app_database.dart';

class SpecsRepo {
  SpecsRepo(this._db);

  final AppDatabase _db;

  $SpecsTable get _t => _db.specs;

  Stream<List<Spec>> watchByWorkspace(int workspaceId) =>
      (_db.select(_t)
            ..where((s) => s.workspaceId.equals(workspaceId))
            ..orderBy([(s) => OrderingTerm.asc(s.code)]))
          .watch();

  Stream<Spec?> watchById(int id) =>
      (_db.select(_t)..where((s) => s.id.equals(id))).watchSingleOrNull();

  Future<Spec?> getById(int id) =>
      (_db.select(_t)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<Spec?> getByCode(int workspaceId, String code) =>
      (_db.select(_t)..where(
            (s) => s.workspaceId.equals(workspaceId) & s.code.equals(code),
          ))
          .getSingleOrNull();

  /// Highest `SPEC-NNN` number registered in the workspace (0 = none).
  Future<int> maxNumber(int workspaceId) async {
    final rows = await (_db.select(
      _t,
    )..where((s) => s.workspaceId.equals(workspaceId))).get();
    var max = 0;
    for (final r in rows) {
      final m = RegExp(r'^SPEC-(\d+)$').firstMatch(r.code);
      final n = m == null ? 0 : int.parse(m.group(1)!);
      if (n > max) max = n;
    }
    return max;
  }

  Future<Spec> insert({
    required int workspaceId,
    required String code,
    required String title,
    required String path,
    SpecStatus status = SpecStatus.draft,
    List<SpecRequirement> requirements = const [],
    List<String>? dependsOn,
    String? phase,
  }) => _db
      .into(_t)
      .insertReturning(
        SpecsCompanion.insert(
          workspaceId: workspaceId,
          code: code,
          title: title,
          path: path,
          status: Value(status),
          requirements: Value(requirements),
          dependsOn: Value.absentIfNull(dependsOn),
          phase: Value(phase),
        ),
      );

  /// Writes the non-absent fields of [changes].
  Future<int> update(int id, SpecsCompanion changes) =>
      (_db.update(_t)..where((s) => s.id.equals(id))).write(changes);

  Future<int> setStatus(int id, SpecStatus status) =>
      update(id, SpecsCompanion(status: Value(status)));

  /// Column of the Quadro.
  Future<int> setStage(int id, SpecStage stage) =>
      update(id, SpecsCompanion(stage: Value(stage)));

  Future<int> setAgent(int id, String? agent) => update(
    id,
    SpecsCompanion(agentName: Value((agent?.isEmpty ?? true) ? null : agent)),
  );

  Future<int> setAutoAdvance(int id, bool on) =>
      update(id, SpecsCompanion(autoAdvance: Value(on)));

  /// Worktree / branch shared by the step sessions (null = none: the
  /// worktree was removed by the merge) and its [index] (port). Clearing it
  /// also forgets the preparation.
  Future<int> setWorktree(
    int id, {
    String? path,
    String? branch,
    String? baseBranch,
    int? index,
  }) => update(
    id,
    SpecsCompanion(
      worktreePath: Value(path),
      branch: Value(branch),
      baseBranch: Value(baseBranch),
      worktreeIndex: Value(index),
      preparedAt: path == null ? const Value(null) : const Value.absent(),
    ),
  );

  /// Phase of the Review column (`auto` / `human` / null) and the rounds
  /// of corrections asked by the automatic reviewer.
  Future<int> setReview(int id, {String? phase, int? rounds}) => update(
    id,
    SpecsCompanion(
      reviewPhase: Value(phase),
      reviewRounds: Value.absentIfNull(rounds),
    ),
  );

  /// One more automatic fix sent by the gate (metrics, schema v13).
  Future<void> countGateResend(int id) => _db.customUpdate(
    'UPDATE specs SET gate_resends = gate_resends + 1 WHERE id = ?',
    variables: [Variable.withInt(id)],
    updates: {_t},
  );

  /// One more hunk rejected in the Review (metrics, schema v13).
  Future<void> countRejectedHunk(int id) => _db.customUpdate(
    'UPDATE specs SET rejected_hunks = rejected_hunks + 1 WHERE id = ?',
    variables: [Variable.withInt(id)],
    updates: {_t},
  );

  /// Order of the cards of a column: [ids] get 0, 1, 2…
  Future<void> setBoardOrder(List<int> ids) => _db.transaction(() async {
    for (final (i, id) in ids.indexed) {
      await update(id, SpecsCompanion(boardOrder: Value(i)));
    }
  });

  /// The worktree got its files and ran `preparar:` (null = not yet).
  Future<int> setPrepared(int id, DateTime? at) =>
      update(id, SpecsCompanion(preparedAt: Value(at)));

  Future<int> delete(int id) =>
      (_db.delete(_t)..where((s) => s.id.equals(id))).go();
}
