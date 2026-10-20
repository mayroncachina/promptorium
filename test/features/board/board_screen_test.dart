import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/step_gate.dart';
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
  test('moveInColumn saves the move against the shown neighbour, keeping '
      'the cards hidden by a filter in place', () {
    // Column 1..5; shown (filtered / attention first): 4, 2, 5.
    expect(moveInColumn([1, 2, 3, 4, 5], 2, 4, -1), [1, 3, 2, 4, 5]);
    expect(moveInColumn([1, 2, 3, 4, 5], 2, 5, 1), [1, 3, 4, 5, 2]);
    expect(moveInColumn([1, 2, 3], 1, 9, 1), [1, 2, 3]);
  });

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

    // Clicking the card opens the side panel (UX v2, U8).
    await tester.tap(find.byKey(const ValueKey('board-open-SPEC-002')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('board-side-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('spec-detail-dialog')), findsNothing);
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
    await tester.tap(find.byKey(const ValueKey('board-side-close')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('board-side-panel')), findsNothing);
  });

  testWidgets('filters, backlog groups, attention first and segments '
      '(UX v2, U8)', (tester) async {
    await pumpBoard(tester);
    // Backlog: SPEC-003 is ready, SPEC-004 blocked by SPEC-002.
    expect(
      find.byKey(const ValueKey('board-group-Prontas · onda 2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('board-group-Bloqueadas · onda 2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('board-segments-SPEC-002')),
      findsOneWidget,
    );
    expect(
      text(tester, 'board-strip'),
      '1 em execução · onda 1 de 2 · \$0.00 hoje',
    );
    // "Precisam de mim": only SPEC-002 (R2 waits for the user).
    expect(find.text('Precisam de mim · 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-filter-attention')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('board-card-SPEC-002')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-card-SPEC-003')), findsNothing);
    expect(find.byKey(const ValueKey('board-card-SPEC-001')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('board-filter-attention')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('board-card-SPEC-003')), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('a step refused by the gate shows its checks on the card and '
      'in the details, with the output and the gate actions', (tester) async {
    final (c, db) = await pumpBoard(tester);
    final report = GateReport(
      at: DateTime(2026, 10, 17, 9, 30),
      attempt: 1,
      checks: const [
        GateCheck(name: 'commit', ok: true),
        GateCheck(
          name: 'arvore',
          ok: false,
          output: 'Arquivos sem commit:\n?? sobrou.txt',
        ),
      ],
    );
    await c.read(specStepsRepoProvider).setGate(2, [
      'R2',
    ], report: report.encode());
    await pumpFor(tester);
    expect(text(tester, 'board-meta-SPEC-002'), 'R2 · verificação falhou');
    expect(
      find.byKey(const ValueKey('board-gate-SPEC-002-arvore')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('board-gate-SPEC-002-arvore')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('gate-report-dialog')), findsOneWidget);
    expect(find.textContaining('sobrou.txt'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await pumpFor(tester);

    await tester.tap(find.byKey(const ValueKey('board-open-SPEC-002')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('step-gate-R2-commit')), findsOneWidget);
    expect(find.byKey(const ValueKey('steps-recheck')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('steps-commit-leftovers')),
      findsOneWidget,
    );
    expect(db, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Board shorter than its columns scrolls vertically to the '
      'last spec', (tester) async {
    await pumpBoard(tester);
    tester.view.physicalSize = const Size(1440, 300);
    await pumpFor(tester);
    expect(tester.takeException(), isNull);
    final scroll = find.byKey(const ValueKey('board-vertical-scroll'));
    expect(scroll, findsOneWidget);
    final pos = tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(pos.maxScrollExtent, greaterThan(0));
    pos.jumpTo(pos.maxScrollExtent);
    await pumpFor(tester, 2);
    final bottom = tester.getBottomLeft(
      find.byKey(const ValueKey('board-column-done')),
    );
    expect(bottom.dy, lessThanOrEqualTo(300));
  });

  testWidgets('a Board that fits shows no scroll bar and keeps its layout', (
    tester,
  ) async {
    await pumpBoard(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('board-vertical-scroll')), findsNothing);
    expect(find.byType(Scrollbar), findsNothing);
    final column = find.byKey(const ValueKey('board-column-done'));
    final columnScrollable = find.descendant(
      of: column,
      matching: find.byType(Scrollable),
    );
    expect(
      tester
          .state<ScrollableState>(columnScrollable.first)
          .position
          .maxScrollExtent,
      0,
    );
    // The Board fills the visible area exactly, as before.
    final box = tester.getRect(
      find.ancestor(of: column, matching: find.byType(SizedBox)).first,
    );
    expect(box.top, greaterThanOrEqualTo(0));
    expect(box.bottom, lessThanOrEqualTo(900));
  });

  testWidgets('Grafo view scrolls vertically to the last row of a tall wave '
      'and keeps scrolling horizontally', (tester) async {
    final (_, db) = await pumpBoard(tester);
    {
      for (var i = 0; i < 10; i++) {
        await db
            .into(db.specs)
            .insert(
              SpecsCompanion.insert(
                workspaceId: 1,
                code: 'SPEC-1${i.toString().padLeft(2, '0')}',
                title: 'Extra $i',
                path: 'specs/extra$i.md',
                dependsOn: const Value(['SPEC-004']),
                status: const Value(SpecStatus.approved),
              ),
            );
      }
    }
    for (final (code, dep) in [
      ('SPEC-200', 'SPEC-100'),
      ('SPEC-201', 'SPEC-200'),
    ]) {
      await db
          .into(db.specs)
          .insert(
            SpecsCompanion.insert(
              workspaceId: 1,
              code: code,
              title: code,
              path: 'specs/$code.md',
              dependsOn: Value([dep]),
              status: const Value(SpecStatus.approved),
            ),
          );
    }
    await tester.tap(find.byKey(const ValueKey('board-view-graph')));
    await pumpFor(tester, 20);
    tester.view.physicalSize = const Size(1440, 500);
    await pumpFor(tester);
    expect(tester.takeException(), isNull);
    final scrollables = find.descendant(
      of: find.byKey(const ValueKey('board-graph')),
      matching: find.byType(Scrollable),
    );
    final horizontal = tester
        .state<ScrollableState>(scrollables.first)
        .position;
    final vertical = tester.state<ScrollableState>(scrollables.at(1)).position;
    expect(horizontal.axis, Axis.horizontal);
    expect(vertical.axis, Axis.vertical);
    expect(vertical.maxScrollExtent, greaterThan(0));
    vertical.jumpTo(vertical.maxScrollExtent);
    await pumpFor(tester, 2);
    expect(find.text('Extra 9'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Extra 9')).dy,
      lessThanOrEqualTo(500),
    );
    expect(horizontal.maxScrollExtent, greaterThan(0));
    horizontal.jumpTo(horizontal.maxScrollExtent);
    await pumpFor(tester, 2);
    expect(horizontal.pixels, horizontal.maxScrollExtent);
    expect(vertical.pixels, vertical.maxScrollExtent);
  });

  testWidgets('the mouse wheel over a spec card scrolls the Board', (
    tester,
  ) async {
    await pumpBoard(tester);
    tester.view.physicalSize = const Size(1440, 300);
    await pumpFor(tester);
    final scroll = find.byKey(const ValueKey('board-vertical-scroll'));
    final pos = tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(pos.pixels, 0);
    final card = find.byType(SpecCard).first;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(card)));
    // The column under the card takes the wheel until its end, then the
    // gesture reaches the Board.
    for (var i = 0; i < 3; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    }
    await pumpFor(tester, 2);
    expect(pos.pixels, greaterThan(0));
  });

  testWidgets('a column with more cards than fit scrolls alone', (
    tester,
  ) async {
    final (_, db) = await pumpBoard(tester);
    for (final stage in [SpecStage.backlog, SpecStage.running]) {
      for (var i = 0; i < 12; i++) {
        await db
            .into(db.specs)
            .insert(
              SpecsCompanion.insert(
                workspaceId: 1,
                code: 'SPEC-${stage.name}-$i',
                title: 'Col ${stage.name} $i',
                path: 'specs/${stage.name}$i.md',
                stage: Value(stage),
                status: const Value(SpecStatus.approved),
              ),
            );
      }
    }
    await pumpFor(tester, 20);
    ScrollPosition columnPos(String stage) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(ValueKey('board-column-$stage')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    final backlog = columnPos('backlog');
    final running = columnPos('running');
    final done = columnPos('done');
    expect(backlog.maxScrollExtent, greaterThan(0));
    expect(running.maxScrollExtent, greaterThan(0));
    final card = find.descendant(
      of: find.byKey(const ValueKey('board-column-backlog')),
      matching: find.byType(SpecCard),
    );
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(card.first)),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await pumpFor(tester, 2);
    expect(backlog.pixels, greaterThan(0));
    expect(running.pixels, 0);
    expect(done.pixels, 0);
  });

  testWidgets('dragging a card still changes its stage while the Board '
      'scrolls vertically', (tester) async {
    final (c, _) = await pumpBoard(tester);
    tester.view.physicalSize = const Size(1440, 300);
    await pumpFor(tester);
    expect(
      find.byKey(const ValueKey('board-vertical-scroll')),
      findsOneWidget,
    );
    final card = find.byKey(const ValueKey('board-card-SPEC-003'));
    await tester.ensureVisible(card);
    await pumpFor(tester);
    await tester.drag(card, const Offset(700, 0));
    await pumpFor(tester);
    final moved = await c.read(specsRepoProvider).getByCode(1, 'SPEC-003');
    expect(moved!.stage, isNot(SpecStage.backlog));
    expect(tester.takeException(), isNull);
  });
}
