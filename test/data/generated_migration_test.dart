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

  test('v18 → v19 keeps the steps, with no plan and no escalation', () async {
    final schema = await verifier.schemaAt(18);
    schema.rawDatabase
      ..execute("INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')")
      ..execute(
        "INSERT INTO specs (id, workspace_id, code, title, path) "
        "VALUES (1, 1, 'SPEC-001', 'x', 'specs/x.md')",
      )
      ..execute(
        "INSERT INTO spec_steps (spec_id, step, status, gate_attempts) "
        "VALUES (1, 'R1', 'done', 1)",
      );
    final db = AppDatabase(schema.newConnection());
    final row = await db.select(db.specSteps).getSingle();
    expect(row.status, StepStatus.done);
    expect(row.gateAttempts, 1);
    expect(
      (
        row.kind,
        row.planModel,
        row.planReason,
        row.userPicked,
        row.escalations,
      ),
      (null, null, null, false, 0),
    );
    expect(await db.select(db.stepRuns).get(), isEmpty);
    await db.close();
  });

  test('v20 → v21 keeps the specs, all in "Sem sprint"', () async {
    final schema = await verifier.schemaAt(20);
    schema.rawDatabase
      ..execute("INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')")
      ..execute(
        "INSERT INTO specs (id, workspace_id, code, title, path) "
        "VALUES (1, 1, 'SPEC-001', 'x', 'specs/x.md')",
      );
    final db = AppDatabase(schema.newConnection());
    final row = await db.select(db.specs).getSingle();
    expect(row.code, 'SPEC-001');
    expect(row.sprintId, equals(null));
    expect(await db.select(db.sprints).get(), isEmpty);
    await db.close();
  });

  test('v21 → v22 keeps the conversations, all active', () async {
    final schema = await verifier.schemaAt(21);
    schema.rawDatabase
      ..execute("INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')")
      ..execute(
        "INSERT INTO conversations (id, workspace_id, title, model) "
        "VALUES (1, 1, 'Como funciona o carrinho?', 'sonnet')",
      );
    final db = AppDatabase(schema.newConnection());
    final row = await db.select(db.conversations).getSingle();
    expect(row.title, 'Como funciona o carrinho?');
    expect(row.archivedAt, equals(null));
    await db.close();
  });

  test(
    'v22 → v23 keeps the specs, none planned until the next reading',
    () async {
      final schema = await verifier.schemaAt(22);
      schema.rawDatabase
        ..execute(
          "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
        )
        ..execute(
          "INSERT INTO specs (id, workspace_id, code, title, path) "
          "VALUES (1, 1, 'SPEC-001', 'Grupos', 'specs/SPEC-001-grupos.md')",
        );
      final db = AppDatabase(schema.newConnection());
      final row = await db.select(db.specs).getSingle();
      expect(row.code, 'SPEC-001');
      expect(row.hasPlan, isFalse);
      await db.close();
    },
  );

  test(
    'v23 → v24 keeps the specs on the Quadro, with no origin in the Prompt',
    () async {
      final schema = await verifier.schemaAt(23);
      schema.rawDatabase
        ..execute(
          "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
        )
        ..execute(
          "INSERT INTO specs (id, workspace_id, code, title, path, status) "
          "VALUES (1, 1, 'SPEC-001', 'Grupos', 'specs/SPEC-001-grupos.md', "
          "'approved')",
        );
      final db = AppDatabase(schema.newConnection());
      final row = await db.select(db.specs).getSingle();
      expect(row.code, 'SPEC-001');
      expect(row.status, SpecStatus.approved);
      expect(row.originConversationId, equals(null));
      expect(row.originAnswer, equals(null));
      expect(row.originItem, equals(null));
      expect(row.originAlias, equals(null));
      expect(row.originTitle, equals(null));
      // The Bandeja is for new specs: the ones on the Quadro stay there.
      expect(row.inTray, isFalse);
      await db.close();
    },
  );

  test('v24 → v25 keeps every spec as a spec and no conversation on a '
      'VIBE', () async {
    final schema = await verifier.schemaAt(24);
    schema.rawDatabase
      ..execute("INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')")
      ..execute(
        "INSERT INTO specs (id, workspace_id, code, title, path, status) "
        "VALUES (1, 1, 'SPEC-001', 'Grupos', 'specs/SPEC-001-grupos.md', "
        "'approved')",
      )
      ..execute(
        "INSERT INTO conversations (id, workspace_id, title, model) "
        "VALUES (1, 1, 'Oi', 'inherit')",
      );
    final db = AppDatabase(schema.newConnection());
    final row = await db.select(db.specs).getSingle();
    expect(row.code, 'SPEC-001');
    expect(row.kind, SpecKind.spec);
    final conv = await db.select(db.conversations).getSingle();
    expect(conv.specId, equals(null));
    await db.close();
  });
}
