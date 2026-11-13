import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../../ui/theme/tokens.dart';
import '../../ui/widgets/svg_path.dart';

/// What the flask does after the intro.
enum SplashAmbient {
  /// Stops in the final frame (no bubbles), as in SPEC-038.
  none,

  /// Sobre (SPEC-066 R2, R3): slow wave, one bubble at a time, the glow
  /// breathing. [SplashTimeline.excite] blends it into the splash rhythm
  /// and lights the nodes (R4).
  calm,

  /// The splash: wave every 2.2 s and the three bubbles every 0.8 s.
  lively,
}

/// One bubble to paint: which of the three, its rise and its opacity.
typedef SplashBubble = ({int i, double dy, double scale, double opacity});

/// Timeline of the splash animation, reproduced from docs/mockups/Splash.dc.html.
///
/// The mockup keyframes are percentages of a 7 s loop. Here the intro plays
/// once at [introSpeed]× (≈2.6 s) and only the ambient parts loop (wave,
/// bubbles, caret, glow pulse) in real time.
class SplashTimeline {
  const SplashTimeline({
    required this.elapsed,
    this.reducedMotion = false,
    this.ambient = SplashAmbient.lively,
    this.ambientClock,
    this.wavePhase,
    this.excite = 0,
    this.level,
    this.burst,
    this.replaying = false,
  });

  /// Real seconds since the intro (re)started.
  final double elapsed;

  /// `MediaQuery.disableAnimations`: everything in its final state.
  final bool reducedMotion;

  final SplashAmbient ambient;

  /// Real seconds of the ambient parts; it doesn't restart with a replay of
  /// the intro, so the wave and the bubbles don't jump. Defaults to
  /// [elapsed].
  final double? ambientClock;

  /// Wave position in cycles (one cycle = 60 viewBox px), accumulated by the
  /// stage so that a change of rhythm doesn't jump. Defaults to the splash
  /// rhythm from [clock].
  final double? wavePhase;

  /// 0 (calm) → 1 (agitated, the mouse over the logo): only for
  /// [SplashAmbient.calm].
  final double excite;

  /// Level of the liquid while an update downloads (SPEC-066 R10): 0 empty,
  /// 1 full. Null is full.
  final double? level;

  /// Seconds since the three bubbles were sent up together (R10), or null.
  final double? burst;

  /// A replay of the intro (SPEC-066 R5): only the flask draws itself again;
  /// the stage and the title stay in place.
  final bool replaying;

  static const cycle = 7.0; // mockup loop length (s)
  static const introEnd = 4.48; // 64% of 7 s: last keyframe (links) done
  static const introSpeed = 1.75;
  static const introSeconds = introEnd / introSpeed;

  /// Wave periods: the splash and the calm rhythm (R2: half the speed).
  static const waveLively = 2.2;
  static const waveCalm = 4.4;

  /// Calm bubbles: one every 2.4 s, each of the three in turn.
  static const calmBubbleGap = 2.4;

  /// Glow breathing period of the calm rhythm (35% ↔ 55%).
  static const calmGlowPeriod = 4.0;

  /// The nodes light up one after the other in this period (R4).
  static const nodeLightPeriod = 0.9;

  /// Duration of the burst of the three bubbles (R10).
  static const burstSeconds = 1.2;

  /// Last stretch of the intro where the bubbles leave, when not looping.
  static const _bubblesFade = 0.4;

  /// Real duration of the intro.
  static Duration get introDuration =>
      Duration(milliseconds: (introEnd / introSpeed * 1000).round());

  /// Wave period for a given [excite].
  static double wavePeriod(SplashAmbient ambient, double excite) =>
      ambient == SplashAmbient.calm
      ? waveCalm + (waveLively - waveCalm) * excite
      : waveLively;

  bool get loop => ambient != SplashAmbient.none;

  double get clock => ambientClock ?? elapsed;

  bool get _introDone => elapsed >= introSeconds;

  /// The final frame: nothing here depends on [elapsed] any more.
  bool get _still => reducedMotion || (!loop && _introDone);

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
  double get stageOpacity => replaying ? 1 : _seg(0, 5, Curves.easeInOut);
  double get stageScale =>
      replaying ? 1 : 0.96 + 0.04 * _seg(0, 5, Curves.easeInOut);

  // .pm-draw 0%→20%
  double get outline => _seg(0, 20);

  /// How far the download level sinks the liquid (R10): 62 = empty.
  double get levelDy => level == null ? 0 : 62 * (1 - level!.clamp(0.0, 1.0));

  // .pm-liquid 14%→42%: translateY 62→0, never above the download level
  double get liquidDy =>
      math.max(62 * (1 - _seg(14, 42, const Cubic(.3, .7, .2, 1))), levelDy);

  // .pm-wave: translateX 0→-60 every cycle, linear
  double get waveDx {
    if (_still) return -60 * ((introSeconds % waveLively) / waveLively);
    final phase = wavePhase ?? clock / waveLively;
    return -60 * (phase % 1.0);
  }

