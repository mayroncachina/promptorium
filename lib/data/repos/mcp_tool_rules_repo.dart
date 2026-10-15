import 'package:drift/drift.dart';

import '../db/app_database.dart';

class McpToolRulesRepo {
  McpToolRulesRepo(this._db);

  final AppDatabase _db;

  $McpToolRulesTable get _t => _db.mcpToolRules;

  Stream<List<McpToolRule>> watchAll() =>
      (_db.select(_t)..orderBy([
            (r) => OrderingTerm.asc(r.server),
            (r) => OrderingTerm.asc(r.tool),
          ]))
          .watch();

  Stream<List<McpToolRule>> watchForServer(String server) =>
      (_db.select(_t)
            ..where((r) => r.server.equals(server))
            ..orderBy([(r) => OrderingTerm.asc(r.tool)]))
          .watch();

  Future<List<McpToolRule>> getForServer(String server) =>
      (_db.select(_t)..where((r) => r.server.equals(server))).get();

  Future<void> setRule(String server, String tool, McpRule rule) => _db
      .into(_t)
      .insertOnConflictUpdate(
        McpToolRulesCompanion.insert(server: server, tool: tool, rule: rule),
      );

  Future<int> delete(String server, String tool) => (_db.delete(
    _t,
  )..where((r) => r.server.equals(server) & r.tool.equals(tool))).go();

  Future<int> deleteServer(String server) =>
      (_db.delete(_t)..where((r) => r.server.equals(server))).go();
}
