import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/theme/tokens.dart';
import 'package:promptorium/ui/widgets/app_pressable.dart';

const box = Key('box');

void motionOn() {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
}

Widget app(Widget child, {bool reduced = false}) => MaterialApp(
  theme: AppTheme.dark(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: Center(child: child)),
  ),
);

Widget pressable({void Function()? onTap, bool enabled = true}) => AppPressable(
  enabled: enabled,
  hoverTint: AppPressable.tint,
  hoverBorder: AppColors.borderHover,
  child: Material(
    child: InkWell(
      key: box,
      onTap: onTap,
      child: const SizedBox(width: 120, height: 40),
    ),
  ),
);

/// No ink: its own fade would keep `hasRunningAnimations` true.
Widget plain() => AppPressable(
  hoverTint: AppPressable.tint,
  child: ColoredBox(
    key: box,
    color: AppColors.panel,
    child: const SizedBox(width: 120, height: 40),
  ),
);

/// The horizontal scale of the [AppPressable].
double scaleOf(WidgetTester tester, [Finder? at]) => tester
    .widget<Transform>(
      find
          .descendant(
            of: at ?? find.byType(AppPressable).first,
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .storage[0];

/// Opacity of the layer over the child.
double hoverOf(WidgetTester tester, [Finder? at]) {
  final fades = find.descendant(
    of: at ?? find.byType(AppPressable).first,
    matching: find.byType(FadeTransition),
  );
  return tester.widget<FadeTransition>(fades.last).opacity.value;
}

Future<TestGesture> mouseOver(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(target));
  return mouse;
}

void main() {
  testWidgets('R6 · press scales to 0,98 without changing the layout, and '
      'release brings it back', (tester) async {
    motionOn();
    await tester.pumpWidget(app(plain()));
    final size = tester.getSize(find.byType(AppPressable));
    final topLeft = tester.getTopLeft(find.byType(AppPressable));
    expect(size, const Size(120, 40));
    expect(scaleOf(tester), 1);

    final press = await tester.startGesture(tester.getCenter(find.byKey(box)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final midway = scaleOf(tester);
    expect(midway, lessThan(1));
    expect(midway, greaterThan(AppPressable.pressedScale));
    await tester.pump(AppMotion.quick);
    expect(scaleOf(tester), closeTo(AppPressable.pressedScale, 1e-6));
    expect(tester.getSize(find.byType(AppPressable)), size);
    expect(tester.getTopLeft(find.byType(AppPressable)), topLeft);

    await press.up();
    await tester.pump();
    await tester.pump(AppMotion.quickExit);
    expect(scaleOf(tester), 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('R6 · the size of the wrapped button is the same as without the '
      'wrapper', (tester) async {
    Widget button(double? width) => SizedBox(
      width: width,
      child: AppPressable(
        child: FilledButton(onPressed: () {}, child: const Text('Executar')),
      ),
    );
    await tester.pumpWidget(app(button(null)));
    final wrapped = tester.getSize(find.byType(AppPressable));
    await tester.pumpWidget(
      app(FilledButton(onPressed: () {}, child: const Text('Executar'))),
    );
    expect(tester.getSize(find.byType(FilledButton)), wrapped);
  });

  testWidgets('R6 · hover fades in quick and leaves in quickExit', (
    tester,
  ) async {
    motionOn();
    await tester.pumpWidget(app(plain()));
    expect(hoverOf(tester), 0);

    final mouse = await mouseOver(tester, find.byKey(box));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(hoverOf(tester), inExclusiveRange(0, 1));
    await tester.pump(AppMotion.quick);
    expect(hoverOf(tester), 1);

    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    await tester.pump(AppMotion.quickExit);
    expect(hoverOf(tester), 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R11 · with reduced motion hover and press show the final state '
      'at once', (tester) async {
    motionOn();
    await tester.pumpWidget(app(plain(), reduced: true));

    final mouse = await mouseOver(tester, find.byKey(box));
    await tester.pump();
    expect(hoverOf(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);

    await mouse.down(tester.getCenter(find.byKey(box)));
    await tester.pump();
    expect(scaleOf(tester), closeTo(AppPressable.pressedScale, 1e-6));
    expect(tester.hasRunningAnimations, isFalse);

    await mouse.up();
    await tester.pump();
    expect(scaleOf(tester), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('R12 · a tap during the press animation counts, and a release '
      'midway leaves from the current scale', (tester) async {
    motionOn();
    var taps = 0;
    await tester.pumpWidget(app(pressable(onTap: () => taps++)));

    final press = await tester.startGesture(tester.getCenter(find.byKey(box)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final midway = scaleOf(tester);
    await press.up();
    expect(taps, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(scaleOf(tester), inInclusiveRange(midway, 1));
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
  });

  testWidgets('disabled: no hover and no press', (tester) async {
    await tester.pumpWidget(app(pressable(enabled: false)));
    final mouse = await mouseOver(tester, find.byKey(box));
    await tester.pump();
    await mouse.down(tester.getCenter(find.byKey(box)));
    await tester.pump();
    expect(hoverOf(tester), 0);
    expect(scaleOf(tester), 1);
    await mouse.up();
  });

  testWidgets('the secondary button does not press', (tester) async {
    await tester.pumpWidget(app(pressable(onTap: () {})));
    final press = await tester.startGesture(
      tester.getCenter(find.byKey(box)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(scaleOf(tester), 1);
    await press.up();
  });

  testWidgets('a press on a nested control scales only that control', (
    tester,
  ) async {
    const outer = Key('outer');
    const menu = Key('menu');
    await tester.pumpWidget(
      app(
        AppPressable(
          key: outer,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmallButton(label: 'Abrir', onTap: () {}),
              Listener(
                onPointerDown: AppPressable.claim,
                child: const ColoredBox(
                  key: menu,
                  color: AppColors.panel,
                  child: SizedBox(width: 30, height: 30),
                ),
              ),
              const ColoredBox(
                key: box,
                color: AppColors.panel,
                child: SizedBox(width: 30, height: 30),
              ),
            ],
          ),
        ),
      ),
    );
    final inner = find.byType(AppPressable).last;

    var press = await tester.startGesture(tester.getCenter(find.text('Abrir')));
    await tester.pump();
    expect(scaleOf(tester, inner), closeTo(AppPressable.pressedScale, 1e-6));
    expect(scaleOf(tester, find.byKey(outer)), 1);
    await press.up();
    await tester.pump();

    press = await tester.startGesture(tester.getCenter(find.byKey(menu)));
    await tester.pump();
    expect(scaleOf(tester, find.byKey(outer)), 1);
    await press.up();
    await tester.pump();

    press = await tester.startGesture(tester.getCenter(find.byKey(box)));
    await tester.pump();
    expect(
      scaleOf(tester, find.byKey(outer)),
      closeTo(AppPressable.pressedScale, 1e-6),
    );
    await press.up();
  });

  testWidgets('a Draggable around it still drags and taps, and the pointer '
      'that outlives the card does not throw', (tester) async {
    motionOn();
    var taps = 0;
    var dropped = 0;
    await tester.pumpWidget(
      app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Draggable<int>(
              data: 1,
              feedback: const SizedBox(width: 120, height: 40),
              childWhenDragging: const SizedBox(width: 120, height: 40),
              child: pressable(onTap: () => taps++),
            ),
            const SizedBox(height: 40),
            DragTarget<int>(
              onAcceptWithDetails: (_) => dropped++,
              builder: (_, _, _) =>
                  const SizedBox(key: Key('target'), width: 120, height: 40),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(box));
    await tester.pumpAndSettle();
    expect(taps, 1);

    final drag = await tester.startGesture(tester.getCenter(find.byKey(box)));
    await tester.pump(const Duration(milliseconds: 20));
    final target = tester.getCenter(find.byKey(const Key('target')));
    await drag.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(find.byKey(box), findsNothing);
    await drag.moveTo(target);
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(dropped, 1);
    expect(taps, 1);
    expect(scaleOf(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R6 · focus reaches the InkWell at once: the wrapper adds no '
      'focus node, and semantics stay those of the button', (tester) async {
    motionOn();
    final handle = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      app(
        AppPressable(
          child: Material(
            child: InkWell(
              focusNode: focus,
              onTap: () {},
              child: const SizedBox(width: 120, height: 40, child: Text('Ir')),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    expect(
      tester.getSemantics(find.text('Ir')),
      matchesSemantics(
        label: 'Ir',
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('the InkWell of SmallButton and AmberButton leaves hover to the '
      'layer and keeps the focus colour', (tester) async {
    await tester.pumpWidget(
      app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SmallButton(
              label: 'A',
              onTap: () {},
              focusColor: AppColors.amberTint,
            ),
            AmberButton(label: 'B', onTap: () {}),
          ],
        ),
      ),
    );
    final wells = tester.widgetList<InkWell>(find.byType(InkWell)).toList();
    expect(wells.map((w) => w.hoverColor), everyElement(Colors.transparent));
    expect(wells.map((w) => w.hoverDuration), everyElement(isNull));
    expect(wells.first.focusColor, AppColors.amberTint);
  });

  testWidgets(
    'theme · a FilledButton gets the hover layer, with no ink hover',
    (tester) async {
      motionOn();
      await tester.pumpWidget(
        app(FilledButton(onPressed: () {}, child: const Text('Executar'))),
      );
      double tint() => tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(HoverLayer),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;
      expect(tint(), 0);
      await mouseOver(tester, find.byType(FilledButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(tint(), inExclusiveRange(0, 1));
      await tester.pump(AppMotion.quick);
      expect(tint(), 1);
      expect(
        AppTheme.filledOverlay.resolve({WidgetState.hovered}),
        Colors.transparent,
      );
      expect(
        AppTheme.filledOverlay.resolve({WidgetState.focused})?.a,
        closeTo(.1, .01),
      );
    },
  );
}