  // .pm-title 24%→34%
  double get titleOpacity => replaying ? 1 : _seg(24, 34);
  double get titleDy => replaying ? 0 : 6 * (1 - _seg(24, 34));

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

  /// Order in which the nodes light up: smallest to largest (R4).
  static const _lightOrder = [1, 2, 0]; // node i → slot (node 2 is smallest)

  /// 0→1→0 flash of node [i] while agitated (R4); 0 otherwise.
  double nodeLight(int i) {
    if (_still || ambient != SplashAmbient.calm || excite <= 0) return 0;
    final off = _lightOrder[i] * nodeLightPeriod / 3;
    final p = ((clock - off) % nodeLightPeriod) / nodeLightPeriod;
    final v = p < .18
        ? p / .18
        : p < .45
        ? 1 - (p - .18) / .27
        : 0.0;
    return v * excite;
  }

  // .pm-link 55%→64%
  double get links => _seg(55, 64);

  /// .pm-glow 40%→60%: 0→.55, then a slow pulse instead of fading out.
  double get glowOpacity {
    final rise = _seg(40, 60, Curves.easeInOut) * 0.55;
    if (_still || _t < introEnd) return rise;
    final since = clock - introSeconds;
    if (ambient == SplashAmbient.calm) {
      return 0.45 - 0.10 * math.cos(since * 2 * math.pi / calmGlowPeriod);
    }
    return 0.45 + 0.10 * math.cos(since * 2 * math.pi / 3.5);
  }

  /// .pm-caret: steps(1) blink, 1 s period.
  double get caretOpacity => _still || (clock % 1.0) < 0.5 ? 1 : 0;

  /// A bubble of the splash rhythm: 2.4 s ease-in; delays 0, .8, 1.6 s.
  ({double dy, double scale, double opacity}) _rise(double t) {
    if (t < 0) return (dy: 0, scale: .6, opacity: 0);
    final p = (t % 2.4) / 2.4;
    return _risePct(p);
  }

  static ({double dy, double scale, double opacity}) _risePct(double p) {
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

  /// The calm bubble [i]: rises in 2.4 s, then waits for the other two.
  ({double dy, double scale, double opacity}) _calmRise(int i) {
    final t = clock - introSeconds - i * calmBubbleGap;
    if (t < 0) return (dy: 0, scale: .6, opacity: 0);
    final c = t % (calmBubbleGap * 3);
    if (c >= 2.4) return (dy: 0, scale: .6, opacity: 0);
    return _risePct(c / 2.4);
  }

  /// The bubble [i] as the main rhythm draws it (tests and the splash).
  ({double dy, double scale, double opacity}) bubble(int i) {
    final layer = bubbles().where((b) => b.i == i);
    if (layer.isEmpty) return (dy: 0, scale: .6, opacity: 0);
    final b = layer.reduce((a, b) => a.opacity >= b.opacity ? a : b);
    return (dy: b.dy, scale: b.scale, opacity: b.opacity);
  }

  /// Every bubble to paint now: the calm and the agitated rhythms cross-fade
  /// by [excite], and a [burst] sends the three up together.
  List<SplashBubble> bubbles() {
    if (_still) return const [];
    final out = <SplashBubble>[];
    void add(int i, ({double dy, double scale, double opacity}) b, double k) {
      final o = b.opacity * k;
      if (o > 0) out.add((i: i, dy: b.dy, scale: b.scale, opacity: o));
    }

    switch (ambient) {
      case SplashAmbient.lively:
        for (var i = 0; i < 3; i++) {
          add(i, _rise(clock - i * 0.8), 1);
        }
      case SplashAmbient.none:
        final k = ((introSeconds - elapsed) / _bubblesFade).clamp(0.0, 1.0);
        for (var i = 0; i < 3; i++) {
          add(i, _rise(elapsed - i * 0.8), k);
        }
      case SplashAmbient.calm:
        for (var i = 0; i < 3; i++) {
          if (excite < 1) add(i, _calmRise(i), 1 - excite);
          if (excite > 0) add(i, _rise(clock - i * 0.8), excite);
        }
    }
    final b = burst;
    if (b != null && b >= 0 && b < burstSeconds) {
      for (var i = 0; i < 3; i++) {
        add(i, _risePct((b / burstSeconds).clamp(0.0, 1.0)), 1);
      }
    }
    return out;
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
    final sink = tl.levelDy;
    for (final b in tl.bubbles()) {
      final (cx, cy, r) = _bubbles[b.i];
      canvas.drawCircle(
        Offset(cx, cy + sink + b.dy),
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
      final light = tl.nodeLight(i);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(s);
      if (light > 0) {
        canvas.drawCircle(
          Offset.zero,
          r + w,
          Paint()
            ..color = AppColors.amberLight.withValues(alpha: .7 * light)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawCircle(Offset.zero, r, Paint()..color = AppColors.liquid);
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = Color.lerp(AppColors.amber, AppColors.amberLight, light)!,
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
