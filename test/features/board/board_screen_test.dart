import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<(ProviderContainer, AppDatabase)> pumpBoard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
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
  Future<Spec> spec(
    String code,
    String title, {
    SpecStage stage = SpecStage.backlog,
    SpecStatus status = SpecStatus.approved,
    int steps = 3,
    List<String> deps = const [],
  }) => db
      .into(db.specs)
      .insertReturning(
        SpecsCompanion.insert(
          workspaceId: ws.id,
          code: code,
          title: title,
          path: 'specs/$code.md',
          status: Value(status),
          stage: Value(stage),
          requirements: Value([
            for (var i = 1; i <= steps; i++) (id: 'R$i', text: 'Req $i'),
          ]),
          dependsOn: Value(deps),
        ),
      );
  final a = await spec('SPEC-001', 'Base', stage: SpecStage.done);
  final b = await spec('SPEC-002', 'Sessões', stage: SpecStage.running);
  await spec('SPEC-003', 'Agentes', deps: ['SPEC-001']);
  await spec('SPEC-004', 'Review', deps: ['SPEC-002']);
  await spec('SPEC-005', 'Rascunho', status: SpecStatus.draft);
  for (final s in ['R1', 'R2', 'R3']) {
    await db
        .into(db.specSteps)
        .insert(
          SpecStepsCompanion.insert(
            specId: a.id,
            step: s,
            status: const Value(StepStatus.done),
          ),
        );
  }
  await db
      .into(db.specSteps)
      .insert(
        SpecStepsCompanion.insert(
          specId: b.id,
          step: 'R1',
          status: const Value(StepStatus.done),
        ),
      );
  await db
      .into(db.specSteps)
      .insert(
        SpecStepsCompanion.insert(
          specId: b.id,
          step: 'R2',
          status: const Value(StepStatus.needsInput),
          sessionId: const Value('s-old'),
        ),
      );
  final c = ProviderContainer(overrides: [databaseOverride(db)]);
  addTearDown(c.dispose);
  await c.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: BoardScreen()),
      ),
    ),
  );
  await pumpFor(tester);
  return (c, db);
}

String text(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  testWidgets('one card per approved spec, in its column, with progress, '
      'blockers and the right action', (tester) async {
    await pumpBoard(tester);
    expect(text(tester, 'board-total'), '4'); // the draft stays out
    expect(find.byKey(const ValueKey('board-card-SPEC-005')), findsNothing);
    expect(text(tester, 'board-column-count-backlog'), '2');
    expect(text(tester, 'board-column-count-running'), '1');
    expect(text(tester, 'board-column-count-review'), '0');
    expect(text(tester, 'board-column-count-done'), '1');

    expect(text(tester, 'board-progress-SPEC-001'), '3/3');
    expect(text(tester, 'board-progress-SPEC-002'), '1/3');
    expect(text(tester, 'board-meta-SPEC-002'), 'R2 aguardando você');
    expect(find.byKey(const ValueKey('board-answer-SPEC-002')), findsOneWidget);

    // SPEC-003 depends on a finished spec; SPEC-004 on one still running.
    expect(text(tester, 'board-meta-SPEC-003'), 'pronta');
    expect(find.byKey(const ValueKey('board-run-SPEC-003')), findsOneWidget);
    expect(text(tester, 'board-meta-SPEC-004'), 'bloqueada por SPEC-002');
    expect(find.byKey(const ValueKey('board-run-SPEC-004')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card menu moves the card; details list the steps and '
      'let the user mark one', (tester) async {
    final (c, _) = await pumpBoard(tester);
    await tester.tap(find.byKey(const ValueKey('board-menu-SPEC-003')));
    await pumpFor(tester, 20);
    await tester.tap(find.text('Mover para Review'));
    await pumpFor(tester);
    expect(text(tester, 'board-column-count-review'), '1');
    expect(text(tester, 'board-meta-SPEC-003'), 'pronta para review');
    // Moved by hand with steps left: it can still run.
    expect(find.byKey(const ValueKey('board-run-SPEC-003')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('board-open-SPEC-002')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('spec-detail-dialog')), findsOneWidget);
    expect(text(tester, 'steps-progress'), '1/3 etapas');
    expect(text(tester, 'step-status-R1'), 'concluída');
    expect(text(tester, 'step-status-R2'), 'aguardando você');
    expect(text(tester, 'step-status-R3'), 'pendente');
    await tester.tap(find.byKey(const ValueKey('step-menu-R2')));
    await pumpFor(tester, 20);
    await tester.tap(find.text('Marcar como concluída'));
    await pumpFor(tester);
    expect(text(tester, 'steps-progress'), '2/3 etapas');

    await tester.tap(find.byKey(const ValueKey('steps-auto-advance')));
    await pumpFor(tester);
    final spec = await c.read(specsRepoProvider).getByCode(1, 'SPEC-002');
    expect(spec!.autoAdvance, isFalse);
  });

  testWidgets('dragging a card changes its stage; old tasks show a banner', (
    tester,
  ) async {
    final (c, db) = await pumpBoard(tester);
    expect(find.byKey(const ValueKey('board-legacy')), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('board-card-SPEC-003')),
      const Offset(700, 0),
    );
    await pumpFor(tester);
    final moved = await c.read(specsRepoProvider).getByCode(1, 'SPEC-003');
    expect(moved!.stage, isNot(SpecStage.backlog));

    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(workspaceId: 1, code: 'TASK-9', title: 'x'),
        );
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('board-legacy')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-legacy-open')));
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('legacy-drop-TASK-9')));
    await pumpFor(tester);
    expect(await db.select(db.tasks).get(), isEmpty);
  });
}
