import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/theme/ambient.dart';

/// A loop on the ambient clock; counts its ticks.
class _Loop extends StatefulWidget {
  const _Loop({required this.onTick});

  final VoidCallback onTick;

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c ??=
        AnimationController(
            vsync: AmbientVsync(context),
            duration: const Duration(seconds: 1),
          )
          ..addListener(widget.onTick)
          ..repeat();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('an ambient loop ticks ~24 times a second, not 60', (
    tester,
  ) async {
    var ticks = 0;
    await tester.pumpWidget(_Loop(onTick: () => ticks++));
    ticks = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(ticks, inInclusiveRange(18, 26));
  });

  testWidgets('a muted TickerMode stops the ambient loop', (tester) async {
    var ticks = 0;
    await tester.pumpWidget(
      TickerMode(enabled: false, child: _Loop(onTick: () => ticks++)),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ticks, 0);
  });

  testWidgets('disposing the loop leaves no timer behind', (tester) async {
    await tester.pumpWidget(_Loop(onTick: () {}));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    // The test binding fails the test if a timer is still pending.
  });

  testWidgets('AmbientSpinner is still with reduced motion', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AmbientSpinner(),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Transform), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
