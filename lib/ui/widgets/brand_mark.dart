import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'svg_path.dart';

/// Colours of the Promptorium mark (assets/icon/mark/mark.svg, SPEC-029).
abstract final class BrandColors {
  static const outline = Color(0xFFF5A23A);
  static const shadow = Color(0xFF14100A);
  static const glass = Color(0xFF0E2226);
  static const liquid = Color(0xFF17B8A6);
  static const surface = Color(0xFF5FE3D2);
  static const bubble = Color(0xFF3FD6C4);
  static const prompt = Color(0xFFE6FFFB);
}

/// One loop of the header animation (SPEC-031 R4).
const brandMotionCycle = Duration(milliseconds: 2400);
const _cycle = 2.4; // seconds

/// Wavelength of the liquid's surface in the 256 box (the splash's 60 in
/// its 200 box) and how far it runs per cycle.
const brandWaveLength = 76.0;

/// Where the bubbles start (x, y, radius) and how far they rise: from the
/// liquid up to the neck, where the mark's top bubble sits.
const brandBubbles = [
  (128.0, 204.0, 11.0),
  (114.0, 208.0, 8.0),
  (140.0, 210.0, 7.0),
];
const brandBubbleRise = 104.0;

/// The molecule's nodes (x, y, radius).
const brandNodes = [
  (132.0, 34.0, 13.0),
  (180.0, 22.0, 15.0),
  (196.0, 60.0, 10.0),
];

/// Horizontal offset of the wave at [t] (0..1 of the cycle), like the
/// splash's `pm-wave`.
double brandWaveOffset(double t) => -brandWaveLength * t;

/// Bubble [i] at [t] (0..1 of the cycle), like the splash's `pm-bubble`:
/// 0.8 s apart, ease-in rise, .6 → 1 scale, fade in to 20%, out after 80%.
({double dy, double scale, double opacity}) brandBubble(int i, double t) {
  final p = ((t * _cycle - i * .8) % _cycle) / _cycle;
  final e = Curves.easeIn.transform(p);
  final double opacity;
  if (p < .2) {
    opacity = Curves.easeIn.transform(p / .2);
  } else if (p < .8) {
    opacity = 1 - .1 * Curves.easeIn.transform((p - .2) / .6);
  } else {
    opacity = .9 * (1 - Curves.easeIn.transform((p - .8) / .2));
  }
  return (dy: -brandBubbleRise * e, scale: .6 + .4 * e, opacity: opacity);
}

/// Scale of molecule node [i] at [t]: one pop to 1.18 per cycle, 0.18 s
/// apart, like the splash's `pm-pop`.
double brandNodeScale(int i, double t) {
  final local = (t * _cycle - i * .18) % _cycle;
  return local < .3 ? 1 + .18 * math.sin(math.pi * local / .3) : 1;
}

/// The Promptorium mark drawn in vector (SPEC-031 R2). Without [wave] it is
/// the still mark of `mark.svg`; with it, the liquid's wave runs, bubbles
/// rise to the neck and the molecule pops, like the splash (R4).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 26, this.wave});
  final double size;
  final Animation<double>? wave;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(size),
      painter: BrandMarkPainter(wave),
    ),
  );
}

class BrandMarkPainter extends CustomPainter {
  BrandMarkPainter(this.wave) : super(repaint: wave);
  final Animation<double>? wave;

  static final _molecule = parseSvgPath('M132 34 L180 22 L196 60');
  static final _body = parseSvgPath(
    'M104 78 L104 122 L34 216 Q24 238 50 240 L206 240 Q232 238 222 216 '
    'L152 122 L152 78 Z',
  );
  static final _rim = parseSvgPath('M90 78 L166 78');
  static final _outline = parseSvgPath(
    'M104 78 L104 122 L34 216 Q24 238 50 240 L206 240 Q232 238 222 216 '
    'L152 122 L152 78 M90 78 L166 78',
  );
  static final _liquid = parseSvgPath(
    'M80 168 Q104 154 128 164 T176 162 L211 213 Q216 224 204 224 L52 224 '
    'Q40 224 45 213 Z',
  );
  static final _surface = parseSvgPath('M80 168 Q104 154 128 164 T176 162');
  static final _prompt = parseSvgPath(
    'M94 184 L114 198 L94 212 M126 212 L158 212',
  );

