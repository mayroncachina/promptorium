import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/review_comments_repo.dart';

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

  test('v25 → v26 (SPEC-050 P1) keeps the comments of the specs '
      'and takes those of a PR without spec, by session', () async {
    final schema = await verifier.schemaAt(25);
    schema.rawDatabase
      ..execute("INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')")
      ..execute(
        "INSERT INTO specs (id, workspace_id, code, title, path) "
        "VALUES (1, 1, 'SPEC-001', 'x', 'specs/x.md')",
      )
      ..execute(
        "INSERT INTO sessions (id, workspace_id, worktree_path, branch, "
        "status, model, started_at) "
        "VALUES ('s1', 1, '/wt', 'feat/x', 'completed', 'sonnet', 0)",
      )
      ..execute(
        "INSERT INTO review_comments (spec_id, round, author, body, "
        "external_id, path, line) "
        "VALUES (1, 1, 'pr', '@ana: renomeie', 'github:9', 'a.dart', 3)",
      )
      ..execute(
        "INSERT INTO review_comments (spec_id, round, author, body) "
        "VALUES (1, 2, 'humano', 'Ajustes pedidos.')",
      );
    final db = AppDatabase(schema.newConnection());
    final rows = await (db.select(
      db.reviewComments,
    )..orderBy([(c) => OrderingTerm.asc(c.id)])).get();
    expect(rows.map((r) => (r.specId, r.sessionId, r.author, r.round)), [
      (1, null, 'pr', 1),
      (1, null, 'humano', 2),
    ]);
    expect(rows.first.externalId, 'github:9');
    expect(rows.first.path, 'a.dart');
    // A comment of the session, with no spec; the external id is unique by
    // session, so reading the PR again never duplicates it.
    final repo = ReviewCommentsRepo(db);
    final row = ReviewCommentsCompanion.insert(
      sessionId: const Value('s1'),
      round: 1,
      author: 'pr',
      body: '@ana: renomeie',
      externalId: const Value('github:9'),
    );
    await repo.insertExternal(row);
    await repo.insertExternal(row);
    final mine = await repo.bySession('s1');
    expect(mine, hasLength(1));
    expect(mine.single.specId, equals(null));
    expect(await repo.bySpec(1), hasLength(2));
    await db.close();
  });
  test('v26 → v27 (SPEC-052) keeps the specs, none created by the agent, and '
      'no notes', () async {
    final schema = await verifier.schemaAt(26);
    schema.rawDatabase
      ..execute("INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')")
      ..execute(
        "INSERT INTO specs (id, workspace_id, code, title, path, status) "
        "VALUES (1, 1, 'SPEC-001', 'Grupos', 'specs/SPEC-001-grupos.md', "
        "'approved')",
      );
    final db = AppDatabase(schema.newConnection());
    final row = await db.select(db.specs).getSingle();
    expect(row.code, 'SPEC-001');
    expect(row.status, SpecStatus.approved);
    expect(row.agentSession, equals(null));
    expect(await db.select(db.specNotes).get(), isEmpty);
    await db
        .into(db.specNotes)
        .insert(
          SpecNotesCompanion.insert(specId: 1, note: 'Comecei pela tabela.'),
        );
    expect(
      (await db.select(db.specNotes).getSingle()).note,
      'Comecei pela tabela.',
    );
    await db.close();
  });

  // SPEC-074: provisional number; whoever integrates last renumbers it.
  test(
    'v27 → v28 (SPEC-074) keeps the specs, none linked to an issue yet',
    () async {
      final schema = await verifier.schemaAt(27);
      schema.rawDatabase
        ..execute(
          "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
        )
        ..execute(
          "INSERT INTO specs (id, workspace_id, code, title, path, status) "
          "VALUES (1, 1, 'SPEC-023', 'Pix', 'specs/SPEC-023-pix.md', "
          "'approved')",
        );
      final db = AppDatabase(schema.newConnection());
      final row = await db.select(db.specs).getSingle();
      expect(row.code, 'SPEC-023');
      expect(row.status, SpecStatus.approved);
      expect(row.issueNumber, equals(null));
      expect(row.issueState, equals(null));
      expect(row.issueImportedAt, equals(null));
      expect(row.issueCommentPending, isFalse);
      await (db.update(db.specs)..where((s) => s.id.equals(1))).write(
        const SpecsCompanion(
          issueNumber: Value(226),
          issueState: Value(IssueState.closed),
          issueClosedBy: Value('PR #250'),
        ),
      );
      final linked = await db.select(db.specs).getSingle();
      expect(linked.issueNumber, 226);
      expect(linked.issueState, IssueState.closed);
      await db.close();
    },
  );

  test('v28 → v29 (SPEC-078) creates the snippets of a workspace', () async {
    final schema = await verifier.schemaAt(28);
    schema.rawDatabase.execute(
      "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
    );
    final db = AppDatabase(schema.newConnection());
    await db
        .into(db.snippets)
        .insert(
          SnippetsCompanion.insert(
            workspaceId: 1,
            name: 'Atrasados',
            nameKey: 'atrasados',
            body: 'select 1;',
            bodyHash: 'h',
          ),
        );
    final row = await db.select(db.snippets).getSingle();
    expect(row.uses, 0);
    expect(row.lastUsedAt, equals(null));
    expect(row.description, '');
    await db.close();
  });

  test('v29 → v30 (SPEC-080) creates the journal of a workspace', () async {
    final schema = await verifier.schemaAt(29);
    schema.rawDatabase.execute(
      "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
    );
    final db = AppDatabase(schema.newConnection());
    await db
        .into(db.activityEvents)
        .insert(
          ActivityEventsCompanion.insert(
            workspaceId: 1,
            kind: 'gate',
            outcome: 'failed',
            title: 'SPEC-077',
            groupKey: 'spec:1',
            at: DateTime(2026, 11, 16),
          ),
        );
    final row = await db.select(db.activityEvents).getSingle();
    expect(row.seed, equals(null));
    expect(row.detail, '');
    await db.close();
  });
  test('v30 → v31 (SPEC-081) creates the usage entries, nothing else '
      'changes', () async {
    final schema = await verifier.schemaAt(30);
    schema.rawDatabase.execute(
      "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
    );
    final db = AppDatabase(schema.newConnection());
    await db
        .into(db.usageEntries)
        .insert(
          UsageEntriesCompanion.insert(
            workspaceId: const Value(1),
            source: UsageSource.etapa,
            at: DateTime(2026, 11, 17),
          ),
        );
    final row = await db.select(db.usageEntries).getSingle();
    expect(row.tokensIn, 0);
    expect(row.costUsd, 0);
    expect(row.weekPct, equals(null));
    expect(row.estimated, isFalse);
    expect(
      (await db.select(db.workspaces).getSingle()).name,
      'r',
      reason: 'the workspaces are kept',
    );
    await db.close();
  });
  test(
    'v31 → v32 (SPEC-084) creates the restore points of a session',
    () async {
      final schema = await verifier.schemaAt(31);
      schema.rawDatabase.execute(
        "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
      );
      final db = AppDatabase(schema.newConnection());
      await db
          .into(db.restorePoints)
          .insert(
            RestorePointsCompanion.insert(
              workspaceId: 1,
              worktreePath: '/r',
              turn: 1,
              startedAt: DateTime(2026, 11, 17, 14, 2),
              startHead: 'a' * 40,
              startSha: 'b' * 40,
            ),
          );
      final row = await db.select(db.restorePoints).getSingle();
      expect(row.state, 'ativo');
      expect(row.largeFiles, '[]');
      expect(row.endSha, equals(null));
      await db.close();
    },
  );
  test('v32 → v33 (SPEC-085) creates the secret waivers', () async {
    final schema = await verifier.schemaAt(32);
    schema.rawDatabase.execute(
      "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
    );
    final db = AppDatabase(schema.newConnection());
    await db
        .into(db.secretWaivers)
        .insert(
          SecretWaiversCompanion.insert(
            workspaceId: 1,
            rule: 'env-file',
            path: '.env',
            fingerprint: 'f',
            scope: 'arquivo',
            reason: 'arquivo local de teste',
            origin: 'sessao:s1',
          ),
        );
    final row = await db.select(db.secretWaivers).getSingle();
    expect(row.scope, 'arquivo');
    await db.close();
  });
}
