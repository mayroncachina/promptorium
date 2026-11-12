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
        final tl = SplashTimeline(elapsed: t, ambient: SplashAmbient.none);
        expectFinalFrame(tl);
        expect(tl.waveDx, reduced.waveDx);
      }
    });

    test('R2 · loop: false plays the intro as the splash does', () {
      for (final t in [0.1, 0.8, 1.5, 2.0]) {
        final a = SplashTimeline(elapsed: t);
        final b = SplashTimeline(elapsed: t, ambient: SplashAmbient.none);
        expect(b.outline, a.outline);
        expect(b.liquidDy, a.liquidDy);
        expect(b.titleOpacity, a.titleOpacity);
        expect(b.nodeScale(0), a.nodeScale(0));
        expect(b.waveDx, a.waveDx);
        expect(b.bubble(0), a.bubble(0));
      }
    });

    test('the bubbles leave before the end, without a jump', () {
      const before = SplashTimeline(
        elapsed: end - 0.01,
        ambient: SplashAmbient.none,
      );
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

    Widget stage({
      bool loop = true,
      SplashAmbient? ambient,
      bool reduced = false,
      bool excited = false,
      bool paused = false,
      Key? key,
    }) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: Center(
            child: SplashStage(
              key: key,
              loop: loop,
              ambient: ambient,
              excited: excited,
              paused: paused,
            ),
          ),
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
      await tester.pumpWidget(stage(ambient: SplashAmbient.none));
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
      await tester.pumpWidget(stage(ambient: SplashAmbient.none));
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
      await tester.pumpWidget(stage(ambient: SplashAmbient.none));
      expect(find.bySemanticsLabel('Ícone do Promptorium'), findsOneWidget);
      expect(find.bySemanticsLabel('Promptorium'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('SPEC-066 · SplashTimeline', () {
    const end = SplashTimeline.introSeconds;

    test(
      'R2 · calm: the wave takes 4.4 s and the glow breathes 35–55% in 4 s',
      () {
        expect(SplashTimeline.wavePeriod(SplashAmbient.calm, 0), 4.4);
        expect(SplashTimeline.wavePeriod(SplashAmbient.calm, 1), 2.2);
        expect(SplashTimeline.wavePeriod(SplashAmbient.lively, 0), 2.2);
        double glow(double s) => SplashTimeline(
          elapsed: end,
          ambient: SplashAmbient.calm,
          ambientClock: end + s,
        ).glowOpacity;
        expect(glow(0), closeTo(.35, 1e-9));
        expect(glow(2), closeTo(.55, 1e-9));
        expect(glow(4), closeTo(.35, 1e-9));
      },
    );

    test('R2 · calm: one bubble at a time, every 2.4 s, the three in turn', () {
      for (var s = 0.05; s < 14.4; s += 0.1) {
        final tl = SplashTimeline(
          elapsed: end,
          ambient: SplashAmbient.calm,
          ambientClock: end + s,
        );
        final shown = tl.bubbles().map((b) => b.i).toSet();
        expect(shown.length, lessThanOrEqualTo(1), reason: 't=$s');
        if (shown.isNotEmpty) {
          expect(shown.single, (s ~/ 2.4) % 3, reason: 't=$s');
        }
      }
    });

    test('R3 · calm: the nodes stay still and unlit', () {
      final tl = SplashTimeline(
        elapsed: end,
        ambient: SplashAmbient.calm,
        ambientClock: end + 5,
      );
      for (var i = 0; i < 3; i++) {
        expect(tl.nodeScale(i), 1);
        expect(tl.nodeLight(i), 0);
      }
    });

    test('R4 · agitated: the three bubbles and the nodes light up smallest '
        'to largest', () {
      SplashTimeline at(double s, [double excite = 1]) => SplashTimeline(
        elapsed: end,
        ambient: SplashAmbient.calm,
        ambientClock: 10 + s,
        excite: excite,
      );
      // node 2 (smallest) peaks first, then node 0, then node 1 (largest)
      double peak(int i) {
        var best = 0.0, at_ = 0.0;
        for (var s = 0.0; s < 0.9; s += 0.01) {
          final v = at(s).nodeLight(i);
          if (v > best) {
            best = v;
            at_ = s;
          }
        }
        return at_;
      }

      final p2 = peak(2), p0 = peak(0), p1 = peak(1);
      expect([p2, p0, p1].map((p) => (p - p2 + 0.9) % 0.9).toList(), [
        closeTo(0, .02),
        closeTo(.3, .02),
        closeTo(.6, .02),
      ]);
      expect(at(.5).bubbles().map((b) => b.i).toSet().length, 3);
      expect(at(.5, 0).nodeLight(0), 0);
    });

    test(
      'R5 · a replay draws the flask again but keeps the stage and title',
      () {
        const tl = SplashTimeline(
          elapsed: 0.1,
          ambient: SplashAmbient.calm,
          ambientClock: 30,
          replaying: true,
        );
        expect(tl.outline, lessThan(1));
        expect(tl.stageOpacity, 1);
        expect(tl.titleOpacity, 1);
      },
    );

    test('R8 · reduced motion stays still in every ambient', () {
      for (final a in SplashAmbient.values) {
        final tl = SplashTimeline(
          elapsed: 3,
          reducedMotion: true,
          ambient: a,
          excite: 1,
        );
        expect(tl.bubbles(), isEmpty);
        expect(tl.nodeLight(0), 0);
        expect(tl.liquidDy, 0);
      }
    });

    test('R9 · the splash keeps its own rhythm and never lights the nodes', () {
      const tl = SplashTimeline(elapsed: end + 3, excite: 1);
      expect(tl.nodeLight(0), 0);
      expect(tl.bubbles().map((b) => b.i).toSet().length, greaterThan(1));
    });
  });

  group('SPEC-066 · SplashStage', () {
    setUp(() => AppMotion.enabled = true);
    tearDown(() => AppMotion.enabled = false);

    int tickers() => SchedulerBinding.instance.transientCallbackCount;

    Widget calm({
      Key? key,
      bool excited = false,
      bool paused = false,
      bool reduced = false,
    }) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: Center(
            child: SplashStage(
              key: key,
              ambient: SplashAmbient.calm,
              excited: excited,
              paused: paused,
            ),
          ),
        ),
      ),
    );

    testWidgets('R2 · calm keeps the ticker after the intro', (tester) async {
      await tester.pumpWidget(calm());
      await tester.pump(SplashTimeline.introDuration * 2);
      await tester.pump();
      expect(tickers(), greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      expect(tickers(), 0);
    });

    testWidgets('R4 · the mouse blends into the agitated rhythm in 400 ms', (
      tester,
    ) async {
      await tester.pumpWidget(calm());
      await tester.pump(SplashTimeline.introDuration);
      await tester.pumpWidget(calm(excited: true));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_timeline(tester).excite, closeTo(.5, .1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_timeline(tester).excite, 1);
      await tester.pumpWidget(calm());
      await tester.pump(const Duration(milliseconds: 450));
      expect(_timeline(tester).excite, 0);
    });

    testWidgets('R5 · replay plays the intro again, and a second call in the '
        'middle does not restart it', (tester) async {
      final key = GlobalKey<SplashStageState>();
      await tester.pumpWidget(calm(key: key));
      await tester.pump(SplashTimeline.introDuration);
      await tester.pump();
      expect(_timeline(tester).outline, 1);
      key.currentState!.replay();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = _timeline(tester).elapsed;
      expect(_timeline(tester).outline, lessThan(1));
      expect(_timeline(tester).stageOpacity, 1);
      expect(key.currentState!.introPlaying, isTrue);
      key.currentState!.replay();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_timeline(tester).elapsed, greaterThan(mid));
      await tester.pump(SplashTimeline.introDuration);
      expect(key.currentState!.introPlaying, isFalse);
      expect(_timeline(tester).outline, 1);
    });

    testWidgets('R7 · paused stops the ticker and goes on from where it was', (
      tester,
    ) async {
      await tester.pumpWidget(calm());
      await tester.pump(SplashTimeline.introDuration);
      await tester.pumpWidget(calm(paused: true));
      expect(tickers(), 0);
      final clock = _timeline(tester).clock;
      await tester.pump(const Duration(seconds: 2));
      expect(_timeline(tester).clock, clock);
      await tester.pumpWidget(calm());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tickers(), greaterThan(0));
      expect(_timeline(tester).clock, closeTo(clock + .1, .02));
    });

    testWidgets('R7 · the window out of focus stops the ticker', (
      tester,
    ) async {
      await tester.pumpWidget(calm());
      await tester.pump(SplashTimeline.introDuration);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(tickers(), 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tickers(), greaterThan(0));
    });

    testWidgets('R8 · with animations off nothing runs, replay included', (
      tester,
    ) async {
      final key = GlobalKey<SplashStageState>();
      await tester.pumpWidget(calm(key: key, reduced: true, excited: true));
      expect(tickers(), 0);
      key.currentState!.replay();
      await tester.pump();
      expect(tickers(), 0);
      expect(_timeline(tester).bubbles(), isEmpty);
    });
  });
}
