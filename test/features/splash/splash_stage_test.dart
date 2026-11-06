import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/splash/splash_painter.dart';
import 'package:promptorium/features/splash/splash_stage.dart';
import 'package:promptorium/ui/theme/motion.dart';

SplashTimeline _timeline(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(SplashStage),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as SplashPainter)
        .timeline();

void main() {
  group('SplashTimeline', () {
    const end = SplashTimeline.introSeconds;

    void expectFinalFrame(SplashTimeline tl) {
      for (var i = 0; i < 3; i++) {
        expect(tl.bubble(i).opacity, 0);
        expect(tl.nodeScale(i), 1);
      }
      expect(tl.stageOpacity, 1);
      expect(tl.titleOpacity, 1);
      expect(tl.liquidDy, 0);
      expect(tl.links, 1);
      expect(tl.caretOpacity, 1);
      expect(tl.glowOpacity, closeTo(.55, 1e-9));
    }

    test('R3 · reduced motion is the final frame, without the bubbles', () {
      for (final t in [0.0, 1.0, 50.0]) {
        expectFinalFrame(SplashTimeline(elapsed: t, reducedMotion: true));
      }
    });

    test('R2 · loop: false ends in the same frame, and it stays still', () {
      const reduced = SplashTimeline(elapsed: 0, reducedMotion: true);
      for (final t in [end, end + 3.3, end + 40]) {
        final tl = SplashTimeline(elapsed: t, loop: false);
        expectFinalFrame(tl);
        expect(tl.waveDx, reduced.waveDx);
      }
    });

    test('R2 · loop: false plays the intro as the splash does', () {
      for (final t in [0.1, 0.8, 1.5, 2.0]) {
        final a = SplashTimeline(elapsed: t);
        final b = SplashTimeline(elapsed: t, loop: false);
        expect(b.outline, a.outline);
        expect(b.liquidDy, a.liquidDy);
        expect(b.titleOpacity, a.titleOpacity);
        expect(b.nodeScale(0), a.nodeScale(0));
        expect(b.waveDx, a.waveDx);
        expect(b.bubble(0), a.bubble(0));
      }
    });

    test('the bubbles leave before the end, without a jump', () {
      const before = SplashTimeline(elapsed: end - 0.01, loop: false);
      expect(before.bubble(1).opacity, lessThan(0.05));
    });

    test('the splash keeps its loop after the intro', () {
      const a = SplashTimeline(elapsed: end + 1);
      const b = SplashTimeline(elapsed: end + 2);
      expect(a.waveDx, isNot(b.waveDx));
      expect(a.bubble(0), isNot(b.bubble(0)));
      expect(a.glowOpacity, isNot(b.glowOpacity));
    });
  });

  group('SplashStage', () {
    setUp(() => AppMotion.enabled = true);
    tearDown(() => AppMotion.enabled = false);

    int tickers() => SchedulerBinding.instance.transientCallbackCount;

    Widget stage({required bool loop, bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: Center(child: SplashStage(loop: loop)),
        ),
      ),
    );

    testWidgets('loop keeps the ticker running after the intro', (
      tester,
    ) async {
      await tester.pumpWidget(stage(loop: true));
      await tester.pump(SplashTimeline.introDuration * 3);
      await tester.pump();
      expect(tickers(), greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      expect(tickers(), 0);
    });

    testWidgets('loop: false stops the ticker at the end of the intro', (
      tester,
    ) async {
      await tester.pumpWidget(stage(loop: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tickers(), greaterThan(0));
      await tester.pump(SplashTimeline.introDuration);
      await tester.pump();
      expect(tickers(), 0);
      expect(_timeline(tester).bubble(0).opacity, 0);
      expect(_timeline(tester).glowOpacity, closeTo(.55, 1e-9));
    });

    testWidgets('leaving the tree before the end stops the ticker', (
      tester,
    ) async {
      await tester.pumpWidget(stage(loop: false));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      expect(tickers(), 0);
    });

    for (final loop in [true, false]) {
      testWidgets('R3 · reduced motion runs no ticker (loop: $loop)', (
        tester,
      ) async {
        await tester.pumpWidget(stage(loop: loop, reduced: true));
        expect(tickers(), 0);
        final tl = _timeline(tester);
        expect(tl.stageOpacity, 1);
        expect(tl.bubble(0).opacity, 0);
      });
    }

    testWidgets('R11 · the mark has a label and the drawing adds nothing', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(stage(loop: false));
      expect(find.bySemanticsLabel('Ícone do Promptorium'), findsOneWidget);
      expect(find.bySemanticsLabel('Promptorium'), findsOneWidget);
      semantics.dispose();
    });
  });
}
