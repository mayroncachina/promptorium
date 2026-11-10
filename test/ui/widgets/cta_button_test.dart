import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/theme/ambient.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/widgets/cta_button.dart';

/// SPEC-053 R1–R6: the "Nova spec" call to action.
void main() {
  setUp(() => AppMotion.enabled = true);
  tearDown(() => AppMotion.enabled = false);

  var taps = 0;
  Widget app({bool attention = false, bool reduced = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: Center(
          child: CtaButton(
            label: 'Nova spec',
            attention: attention,
            onTap: () => taps++,
          ),
        ),
      ),
    ),
  );

  double plusAngle(WidgetTester tester) {
    final m = tester
        .widget<Transform>(find.byKey(const ValueKey('cta-plus')))
        .transform;
    return math.atan2(m.entry(1, 0), m.entry(0, 0));
  }

  Future<TestGesture> hover(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(CtaButton)));
    return mouse;
  }

  testWidgets('hover: the plus turns 90° and a light crosses once; leaving '
      'goes back to rest (R1)', (tester) async {
    await tester.pumpWidget(app());
    final mouse = await hover(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('cta-sheen')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(plusAngle(tester), closeTo(math.pi / 2, .01));
    expect(find.byKey(const ValueKey('cta-sheen')), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);

    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(plusAngle(tester), closeTo(0, .01));
    expect(find.byKey(const ValueKey('cta-sheen')), findsNothing);
  });

  testWidgets('press shrinks to 97% and the tap is not delayed (R2)', (
    tester,
  ) async {
    taps = 0;
    await tester.pumpWidget(app());
    final g = await tester.startGesture(
      tester.getCenter(find.byType(CtaButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .97);
    await g.up();
    await tester.pump();
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('keyboard focus shows the ring and Enter activates (R3)', (
    tester,
  ) async {
    taps = 0;
    await tester.pumpWidget(app());
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final ring = tester.widget<Container>(
      find.byKey(const ValueKey('cta-focus-ring')),
    );
    final border = (ring.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, CtaButton.focusRing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 1);
  });

  testWidgets('attention breathes on the ambient clock and stops for good '
      'once hovered (R4, R6)', (tester) async {
    await tester.pumpWidget(app(attention: true));
    expect(AmbientTicker.debugActive, greaterThan(0));
    final mouse = await hover(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(AmbientTicker.debugActive, 0);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(AmbientTicker.debugActive, 0);
  });

  testWidgets('at rest, without attention, it asks for no frame (R6)', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(AmbientTicker.debugActive, 0);
  });

  testWidgets('reduced motion: no turn, no light, no breath (R5)', (
    tester,
  ) async {
    await tester.pumpWidget(app(attention: true, reduced: true));
    expect(AmbientTicker.debugActive, 0);
    await hover(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('cta-sheen')), findsNothing);
    expect(plusAngle(tester), closeTo(0, .01));
  });
}
