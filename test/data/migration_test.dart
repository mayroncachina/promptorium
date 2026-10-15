import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/conversations_repo.dart';
import 'package:promptorium/data/repos/sessions_repo.dart';
import 'package:promptorium/data/repos/tasks_repo.dart';

/// v1 shape (Fase 3) of the tables touched by the v3 upgrade.
const v1TasksAndConversations = [
  ('CREATE TABLE tasks (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'spec_id INTEGER NULL, workspace_id INTEGER NOT NULL, '
      'code TEXT NOT NULL, title TEXT NOT NULL, '
      "status TEXT NOT NULL DEFAULT 'backlog', agent_name TEXT NULL, "
      "depends_on TEXT NOT NULL DEFAULT '[]', "
      'created_at INTEGER NOT NULL DEFAULT 0)'),
  ('CREATE TABLE conversations (id INTEGER NOT NULL PRIMARY KEY '
      'AUTOINCREMENT, workspace_id INTEGER NOT NULL, title TEXT NOT NULL, '
      "provider TEXT NOT NULL DEFAULT 'claude', model TEXT NOT NULL, "
      'session_id TEXT NULL, created_at INTEGER NOT NULL DEFAULT 0)'),
];

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
          v1TasksAndConversations.forEach(raw.execute);
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
    expect(v.data.values.single, 3);
  });

  test('v2 → v3 adds conversation columns, conversation_events and '
      'tasks.body', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE workspaces (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, '
            'created_at INTEGER NOT NULL DEFAULT 0)',
          );
          v1TasksAndConversations.forEach(raw.execute);
          raw.execute("INSERT INTO workspaces (path, name) VALUES ('/r', 'r')");
          raw.execute(
            "INSERT INTO conversations (workspace_id, title, model) "
            "VALUES (1, 'Antiga', 'sonnet')",
          );
          raw.execute(
            "INSERT INTO tasks (workspace_id, code, title) "
            "VALUES (1, 'T-001', 'Antiga')",
          );
          raw.userVersion = 2;
        },
      ),
    );
    addTearDown(db.close);
    await db.ensureOpen();

    final convs = ConversationsRepo(db);
    final old = await convs.getById(1);
    expect(old!.mode, 'ask');
    expect(old.claudeSessionId, isNull);
    expect(old.tokensIn, 0);
    expect(old.messageCount, 0);
    await convs.appendEvent(1, type: 'promptorium_user', json: '{}');
    expect(await convs.events(1), hasLength(1));

    final tasks = TasksRepo(db);
    expect((await tasks.getById(1))!.body, isNull);
    expect(await tasks.nextCode(1), 'T-002');
    final t = await tasks.insert(
      workspaceId: 1,
      code: 'T-002',
      title: 'Nova',
      body: 'corpo',
    );
    expect(t.body, 'corpo');
  });
}
