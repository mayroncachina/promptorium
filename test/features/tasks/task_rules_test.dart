import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/tasks/task_actions.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_manager_test.dart' show permissionLine;
import '../sessions/session_test_utils.dart';

Task task(
  String code, {
  TaskStatus status = TaskStatus.backlog,
  List<String> deps = const [],
}) => Task(
  id: code.hashCode,
  workspaceId: 1,
  code: code,
  title: code,
  status: status,
  dependsOn: deps,
  createdAt: DateTime(2026),
);

String resultLine({bool success = true, double cost = 0.01}) => jsonEncode({
  'type': 'result',
  'subtype': success ? 'success' : 'error_during_execution',
  'is_error': !success,
  'total_cost_usd': cost,
  'num_turns': 1,
  'usage': {'input_tokens': 10, 'output_tokens': 5},
});

void main() {
  test('a task is blocked while any dependency is not done', () {
    final a = task('TASK-001', status: TaskStatus.done);
    final b = task('TASK-002', status: TaskStatus.review);
    final c = task('TASK-003', deps: ['TASK-001', 'TASK-002']);
    final d = task('TASK-004', deps: ['TASK-001', 'NAO-EXISTE']);
    final byCode = tasksByCode([a, b, c, d]);
    expect(blockersOf(c, byCode), ['TASK-002']);
    expect(isBlocked(c, byCode), isTrue);
    expect(isBlocked(d, byCode), isFalse); // unknown codes are ignored
    final done = tasksByCode([a, task('TASK-002', status: TaskStatus.done), c]);
    expect(isBlocked(c, done), isFalse);
  });

  test('taskStatusForSession', () {
    expect(
      taskStatusForSession(TaskStatus.backlog, SessionStatus.running),
      TaskStatus.running,
    );
    expect(
      taskStatusForSession(TaskStatus.review, SessionStatus.waitingApproval),
      TaskStatus.running,
    );
    expect(
      taskStatusForSession(
        TaskStatus.running,
        SessionStatus.completed,
        fromResult: true,
      ),
      TaskStatus.review,
    );
    // `completed` without a result (resume without message) does not move.
    expect(
      taskStatusForSession(TaskStatus.running, SessionStatus.completed),
      isNull,
    );
    expect(
      taskStatusForSession(
        TaskStatus.running,
        SessionStatus.failed,
        fromResult: true,
      ),
      isNull,
    );
    expect(
      taskStatusForSession(TaskStatus.done, SessionStatus.running),
      isNull,
    );
    expect(
      taskStatusForSession(TaskStatus.running, SessionStatus.running),
      isNull,
    );
  });

  test('session prompt carries the description and the @spec mention', () {
    final t = Task(
      id: 1,
      workspaceId: 1,
      code: 'TASK-007',
      title: 'Persistir eventos',
      status: TaskStatus.backlog,
      body: 'Gravar cada linha em session_events.',
      requirement: 'R2',
      dependsOn: const ['TASK-006'],
      createdAt: DateTime(2026),
    );
    const spec = Spec(
      id: 1,
      workspaceId: 1,
      code: 'SPEC-002',
      title: 'Sessões',
      status: SpecStatus.approved,
      path: 'specs/SPEC-002-sessoes.md',
    );
    final p = taskSessionPrompt(t, spec: spec);
    expect(p, startsWith('Implemente a tarefa TASK-007: Persistir eventos'));
    expect(p, contains('Gravar cada linha em session_events.'));
    expect(p, contains('@specs/SPEC-002-sessoes.md'));
    expect(p, contains('requisito R2'));
    expect(taskSessionTitle(t), 'TASK-007 · Persistir eventos');
  });

  group('task status follows its session', () {
    late Directory tmp;
    late String repo;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-tasks-');
      repo = await createRepo(tmp);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('running → Em execução; result success → Review; markDone → '
        'Feito and a new run does not undo it', () async {
      final db = memoryDatabase();
      final cli = FakeCli();
      final c = sessionContainer(
        sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'repo');
      final t = await c
          .read(taskActionsProvider)
          .create(workspaceId: ws.id, title: 'Shell da IDE');
      expect(t.code, 'TASK-001');
      final tasks = c.read(tasksRepoProvider);

      final id = await c
          .read(sessionManagerProvider.notifier)
          .create(
            NewSessionRequest(
              workspace: ws,
              title: taskSessionTitle(t),
              prompt: taskSessionPrompt(t),
              useWorktree: false,
              taskId: t.id,
            ),
          );
      await settle();
      expect((await c.read(sessionsRepoProvider).getById(id))!.taskId, t.id);
      expect((await tasks.getById(t.id))!.status, TaskStatus.running);

      cli.last.emit(permissionLine('req-1'));
      await settle();
      expect((await tasks.getById(t.id))!.status, TaskStatus.running);
      await c.read(sessionManagerProvider.notifier).approve(id, 'req-1');

      cli.last.emit(resultLine());
      await settle();
      expect((await tasks.getById(t.id))!.status, TaskStatus.review);

      // Another message → back to running, then a failed result keeps it.
      await c.read(sessionManagerProvider.notifier).send(id, 'Ajuste X');
      await settle();
      expect((await tasks.getById(t.id))!.status, TaskStatus.running);
      cli.last.emit(resultLine(success: false, cost: 0.02));
      await settle();
      expect((await tasks.getById(t.id))!.status, TaskStatus.running);

      await c.read(taskActionsProvider).markDone(t.id);
      await c.read(sessionManagerProvider.notifier).send(id, 'Mais um');
      await settle();
      expect((await tasks.getById(t.id))!.status, TaskStatus.done);
    });
  });
}
