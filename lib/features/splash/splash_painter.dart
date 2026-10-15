import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../../ui/theme/tokens.dart';
import '../../ui/widgets/svg_path.dart';

/// Timeline of the splash animation, reproduced from docs/mockups/Splash.dc.html.
///
/// The mockup keyframes are percentages of a 7 s loop. Here the intro plays
/// once at [introSpeed]× (≈2.6 s) and only the ambient parts loop (wave,
/// bubbles, caret, glow pulse) in real time.
class SplashTimeline {
  const SplashTimeline({required this.elapsed, this.reducedMotion = false});

  /// Real seconds since the splash appeared.
  final double elapsed;

  /// `MediaQuery.disableAnimations`: everything in its final state.
  final bool reducedMotion;

  static const cycle = 7.0; // mockup loop length (s)
  static const introEnd = 4.48; // 64% of 7 s: last keyframe (links) done
  static const introSpeed = 1.75;

  /// Real duration of the intro.
  static Duration get introDuration =>
      Duration(milliseconds: (introEnd / introSpeed * 1000).round());

  /// Time in mockup seconds, clamped to the end of the intro.
  double get _t =>
      reducedMotion ? introEnd : math.min(elapsed * introSpeed, introEnd);

  /// Progress of the keyframe segment [fromPct]→[toPct] (percent of 7 s).
  double _seg(double fromPct, double toPct, [Curve curve = Curves.easeOut]) {
    final from = fromPct / 100 * cycle, to = toPct / 100 * cycle;
    final v = ((_t - from) / (to - from)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  // .pm-stage 0%→5%: opacity 0→1, scale .96→1
  double get stageOpacity => _seg(0, 5, Curves.easeInOut);
  double get stageScale => 0.96 + 0.04 * _seg(0, 5, Curves.easeInOut);

  // .pm-draw 0%→20%
  double get outline => _seg(0, 20);

  // .pm-liquid 14%→42%: translateY 62→0
  double get liquidDy => 62 * (1 - _seg(14, 42, const Cubic(.3, .7, .2, 1)));

  // .pm-wave: translateX 0→-60 every 2.2 s, linear
  double get waveDx => reducedMotion ? 0 : -60 * ((elapsed % 2.2) / 2.2);

  // .pm-title 24%→34%
  double get titleOpacity => _seg(24, 34);
  double get titleDy => 6 * (1 - _seg(24, 34));

  // .pm-chev 40%→48%
  double get chevOpacity => _seg(40, 48);
  double get chevDx => -6 * (1 - _seg(40, 48));

  /// .pm-node 46%→53%: 0→1.18, 53%→57%: 1.18→1; delays .18 s / .36 s.
  double nodeScale(int i) {
    if (reducedMotion) return 1;
    final t = _t - i * 0.18;
    final a = 0.46 * cycle, b = 0.53 * cycle, c = 0.57 * cycle;
    if (t <= a) return 0;
    if (t < b) return 1.18 * Curves.easeOut.transform((t - a) / (b - a));
    if (t < c) return 1.18 - 0.18 * Curves.easeOut.transform((t - b) / (c - b));
    return 1;
  }

  // .pm-link 55%→64%
  double get links => _seg(55, 64);

  /// .pm-glow 40%→60%: 0→.55, then a slow pulse instead of fading out.
  double get glowOpacity {
    final rise = _seg(40, 60, Curves.easeInOut) * 0.55;
    if (reducedMotion || _t < introEnd) return rise;
    final since = elapsed - introDuration.inMilliseconds / 1000;
    return 0.45 + 0.10 * math.cos(since * 2 * math.pi / 3.5);
  }

  /// .pm-caret: steps(1) blink, 1 s period.
  double get caretOpacity => reducedMotion || (elapsed % 1.0) < 0.5 ? 1 : 0;

  /// .pm-bubble i: 2.4 s ease-in; delays 0, .8, 1.6 s.
  ({double dy, double scale, double opacity}) bubble(int i) {
    if (reducedMotion) return (dy: 0, scale: 1, opacity: 1);
    final t = elapsed - i * 0.8;
    if (t < 0) return (dy: 0, scale: .6, opacity: 0);
    final p = (t % 2.4) / 2.4;
    final e = Curves.easeIn.transform(p);
    double opacity;
    if (p < .2) {
      opacity = Curves.easeIn.transform(p / .2);
    } else if (p < .8) {
      opacity = 1 - .1 * Curves.easeIn.transform((p - .2) / .6);
    } else {
      opacity = .9 * (1 - Curves.easeIn.transform((p - .8) / .2));
    }
    return (dy: -46 * e, scale: .6 + .4 * e, opacity: opacity);
  }
}

/// Paints the flask icon (SVG viewBox 200×200) into a square canvas.
class SplashPainter extends CustomPainter {
  SplashPainter({required this.timeline, super.repaint});

  final SplashTimeline Function() timeline;

  // Paths copied verbatim from docs/mockups/Splash.dc.html.
  static final _inside = parseSvgPath(
    'M91 78 V104 L52 162 Q47 170 57 170 H143 Q153 170 148 162 L109 104 V78 Z',
  );
  static const _waveD =
      'M0 124 Q15 118 30 124 T60 124 T90 124 T120 124 T150 124 T180 124 '
      'T210 124 T240 124 T270 124';
  static final _waveFill = parseSvgPath('$_waveD V200 H0 Z');
  static final _waveLine = parseSvgPath(_waveD);
  static final _chev = parseSvgPath('M78 136 L92 145 L78 154');
  static final _caret = RRect.fromRectAndRadius(
    const Rect.fromLTWH(98, 151, 22, 5),
    const Radius.circular(2),
  );
  static final _outline = parseSvgPath(
    'M84 70 H116 M91 72 V104 L50 164 Q44 176 58 176 H142 Q156 176 150 164 '
    'L109 104 V72',
  );
  static final _links = parseSvgPath(
    '${svgLine(89, 47, 109, 35)} ${svgLine(118, 42, 116, 52)}',
  );
  static const _bubbles = [
    (100.0, 118.0, 5.0),
    (94.0, 122.0, 3.5),
    (104.0, 120.0, 2.5),
  ];
  static const _nodes = [
    (82.0, 51.0, 9.0, 4.5),
    (119.0, 30.0, 12.0, 4.5),
    (115.0, 58.0, 6.5, 4.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final tl = timeline();

    // Glow: `inset: 24px` circle blurred 42px (in widget pixels, 168 box).
    final glow = tl.glowOpacity;
    if (glow > 0) {
      final unit = size.width / 168;
      canvas.drawCircle(
        size.center(Offset.zero),
        (168 / 2 - 24) * unit,
        Paint()
          ..color = AppColors.teal.withValues(alpha: glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 42 * unit),
      );
    }

    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);

    // Liquid + bubbles, clipped to the flask interior.
    canvas.save();
    canvas.clipPath(_inside);
    canvas.save();
    canvas.translate(tl.waveDx, tl.liquidDy);
    canvas.drawPath(_waveFill, Paint()..color = AppColors.liquid);
    canvas.drawPath(
      _waveLine,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.teal,
    );
    canvas.restore();
    for (var i = 0; i < _bubbles.length; i++) {
      final (cx, cy, r) = _bubbles[i];
      final b = tl.bubble(i);
      if (b.opacity <= 0) continue;
      canvas.drawCircle(
        Offset(cx, cy + b.dy),
        r * b.scale,
        Paint()..color = AppColors.bubble.withValues(alpha: b.opacity),
      );
    }
    canvas.restore();

    // Prompt chevron `>` and caret `_`.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (tl.chevOpacity > 0) {
      canvas.save();
      canvas.translate(tl.chevDx, 0);
      canvas.drawPath(
        _chev,
        stroke
          ..strokeWidth = 5.5
          ..color = AppColors.glowText.withValues(alpha: tl.chevOpacity),
      );
      canvas.restore();
    }
    if (tl.caretOpacity > 0) {
      canvas.drawRRect(
        _caret,
        Paint()..color = AppColors.glowText.withValues(alpha: tl.caretOpacity),
      );
    }

    // Flask outline drawing itself.
    _drawPartial(
      canvas,
      _outline,
      tl.outline,
      stroke
        ..strokeWidth = 8
        ..color = AppColors.amber,
    );

    // Links between nodes.
    _drawPartial(
      canvas,
      _links,
      tl.links,
      stroke
        ..strokeWidth = 4
        ..color = AppColors.amber,
    );

    // Nodes popping with overshoot (scale around their own center).
    for (var i = 0; i < _nodes.length; i++) {
      final s = tl.nodeScale(i);
      if (s <= 0) continue;
      final (cx, cy, r, w) = _nodes[i];
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(s);
      canvas.drawCircle(Offset.zero, r, Paint()..color = AppColors.liquid);
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = AppColors.amber,
      );
      canvas.restore();
    }

    canvas.restore();
  }

  /// Draws the first [fraction] of [path] (like `pathLength=1` +
  /// `stroke-dashoffset`), across all its sub-paths in order.
  static void _drawPartial(Canvas canvas, Path path, double fraction, Paint p) {
    if (fraction <= 0) return;
    if (fraction >= 1) {
      canvas.drawPath(path, p);
      return;
    }
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (a, m) => a + m.length);
    var remaining = total * fraction;
    final out = Path();
    for (final m in metrics) {
      if (remaining <= 0) break;
      out.addPath(m.extractPath(0, math.min(remaining, m.length)), Offset.zero);
      remaining -= m.length;
    }
    canvas.drawPath(out, p);
  }

  @override
  bool shouldRepaint(SplashPainter oldDelegate) => true;
}
