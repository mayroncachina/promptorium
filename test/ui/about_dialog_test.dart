import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/shell/shortcut_sheet.dart';

import 'app_shell_test.dart' show pumpShell;

const _about = ValueKey('about-dialog');

Future<void> _expectAbout(WidgetTester tester) async {
  // The provider's future resolves outside the fake clock: wait for it.
  for (
    var i = 0;
    i < 100 && find.byType(MarkdownBody).evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(find.byKey(_about), findsOneWidget);
  expect(find.byKey(const ValueKey('about-version')), findsOneWidget);
  expect(
    find.text('https://github.com/mayroncachina/promptorium'),
    findsOneWidget,
  );
  final md = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
  expect(md.data, contains('Todas as mudanças relevantes'));
}

/// Reads the asset outside the fake clock so the dialog finds it cached.
Future<void> _preloadChangelog(WidgetTester tester) async {
  await tester.runAsync(() => rootBundle.loadString('CHANGELOG.md'));
}

Future<void> _f1(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.f1);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('F1 opens the dialog with version, repository and changelog, '
      'and F1 closes it', (tester) async {
    await pumpShell(tester);
    await _preloadChangelog(tester);
    await _f1(tester);
    await _expectAbout(tester);
    await _f1(tester);
    expect(find.byKey(_about), findsNothing);
  });

  testWidgets('the palette item "Sobre" opens the dialog', (tester) async {
    await pumpShell(tester);
    await _preloadChangelog(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sobre');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sobre'));
    await tester.pumpAndSettle();
    await _expectAbout(tester);
  });

  testWidgets('the "Sobre" button of Configurações opens the dialog', (
    tester,
  ) async {
    await pumpShell(tester);
    await _preloadChangelog(tester);
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atualizações').first);
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('open-about'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _expectAbout(tester);
  });

  test('the shortcut sheet lists Sobre with F1', () {
    final entries = [for (final g in shortcutGroups) ...g.entries];
    expect(entries.any((e) => e.label == 'Sobre' && e.keys == 'F1'), isTrue);
  });

  testWidgets('F1 opens the dialog while a text field has focus', (
    tester,
  ) async {
    await pumpShell(tester);
    await _preloadChangelog(tester);
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('settings-search'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>(),
      isNotNull,
    );
    await _f1(tester);
    await _expectAbout(tester);
  });
}
