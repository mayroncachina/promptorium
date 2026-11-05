import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/ui/shell/shortcut_sheet.dart';

import 'canvas_fixture.dart';

Finder row(String code) => byKey('folder-row-$code');

const specs = [
  CanvasSpec('SPEC-001', title: 'Ícone na bandeja'),
  CanvasSpec('SPEC-002', title: 'Fila de review'),
  CanvasSpec('SPEC-012', title: 'Review: merge guiado'),
];

Future<void> pumpSearch(WidgetTester tester) => pumpCanvas(
  tester,
  specs,
  size: const Size(1440, 1100),
  view: BoardView.focus,
);

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await pumpFor(tester);
}

Future<void> slash(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
  await pumpFor(tester);
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(byKey('folder-search'), text);
  await pumpFor(tester);
}

bool searchFocused(WidgetTester tester) =>
    tester.widget<TextField>(byKey('folder-search')).focusNode!.hasFocus;

String count(WidgetTester tester) =>
    tester.widget<Text>(byKey('folder-count')).data!;

void main() {
  group('R6 · shortcuts', () {
    testWidgets('/ focuses the field', (tester) async {
      await pumpSearch(tester);
      expect(searchFocused(tester), isFalse);
      await slash(tester);
      expect(searchFocused(tester), isTrue);
      expect(
        tester.widget<TextField>(byKey('folder-search')).controller!.text,
        isEmpty,
      );
    });

    testWidgets('Ctrl+F focuses the field', (tester) async {
      await pumpSearch(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await pumpFor(tester);
      expect(searchFocused(tester), isTrue);
    });

    testWidgets('inside a text field / is only text', (tester) async {
      await pumpSearch(tester);
      await slash(tester);
      final focus = primaryFocus;
      final handled = await tester.sendKeyEvent(
        LogicalKeyboardKey.slash,
        character: '/',
      );
      expect(handled, isFalse, reason: 'the key must reach the field');
      expect(primaryFocus, focus);
    });

    testWidgets('the shortcuts do nothing in the other views', (tester) async {
      await pumpCanvas(tester, specs, view: BoardView.columns);
      await slash(tester);
      expect(byKey('folder-search'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapsed, the magnifier and the shortcut open the folder', (
      tester,
    ) async {
      await pumpSearch(tester);
      await tester.tap(byKey('folder-toggle'));
      await pumpFor(tester);
      expect(byKey('folder-search'), findsNothing);
      await tester.tap(byKey('folder-search-open'));
      await pumpFor(tester);
      expect(searchFocused(tester), isTrue);

      await press(tester, LogicalKeyboardKey.escape);
      await tester.tap(byKey('folder-toggle'));
      await pumpFor(tester);
      await slash(tester);
      expect(searchFocused(tester), isTrue);
    });

    test('are on the shortcut sheet', () {
      final keys = [
        for (final g in shortcutGroups)
          for (final e in g.entries) e.keys,
      ];
      expect(keys, contains('/ · Ctrl+F'));
    });
  });

  group('R7 · filter', () {
    testWidgets('compares number and title, ignoring case and accents', (
      tester,
    ) async {
      await pumpSearch(tester);
      await type(tester, 'icone');
      expect(row('SPEC-001'), findsOneWidget);
      expect(row('SPEC-002'), findsNothing);
      expect(count(tester), '1 de 3');

      await type(tester, 'REVIEW');
      expect(row('SPEC-001'), findsNothing);
      expect(count(tester), '2 de 3');

      await type(tester, '012');
      expect(row('SPEC-012'), findsOneWidget);
      expect(count(tester), '1 de 3');
    });

    testWidgets('the first result is expanded and the arrows move it', (
      tester,
    ) async {
      await pumpSearch(tester);
      await slash(tester);
      await type(tester, 'review');
      expect(byKey('folder-card-SPEC-012'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(byKey('folder-card-SPEC-012'), findsNothing);
      expect(byKey('folder-card-SPEC-002'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(byKey('folder-card-SPEC-002'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(byKey('folder-card-SPEC-012'), findsOneWidget);
    });

    testWidgets('Esc clears the search and gives the focus back', (
      tester,
    ) async {
      await pumpSearch(tester);
      await slash(tester);
      await type(tester, 'review');
      await press(tester, LogicalKeyboardKey.escape);
      expect(count(tester), '3');
      expect(row('SPEC-001'), findsOneWidget);
      expect(searchFocused(tester), isFalse);
    });

    testWidgets('without a result, says so', (tester) async {
      await pumpSearch(tester);
      await type(tester, 'xyz');
      expect(find.text('Nenhuma spec com "xyz"'), findsOneWidget);
      expect(count(tester), '0 de 3');
      await slash(tester);
      await press(tester, LogicalKeyboardKey.enter);
      expect(tester.takeException(), isNull);
    });
  });
}
