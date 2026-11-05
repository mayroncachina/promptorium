import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/widgets/spec_folder.dart';

import 'canvas_fixture.dart';

Finder row(String code) => byKey('folder-row-$code');

String code(int n) => 'SPEC-${n.toString().padLeft(3, '0')}';

List<CanvasSpec> many(int n) => [
  for (var i = 1; i <= n; i++) CanvasSpec(code(i), title: 'Spec número $i'),
];

Future<(ProviderContainer, AppDatabase)> pumpFolder(
  WidgetTester tester,
  List<CanvasSpec> specs, {
  Size size = const Size(1440, 1100),
}) => pumpCanvas(tester, specs, size: size, view: BoardView.focus);

/// Lines whose whole height is inside the list.
List<String> shownRows(WidgetTester tester, Iterable<String> codes) {
  final list = tester.getRect(byKey('folder-list'));
  return [
    for (final c in codes)
      if (row(c).evaluate().isNotEmpty &&
          tester.getRect(row(c)).top >= list.top - .5 &&
          tester.getRect(row(c)).bottom <= list.bottom + .5)
        c,
  ];
}

Future<TestGesture> hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(target));
  await pumpFor(tester);
  return mouse;
}

double offsetOf(WidgetTester tester) =>
    tester.widget<ListView>(byKey('folder-list')).controller!.offset;

