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

  /// Tasks the schema v8 could not turn into steps (no spec or no
  /// requirement) and not done yet: the Quadro offers to make them specs.
  Stream<List<Task>> watchLegacy(int workspaceId) =>
      (_db.select(_t)
            ..where(
              (t) =>
                  t.workspaceId.equals(workspaceId) &
                  t.status.equals(TaskStatus.done.name).not() &
                  (t.specId.isNull() |
                      t.requirement.isNull() |
                      t.requirement.equals('')),
            )
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
    String? body,
    String? requirement,
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
          body: Value(body),
          requirement: Value(requirement),
          dependsOn: Value(dependsOn),
          status: Value(status),
        ),
      );

  /// Highest task number of the workspace (`TASK-NNN`, or the `T-NNN` codes
  /// written before Fase 8). 0 = none.
  Future<int> maxNumber(int workspaceId) async {
    final rows = await (_db.select(
      _t,
    )..where((t) => t.workspaceId.equals(workspaceId))).get();
    var max = 0;
    for (final r in rows) {
      final m = RegExp(r'^(?:TASK|T)-(\d+)$').firstMatch(r.code);
      final n = m == null ? 0 : int.parse(m.group(1)!);
      if (n > max) max = n;
    }
    return max;
  }

  /// `TASK-NNN` code for number [n].
  static String codeFor(int n) => 'TASK-${n.toString().padLeft(3, '0')}';

  /// Next free `TASK-NNN` code of the workspace (sequential per workspace).
  Future<String> nextCode(int workspaceId) async =>
      codeFor(await maxNumber(workspaceId) + 1);

  /// Runs [action] in a transaction (several inserts that must all land).
  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  Future<int> update(int id, TasksCompanion changes) =>
      (_db.update(_t)..where((t) => t.id.equals(id))).write(changes);

  Future<int> setStatus(int id, TaskStatus status) =>
      update(id, TasksCompanion(status: Value(status)));

  Future<int> assignAgent(int id, String? agentName) =>
      update(id, TasksCompanion(agentName: Value(agentName)));

  Future<int> delete(int id) =>
      (_db.delete(_t)..where((t) => t.id.equals(id))).go();
}
