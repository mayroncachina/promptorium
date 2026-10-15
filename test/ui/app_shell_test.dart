import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/ui/shell/app_shell.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/shell/side_bar.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../helpers/test_db.dart';

/// Pumps the shell on a fresh in-memory database (returned for assertions).
Future<AppDatabase> pumpShell(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  AppDatabase? db,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final database = db ?? memoryDatabase();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseOverride(database)],
      child: MaterialApp(theme: AppTheme.dark(), home: const AppShell()),
    ),
  );
  // Unmount (closing the database) before the test ends.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    // Drift cancels stream queries with a zero-duration timer.
    await tester.pump(Duration.zero);
  });
  return database;
}

SideBarItem item(WidgetTester tester, AppSection s) =>
    tester.widget<SideBarItem>(find.byKey(ValueKey('nav-${s.name}')));

Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders 8 navigation items in mockup order plus the gear', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(AppSection.navItems.map((s) => s.label), [
      'Sessões',
      'Prompt',
      'Specs',
      'Tarefas',
      'Agentes',
      'Review',
      'Código',
      'Servidores MCP',
    ]);
    expect(find.byType(SideBarItem), findsNWidgets(9));
    for (final s in AppSection.navItems) {
      expect(find.byKey(ValueKey('nav-${s.name}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('nav-settings')), findsOneWidget);

    // Gear is below the 8 items.
    final gearY = tester
        .getTopLeft(find.byKey(const ValueKey('nav-settings')))
        .dy;
    final mcpY = tester.getTopLeft(find.byKey(const ValueKey('nav-mcp'))).dy;
    expect(gearY, greaterThan(mcpY));

    expect(item(tester, AppSection.sessions).active, isTrue);
    expect(find.text('Nova sessão'), findsOneWidget);
    expect(find.text('Claude Code CLI —'), findsOneWidget);
  });

  testWidgets('clicking an item changes the screen and the active item', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('nav-specs')));
    await tester.pumpAndSettle();

    expect(item(tester, AppSection.specs).active, isTrue);
    expect(item(tester, AppSection.sessions).active, isFalse);
    expect(find.byKey(const ValueKey('screen-specs')), findsOneWidget);
    expect(find.text('Nova spec'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    expect(item(tester, AppSection.settings).active, isTrue);
    expect(find.text('Configurações'), findsOneWidget);
    expect(find.byKey(const ValueKey('title-action')), findsNothing);
  });

  testWidgets('Ctrl+1..8 switch screens and zoom shortcuts hit the editor', (
    tester,
  ) async {
    await pumpShell(tester);

    await ctrl(tester, LogicalKeyboardKey.digit7);
    expect(item(tester, AppSection.code).active, isTrue);
    expect(find.text('100%'), findsOneWidget);

    await ctrl(tester, LogicalKeyboardKey.equal);
    await ctrl(tester, LogicalKeyboardKey.equal);
    expect(find.text('120%'), findsOneWidget);

    // Zoom is kept per editor.
    await ctrl(tester, LogicalKeyboardKey.digit3);
    expect(item(tester, AppSection.specs).active, isTrue);
    expect(find.text('100%'), findsOneWidget);
    await ctrl(tester, LogicalKeyboardKey.minus);
    expect(find.text('90%'), findsOneWidget);

    await ctrl(tester, LogicalKeyboardKey.digit7);
    expect(find.text('120%'), findsOneWidget);
    await ctrl(tester, LogicalKeyboardKey.digit0);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('Ctrl+K opens the palette and a command navigates', (
    tester,
  ) async {
    await pumpShell(tester);

    await ctrl(tester, LogicalKeyboardKey.keyK);
    expect(find.text('Ir para Tarefas'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'agen');
    await tester.pumpAndSettle();
    expect(find.text('Ir para Tarefas'), findsNothing);
    await tester.tap(find.text('Ir para Agentes'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(item(tester, AppSection.agents).active, isTrue);
  });

  testWidgets('fits the minimum window size without overflow', (tester) async {
    await pumpShell(tester, size: const Size(1100, 700));
    expect(tester.takeException(), isNull);
    for (final s in AppSection.values) {
      await tester.tap(find.byKey(ValueKey('nav-${s.name}')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('"Nova sessão" and Ctrl+N open the new session dialog', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('title-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-session-dialog')), findsOneWidget);
    // Without a workspace the dialog explains what to do.
    await tester.enterText(
      find.byKey(const ValueKey('new-session-title')),
      't',
    );
    await tester.tap(find.byKey(const ValueKey('new-session-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-session-error')), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-session-dialog')), findsNothing);

    await ctrl(tester, LogicalKeyboardKey.digit3);
    await ctrl(tester, LogicalKeyboardKey.keyN);
    expect(find.byKey(const ValueKey('new-session-dialog')), findsOneWidget);
    expect(item(tester, AppSection.sessions).active, isTrue);
  });
}
