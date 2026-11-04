import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/widgets/app_pressable.dart';
import 'package:promptorium/ui/widgets/motion_enter.dart';

void motionOn() {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
}

Widget app(Widget child, {bool reduced = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduced),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

double opacityOf(WidgetTester tester) =>
    tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;

void main() {
  test('R1 · the tokens: leaving is faster than arriving, in both curves', () {
    expect(AppMotion.quick.inMilliseconds, 120);
    expect(AppMotion.quickExit.inMilliseconds, 80);
    expect(AppMotion.base.inMilliseconds, 160);
    expect(AppMotion.baseExit.inMilliseconds, 110);
    expect(AppMotion.emphasis.inMilliseconds, 220);
    expect(AppMotion.emphasisExit.inMilliseconds, 150);
    expect(AppMotion.section.inMilliseconds, 640);
    expect(AppMotion.enter, const Cubic(.2, .8, .2, 1));
    expect(AppMotion.exit, const Cubic(.4, 0, 1, 1));
  });

  testWidgets('the suite runs with animations off', (tester) async {
    await tester.pumpWidget(app(const MotionEnter(child: SizedBox())));
    expect(opacityOf(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R11 · with reduced motion the duration is zero and the final '
      'state shows at once', (tester) async {
    motionOn();
    late BuildContext ctx;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (c) {
            ctx = c;
            return const MotionEnter(child: SizedBox());
          },
        ),
        reduced: true,
      ),
    );
    expect(AppMotion.animate(ctx), isFalse);
    expect(AppMotion.duration(ctx, AppMotion.section), Duration.zero);
    expect(opacityOf(tester), 1);
  });

  testWidgets('MotionEnter fades in, moves up to its place and stops asking '
      'for frames', (tester) async {
    motionOn();
    await tester.pumpWidget(app(const MotionEnter(child: SizedBox())));
    expect(opacityOf(tester), 0);
    expect(
      tester
          .widget<Transform>(find.byType(Transform))
          .transform
          .getTranslation()
          .y,
      8,
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(AppMotion.base);
    expect(opacityOf(tester), 1);
    expect(
      tester
          .widget<Transform>(find.byType(Transform))
          .transform
          .getTranslation()
          .y,
      0,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R12 · a tap during the entrance already counts', (tester) async {
    motionOn();
    var taps = 0;
    await tester.pumpWidget(
      app(
        MotionEnter(
          duration: AppMotion.section,
          child: GestureDetector(
            onTap: () => taps++,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byType(GestureDetector));
    expect(taps, 1);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(AppMotion.section);
  });

  testWidgets('R13 · with the app idle, hover, press and entrances ask for no '
      'more frames', (tester) async {
    motionOn();
    await tester.pumpWidget(
      app(
        const MotionEnter(
          child: AppPressable(child: SizedBox(width: 100, height: 100)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(AppMotion.base);
    await tester.pump(AppMotion.quick);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
