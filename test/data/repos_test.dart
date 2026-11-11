import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/agent_settings_repo.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/data/repos/conversations_repo.dart';
import 'package:promptorium/data/repos/mcp_tool_rules_repo.dart';
import 'package:promptorium/data/repos/review_comments_repo.dart';
import 'package:promptorium/data/repos/saved_prompts_repo.dart';
import 'package:promptorium/data/repos/sessions_repo.dart';
import 'package:promptorium/data/repos/spec_steps_repo.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/data/repos/step_runs_repo.dart';
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

    test('archive and unarchive keep the row (SPEC-056)', () async {
      final repo = ConversationsRepo(db);
      final w = await ws();
      final c = await repo.insert(
        workspaceId: w.id,
        title: 'Plano: cupom',
        model: 'sonnet',
      );
      final at = DateTime(2026, 11, 3, 10);
      await repo.archive(c.id, at: at);
      expect((await repo.getById(c.id))!.archivedAt, at);
      // Still listed by the workspace: the split is ConversationLists'.
      expect(await repo.watchByWorkspace(w.id).first, hasLength(1));
      await repo.unarchive(c.id);
      expect((await repo.getById(c.id))!.archivedAt, isNull);
      await repo.rename(c.id, 'Cupom 10%');
      expect((await repo.getById(c.id))!.title, 'Cupom 10%');
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

  group('spec criteria in batch (SPEC-018)', () {
    Future<Spec> spec(AppDatabase d) async => SpecsRepo(d).insert(
      workspaceId: (await WorkspacesRepo(d).add(path: '/r', name: 'r')).id,
      code: 'SPEC-001',
      title: 'A',
      path: 'specs/SPEC-001.md',
    );

    Future<Map<String, (bool, String?)>> marks(
      ReviewCommentsRepo r,
      int id,
    ) async => {
      for (final m in await r.criteria(id))
        m.criterion: (m.checked, m.checkedBy),
    };

    test('setCriteria is all or none: a failed second insert rolls back '
        'the first', () async {
      final failing = _FailSecondInsert();
      final d = AppDatabase(NativeDatabase.memory().interceptWith(failing));
      addTearDown(d.close);
      final s = await spec(d);
      final r = ReviewCommentsRepo(d);
      failing.armed = true;
      await expectLater(
        r.setCriteria(s.id, ['a', 'b', 'c'], checked: true, by: 'humano'),
        throwsA(isA<StateError>()),
      );
      failing.armed = false;
      expect(await r.criteria(s.id), isEmpty);
    });

    test('setCriteria reads the marks again: what the gate checked '
        'meanwhile is kept, the returned list is what changed', () async {
      final s = await spec(db);
      final r = ReviewCommentsRepo(db);
      await r.setCriterion(s.id, 'b', checked: true, by: 'gate');
      expect(
        await r.setCriteria(s.id, ['a', 'b'], checked: true, by: 'humano'),
        ['a'],
      );
      expect(await marks(r, s.id), {
        'a': (true, 'humano'),
        'b': (true, 'gate'),
      });
      expect(
        await r.setCriteria(s.id, ['a', 'b'], checked: true, by: 'humano'),
        isEmpty,
      );
    });

    test(
      'uncheckHumanOnly only unchecks the marks still by the user',
      () async {
        final s = await spec(db);
        final r = ReviewCommentsRepo(db);
        await r.setCriteria(s.id, ['a', 'b', 'c'], checked: true, by: 'humano');
        await r.setCriterion(s.id, 'b', checked: true, by: 'gate');
        await r.setCriterion(s.id, 'd', checked: true, by: 'revisor');
        expect(await r.uncheckHumanOnly(s.id, ['a', 'b', 'c', 'd', 'e']), [
          'a',
          'c',
        ]);
        expect(await marks(r, s.id), {
          'a': (false, null),
          'b': (true, 'gate'),
          'c': (false, null),
          'd': (true, 'revisor'),
        });
      },
    );
  });

  group('orchestrator plan and step runs (SPEC-035)', () {
    Future<Spec> spec() async => SpecsRepo(db).insert(
      workspaceId: (await ws()).id,
      code: 'SPEC-035',
      title: 'Orquestrador',
      path: 'specs/SPEC-035.md',
    );

    test('setPlan keeps the status; escalations count and reset', () async {
      final s = await spec();
      final repo = SpecStepsRepo(db);
      await repo.set(s.id, 'R1', StepStatus.running, sessionId: 's1');
      await repo.setPlan(
        s.id,
        'R1',
        kind: 'mecanica',
        model: 'haiku',
        effort: 'low',
        hash: 'h1',
        reason: 'troca de nomes',
      );
      // A step without a row gets one.
      await repo.setPlan(
        s.id,
        'R2',
        kind: 'altoRisco',
        model: 'opus',
        effort: 'high',
        userPicked: true,
      );
      final r1 = (await repo.byStep(s.id, 'R1'))!;
      expect(r1.status, StepStatus.running);
      expect(r1.sessionId, 's1');
      expect(
        (r1.kind, r1.planModel, r1.planEffort, r1.planHash, r1.userPicked),
        ('mecanica', 'haiku', 'low', 'h1', false),
      );
      expect(r1.planReason, 'troca de nomes');
      expect(r1.escalations, 0);
      final r2 = (await repo.byStep(s.id, 'R2'))!;
      expect(
        (r2.status, r2.planModel, r2.userPicked),
        (StepStatus.pending, 'opus', true),
      );

      expect(await repo.incrementEscalations(s.id, 'R1'), 1);
      expect(await repo.incrementEscalations(s.id, 'R1'), 2);
      expect((await repo.byStep(s.id, 'R1'))!.escalations, 2);
      // The escalated model is not the plan's (R13).
      expect((await repo.byStep(s.id, 'R1'))!.planModel, 'haiku');
      await repo.resetEscalations(s.id, ['R1']);
      expect((await repo.byStep(s.id, 'R1'))!.escalations, 0);

      await repo.clearPlan(s.id, ['R1']);
      final cleared = (await repo.byStep(s.id, 'R1'))!;
      expect(
        (cleared.kind, cleared.planModel, cleared.status),
        (null, null, StepStatus.running),
      );
      expect(await repo.byStep(s.id, 'R9'), isNull);
    });

    test('step runs are read by period, oldest first', () async {
      final s = await spec();
      final repo = StepRunsRepo(db);
      final now = DateTime(2026, 11, 4, 12);
      await repo.add(
        specId: s.id,
        step: 'R1',
        kind: 'mecanica',
        model: 'haiku',
        effort: 'low',
        sessionId: 's1',
        result: StepRunResult.escalated,
        costUsd: 0.12,
        at: now.subtract(const Duration(days: 40)),
      );
      await repo.add(
        specId: s.id,
        step: 'R1',
        kind: 'mecanica',
        model: 'sonnet',
        effort: 'medium',
        result: StepRunResult.passed,
        at: now.subtract(const Duration(days: 2)),
      );
      await repo.add(
        specId: s.id,
        step: 'R2',
        kind: null,
        model: 'opus',
        result: StepRunResult.failed,
        at: now,
      );
      final last30 = await repo.between(now.subtract(const Duration(days: 30)));
      expect(last30.map((r) => (r.step, r.model, r.result)), [
        ('R1', 'sonnet', StepRunResult.passed),
        ('R2', 'opus', StepRunResult.failed),
      ]);
      expect(last30.first.costUsd, isNull);
      final before = await repo.between(
        now.subtract(const Duration(days: 90)),
        now,
      );
      expect(before.map((r) => r.model), ['haiku', 'sonnet']);
      expect(before.first.costUsd, 0.12);
      expect(await repo.bySpec(s.id), hasLength(3));

      // Deleting the spec takes its runs.
      await SpecsRepo(db).delete(s.id);
      expect(await repo.bySpec(s.id), isEmpty);
    });
  });
}

/// Fails the second insert into `spec_criteria` while [armed].
class _FailSecondInsert extends QueryInterceptor {
  bool armed = false;
  int _inserts = 0;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (armed && statement.contains('spec_criteria') && ++_inserts == 2) {
      throw StateError('falha de teste');
    }
    return executor.runInsert(statement, args);
  }
}
