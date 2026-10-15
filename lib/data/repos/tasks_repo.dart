import 'package:drift/drift.dart';

import '../db/app_database.dart';

class TasksRepo {
  TasksRepo(this._db);

  final AppDatabase _db;

  $TasksTable get _t => _db.tasks;

  Stream<List<Task>> watchByWorkspace(int workspaceId) =>
      (_db.select(_t)
            ..where((t) => t.workspaceId.equals(workspaceId))
            ..orderBy([(t) => OrderingTerm.asc(t.code)]))
          .watch();

  Stream<List<Task>> watchBySpec(int specId) =>
      (_db.select(_t)
            ..where((t) => t.specId.equals(specId))
            ..orderBy([(t) => OrderingTerm.asc(t.code)]))
          .watch();

  Future<Task?> getById(int id) =>
      (_db.select(_t)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Task> insert({
    required int workspaceId,
    required String code,
    required String title,
    int? specId,
    String? agentName,
    List<String> dependsOn = const [],
    TaskStatus status = TaskStatus.backlog,
  }) => _db
      .into(_t)
      .insertReturning(
        TasksCompanion.insert(
          workspaceId: workspaceId,
          code: code,
          title: title,
          specId: Value(specId),
          agentName: Value(agentName),
          dependsOn: Value(dependsOn),
          status: Value(status),
        ),
      );

  Future<int> update(int id, TasksCompanion changes) =>
      (_db.update(_t)..where((t) => t.id.equals(id))).write(changes);

  Future<int> setStatus(int id, TaskStatus status) =>
      update(id, TasksCompanion(status: Value(status)));

  Future<int> assignAgent(int id, String? agentName) =>
      update(id, TasksCompanion(agentName: Value(agentName)));

  Future<int> delete(int id) =>
      (_db.delete(_t)..where((t) => t.id.equals(id))).go();
}
