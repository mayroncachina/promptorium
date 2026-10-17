import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// `SPEC SUGESTÃO: …` of the step sessions (schema v11).
class SpecSuggestionsRepo {
  SpecSuggestionsRepo(this._db);

  final AppDatabase _db;

  $SpecSuggestionsTable get _t => _db.specSuggestions;

  /// Pending suggestions of the specs of [workspaceId], oldest first.
  Stream<List<SpecSuggestion>> watchPending(int workspaceId) {
    final q =
        _db.select(_t).join([
            innerJoin(_db.specs, _db.specs.id.equalsExp(_t.specId)),
          ])
          ..where(
            _db.specs.workspaceId.equals(workspaceId) &
                _t.state.equals('pendente'),
          )
          ..orderBy([OrderingTerm.asc(_t.id)]);
    return q.watch().map((rows) => [for (final r in rows) r.readTable(_t)]);
  }

  Future<void> add({
    required int specId,
    required String body,
    String? sessionId,
    String? steps,
  }) => _db
      .into(_t)
      .insert(
        SpecSuggestionsCompanion.insert(
          specId: specId,
          body: body,
          sessionId: Value(sessionId),
          steps: Value(steps),
        ),
      );

  /// `aplicada` / `ignorada`.
  Future<void> setState(int id, String state) =>
      (_db.update(_t)..where((s) => s.id.equals(id))).write(
        SpecSuggestionsCompanion(state: Value(state)),
      );
}
