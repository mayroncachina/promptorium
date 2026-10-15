import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/sessions_repo.dart';

void main() {
  test('v1 → v2 adds sessions.title and sessions.permission_mode', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          // Schema v1 (Fase 3) of the two tables the upgrade touches.
          raw.execute(
            'CREATE TABLE workspaces (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, '
            'created_at INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', '
            'CURRENT_TIMESTAMP) AS INTEGER)))',
          );
          raw.execute(
            'CREATE TABLE sessions (id TEXT NOT NULL PRIMARY KEY, '
            'workspace_id INTEGER NOT NULL REFERENCES workspaces (id), '
            'task_id INTEGER NULL, agent_name TEXT NULL, '
            'worktree_path TEXT NOT NULL, branch TEXT NOT NULL, '
            "status TEXT NOT NULL DEFAULT 'running', model TEXT NOT NULL, "
            'cost_usd REAL NOT NULL DEFAULT 0, '
            'tokens_in INTEGER NOT NULL DEFAULT 0, '
            'tokens_out INTEGER NOT NULL DEFAULT 0, '
            'started_at INTEGER NOT NULL DEFAULT 0, ended_at INTEGER NULL)',
          );
          raw.execute("INSERT INTO workspaces (path, name) VALUES ('/r', 'r')");
          raw.execute(
            "INSERT INTO sessions (id, workspace_id, worktree_path, branch, "
            "model) VALUES ('old', 1, '/r', 'main', 'haiku')",
          );
          raw.userVersion = 1;
        },
      ),
    );
    addTearDown(db.close);
    await db.ensureOpen();

    final repo = SessionsRepo(db);
    final old = await repo.getById('old');
    expect(old!.title, isNull);
    expect(old.permissionMode, isNull);
    await repo.insert(
      id: 'new',
      workspaceId: 1,
      worktreePath: '/r',
      branch: 'main',
      model: 'haiku',
      title: 'Nova',
      permissionMode: 'plan',
    );
    final n = await repo.getById('new');
    expect(n!.title, 'Nova');
    expect(n.permissionMode, 'plan');
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.data.values.single, 2);
  });
}
