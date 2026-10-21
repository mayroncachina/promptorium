import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/agent_settings_repo.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/data/repos/conversations_repo.dart';
import 'package:promptorium/data/repos/mcp_tool_rules_repo.dart';
import 'package:promptorium/data/repos/saved_prompts_repo.dart';
import 'package:promptorium/data/repos/sessions_repo.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/data/repos/tasks_repo.dart';
import 'package:promptorium/data/repos/workspaces_repo.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late WorkspacesRepo workspaces;

  setUp(() {
    db = memoryDatabase();
    workspaces = WorkspacesRepo(db);
  });
  tearDown(() => db.close());

  Future<Workspace> ws([String path = '/repo/a']) =>
      workspaces.add(path: path, name: path.split('/').last);

  group('workspaces', () {
    test('CRUD, unique path and ordering', () async {
      final b = await ws('/repo/b');
      final a = await ws('/repo/a');
      expect(a.id, isNot(b.id));
      expect(a.createdAt, isNotNull);

      // Same path returns the existing row.
      final again = await ws('/repo/a');
      expect(again.id, a.id);
      expect((await workspaces.getAll()).map((w) => w.name), ['a', 'b']);

      await workspaces.rename(a.id, 'z');
      expect((await workspaces.getById(a.id))!.name, 'z');
      expect((await workspaces.getByPath('/repo/b'))!.id, b.id);

      expect(await workspaces.delete(b.id), 1);
      expect(await workspaces.getAll(), hasLength(1));
    });

    test('watchAll emits on every change', () async {
      final stream = workspaces.watchAll().map((l) => l.length);
      final expectation = expectLater(stream, emitsInOrder([0, 1, 2, 1]));
      await pumpEventQueue();
      final a = await ws('/repo/a');
      await pumpEventQueue();
      await ws('/repo/b');
      await pumpEventQueue();
      await workspaces.delete(a.id);
      await expectation;
    });

    test('deleting a workspace cascades to its data', () async {
      final w = await ws();
      final spec = await SpecsRepo(
        db,
      ).insert(workspaceId: w.id, code: 'SPEC-001', title: 't', path: 'p.md');
      await TasksRepo(db)
          .insert(workspaceId: w.id, code: 'T-1', title: 't', specId: spec.id);
      await workspaces.delete(w.id);
      expect(await db.select(db.specs).get(), isEmpty);
      expect(await db.select(db.tasks).get(), isEmpty);
    });
  });

  group('specs', () {
    test('CRUD with enum status', () async {
      final repo = SpecsRepo(db);
      final w = await ws();
      final s = await repo.insert(
        workspaceId: w.id,
        code: 'SPEC-001',
        title: 'Login',
        path: 'specs/SPEC-001-login.md',
      );
      expect(s.status, SpecStatus.draft);

      await repo.setStatus(s.id, SpecStatus.approved);
      await repo.update(s.id, const SpecsCompanion(title: Value('Login 2')));
      final got = (await repo.getByCode(w.id, 'SPEC-001'))!;
      expect(got.status, SpecStatus.approved);
      expect(got.title, 'Login 2');

      // (workspaceId, code) is unique.
      expect(
        () => repo.insert(
          workspaceId: w.id,
          code: 'SPEC-001',
          title: 'dup',
          path: 'x',
        ),
        throwsA(anything),
      );

      expect(await repo.delete(s.id), 1);
      expect(await repo.getById(s.id), isNull);
    });

    test('watchByWorkspace only sees its workspace', () async {
      final repo = SpecsRepo(db);
      final a = await ws('/a');
      final b = await ws('/b');
      // Drift re-runs the query on any change to the table: the insert into
      // workspace b emits again with the same (empty) result.
      final stream = repo
          .watchByWorkspace(a.id)
          .map((l) => l.length)
          .distinct();
      final exp = expectLater(stream, emitsInOrder([0, 1]));
      await pumpEventQueue();
      await repo.insert(workspaceId: b.id, code: 'S', title: 't', path: 'p');
      await repo.insert(workspaceId: a.id, code: 'S', title: 't', path: 'p');
      await exp;
    });
  });

  group('tasks', () {
    test('CRUD, dependsOn JSON and spec set null', () async {
      final repo = TasksRepo(db);
      final w = await ws();
      final spec = await SpecsRepo(db)
          .insert(workspaceId: w.id, code: 'SPEC-001', title: 't', path: 'p');
      final t = await repo.insert(
        workspaceId: w.id,
        specId: spec.id,
        code: 'T-002',
        title: 'Tela',
        dependsOn: ['T-001'],
      );
      expect(t.status, TaskStatus.backlog);
      expect(t.dependsOn, ['T-001']);
      expect(t.agentName, isNull);

      await repo.setStatus(t.id, TaskStatus.running);
      await repo.assignAgent(t.id, 'flutter-dev');
      await repo.update(
        t.id,
        const TasksCompanion(dependsOn: Value(['T-001', 'T-003'])),
      );
      var got = (await repo.getById(t.id))!;
      expect(got.status, TaskStatus.running);
      expect(got.agentName, 'flutter-dev');
      expect(got.dependsOn, ['T-001', 'T-003']);

      await SpecsRepo(db).delete(spec.id);
      got = (await repo.getById(t.id))!;
      expect(got.specId, isNull);

      expect(await repo.delete(t.id), 1);
    });

    test('watchBySpec emits updates', () async {
      final repo = TasksRepo(db);
      final w = await ws();
      final spec = await SpecsRepo(db)
          .insert(workspaceId: w.id, code: 'S', title: 't', path: 'p');
      final t = await repo.insert(
        workspaceId: w.id,
        specId: spec.id,
        code: 'T-1',
        title: 't',
      );
      final stream = repo.watchBySpec(spec.id).map((l) => l.single.status);
      final exp = expectLater(
        stream,
        emitsInOrder([TaskStatus.backlog, TaskStatus.review]),
      );
      await pumpEventQueue();
      await repo.setStatus(t.id, TaskStatus.review);
      await exp;
    });
  });

  group('sessions and events', () {
    test(
      'Codex identity and configuration remain separate from local id',
      () async {
        final repo = SessionsRepo(db);
        final w = await ws();
        final s = await repo.insert(
          id: 'local-session',
          workspaceId: w.id,
          worktreePath: '/w',
          branch: 'main',
          model: 'inherit',
          provider: 'codex',
          runConfig: '{"mode":"ask"}',
        );
        expect(s.externalId, isNull);
        await repo.setExternalId(s.id, 'codex-thread');
        await repo.setRunConfig(s.id, '{"mode":"edit"}');
        final stored = (await repo.getById(s.id))!;
        expect(stored.id, 'local-session');
        expect(stored.provider, 'codex');
        expect(stored.externalId, 'codex-thread');
        expect(stored.runConfig, '{"mode":"edit"}');
      },
    );

    const id = '0b0f5c1e-1a2b-4c3d-8e9f-0123456789ab';

    Future<Session> session(SessionsRepo repo, Workspace w) => repo.insert(
      id: id,
      workspaceId: w.id,
      worktreePath: '/home/x/.promptorium/worktrees/login',
      branch: 'pr/login',
      model: 'sonnet',
    );

    test('CRUD, usage and endedAt', () async {
      final repo = SessionsRepo(db);
      final w = await ws();
      final s = await session(repo, w);
      expect(s.status, SessionStatus.running);
      expect(s.costUsd, 0);
      expect(s.endedAt, isNull);

      await repo.addUsage(id, costUsd: 0.25, tokensIn: 100, tokensOut: 20);
      await repo.addUsage(id, costUsd: 0.5, tokensIn: 1, tokensOut: 2);
      await repo.setStatus(id, SessionStatus.completed);
      var got = (await repo.getById(id))!;
      expect(got.costUsd, closeTo(0.75, 1e-9));
      expect(got.tokensIn, 101);
      expect(got.tokensOut, 22);
      expect(got.status, SessionStatus.completed);
      expect(got.endedAt, isNotNull);

      await repo.setStatus(id, SessionStatus.running);
      got = (await repo.getById(id))!;
      expect(got.endedAt, isNull);

      expect(await repo.markLiveAsInterrupted(), 1);
      expect((await repo.getById(id))!.status, SessionStatus.interrupted);

      expect(await repo.delete(id), 1);
      expect(await repo.getById(id), isNull);
    });

    test('events get sequential seq, are watched and cascade', () async {
      final repo = SessionsRepo(db);
      final w = await ws();
      await session(repo, w);

      final stream = repo.watchEvents(id).map((l) => l.map((e) => e.seq));
      final exp = expectLater(
        stream,
        emitsInOrder([
          <int>[],
          [1],
          [1, 2],
        ]),
      );
      await pumpEventQueue();
      final e1 = await repo.appendEvent(id, type: 'system/init', json: '{}');
      await pumpEventQueue();
      final e2 = await repo.appendEvent(id, type: 'result', json: '{"a":1}');
      await exp;
      expect([e1.seq, e2.seq], [1, 2]);
      expect((await repo.events(id)).last.type, 'result');

      await repo.delete(id);
      expect(await db.select(db.sessionEvents).get(), isEmpty);
    });

    test('watchByWorkspace and watchById', () async {
      final repo = SessionsRepo(db);
      final w = await ws();
      final byId = expectLater(
        repo.watchById(id).map((s) => s?.status),
        emitsInOrder([null, SessionStatus.running, SessionStatus.stopped]),
      );
      final list = expectLater(
        repo.watchByWorkspace(w.id).map((l) => l.length),
        emitsInOrder([0, 1]),
      );
      await pumpEventQueue();
      await session(repo, w);
      await pumpEventQueue();
      await repo.setStatus(id, SessionStatus.stopped);
      await byId;
      await list;
    });

    test('unknown session id is rejected by the foreign key', () async {
      final repo = SessionsRepo(db);
      expect(
        () => repo.appendEvent('nope', type: 'x', json: '{}'),
        throwsA(anything),
      );
    });
  });

  group('conversations', () {
    test('CRUD, link session and watch', () async {
      final repo = ConversationsRepo(db);
      final w = await ws();
      final stream = repo
          .watchByWorkspace(w.id)
          .map((l) => l.map((c) => c.title).toList());
      final exp = expectLater(
        stream,
        emitsInOrder([
          <String>[],
          ['Primeira'],
          ['Renomeada'],
        ]),
      );
      await pumpEventQueue();
      final c = await repo.insert(
        workspaceId: w.id,
        title: 'Primeira',
        model: 'sonnet',
      );
      expect(c.provider, 'claude');
      await pumpEventQueue();
      await repo.rename(c.id, 'Renomeada');
      await exp;

      const sid = '11111111-2222-4333-8444-555555555555';
      await SessionsRepo(db).insert(
        id: sid,
        workspaceId: w.id,
        worktreePath: '/w',
        branch: 'b',
        model: 'sonnet',
      );
      await repo.linkSession(c.id, sid);
      expect((await repo.getById(c.id))!.sessionId, sid);
      await SessionsRepo(db).delete(sid);
      expect((await repo.getById(c.id))!.sessionId, isNull);

      expect(await repo.delete(c.id), 1);
    });
  });

  group('saved prompts', () {
    test('upsert keeps uses, unique command, increment, delete', () async {
      final repo = SavedPromptsRepo(db);
      final exp = expectLater(
        repo.watchAll().map((l) => l.map((p) => p.command).toList()),
        emitsInOrder([
          <String>[],
          ['testes'],
        ]),
      );
      await pumpEventQueue();
      final p = await repo.upsert(command: 'testes', body: 'Escreva testes');
      await exp;
      expect(p.uses, 0);
      expect(p.description, '');

      await repo.incrementUses('testes');
      await repo.incrementUses('testes');
      final p2 = await repo.upsert(
        command: 'testes',
        body: 'Novo corpo',
        description: 'd',
      );
      expect(p2.id, p.id);
      expect(p2.body, 'Novo corpo');
      expect(p2.uses, 2);
      expect(await db.select(db.savedPrompts).get(), hasLength(1));

      expect(await repo.delete('testes'), 1);
      expect(await repo.getByCommand('testes'), isNull);
    });
  });

  group('agent settings', () {
    test('composite key (agentName, scope) and upsert', () async {
      final repo = AgentSettingsRepo(db);
      const global = AgentSetting(
        agentName: 'planner',
        scope: AgentScope.global,
        permissionMode: 'plan',
        budgetUsd: 1.5,
        maxTurns: 10,
        mcpServers: ['github'],
      );
      await repo.upsert(global);
      await repo.upsert(
        global.copyWith(scope: AgentScope.project, maxTurns: const Value(3)),
      );
      await repo.upsert(global.copyWith(mcpServers: ['github', 'figma']));

      final g = (await repo.get('planner', AgentScope.global))!;
      expect(g.mcpServers, ['github', 'figma']);
      expect(g.budgetUsd, 1.5);
      final p = (await repo.get('planner', AgentScope.project))!;
      expect(p.maxTurns, 3);
      expect(await db.select(db.agentSettings).get(), hasLength(2));

      final exp = expectLater(
        repo.watchAll().map((l) => l.length),
        emitsInOrder([2, 1]),
      );
      await pumpEventQueue();
      expect(await repo.delete('planner', AgentScope.global), 1);
      await exp;
    });
  });

  group('mcp tool rules', () {
    test('composite key (server, tool), setRule overwrites', () async {
      final repo = McpToolRulesRepo(db);
      final exp = expectLater(
        repo.watchForServer('github').map((l) => l.map((r) => r.rule)),
        emitsInOrder([
          <McpRule>[],
          [McpRule.ask],
          [McpRule.block],
        ]),
      );
      await pumpEventQueue();
      await repo.setRule('github', 'create_pr', McpRule.ask);
      await pumpEventQueue();
      await repo.setRule('github', 'create_pr', McpRule.block);
      await exp;
      await repo.setRule('github', 'list_issues', McpRule.allow);
      await repo.setRule('figma', 'get_file', McpRule.allow);
      expect(await repo.getForServer('github'), hasLength(2));

      expect(await repo.delete('github', 'create_pr'), 1);
      expect(await repo.deleteServer('github'), 1);
      expect(await db.select(db.mcpToolRules).get(), hasLength(1));
    });
  });

  group('app settings', () {
    test('round-trip, overwrite, int helpers, remove and watch', () async {
      final repo = AppSettingsRepo(db);
      expect(await repo.get('x'), isNull);

      final exp = expectLater(
        repo.watch(AppSettingKeys.lastSection),
        emitsInOrder([null, 'specs', 'code', null]),
      );
      await pumpEventQueue();
      await repo.set(AppSettingKeys.lastSection, 'specs');
      await pumpEventQueue();
      await repo.set(AppSettingKeys.lastSection, 'code');
      await pumpEventQueue();
      await repo.remove(AppSettingKeys.lastSection);
      await exp;

      await repo.setInt(AppSettingKeys.editorZoom('specs'), 130);
      expect(await repo.getInt('editor.zoom.specs'), 130);
      expect(await repo.getAll(), {'editor.zoom.specs': '130'});
    });
  });
}
