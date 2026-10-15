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
  }) => _db
      .into(_t)
      .insertReturning(
        SpecsCompanion.insert(
          workspaceId: workspaceId,
          code: code,
          title: title,
          path: path,
          status: Value(status),
        ),
      );

  /// Writes the non-absent fields of [changes].
  Future<int> update(int id, SpecsCompanion changes) =>
      (_db.update(_t)..where((s) => s.id.equals(id))).write(changes);

  Future<int> setStatus(int id, SpecStatus status) =>
      update(id, SpecsCompanion(status: Value(status)));

  Future<int> delete(int id) =>
      (_db.delete(_t)..where((s) => s.id.equals(id))).go();
}
