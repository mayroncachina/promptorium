import 'package:drift/drift.dart';

import '../db/app_database.dart';

class SavedPromptsRepo {
  SavedPromptsRepo(this._db);

  final AppDatabase _db;

  $SavedPromptsTable get _t => _db.savedPrompts;

  Stream<List<SavedPrompt>> watchAll() =>
      (_db.select(_t)..orderBy([(p) => OrderingTerm.asc(p.command)])).watch();

  Future<SavedPrompt?> getByCommand(String command) => (_db.select(
    _t,
  )..where((p) => p.command.equals(command))).getSingleOrNull();

  /// Inserts or replaces description/body of [command] (keeps `uses`).
  Future<SavedPrompt> upsert({
    required String command,
    required String body,
    String description = '',
  }) => _db
      .into(_t)
      .insertReturning(
        SavedPromptsCompanion.insert(
          command: command,
          body: body,
          description: Value(description),
        ),
        onConflict: DoUpdate(
          (_) => SavedPromptsCompanion(
            body: Value(body),
            description: Value(description),
          ),
          target: [_t.command],
        ),
      );

  Future<void> incrementUses(String command) => _db.customUpdate(
    'UPDATE saved_prompts SET uses = uses + 1 WHERE command = ?',
    variables: [Variable.withString(command)],
    updates: {_t},
    updateKind: UpdateKind.update,
  );

  Future<int> delete(String command) =>
      (_db.delete(_t)..where((p) => p.command.equals(command))).go();
}
