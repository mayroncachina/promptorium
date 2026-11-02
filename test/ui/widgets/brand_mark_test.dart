import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/widgets/brand_mark.dart';

/// SPEC-031 R2, R4: the mark in vector and the splash's ambient loop.
void main() {
  testWidgets('paints still and animated at 16, 26 and 64 px (R2)', (
    tester,
  ) async {
    final wave = AnimationController(vsync: tester, duration: brandMotionCycle)
      ..value = .4;
    addTearDown(wave.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            for (final s in [16.0, 26.0, 64.0]) ...[
              BrandMark(size: s),
              BrandMark(size: s, wave: wave),
            ],
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BrandMark).at(2)), const Size(26, 26));
  });

  test('the cycle is 2.4 s and the wave runs one wavelength (R4)', () {
    expect(brandMotionCycle, const Duration(milliseconds: 2400));
    expect(brandWaveOffset(0), 0);
    expect(brandWaveOffset(1), -brandWaveLength);
  });

  test('bubbles are 0.8 s apart, grow .6 → 1 and rise to the neck (R4)', () {
    final b0 = brandBubble(0, 0);
    expect(b0.opacity, 0);
    expect(b0.scale, closeTo(.6, 1e-9));
    // Bubble 1 starts 0.8 s (1/3 of the cycle) after bubble 0.
    final a = brandBubble(0, .1), b1 = brandBubble(1, 1 / 3 + .1);
    expect(b1.opacity, closeTo(a.opacity, 1e-6));
    expect(b1.dy, closeTo(a.dy, 1e-6));
    // Somewhere in the loop a visible bubble reaches the neck (y ≤ 110).
    var top = double.infinity;
    for (var i = 0; i <= 240; i++) {
      final t = i / 240;
      for (final (j, (_, y, _)) in brandBubbles.indexed) {
        final b = brandBubble(j, t);
        if (b.opacity > .3) top = top < y + b.dy ? top : y + b.dy;
      }
    }
    expect(top, lessThanOrEqualTo(110));
  });

  test('each molecule node pops to 1.18, one after the other (R4)', () {
    var peak = 0.0;
    for (var i = 0; i <= 240; i++) {
      final s = brandNodeScale(0, i / 240);
      if (s > peak) peak = s;
    }
    expect(peak, closeTo(1.18, .005));
    expect(brandNodeScale(1, 0), 1); // node 1 waits 0.18 s
    expect(brandNodeScale(1, .18 / 2.4 + .15 / 2.4), closeTo(1.18, .005));
    expect(brandNodeScale(0, .5), 1);
  });
}