void main() {
  group('R1 · Foco view', () {
    testWidgets('the Quadro offers Colunas, Grafo and Foco', (tester) async {
      final (c, _) = await pumpCanvas(tester, [
        const CanvasSpec('SPEC-001'),
      ], view: BoardView.columns);
      expect(find.text('Colunas'), findsOneWidget);
      expect(find.text('Grafo'), findsOneWidget);
      expect(find.text('Foco'), findsOneWidget);
      await tester.tap(byKey('board-view-focus'));
      await pumpFor(tester);
      expect(c.read(boardGraphViewProvider), BoardView.focus);
      expect(byKey('spec-folder'), findsOneWidget);
      expect(byKey('stage-hint'), findsOneWidget);
      await tester.tap(byKey('board-view-graph'));
      await pumpFor(tester);
      expect(byKey('spec-folder'), findsNothing);
      expect(byKey('board-graph'), findsOneWidget);
    });

    testWidgets('lists number and title, newest first, even past 999', (
      tester,
    ) async {
      await pumpFolder(tester, [
        const CanvasSpec('SPEC-009', title: 'Nove'),
        const CanvasSpec('SPEC-1000', title: 'Mil'),
        const CanvasSpec('SPEC-010', title: 'Dez'),
      ]);
      final tops = [
        for (final c in ['SPEC-1000', 'SPEC-010', 'SPEC-009'])
          tester.getTopLeft(row(c)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(find.text('010'), findsOneWidget);
      expect(find.text('Dez'), findsOneWidget);
      expect(tester.widget<Text>(byKey('folder-count')).data, '3');
    });

    testWidgets('a long title ends in an ellipsis on one line', (tester) async {
      await pumpFolder(tester, [
        CanvasSpec('SPEC-001', title: 'Título muito longo ' * 8),
      ]);
      final title = tester.widget<Text>(byKey('folder-title-SPEC-001'));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('"Ocultar concluídas" also hides lines of the folder', (
      tester,
    ) async {
      await pumpFolder(tester, const [
        CanvasSpec('SPEC-001', stage: SpecStage.done),
        CanvasSpec('SPEC-002'),
      ]);
      expect(row('SPEC-001'), findsOneWidget);
      await tester.tap(byKey('board-filter-hide-done'));
      await pumpFor(tester);
      expect(row('SPEC-001'), findsNothing);
      expect(row('SPEC-002'), findsOneWidget);
      expect(tester.widget<Text>(byKey('folder-count')).data, '1');
    });
  });

  group('R2 · status', () {
    test('the balloon comes before the stage', () {
      expect(
        folderStatus(SpecStage.running, attention: true),
        FolderStatus.attention,
      );
      expect(
        folderStatus(SpecStage.running, attention: false),
        FolderStatus.running,
      );
    });

    testWidgets('each status has its shape and an accessible name', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpFolder(tester, const [
        CanvasSpec('SPEC-001', stage: SpecStage.done),
        CanvasSpec('SPEC-002', stage: SpecStage.running),
        CanvasSpec('SPEC-003', stage: SpecStage.review),
        CanvasSpec('SPEC-004'),
        CanvasSpec(
          'SPEC-005',
          stage: SpecStage.running,
          steps: [StepStatus.needsInput],
        ),
      ]);
      for (final label in [
        'Feito',
        'Em execução',
        'Review',
        'Backlog',
        'Aguardando você',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(
        find.descendant(
          of: byKey('folder-status-SPEC-001'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: byKey('folder-status-SPEC-002'),
          matching: byKey('folder-spinner'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('R3 · height and scrolling', () {
    final codes = [for (var i = 1; i <= 30; i++) code(i)];

    testWidgets('shows at most 15 lines', (tester) async {
      await pumpFolder(tester, many(30));
      expect(shownRows(tester, codes), hasLength(folderMaxRows));
    });

    testWidgets('a smaller window shows the lines that fit', (tester) async {
      await pumpFolder(tester, many(30), size: const Size(1440, 660));
      final shown = shownRows(tester, codes).length;
      expect(shown, inExclusiveRange(1, folderMaxRows));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolls by the wheel', (tester) async {
      await pumpFolder(tester, many(30));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      mouse.hover(tester.getCenter(byKey('folder-list')));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await pumpFor(tester);
      expect(offsetOf(tester), 120);
    });

    testWidgets('the arrows move 4 lines and stop at the ends', (tester) async {
      await pumpFolder(tester, many(30));
      IconButton arrow(String name) =>
          tester.widget<IconButton>(byKey('folder-scroll-$name'));
      await pumpFor(tester);
      expect(arrow('up').onPressed, isNull);
      expect(arrow('down').onPressed, isNotNull);
      await tester.tap(byKey('folder-scroll-down'));
      await pumpFor(tester);
      expect(offsetOf(tester), 4 * folderRowStride);
      expect(arrow('up').onPressed, isNotNull);
      for (var i = 0; i < 12 && arrow('down').onPressed != null; i++) {
        await tester.tap(byKey('folder-scroll-down'));
        await pumpFor(tester);
      }
      expect(arrow('down').onPressed, isNull);
    });

    testWidgets('the keyboard moves one line with the focus on the folder', (
      tester,
    ) async {
      await pumpFolder(tester, many(30));
      await tester.tap(byKey('folder-scroll-down'));
      await pumpFor(tester);
      final before = offsetOf(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await pumpFor(tester);
      expect(offsetOf(tester), before + folderRowStride);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await pumpFor(tester);
      expect(offsetOf(tester), before);
    });

    testWidgets('Tab onto a line out of view scrolls to it', (tester) async {
      await pumpFolder(tester, many(30));
      await tester.tap(byKey('folder-scroll-up'), warnIfMissed: false);
      await pumpFor(tester);
      for (var i = 0; i < 18; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await pumpFor(tester, 3);
      }
      expect(offsetOf(tester), greaterThan(0));
      final focused = primaryFocus!.context!;
      final box = focused.findRenderObject()! as RenderBox;
      final list = tester.getRect(byKey('folder-list'));
      final top = box.localToGlobal(Offset.zero).dy;
      expect(top, greaterThanOrEqualTo(list.top - 1));
      expect(top, lessThan(list.bottom));
    });
  });

  group('R4 · the line grows', () {
    testWidgets('hover turns the line into the card and pushes the others', (
      tester,
    ) async {
      await pumpFolder(tester, const [
        CanvasSpec('SPEC-003', title: 'Terceira'),
        CanvasSpec('SPEC-002', title: 'Segunda'),
        CanvasSpec('SPEC-001', title: 'Primeira'),
      ]);
      final top = tester.getTopLeft(row('SPEC-002')).dy;
      final next = tester.getTopLeft(row('SPEC-001')).dy;
      await hover(tester, row('SPEC-002'));
      expect(byKey('folder-card-SPEC-002'), findsOneWidget);
      expect(find.text('SPEC-002'), findsOneWidget);
      expect(find.text('Backlog'), findsOneWidget);
      expect(tester.getTopLeft(row('SPEC-002')).dy, top);
      final card = tester.getRect(row('SPEC-002'));
      expect(card.height, greaterThan(folderRowHeight + 30));
      expect(tester.getTopLeft(row('SPEC-001')).dy, greaterThan(next));
      expect(
        tester.getTopLeft(row('SPEC-001')).dy,
        greaterThanOrEqualTo(card.bottom),
      );
    });

    testWidgets('the card shows the whole title', (tester) async {
      final title = 'Um título bem longo que nunca cabe numa linha só ' * 3;
      await pumpFolder(tester, [CanvasSpec('SPEC-001', title: title)]);
      await hover(tester, row('SPEC-001'));
      final text = tester.widget<Text>(find.text(title));
      expect(text.maxLines, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the focus grows the line too', (tester) async {
      await pumpFolder(tester, const [CanvasSpec('SPEC-001')]);
      Focus.of(tester.element(find.text('001'))).requestFocus();
      await pumpFor(tester);
      expect(byKey('folder-card-SPEC-001'), findsOneWidget);
    });

    testWidgets('the last line grows without being cut', (tester) async {
      await pumpFolder(tester, many(30));
      final list = tester.widget<ListView>(byKey('folder-list'));
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await pumpFor(tester);
      await hover(tester, row(code(1)));
      expect(
        tester.getRect(row(code(1))).bottom,
        lessThanOrEqualTo(tester.getRect(byKey('folder-list')).bottom),
      );
    });
  });

  group('R5 · collapsed', () {
    testWidgets('shows only the icon and the number', (tester) async {
      await pumpFolder(tester, const [
        CanvasSpec('SPEC-001', title: 'Primeira'),
      ]);
      await tester.tap(byKey('folder-toggle'));
      await pumpFor(tester);
      expect(find.text('Primeira'), findsNothing);
      expect(find.text('001'), findsOneWidget);
      expect(byKey('folder-status-SPEC-001'), findsOneWidget);
      expect(
        tester.getSize(byKey('spec-folder')).width,
        lessThan(folderCollapsedWidth + 20),
      );
      await tester.tap(byKey('folder-toggle'));
      await pumpFor(tester);
      expect(find.text('Primeira'), findsOneWidget);
    });

    testWidgets('the stage takes the room and stays centered', (tester) async {
      await pumpFolder(tester, const [CanvasSpec('SPEC-001')]);
      final open = tester.getCenter(byKey('stage-hint')).dx;
      await tester.tap(byKey('folder-toggle'));
      await pumpFor(tester);
      expect(tester.getCenter(byKey('stage-hint')).dx, lessThan(open));
    });

    testWidgets('hover shows the card over the stage, without moving lines', (
      tester,
    ) async {
      await pumpFolder(tester, const [
        CanvasSpec('SPEC-002', title: 'Segunda'),
        CanvasSpec('SPEC-001', title: 'Primeira'),
      ]);
      await tester.tap(byKey('folder-toggle'));
      await pumpFor(tester);
      final next = tester.getTopLeft(row('SPEC-001')).dy;
      await hover(tester, row('SPEC-002'));
      expect(find.text('Segunda'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Segunda')).dx,
        greaterThan(tester.getRect(row('SPEC-002')).right),
      );
      expect(tester.getTopLeft(row('SPEC-001')).dy, next);
    });

    testWidgets('is saved per workspace', (tester) async {
      final (c, db) = await pumpFolder(tester, const [CanvasSpec('SPEC-001')]);
      await tester.tap(byKey('folder-toggle'));
      await pumpFor(tester);
      final id = c.read(activeWorkspaceProvider)!.id;
      expect(
        AppSettingKeys.boardFolderCollapsed(id),
        'board.folderCollapsed.$id',
      );
      final saved = await (db.select(
        db.appSettings,
      )..where((t) => t.key.equals('board.folderCollapsed.$id'))).getSingle();
      expect(saved.value, '1');
      expect(c.read(boardFolderCollapsedProvider), isTrue);
    });
  });

  testWidgets('R16 · no overflow at 1100×700, open and collapsed', (
    tester,
  ) async {
    await tester.runAsync(loadAppFonts);
    await pumpFolder(tester, many(30), size: minimumBoard);
    expect(tester.takeException(), isNull);
    await hover(tester, row(code(30)));
    expect(tester.takeException(), isNull);
    await tester.tap(byKey('folder-toggle'));
    await pumpFor(tester);
    expect(tester.takeException(), isNull);
  });
}
