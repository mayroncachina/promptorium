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

/// v2–v4 shape of `sessions` (touched by the v5 upgrade).
const v2Sessions =
    'CREATE TABLE sessions (id TEXT NOT NULL PRIMARY KEY, '
    'workspace_id INTEGER NOT NULL REFERENCES workspaces (id), '
    'task_id INTEGER NULL, agent_name TEXT NULL, title TEXT NULL, '
    'permission_mode TEXT NULL, '
    'worktree_path TEXT NOT NULL, branch TEXT NOT NULL, '
    "status TEXT NOT NULL DEFAULT 'running', model TEXT NOT NULL, "
    'cost_usd REAL NOT NULL DEFAULT 0, '
    'tokens_in INTEGER NOT NULL DEFAULT 0, '
    'tokens_out INTEGER NOT NULL DEFAULT 0, '
    'started_at INTEGER NOT NULL DEFAULT 0, ended_at INTEGER NULL)';

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
    expect(v.data.values.single, 8);
  });

  test('v2 → v4 adds conversation columns, conversation_events, '
      'tasks.body and tasks.requirement', () async {
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
          raw.execute(v2Sessions);
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
    expect((await tasks.getById(1))!.requirement, isNull);
    // Old `T-NNN` codes count for the next `TASK-NNN` (Fase 8).
    expect(await tasks.nextCode(1), 'TASK-002');
    final t = await tasks.insert(
      workspaceId: 1,
      code: 'TASK-002',
      title: 'Nova',
      body: 'corpo',
      requirement: 'R1',
    );
    expect(t.body, 'corpo');
    expect(t.requirement, 'R1');
  });

  test(
    'v3 → v4 adds tasks.requirement and preserves the existing rows',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute(
              'CREATE TABLE workspaces (id INTEGER NOT NULL PRIMARY KEY '
              'AUTOINCREMENT, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, '
              'created_at INTEGER NOT NULL DEFAULT 0)',
            );
            raw.execute(v1TasksAndConversations.first);
            raw.execute('ALTER TABLE tasks ADD COLUMN body TEXT NULL');
            raw.execute(v2Sessions);
            raw.execute(
              "INSERT INTO workspaces (path, name) VALUES ('/r', 'r')",
            );
            raw.execute(
              'INSERT INTO tasks (workspace_id, code, title, status, '
              'agent_name, depends_on, body) VALUES '
              "(1, 'T-007', 'Antiga', 'review', 'dev', "
              "'[\"T-001\"]', 'corpo antigo')",
            );
            raw.userVersion = 3;
          },
        ),
      );
      addTearDown(db.close);
      await db.ensureOpen();

      final tasks = TasksRepo(db);
      final old = (await tasks.getById(1))!;
      expect(old.code, 'T-007');
      expect(old.title, 'Antiga');
      expect(old.status, TaskStatus.review);
      expect(old.agentName, 'dev');
      expect(old.dependsOn, ['T-001']);
      expect(old.body, 'corpo antigo');
      expect(old.requirement, isNull);
      expect(await tasks.nextCode(1), 'TASK-008');
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.single, 8);
    },
  );

  test('v4 → v5 adds sessions.base_branch, merge_commit and pr_url '
      '(existing rows preserved; merged status round-trips)', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE workspaces (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, '
            'created_at INTEGER NOT NULL DEFAULT 0)',
          );
          raw.execute(v2Sessions);
          raw.execute("INSERT INTO workspaces (path, name) VALUES ('/r', 'r')");
          raw.execute(
            'INSERT INTO sessions (id, workspace_id, worktree_path, branch, '
            "model, title, status) VALUES ('old', 1, '/wt', 'pr/x', "
            "'haiku', 'Antiga', 'completed')",
          );
          raw.userVersion = 4;
        },
      ),
    );
    addTearDown(db.close);
    await db.ensureOpen();
    final repo = SessionsRepo(db);
    final old = (await repo.getById('old'))!;
    expect(old.title, 'Antiga');
    expect(old.status, SessionStatus.completed);
    expect(old.baseBranch, isNull);
    expect(old.mergeCommit, isNull);
    expect(old.prUrl, isNull);
    await repo.setMerged('old', 'abc123');
    await repo.setPrUrl('old', 'https://example.com/pr/1');
    final m = (await repo.getById('old'))!;
    expect(m.status, SessionStatus.merged);
    expect(m.mergeCommit, 'abc123');
    expect(m.prUrl, 'https://example.com/pr/1');
    expect(m.endedAt, isNotNull);
    await repo.insert(
      id: 'new',
      workspaceId: 1,
      worktreePath: '/wt2',
      branch: 'pr/y',
      model: 'haiku',
      baseBranch: 'main',
    );
    expect((await repo.getById('new'))!.baseBranch, 'main');
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.data.values.single, 8);
  });

  test(
    'v6 → v7 adds sessions.effort and drops the daily token totals',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute(
              'CREATE TABLE workspaces (id INTEGER NOT NULL PRIMARY KEY '
              'AUTOINCREMENT, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, '
              'created_at INTEGER NOT NULL DEFAULT 0)',
            );
            raw.execute(
              v2Sessions.replaceFirst(
                'ended_at INTEGER NULL)',
                'ended_at INTEGER NULL, base_branch TEXT NULL, '
                    'merge_commit TEXT NULL, pr_url TEXT NULL)',
              ),
            );
            raw.execute(
              'CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, '
              'value TEXT NOT NULL)',
            );
            raw.execute(
              "INSERT INTO workspaces (path, name) VALUES ('/r', 'r')",
            );
            raw.execute(
              'INSERT INTO sessions (id, workspace_id, worktree_path, branch, '
              "model) VALUES ('old', 1, '/wt', 'pr/x', 'opus')",
            );
            raw.execute(
              'INSERT INTO app_settings (key, value) VALUES '
              "('usage.2026-10-15', '{}'), ('workspace.active', '1'), "
              "('usage.rateLimit', '{}')",
            );
            raw.userVersion = 6;
          },
        ),
      );
      addTearDown(db.close);
      await db.ensureOpen();
      final repo = SessionsRepo(db);
      expect((await repo.getById('old'))!.effort, isNull);
      await repo.insert(
        id: 'new',
        workspaceId: 1,
        worktreePath: '/wt2',
        branch: 'pr/y',
        model: 'sonnet',
        effort: 'medium',
      );
      expect((await repo.getById('new'))!.effort, 'medium');
      final keys = [
        for (final r
            in await db.customSelect('SELECT key FROM app_settings').get())
          r.read<String>('key'),
      ];
      expect(keys, unorderedEquals(['workspace.active', 'usage.rateLimit']));
    },
  );

  test('v7 → v8: tasks of a spec become step states, stage and spec '
      'dependencies; loose tasks stay', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE workspaces (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, '
            'created_at INTEGER NOT NULL DEFAULT 0)',
          );
          raw.execute(
            'CREATE TABLE specs (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, workspace_id INTEGER NOT NULL, code TEXT NOT NULL, '
            "title TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft', "
            'path TEXT NOT NULL, UNIQUE (workspace_id, code))',
          );
          raw.execute(
            'CREATE TABLE tasks (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, spec_id INTEGER NULL, workspace_id INTEGER NOT NULL, '
            'code TEXT NOT NULL, title TEXT NOT NULL, '
            "status TEXT NOT NULL DEFAULT 'backlog', agent_name TEXT NULL, "
            "body TEXT NULL, requirement TEXT NULL, depends_on TEXT NOT NULL "
            "DEFAULT '[]', created_at INTEGER NOT NULL DEFAULT 0)",
          );
          raw.execute(
            v2Sessions.replaceFirst(
              'ended_at INTEGER NULL)',
              'ended_at INTEGER NULL, base_branch TEXT NULL, '
                  'merge_commit TEXT NULL, pr_url TEXT NULL, effort TEXT NULL)',
            ),
          );
          raw.execute("INSERT INTO workspaces (path, name) VALUES ('/r', 'r')");
          raw.execute(
            'INSERT INTO specs (workspace_id, code, title, status, path) VALUES '
            "(1, 'SPEC-001', 'Base', 'approved', 'specs/SPEC-001.md'), "
            "(1, 'SPEC-002', 'Telas', 'approved', 'specs/SPEC-002.md'), "
            "(1, 'SPEC-003', 'Feita', 'approved', 'specs/SPEC-003.md')",
          );
          raw.execute(
            'INSERT INTO tasks (spec_id, workspace_id, code, title, status, '
            'requirement, depends_on) VALUES '
            "(1, 1, 'TASK-001', 'a', 'done', 'R1', '[]'), "
            "(1, 1, 'TASK-002', 'b', 'backlog', 'R2', '[\"TASK-001\"]'), "
            "(1, 1, 'TASK-003', 'b2', 'done', 'R2', '[]'), "
            "(2, 1, 'TASK-004', 'c', 'running', 'R1', "
            "'[\"TASK-002\",\"TASK-005\"]'), "
            "(3, 1, 'TASK-005', 'd', 'done', 'R1', '[]'), "
            "(NULL, 1, 'TASK-006', 'solta', 'backlog', NULL, '[]'), "
            "(2, 1, 'TASK-007', 'sem req', 'backlog', NULL, '[]')",
          );
          raw.execute(
            'INSERT INTO sessions (id, workspace_id, task_id, worktree_path, '
            "branch, model) VALUES ('s4', 1, 4, '/wt', 'pr/x', 'sonnet')",
          );
          raw.userVersion = 7;
        },
      ),
    );
    addTearDown(db.close);
    await db.ensureOpen();

    final specs = {for (final s in await db.select(db.specs).get()) s.code: s};
    expect(specs['SPEC-001']!.stage, SpecStage.backlog);
    expect(specs['SPEC-002']!.stage, SpecStage.running);
    expect(specs['SPEC-003']!.stage, SpecStage.done);
    expect(specs['SPEC-001']!.dependsOn, isEmpty);
    expect(specs['SPEC-002']!.dependsOn, ['SPEC-001', 'SPEC-003']);
    expect(specs['SPEC-001']!.requirements, isEmpty); // filled by the sync
    expect(specs['SPEC-001']!.autoAdvance, isTrue);

    final steps = {
      for (final s in await db.select(db.specSteps).get())
        '${specs.values.firstWhere((x) => x.id == s.specId).code}/${s.step}':
            s.status,
    };
    expect(steps, {
      'SPEC-001/R1': StepStatus.done,
      'SPEC-001/R2': StepStatus.pending, // one of its two tasks is open
      'SPEC-002/R1': StepStatus.pending,
      'SPEC-003/R1': StepStatus.done,
    });
    expect(
      (await SessionsRepo(db).getById('s4'))!.specId,
      specs['SPEC-002']!.id,
    );
    final legacy = await TasksRepo(db).watchLegacy(1).first;
    expect(legacy.map((t) => t.code), ['TASK-006', 'TASK-007']);
  });
}
