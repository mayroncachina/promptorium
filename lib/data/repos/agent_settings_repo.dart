import 'package:drift/drift.dart';

import '../db/app_database.dart';

class AgentSettingsRepo {
  AgentSettingsRepo(this._db);

  final AppDatabase _db;

  $AgentSettingsTable get _t => _db.agentSettings;

  Stream<List<AgentSetting>> watchAll() =>
      (_db.select(_t)..orderBy([
            (a) => OrderingTerm.asc(a.agentName),
            (a) => OrderingTerm.asc(a.scope),
          ]))
          .watch();

  Future<AgentSetting?> get(String agentName, AgentScope scope) =>
      (_db.select(_t)..where(
            (a) => a.agentName.equals(agentName) & a.scope.equalsValue(scope),
          ))
          .getSingleOrNull();

  /// Inserts or replaces every column of the row.
  Future<void> upsert(AgentSetting setting) =>
      _db.into(_t).insertOnConflictUpdate(setting);

  Future<int> delete(String agentName, AgentScope scope) =>
      (_db.delete(_t)..where(
            (a) => a.agentName.equals(agentName) & a.scope.equalsValue(scope),
          ))
          .go();
}
