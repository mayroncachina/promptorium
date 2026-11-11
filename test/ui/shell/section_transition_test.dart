import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/ui/shell/app_shell.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/shell/side_bar.dart';
import 'package:promptorium/ui/shell/title_bar.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/theme/tokens.dart';
import 'package:promptorium/ui/widgets/app_icon.dart';
import 'package:promptorium/ui/widgets/motion_enter.dart';

import '../../helpers/test_db.dart';

const _highlight = ValueKey('nav-highlight');

Finder nav(AppSection s) => find.byKey(ValueKey('nav-${s.name}'));

Finder screen(AppSection s) => find.byKey(ValueKey('screen-${s.name}'));

Future<void> pumpShell(WidgetTester tester, {bool reduced = false}) async {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (reduced) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
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
  // Unmount (closing the database) before the test ends.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}

/// Selects [s] in the sidebar and shows the first frame of the change.
Future<void> go(WidgetTester tester, AppSection s) async {
  await tester.tap(nav(s));
  await tester.pump();
}

/// Past the end of everything a section change starts.
Future<void> finish(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(AppMotion.section);
}

Finder enterOf(AppSection s) =>
    find.ancestor(of: screen(s), matching: find.byType(MotionEnter));

double opacity(WidgetTester tester, AppSection s) => tester
    .widget<FadeTransition>(
      find
          .descendant(of: enterOf(s), matching: find.byType(FadeTransition))
          .first,
    )
    .opacity
    .value;

double offsetY(WidgetTester tester, AppSection s) => tester
    .widget<Transform>(
      find.descendant(of: enterOf(s), matching: find.byType(Transform)).first,
    )
    .transform
    .getTranslation()
    .y;

double highlightY(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(_highlight)).dy;

double itemY(WidgetTester tester, AppSection s) => tester.getTopLeft(nav(s)).dy;

Color? iconColor(WidgetTester tester, AppSection s) => tester
    .widget<AppIcon>(
      find.descendant(of: nav(s), matching: find.byType(AppIcon)),
    )
    .color;

void main() {
  test('every section has a coherent place in the sidebar order', () {
    expect(AppSection.home.navIndex, 0);
    expect(AppSection.prompt.navIndex, 2);
    expect(AppSection.tasks.navIndex, 4);
    for (final tool in AppSection.toolTabs) {
      expect(tool.navItem, AppSection.agents);
      expect(tool.navIndex, AppSection.navItems.indexOf(AppSection.agents));
    }
    expect(AppSection.settings.navItem, AppSection.settings);
    expect(AppSection.settings.navIndex, AppSection.navItems.length);
  });

  group('R2 · the new screen', () {
    testWidgets('the app opens on its screen without an entrance', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(opacity(tester, AppSection.home), 1);
      expect(offsetY(tester, AppSection.home), 0);
    });

    testWidgets('an item below comes from below, in section, and the old '
        'screen leaves at once', (tester) async {
      await pumpShell(tester);
      await go(tester, AppSection.specs);

      expect(screen(AppSection.home), findsNothing);
      expect(screen(AppSection.specs), findsOneWidget);
      expect(opacity(tester, AppSection.specs), 0);
      expect(offsetY(tester, AppSection.specs), 8);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(AppMotion.section ~/ 2);
      final t = AppMotion.enter.transform(.5);
      expect(opacity(tester, AppSection.specs), closeTo(t, .01));
      expect(offsetY(tester, AppSection.specs), closeTo(8 * (1 - t), .1));

      await tester.pump(AppMotion.section ~/ 2);
      expect(opacity(tester, AppSection.specs), 1);
      expect(offsetY(tester, AppSection.specs), 0);
    });

    testWidgets('an item above comes from above', (tester) async {
      await pumpShell(tester);
      await go(tester, AppSection.specs);
      await finish(tester);

      await go(tester, AppSection.project);
      expect(screen(AppSection.specs), findsNothing);
      expect(opacity(tester, AppSection.project), 0);
      expect(offsetY(tester, AppSection.project), -8);
      await finish(tester);
    });

    testWidgets('the gear counts as the last item and the tools as '
        '"Ferramentas"', (tester) async {
      await pumpShell(tester);
      await go(tester, AppSection.agents);
      await finish(tester);

      await go(tester, AppSection.settings);
      expect(offsetY(tester, AppSection.settings), 8);
      await finish(tester);

      await tester.tap(nav(AppSection.agents));
      await tester.pump();
      expect(offsetY(tester, AppSection.agents), -8);
      await finish(tester);
    });

    testWidgets('the tabs of "Ferramentas" swap without an entrance', (
      tester,
    ) async {
      await pumpShell(tester);
      await go(tester, AppSection.agents);
      await finish(tester);

      await tester.tap(find.byKey(const ValueKey('tools-tab-skills')));
      await tester.pump();
      expect(screen(AppSection.agents), findsNothing);
      expect(opacity(tester, AppSection.skills), 1);
      expect(offsetY(tester, AppSection.skills), 0);
    });

    testWidgets('the title bar and the sidebar stay out of it', (tester) async {
      await pumpShell(tester);
      await go(tester, AppSection.specs);
      for (final type in [TitleBar, SideBar]) {
        expect(
          find.ancestor(
            of: find.byType(type),
            matching: find.byType(MotionEnter),
          ),
          findsNothing,
        );
      }
      await finish(tester);
    });

    testWidgets('R12 · changing again during the entrance already shows the '
        'next screen', (tester) async {
      await pumpShell(tester);
      await go(tester, AppSection.review);
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(tester, AppSection.review), inExclusiveRange(0, 1));

      await go(tester, AppSection.project);
      expect(screen(AppSection.review), findsNothing);
      expect(screen(AppSection.project), findsOneWidget);
      expect(offsetY(tester, AppSection.project), -8);

      await finish(tester);
      expect(opacity(tester, AppSection.project), 1);
      expect(offsetY(tester, AppSection.project), 0);
    });
  });

  group('R3 · the highlight', () {
    testWidgets('it is one element, on the active item', (tester) async {
      await pumpShell(tester);
      expect(find.byKey(_highlight), findsOneWidget);
      expect(highlightY(tester), itemY(tester, AppSection.home));
      expect(
        tester.getSize(find.byKey(_highlight)),
        tester.getSize(nav(AppSection.home)),
      );
      expect(
        tester.getTopLeft(find.byKey(_highlight)).dx,
        tester.getTopLeft(nav(AppSection.home)).dx,
      );
    });

    testWidgets('it slides to the new item in section', (tester) async {
      await pumpShell(tester);
      final from = itemY(tester, AppSection.home);
      final to = itemY(tester, AppSection.review);

      await go(tester, AppSection.review);
      expect(highlightY(tester), from);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(AppMotion.section ~/ 2);
      expect(find.byKey(_highlight), findsOneWidget);
      final t = AppMotion.enter.transform(.5);
      expect(highlightY(tester), closeTo(from + (to - from) * t, .5));

      await tester.pump(AppMotion.section ~/ 2);
      expect(highlightY(tester), to);
    });

    testWidgets('R12 · a new item starts from where it is', (tester) async {
      await pumpShell(tester);
      await go(tester, AppSection.review);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      final midway = highlightY(tester);
      expect(midway, greaterThan(itemY(tester, AppSection.home)));

      await go(tester, AppSection.project);
      expect(highlightY(tester), closeTo(midway, .5));

      await finish(tester);
      expect(highlightY(tester), itemY(tester, AppSection.project));
    });

    testWidgets('it reaches the gear and stays with it when the window '
        'changes', (tester) async {
      await pumpShell(tester);
      await go(tester, AppSection.settings);
      await finish(tester);
      expect(highlightY(tester), itemY(tester, AppSection.settings));

      tester.view.physicalSize = const Size(1440, 760);
      await tester.pump();
      expect(highlightY(tester), itemY(tester, AppSection.settings));
    });

    testWidgets('"Ferramentas" stays lit on any tab, without a slide', (
      tester,
    ) async {
      await pumpShell(tester);
      await go(tester, AppSection.agents);
      await finish(tester);

      await tester.tap(find.byKey(const ValueKey('tools-tab-mcp')));
      await tester.pump();
      expect(highlightY(tester), itemY(tester, AppSection.agents));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('selected, tooltip and the item keys are kept', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpShell(tester);
      await go(tester, AppSection.specs);
      await finish(tester);

      Finder ink(AppSection s) =>
          find.descendant(of: nav(s), matching: find.byType(InkWell));
      expect(
        tester.getSemantics(ink(AppSection.specs)),
        isSemantics(label: 'Specs', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(ink(AppSection.home)),
        isSemantics(label: 'Início', isButton: true, isSelected: false),
      );
      expect(find.byTooltip('Specs'), findsOneWidget);
      expect(tester.widget<SideBarItem>(nav(AppSection.specs)).active, isTrue);
      semantics.dispose();
    });
  });

  group('R6 · the items of the sidebar', () {
    testWidgets('hover changes the color in quick and leaves faster', (
      tester,
    ) async {
      await pumpShell(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(nav(AppSection.project)));
      await tester.pump();
      expect(iconColor(tester, AppSection.project), AppColors.textSecondary);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(AppMotion.quick ~/ 4);
      expect(
        iconColor(tester, AppSection.project),
        isNot(anyOf(AppColors.textSecondary, AppColors.text)),
      );
      await tester.pump(AppMotion.quick);
      expect(iconColor(tester, AppSection.project), AppColors.text);

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(AppMotion.quickExit);
      expect(iconColor(tester, AppSection.project), AppColors.textSecondary);
    });

    testWidgets('the active item keeps its color on hover', (tester) async {
      await pumpShell(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(nav(AppSection.home)));
      await tester.pump();
      await tester.pump(AppMotion.quick);
      expect(iconColor(tester, AppSection.home), AppColors.amber);
    });

    testWidgets('a press scales to 0.98 without moving the layout', (
      tester,
    ) async {
      await pumpShell(tester);
      final rest = tester.getSize(nav(AppSection.project));
      final next = itemY(tester, AppSection.specs);
      double scale() => tester
          .widget<AnimatedScale>(
            find.descendant(
              of: nav(AppSection.project),
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale;

      final press = await tester.startGesture(
        tester.getCenter(nav(AppSection.project)),
      );
      await tester.pump();
      await tester.pump(AppMotion.quick);
      expect(scale(), .98);
      expect(tester.getSize(nav(AppSection.project)), rest);
      expect(itemY(tester, AppSection.specs), next);

      await press.up();
      await tester.pump();
      expect(scale(), 1);
      await finish(tester);
    });
  });

  testWidgets('R11 · with reduced motion everything is at its end at once', (
    tester,
  ) async {
    await pumpShell(tester, reduced: true);
    await go(tester, AppSection.review);

    expect(screen(AppSection.home), findsNothing);
    expect(opacity(tester, AppSection.review), 1);
    expect(offsetY(tester, AppSection.review), 0);
    await tester.pump();
    expect(highlightY(tester), itemY(tester, AppSection.review));
  });

  testWidgets('R13 · nothing asks for frames once the change is over', (
    tester,
  ) async {
    await pumpShell(tester);
    await go(tester, AppSection.specs);
    await finish(tester);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
