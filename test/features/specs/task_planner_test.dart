import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/providers/claude_code_provider.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/tasks_repo.dart';
import 'package:promptorium/features/specs/task_planner.dart';
import 'package:promptorium/features/tasks/task_rules.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

/// Real `result` line of a `--json-schema` run (CLI 2.1.300, haiku,
/// US$ 0.0055 — plano, Fase 8).
String fixtureResultLine() =>
    File('test/fixtures/planner-result.json').readAsStringSync().trim();

Result fixtureResult() =>
    ClaudeEvent.fromJson(jsonDecode(fixtureResultLine())) as Result;

void main() {
  test('real fixture: structured_output carries the task list', () {
    final r = fixtureResult();
    expect(r.isSuccess, isTrue);
    expect(r.json['structured_output'], isA<Map<String, dynamic>>());
    // The same JSON also arrives as a string in `result`.
    expect(jsonDecode(r.result!), r.json['structured_output']);
    final tasks = parsePlannerResult(r);
    expect(tasks, hasLength(7));
    expect(tasks.first.code, 'T1');
    expect(tasks.first.requirement, 'R1');
    expect(tasks[2].dependsOn, ['T1', 'T2']);
  });

  test('falls back to `result` text; errors are reported', () {
    final j = jsonDecode(fixtureResultLine()) as Map<String, dynamic>
      ..remove('structured_output');
    expect(parsePlannerResult(ClaudeEvent.fromJson(j) as Result), hasLength(7));
    expect(
      () => parsePlannerResult(
        ClaudeEvent.fromJson({
          'type': 'result',
          'subtype': 'error_max_budget_usd',
          'is_error': true,
        }) as Result,
      ),
      throwsA(isA<PlannerException>()),
    );
    expect(
      () => parsePlannerResult(
        ClaudeEvent.fromJson({
          'type': 'result',
          'subtype': 'success',
          'result': 'sem json',
        }) as Result,
      ),
      throwsA(isA<PlannerException>()),
    );
  });

  test('saves TASK-NNN with translated dependencies (sequential per '
      'workspace)', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final ws = await db
        .into(db.workspaces)
        .insertReturning(WorkspacesCompanion.insert(path: '/r', name: 'r'));
    final repo = TasksRepo(db);
    await repo.insert(workspaceId: ws.id, code: 'T-004', title: 'antiga');

    final saved = await savePlannedTasks(
      repo,
      workspaceId: ws.id,
      specId: null,
      planned: parsePlannerResult(fixtureResult()),
      existingCodes: {'T-004'},
    );
    expect(saved.map((t) => t.code), [
      for (var i = 5; i <= 11; i++) 'TASK-${i.toString().padLeft(3, '0')}',
    ]);
    final byCode = tasksByCode(saved);
    expect(byCode['TASK-005']!.dependsOn, isEmpty);
    expect(byCode['TASK-007']!.dependsOn, ['TASK-005', 'TASK-006']);
    expect(byCode['TASK-009']!.dependsOn, ['TASK-005', 'TASK-008']);
    expect(byCode['TASK-011']!.dependsOn, ['TASK-009']);
    expect(byCode['TASK-005']!.requirement, 'R1');
    expect(byCode['TASK-011']!.requirement, 'R3');
    expect(byCode['TASK-005']!.body, contains('counter.txt'));
    expect(saved.every((t) => t.status == TaskStatus.backlog), isTrue);

    // Unknown / self references are dropped; existing codes are kept.
    final more = await savePlannedTasks(
      repo,
      workspaceId: ws.id,
      specId: null,
      planned: const [
        PlannedTask(code: 'A', title: 'a', dependsOn: ['A', 'T-004', 'X9']),
        PlannedTask(title: 'b', dependsOn: ['1']),
      ],
      existingCodes: {'T-004'},
    );
    expect(more.map((t) => t.code), ['TASK-012', 'TASK-013']);
    expect(more[0].dependsOn, ['T-004']);
    expect(more[1].dependsOn, ['TASK-012']);
  });

  test('generate: read-only claude -p with --json-schema, denies '
      'permissions, stores the tasks and stops the process', () async {
    final db = memoryDatabase();
    final cli = FakeCli();
    final c = sessionContainer(
      sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: '/r', name: 'r');
    final spec = await c
        .read(specsRepoProvider)
        .insert(
          workspaceId: ws.id,
          code: 'SPEC-001',
          title: 'Contador',
          path: 'specs/SPEC-001-contador.md',
        );

    final future = c
        .read(taskPlannerProvider)
        .generate(workspace: ws, spec: spec);
    await settle();
    final args = cli.args.single;
    expect(cli.cwds.single, '/r');
    expect(args, containsAllInOrder(['--permission-mode', 'default']));
    expect(args, containsAllInOrder(['--max-budget-usd', '0.5']));
    expect(args, isNot(contains('--include-partial-messages')));
    final schema = args[args.indexOf('--json-schema') + 1];
    expect(jsonDecode(schema), plannerTaskSchema);
    final disallowed = args.sublist(args.indexOf('--disallowedTools') + 1);
    expect(disallowed, ClaudeCodeProvider.readOnlyDisallowedTools);
    expect(args, isNot(contains('bypassPermissions')));
    final sent = cli.last.writtenJson.single['message']['content'] as String;
    expect(sent, contains('@specs/SPEC-001-contador.md'));

    cli.last.emit(
      jsonEncode({
        'type': 'control_request',
        'request_id': 'req-9',
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': 'Write',
          'input': {'file_path': '/r/x'},
          'tool_use_id': 'toolu_9',
        },
      }),
    );
    await settle();
    final deny = cli.last.writtenJson.last;
    expect(deny['type'], 'control_response');
    expect(deny['response']['response']['behavior'], 'deny');

    cli.last.emit(fixtureResultLine());
    final out = await future;
    expect(out.tasks, hasLength(7));
    expect(out.costUsd, closeTo(0.0054766, 1e-6));
    expect(out.tasks.every((t) => t.specId == spec.id), isTrue);
    expect(cli.last.signals, isNotEmpty); // stopped after the result
    final stored = await c.read(tasksRepoProvider).watchBySpec(spec.id).first;
    expect(stored.map((t) => t.code).first, 'TASK-001');
  });

  test('generate fails clearly when the CLI exits without a result', () async {
    final db = memoryDatabase();
    final cli = FakeCli();
    final c = sessionContainer(
      sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: '/r', name: 'r');
    final spec = await c
        .read(specsRepoProvider)
        .insert(workspaceId: ws.id, code: 'SPEC-001', title: 't', path: 'p');
    final future = c
        .read(taskPlannerProvider)
        .generate(workspace: ws, spec: spec);
    await settle();
    await cli.last.finish(1);
    await expectLater(future, throwsA(isA<PlannerException>()));
    expect(await c.read(tasksRepoProvider).watchBySpec(spec.id).first, isEmpty);
  });
}
