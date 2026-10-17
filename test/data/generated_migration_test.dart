import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';

import '../generated_migrations/schema.dart';

/// Every stored schema (drift_schemas/, v8 onwards) migrates to the current
/// one and ends exactly as a fresh database (F11). Regenerate after a
/// schema change:
///   dart run drift_dev schema dump lib/data/db/app_database.dart drift_schemas/drift_schema_vN.json
///   dart run drift_dev schema steps drift_schemas/ lib/data/db/schema_versions.dart
///   dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  for (final from in GeneratedHelper.versions) {
    if (from == appSchemaVersion) continue;
    test('v$from → v$appSchemaVersion', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, appSchemaVersion);
      await db.close();
    });
  }
}
