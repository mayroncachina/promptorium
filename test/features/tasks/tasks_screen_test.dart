import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/tasks_repo.dart';
import 'package:promptorium/features/tasks/tasks_screen.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<AppDatabase> pumpBoard(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final ws = await db
      .into(db.workspaces)
      .insertReturning(
        WorkspacesCompanion.insert(path: '/work/repo', name: 'repo'),
      );
  await db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: AppSettingKeys.activeWorkspace,
          value: '${ws.id}',
        ),
      );
  final spec2 = await db
      .into(db.specs)
      .insertReturning(
        SpecsCompanion.insert(
          workspaceId: ws.id,
          code: 'SPEC-002',
          title: 'Sessões',
          path: 'specs/SPEC-002-sessoes.md',
        ),
      );
  final spec3 = await db
      .into(db.specs)
      .insertReturning(
        SpecsCompanion.insert(
          workspaceId: ws.id,
          code: 'SPEC-003',
          title: 'Agentes',
          path: 'specs/SPEC-003-agentes.md',
        ),
      );
  final repo = TasksRepo(db);
  Future<Task> add(
    String code,
    String title,
    TaskStatus status, {
    int? spec,
    List<String> deps = const [],
    String agent = 'implementer',
  }) => repo.insert(
    workspaceId: ws.id,
    code: code,
    title: title,
    status: status,
    specId: spec,
    dependsOn: deps,
    agentName: agent,
  );
  await add(
    'TASK-020',
    'GitService: worktrees',
    TaskStatus.done,
    spec: spec2.id,
  );
  await add(
    'TASK-021',
    'ClaudeProcess: parser stream-json com um título bem longo que precisa '
        'de reticências para caber no card do kanban',
    TaskStatus.running,
    spec: spec2.id,
    deps: ['TASK-020'],
  );
  await add(
    'TASK-022',
    'Persistir eventos com drift',
    TaskStatus.backlog,
    spec: spec2.id,
    deps: ['TASK-021'],
  );
  await add(
    'TASK-024',
    'Fila de aprovações na UI',
    TaskStatus.backlog,
    spec: spec2.id,
    deps: ['TASK-020'],
  );
  await add(
    'TASK-030',
    'Formulário do editor de agentes',
    TaskStatus.backlog,
    spec: spec3.id,
    agent: 'tester',
  );
  for (var i = 0; i < 8; i++) {
    await add('TASK-${100 + i}', 'Tarefa de review $i', TaskStatus.review);
  }
  await db
      .into(db.sessions)
      .insert(
        SessionsCompanion.insert(
          id: 'sess-021',
          workspaceId: ws.id,
          taskId: const Value(2),
          worktreePath: '/work/wt',
          branch: 'pr/x',
          model: 'sonnet',
          status: const Value(SessionStatus.waitingApproval),
        ),
      );
  final container = ProviderContainer(
    overrides: sessionOverrides(
      db: db,
      cli: FakeCli(),
      notifier: FakeNotifier(),
    ),
  );
  await container.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: TasksScreen()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(Duration.zero);
  });
  await pumpFor(tester);
  return db;
}

Finder card(String code) => find.byKey(ValueKey('task-card-$code'));

Finder inColumn(TaskStatus s, Finder f) => find.descendant(
  of: find.byKey(ValueKey('task-column-${s.name}')),
  matching: f,
);

void main() {
  testWidgets('columns, blocked cards and "Executar com agente"', (
    tester,
  ) async {
    await pumpBoard(tester);
    expect(inColumn(TaskStatus.backlog, card('TASK-022')), findsOneWidget);
    expect(inColumn(TaskStatus.running, card('TASK-021')), findsOneWidget);
    expect(inColumn(TaskStatus.done, card('TASK-020')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('task-column-count-review')))
          .data,
      '8',
    );
    // TASK-022 depends on TASK-021 (running): blocked, no run button.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('task-meta-TASK-022')))
          .data,
      'bloqueada por TASK-021',
    );
    expect(find.byKey(const ValueKey('task-run-TASK-022')), findsNothing);
    // TASK-024 depends on a done task: ready.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('task-meta-TASK-024')))
          .data,
      'pronta',
    );
    expect(find.byKey(const ValueKey('task-run-TASK-024')), findsOneWidget);
    // Running task with a session waiting approval (process not alive here).
    expect(find.byKey(const ValueKey('task-meta-TASK-021')), findsOneWidget);
    expect(find.text('SPEC-002'), findsWidgets);
  });

  testWidgets('kanban fits the minimum window (1100×700) without overflow', (
    tester,
  ) async {
    // The shell sidebar takes 56px; title bar + footer ≈ 72px.
    await pumpBoard(tester, size: const Size(1044, 628));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('tasks-filter-spec')));
    await pumpFor(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a card to another column changes its status', (
    tester,
  ) async {
    final db = await pumpBoard(tester);
    final target = find.byKey(const ValueKey('task-column-review'));
    final from = tester.getCenter(card('TASK-030'));
    final to = tester.getCenter(target);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await pumpFor(tester);
    final t = await (db.select(
      db.tasks,
    )..where((t) => t.code.equals('TASK-030'))).getSingle();
    expect(t.status, TaskStatus.review);
    expect(inColumn(TaskStatus.review, card('TASK-030')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('task-column-count-review')))
          .data,
      '9',
    );
  });

  testWidgets('filters by spec and agent', (tester) async {
    await pumpBoard(tester);
    Future<void> pick(String key, String item) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await pumpFor(tester, 25); // popup animation
      await tester.tap(find.text(item).last);
      await pumpFor(tester, 25);
    }

    await pick('tasks-filter-spec', 'SPEC-003 · Agentes');
    expect(card('TASK-030'), findsOneWidget);
    expect(card('TASK-022'), findsNothing);
    expect(card('TASK-100'), findsNothing);

    await pick('tasks-filter-spec', 'todas');
    expect(card('TASK-100'), findsOneWidget);
    await pick('tasks-filter-agent', 'tester');
    expect(card('TASK-030'), findsOneWidget);
    expect(card('TASK-024'), findsNothing);
  });
}
