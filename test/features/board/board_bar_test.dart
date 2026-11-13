import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';

import 'canvas_fixture.dart';

/// SPEC-053 R7–R9: the Quadro's bar in three zones.
void main() {
  const specs = [
    CanvasSpec('SPEC-001', stage: SpecStage.running, agent: 'backend'),
    CanvasSpec('SPEC-002', agent: 'frontend'),
  ];

  Rect rect(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  // The test font draws every glyph 1 em wide: a 1800 px window gives the
  // room a 1440 px one has with the app's font.
  testWidgets('wide: Colunas/Grafo/Foco in the middle of the bar, '
      'Agendar and Executar tudo at the right end (R7)', (tester) async {
    await pumpCanvas(
      tester,
      specs,
      size: const Size(1800, 900),
      view: BoardView.columns,
    );
    final bar = rect(tester, 'board-bar-left').left;
    final end = rect(tester, 'board-bar-right').right;
    final center = rect(tester, 'board-view-switch').center.dx;
    expect(center, closeTo((bar + end) / 2, 1));
    // Executar tudo is the last thing on the right, after Agendar.
    expect(rect(tester, 'board-autopilot').right, closeTo(end, 1));
    expect(
      rect(tester, 'board-schedule').right,
      lessThan(rect(tester, 'board-autopilot').left),
    );
    expect(
      find.byKey(const ValueKey('board-filter-hide-done')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('board-filters-folded')), findsNothing);
  });

  testWidgets('1100×700 with every filter: the filters fold into one chip, '
      'nothing overlaps and both buttons stay (R9)', (tester) async {
    // A width check needs the app's fonts (SPEC-036 R16): with the test
    // font the Bandeja (SPEC-068 R7) alone pushed the bar past 1100 px.
    await loadAppFonts();
    await pumpCanvas(
      tester,
      specs,
      size: const Size(1100, 700),
      view: BoardView.columns,
    );
    expect(find.byKey(const ValueKey('board-filters-folded')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-filter-hide-done')), findsNothing);
    final left = rect(tester, 'board-bar-left');
    final mid = rect(tester, 'board-view-switch');
    final right = rect(tester, 'board-bar-right');
    expect(left.overlaps(mid), isFalse);
    expect(mid.overlaps(right), isFalse);
    expect(right.right, lessThanOrEqualTo(1100));
    expect(
      find.byKey(const ValueKey('board-autopilot')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('board-schedule')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // The folded chip still filters: "Precisam de mim" from its menu.
    await tester.tap(find.byKey(const ValueKey('board-filters-folded')));
    await pumpFor(tester);
    await tester.tap(find.text('Ocultar concluídas').last);
    await pumpFor(tester);
    expect(find.text('Filtros · 1'), findsOneWidget);
  });

  testWidgets('arrows move between the views; the group is announced as '
      '"Visão do quadro" with the chosen one selected (R8)', (tester) async {
    final (c, _) = await pumpCanvas(tester, specs, view: BoardView.columns);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Visão do quadro'), findsOneWidget);
    final colunas = tester.getSemantics(
      find.byKey(const ValueKey('board-view-columns')),
    );
    expect(colunas.flagsCollection.isSelected, Tristate.isTrue);

    await tester.tap(find.byKey(const ValueKey('board-view-columns')));
    await pumpFor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await pumpFor(tester);
    expect(c.read(boardGraphViewProvider), BoardView.graph);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await pumpFor(tester);
    expect(c.read(boardGraphViewProvider), BoardView.focus);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await pumpFor(tester);
    expect(c.read(boardGraphViewProvider), BoardView.graph);
    handle.dispose();
  });
}
