import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:promptorium/data/providers.dart';

/// Fresh in-memory database (foreign keys on, schema created on first use).
AppDatabase memoryDatabase() {
  // Every test opens its own database on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Overrides [appDatabaseProvider] with [db] (closed by the container).
Override databaseOverride(AppDatabase db) =>
    appDatabaseProvider.overrideWith((ref) {
      ref.onDispose(db.close);
      return db;
    });
