import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Best-of-N attempts of a step (schema v14).
class SpecDuelsRepo {
  SpecDuelsRepo(this._db);

  final AppDatabase _db;

  $SpecDuelsTable get _t => _db.specDuels;

  Future<SpecDuel?> getById(int id) =>
      (_db.select(_t)..where((d) => d.id.equals(id))).getSingleOrNull();

  /// The open duel of [specId] (running or waiting for a choice).
  Future<SpecDuel?> openOf(int specId) =>
      (_db.select(_t)
            ..where(
              (d) =>
                  d.specId.equals(specId) & d.state.isIn(['rodando', 'pronto']),
            )
            ..orderBy([(d) => OrderingTerm.desc(d.id)])
            ..limit(1))
          .getSingleOrNull();

  /// Open duels of the specs of [workspaceId] (Quadro).
  Stream<List<SpecDuel>> watchOpen(int workspaceId) {
    final q =
        _db.select(_t).join([
          innerJoin(_db.specs, _db.specs.id.equalsExp(_t.specId)),
        ])..where(
          _db.specs.workspaceId.equals(workspaceId) &
              _t.state.isIn(['rodando', 'pronto']),
        );
    return q.watch().map((rows) => [for (final r in rows) r.readTable(_t)]);
  }

  Future<SpecDuel> insert(SpecDuelsCompanion row) =>
      _db.into(_t).insertReturning(row);

  Future<void> update(int id, SpecDuelsCompanion changes) =>
      (_db.update(_t)..where((d) => d.id.equals(id))).write(changes);
}
