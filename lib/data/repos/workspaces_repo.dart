import 'package:drift/drift.dart';

import '../db/app_database.dart';

class WorkspacesRepo {
  WorkspacesRepo(this._db);

  final AppDatabase _db;

  $WorkspacesTable get _t => _db.workspaces;

  SimpleSelectStatement<$WorkspacesTable, Workspace> _ordered() =>
      _db.select(_t)..orderBy([(w) => OrderingTerm.asc(w.name)]);

  Stream<List<Workspace>> watchAll() => _ordered().watch();

  Future<List<Workspace>> getAll() => _ordered().get();

  Future<Workspace?> getById(int id) =>
      (_db.select(_t)..where((w) => w.id.equals(id))).getSingleOrNull();

  Future<Workspace?> getByPath(String path) =>
      (_db.select(_t)..where((w) => w.path.equals(path))).getSingleOrNull();

  /// Inserts [path] or returns the existing workspace with that path.
  Future<Workspace> add({required String path, required String name}) async {
    final existing = await getByPath(path);
    if (existing != null) return existing;
    return _db
        .into(_t)
        .insertReturning(WorkspacesCompanion.insert(path: path, name: name));
  }

  Future<void> rename(int id, String name) =>
      (_db.update(_t)..where((w) => w.id.equals(id))).write(
        WorkspacesCompanion(name: Value(name)),
      );

  /// Also deletes its specs, tasks, sessions and conversations (cascade).
  Future<int> delete(int id) =>
      (_db.delete(_t)..where((w) => w.id.equals(id))).go();
}
