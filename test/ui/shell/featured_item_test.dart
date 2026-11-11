import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/ui/shell/app_shell.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/shell/side_bar.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../../helpers/test_db.dart';

/// SPEC-055: the Prompt as the featured item of the sidebar.

const _highlight = ValueKey('nav-highlight');

Finder nav(AppSection s) => find.byKey(ValueKey('nav-${s.name}'));

Future<void> pumpShell(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        processRunnerProvider.overrideWithValue(
          (exe, args) async =>
              ProcessResult(0, 1, '', 'not installed in widget fixture'),
        ),
        databaseOverride(memoryDatabase()),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: const AppShell()),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}

/// Ends a test that is on the Prompt screen: the binding would unmount it
/// after the body, leaving drift's closing timer behind.
Future<void> leavePrompt(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

Future<void> go(WidgetTester tester, AppSection s) async {
  await tester.tap(nav(s));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(AppMotion.section);
}

Rect rectOf(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  test('R1 · the new order and R6 · the shortcuts', () {
    expect(AppSection.navItems, [
      AppSection.home,
      AppSection.project,
      AppSection.prompt,
      AppSection.specs,
      AppSection.tasks,
      AppSection.sessions,
      AppSection.review,
      AppSection.repository,
      AppSection.code,
      AppSection.agents,
    ]);
    expect(AppSection.prompt.shortcutLabel, 'Ctrl 3');
    expect(AppSection.specs.shortcutLabel, 'Ctrl 4');
    expect(AppSection.code.shortcutLabel, 'Ctrl 9');
    expect(AppSection.agents.shortcutLabel, 'Ctrl 0');
    expect(AppSection.shortcutsVersion, 5);
    expect(
      [
        for (final s in AppSection.values)
          if (s.featured) s,
      ],
      [AppSection.prompt],
    );
  });

  testWidgets('R1, R2 · the Prompt is 48 × 58 with its name, right below '
      'Projeto and between two separators', (tester) async {
    await pumpShell(tester);
    final prompt = rectOf(tester, nav(AppSection.prompt));
    expect(prompt.size, const Size(48, 58));
    expect(
      find.descendant(
        of: nav(AppSection.prompt),
        matching: find.text('Prompt'),
      ),
      findsOneWidget,
    );
    // The other items keep 44 × 44.
    expect(tester.getSize(nav(AppSection.specs)), const Size.square(44));

    final seps = find.byKey(const ValueKey('nav-separator'));
    expect(seps, findsNWidgets(2));
    final above = rectOf(tester, seps.first);
    final below = rectOf(tester, seps.last);
    expect(above.size, const Size(28, 1));
    expect(
      above.top,
      greaterThan(rectOf(tester, nav(AppSection.project)).bottom),
    );
    expect(above.bottom, lessThanOrEqualTo(prompt.top));
    expect(below.top, greaterThanOrEqualTo(prompt.bottom));
    expect(below.bottom, lessThan(rectOf(tester, nav(AppSection.specs)).top));
  });

  testWidgets('R8 · the highlight takes the real place and size of the '
      'Prompt and of the items below it', (tester) async {
    await pumpShell(tester);
    await go(tester, AppSection.prompt);
    expect(
      rectOf(tester, find.byKey(_highlight)),
      rectOf(tester, nav(AppSection.prompt)),
    );
    for (final s in [AppSection.specs, AppSection.code, AppSection.agents]) {
      await go(tester, s);
      expect(rectOf(tester, find.byKey(_highlight)), rectOf(tester, nav(s)));
    }
    await go(tester, AppSection.settings);
    expect(
      rectOf(tester, find.byKey(_highlight)),
      rectOf(tester, nav(AppSection.settings)),
    );
  });

  testWidgets('R8 · at 1100 × 700 the sidebar fits: nothing overflows and '
      'the gear stays below Ferramentas', (tester) async {
    await pumpShell(tester, size: const Size(1100, 700));
    expect(tester.takeException(), isNull);
    final tools = rectOf(tester, nav(AppSection.agents));
    final gear = rectOf(tester, nav(AppSection.settings));
    expect(gear.top, greaterThanOrEqualTo(tools.bottom));
    expect(gear.bottom, lessThanOrEqualTo(700));
    await go(tester, AppSection.prompt);
    expect(tester.takeException(), isNull);
    await leavePrompt(tester);
  });

  testWidgets('R3 · active: the label turns light amber; selected and the '
      'name are announced', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpShell(tester);
    Text label() => tester.widget<Text>(
      find.descendant(
        of: nav(AppSection.prompt),
        matching: find.byKey(const ValueKey('nav-featured-label')),
      ),
    );
    expect(label().style!.color, AppColors.text);
    final ink = find.descendant(
      of: nav(AppSection.prompt),
      matching: find.byType(InkWell),
    );
    expect(
      tester.getSemantics(ink),
      isSemantics(label: 'Prompt', isButton: true, isSelected: false),
    );

    await go(tester, AppSection.prompt);
    expect(label().style!.color, AppColors.amberLight);
    expect(
      tester.getSemantics(ink),
      isSemantics(label: 'Prompt', isButton: true, isSelected: true),
    );
    expect(find.byTooltip('Prompt'), findsOneWidget);
    semantics.dispose();
    await leavePrompt(tester);
  });

  testWidgets('R3 · keyboard focus draws the light amber ring at once', (
    tester,
  ) async {
    await pumpShell(tester);
    final ring = find.byKey(const ValueKey('nav-featured-focus'));
    expect(ring, findsNothing);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final focus = tester
        .widget<InkWell>(
          find.descendant(
            of: nav(AppSection.prompt),
            matching: find.byType(InkWell),
          ),
        )
        .focusNode;
    final node =
        focus ??
        Focus.of(
          tester.element(
            find.descendant(
              of: nav(AppSection.prompt),
              matching: find.byKey(const ValueKey('nav-featured-label')),
            ),
          ),
        );
    node.requestFocus();
    await tester.pump();
    expect(ring, findsOneWidget);
    final prompt = rectOf(tester, nav(AppSection.prompt));
    // 2px ring, 3px away from the item.
    expect(rectOf(tester, ring), prompt.inflate(5));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(AppMotion.section);
    expect(
      tester.widget<SideBarFeaturedItem>(nav(AppSection.prompt)).active,
      isTrue,
    );
    await leavePrompt(tester);
  });
}