  /// The still liquid's sides and bottom, carried up to the neck: the wave
  /// fills the same shape as the still mark.
  static final _liquidBounds = parseSvgPath(
    'M101.8 140 L80 168 L45 213 Q40 224 52 224 L204 224 Q216 224 211 213 '
    'L176 162 L160.9 140 Z',
  );
  static final _waveLine = _wave(close: false);
  static final _waveFill = _wave(close: true);

  /// A periodic surface at level 164, amplitude 7, from x = −152 to 380.
  static Path _wave({required bool close}) {
    const level = 164.0, amp = 7.0, half = brandWaveLength / 2;
    var x = -2 * brandWaveLength;
    final b = StringBuffer('M$x $level Q${x + half / 2} ${level - amp} ')
      ..write('${x + half} $level');
    x += half;
    for (var i = 0; i < 14; i++) {
      x += half;
      b.write(' T$x $level');
    }
    if (close) b.write(' V250 H${-2 * brandWaveLength} Z');
    return parseSvgPath(b.toString());
  }

  Paint _stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = c;

  @override
  void paint(Canvas canvas, Size size) {
    final t = wave?.value;
    canvas.save();
    canvas.scale(size.width / 256, size.height / 256);

    // Dark outer contour: separates the mark from light backgrounds.
    canvas.drawPath(_molecule, _stroke(BrandColors.shadow, 13));
    for (final (x, y, r) in brandNodes) {
      canvas.drawCircle(Offset(x, y), r, _stroke(BrandColors.shadow, 13));
    }
    canvas.drawPath(_body, Paint()..color = BrandColors.glass);
    canvas.drawPath(_body, _stroke(BrandColors.shadow, 26));
    canvas.drawPath(_rim, _stroke(BrandColors.shadow, 26));

    // Molecule.
    canvas.drawPath(_molecule, _stroke(BrandColors.outline, 6));
    for (final (i, (x, y, r)) in brandNodes.indexed) {
      final s = t == null ? 1.0 : brandNodeScale(i, t);
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(s);
      canvas.drawCircle(Offset.zero, r, Paint()..color = BrandColors.liquid);
      canvas.drawCircle(Offset.zero, r, _stroke(BrandColors.outline, 6));
      canvas.restore();
    }

    if (t == null) {
      canvas.drawPath(_liquid, Paint()..color = BrandColors.liquid);
      canvas.drawPath(_surface, _stroke(BrandColors.surface, 5));
      final bubble = Paint()..color = BrandColors.bubble;
      canvas.drawCircle(const Offset(132, 134), 8, bubble);
      canvas.drawCircle(const Offset(114, 108), 5, bubble);
    } else {
      canvas.save();
      canvas.clipPath(_body);
      canvas.save();
      canvas.clipPath(_liquidBounds);
      canvas.translate(brandWaveOffset(t), 0);
      canvas.drawPath(_waveFill, Paint()..color = BrandColors.liquid);
      canvas.drawPath(_waveLine, _stroke(BrandColors.surface, 5));
      canvas.restore();
      for (final (i, (x, y, r)) in brandBubbles.indexed) {
        final b = brandBubble(i, t);
        if (b.opacity <= 0) continue;
        canvas.drawCircle(
          Offset(x, y + b.dy),
          r * b.scale,
          Paint()..color = BrandColors.bubble.withValues(alpha: b.opacity),
        );
      }
      canvas.restore();
    }

    canvas.drawPath(_prompt, _stroke(BrandColors.prompt, 9));
    canvas.drawPath(_outline, _stroke(BrandColors.outline, 13));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BrandMarkPainter old) => old.wave != wave;
}
