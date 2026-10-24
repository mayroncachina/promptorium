import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';

import 'canvas_fixture.dart';

/// "Ocultar concluídas" in Colunas and Canvas (SPEC-019 R1–R7).
void main() {
  String chipText(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: byKey('board-filter-hide-done'),
          matching: find.byType(Text),
        ),
      )
      .data!;

  String strip(WidgetTester tester) =>
      tester.widget<Text>(byKey('board-strip')).data!;

  Future<void> showColumns(WidgetTester tester) async {
    await tester.tap(byKey('board-view-columns'));
    await pumpFor(tester, 20);
  }

  Future<void> showCanvas(WidgetTester tester) async {
    await tester.tap(byKey('board-view-graph'));
    await pumpFor(tester, 20);
  }

  IconData? canvasIcon(WidgetTester tester) => tester
      .widget<Icon>(
        find.descendant(
          of: byKey('canvas-hide-done'),
          matching: find.byType(Icon),
        ),
      )
      .icon;

  testWidgets('hiding concluded specs removes them from Canvas and Colunas; '
      'the chip counts them and the canvas button follows (R1, R2, R5, R7)', (
    tester,
  ) async {
    await pumpCanvas(tester, const [
      CanvasSpec('SPEC-001', stage: SpecStage.done),
      CanvasSpec('SPEC-002', deps: ['SPEC-001']),
      CanvasSpec('SPEC-003', stage: SpecStage.done),
    ]);
    final waves = strip(tester);
    expect(byKey('board-open-SPEC-001'), findsOneWidget);
    expect(chipText(tester), 'Ocultar concluídas');
    expect(canvasIcon(tester), Icons.visibility_outlined);

    await tester.tap(byKey('board-filter-hide-done'));
    await pumpFor(tester, 20);
    expect(byKey('board-open-SPEC-001'), findsNothing);
    expect(byKey('board-open-SPEC-003'), findsNothing);
    expect(byKey('board-open-SPEC-002'), findsOneWidget);
    expect(chipText(tester), 'Ocultar concluídas · 2');
    expect(canvasIcon(tester), Icons.visibility_off_outlined);
    // The header waves still count every card.
    expect(strip(tester), waves);

    await showColumns(tester);
    expect(byKey('board-card-SPEC-001'), findsNothing);
    expect(byKey('board-card-SPEC-003'), findsNothing);
    expect(byKey('board-card-SPEC-002'), findsOneWidget);

    await tester.tap(byKey('board-filter-hide-done'));
    await pumpFor(tester, 20);
    expect(byKey('board-card-SPEC-001'), findsOneWidget);
    expect(byKey('board-card-SPEC-003'), findsOneWidget);
    expect(chipText(tester), 'Ocultar concluídas');

    // The canvas button toggles the same state as the chip.
    await showCanvas(tester);
    expect(byKey('board-open-SPEC-001'), findsOneWidget);
    await tester.tap(byKey('canvas-hide-done'));
    await pumpFor(tester, 20);
    expect(byKey('board-open-SPEC-001'), findsNothing);
    expect(chipText(tester), 'Ocultar concluídas · 2');
    await tester.tap(byKey('canvas-hide-done'));
    await pumpFor(tester, 20);
    expect(byKey('board-open-SPEC-001'), findsOneWidget);
    expect(chipText(tester), 'Ocultar concluídas');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chip counts only the concluded cards that pass the other '
      'filters (R5)', (tester) async {
    await pumpCanvas(tester, const [
      CanvasSpec('SPEC-001', stage: SpecStage.done),
      CanvasSpec('SPEC-002', stage: SpecStage.done),
      CanvasSpec(
        'SPEC-003',
        steps: [StepStatus.needsInput],
        sessionStatus: SessionStatus.waitingApproval,
      ),
    ]);
    await tester.tap(byKey('board-filter-hide-done'));
    await pumpFor(tester, 20);
    expect(chipText(tester), 'Ocultar concluídas · 2');
    await tester.tap(byKey('board-filter-attention'));
    await pumpFor(tester, 20);
    expect(chipText(tester), 'Ocultar concluídas · 0');
    expect(byKey('board-open-SPEC-003'), findsOneWidget);
  });

  testWidgets('only concluded specs hidden: own message and "Mostrar '
      'concluídas"; nothing hidden keeps the filters message (R6)', (
    tester,
  ) async {
    await pumpCanvas(tester, const [
      CanvasSpec('SPEC-001', stage: SpecStage.done),
      CanvasSpec('SPEC-002', stage: SpecStage.done),
    ]);
    await tester.tap(byKey('board-filter-hide-done'));
    await pumpFor(tester, 20);
    expect(
      find.text(
        'Nenhum cartão em andamento. 2 specs concluídas estão ocultas.',
      ),
      findsOneWidget,
    );
    expect(find.text('Nenhum cartão passa pelos filtros.'), findsNothing);
    await tester.tap(byKey('board-show-done'));
    await pumpFor(tester, 20);
    expect(byKey('board-open-SPEC-001'), findsOneWidget);
    expect(chipText(tester), 'Ocultar concluídas');
  });

  testWidgets('no concluded card hidden: the empty board keeps "Nenhum cartão '
      'passa pelos filtros." (R6)', (tester) async {
    await pumpCanvas(tester, const [
      CanvasSpec('SPEC-001', stage: SpecStage.done),
      CanvasSpec('SPEC-002'),
    ]);
    await tester.tap(byKey('board-filter-hide-done'));
    await pumpFor(tester, 20);
    // "Precisam de mim" with no card waiting: nothing passes, nothing done.
    await tester.tap(byKey('board-filter-attention'));
    await pumpFor(tester, 20);
    expect(find.text('Nenhum cartão passa pelos filtros.'), findsOneWidget);
    expect(byKey('board-show-done'), findsNothing);
  });

  testWidgets('the filter is per project: B opens without it, A gets it back '
      '(R4)', (tester) async {
    final (c, db) = await pumpCanvas(tester, const [
      CanvasSpec('SPEC-001', stage: SpecStage.done),
      CanvasSpec('SPEC-002'),
    ]);
    final a = c.read(activeWorkspaceProvider)!;
    final b = await db
        .into(db.workspaces)
        .insertReturning(WorkspacesCompanion.insert(path: '/b', name: 'b'));
    await db
        .into(db.specs)
        .insert(
          SpecsCompanion.insert(
            workspaceId: b.id,
            code: 'SPEC-009',
            title: 'Pronta em B',
            path: 'specs/SPEC-009.md',
            status: const Value(SpecStatus.approved),
            stage: const Value(SpecStage.done),
          ),
        );
    await pumpFor(tester, 20);
    await tester.tap(byKey('board-filter-hide-done'));
    await pumpFor(tester, 20);
    expect(byKey('board-open-SPEC-001'), findsNothing);

    final settings = c.read(appSettingsProvider.notifier);
    await settings.set(AppSettingKeys.activeWorkspace, '${b.id}');
    await pumpFor(tester, 20);
    expect(c.read(boardHideDoneProvider), isFalse);
    expect(byKey('board-open-SPEC-009'), findsOneWidget);
    expect(chipText(tester), 'Ocultar concluídas');

    await settings.set(AppSettingKeys.activeWorkspace, '${a.id}');
    await pumpFor(tester, 20);
    expect(c.read(boardHideDoneProvider), isTrue);
    expect(byKey('board-open-SPEC-001'), findsNothing);
    expect(byKey('board-open-SPEC-002'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
