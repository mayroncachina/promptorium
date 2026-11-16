import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../activity.dart';

/// The robot of an agent (SPEC-076 R9–R11): a shape, a colour and a name
/// taken from a seed, and an animation that says what it is doing. Drawn
/// from the canvas' SVG (`viewBox 0 0 40 46`) with a [CustomPainter].

/// The five shapes of the canvas.
enum RobotShape { antenna, round, visor, dome, square }

const _palette = [
  Color(0xFF4FD1B5), // teal
  Color(0xFFF2A541), // amber
  Color(0xFFB9A4F5), // lilac
  Color(0xFF6EA8FE), // blue
  Color(0xFFF59BC3), // pink
  Color(0xFFB6E36B), // lime
  Color(0xFFFF8A8A), // red
];

const robotNames = [
  'Ada',
  'Bruno',
  'Caio',
  'Clara',
  'Davi',
  'Elisa',
  'Gil',
  'Hugo',
  'Íris',
  'Joana',
  'Lia',
  'Miro',
  'Nina',
  'Otto',
  'Rui',
  'Tito',
];

/// FNV-1a of [s]: stable across runs and platforms (`String.hashCode` is
/// not promised to be).
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Who the robot is (R9): the same seed, the same robot (R5).
@immutable
class RobotIdentity {
  const RobotIdentity({
    required this.shape,
    required this.color,
    required this.name,
    required this.speed,
    required this.delay,
  });

  factory RobotIdentity.of(String seed) {
    final h = stableHash(seed);
    return RobotIdentity(
      shape: RobotShape.values[h % RobotShape.values.length],
      color: _palette[(h ~/ 5) % _palette.length],
      name: robotNames[(h ~/ 35) % robotNames.length],
      // The blink and the sway vary a bit from robot to robot (R10).
      speed: .85 + ((h >> 12) % 36) / 100,
      delay: ((h >> 20) % 150) / 100,
    );
  }

  final RobotShape shape;
  final Color color;
  final String name;

  /// Multiplies the period of the slow loops (blink, bob, sway).
  final double speed;

  /// Seconds of phase.
  final double delay;
}

/// The extra pieces a pose shows (R10).
enum RobotProp { z, lupa, spark, gear, think, clip, wrench, smoke }

/// The props of [pose]: what the tests and the painter agree on.
Set<RobotProp> robotProps(ActivityPose pose) => switch (pose) {
  ActivityPose.sleep => {RobotProp.z},
  ActivityPose.read || ActivityPose.gate => {RobotProp.lupa},
  ActivityPose.edit => {RobotProp.spark},
  ActivityPose.run => {RobotProp.gear},
  ActivityPose.think => {RobotProp.think},
  ActivityPose.wait => {RobotProp.clip},
  ActivityPose.fix => {RobotProp.wrench},
  ActivityPose.error => {RobotProp.smoke},
  ActivityPose.wave || ActivityPose.watch => const {},
};

/// Whether [pose] shows the eyes closed (sleeping, fallen).
bool robotEyesClosed(ActivityPose pose) =>
    pose == ActivityPose.sleep || pose == ActivityPose.error;

/// The robot. [seed] gives who it is; [pose] what it does. With "reduzir
/// movimento" it stands still in the pose; out of the screen (TickerMode)
/// or with the window out of focus it stops moving (R11).
class RobotAvatar extends StatefulWidget {
  const RobotAvatar({
    super.key,
    required this.seed,
    required this.pose,
    this.size = 32,
    this.selected = false,
    this.semanticLabel,
  });

  final String seed;
  final ActivityPose pose;

  /// Width; the height is `size × 46 / 40`.
  final double size;
  final bool selected;
  final String? semanticLabel;

  @override
  State<RobotAvatar> createState() => _RobotAvatarState();
}

class _RobotAvatarState extends State<RobotAvatar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);
  late final AppLifecycleListener _lifecycle;
  bool _still = false;
  bool _focused = true;
  Duration _base = Duration.zero;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    final state = SchedulerBinding.instance.lifecycleState;
    _focused = state == null || state == AppLifecycleState.resumed;
  }

  void _onLifecycle(AppLifecycleState state) {
    _focused = state == AppLifecycleState.resumed;
    _sync();
  }

  void _tick(Duration elapsed) {
    _last = elapsed;
    _time.value = (_base + elapsed).inMicroseconds / 1e6;
  }

  /// Runs the ticker only when it moves something on screen.
  void _sync() {
    final run = !_still && _focused;
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _base += _last;
      _last = Duration.zero;
      _ticker.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = RobotIdentity.of(widget.seed);
    final h = widget.size * 46 / 40;
    return Semantics(
      label: widget.semanticLabel ?? id.name,
      image: true,
      child: RepaintBoundary(
        child: CustomPaint(
          key: ValueKey('robot-${widget.pose.name}'),
          size: Size(widget.size, h),
          painter: RobotPainter(
            identity: id,
            pose: widget.pose,
            time: _time,
            selected: widget.selected,
          ),
        ),
      ),
    );
  }
}

const _dark = Color(0xFF0A0C10);
const _light = Color(0xFFE7E9EE);
const _gray = Color(0xFFA0A8B6);

/// Paints one frame of the robot at [time] seconds.
class RobotPainter extends CustomPainter {
  RobotPainter({
    required this.identity,
    required this.pose,
    required ValueListenable<double> time,
    this.selected = false,
  }) : _time = time,
       super(repaint: time);

  final RobotIdentity identity;
  final ActivityPose pose;
  final ValueListenable<double> _time;
  final bool selected;

  static final _zText = <double, TextPainter>{};

  /// 0–1 phase of a loop of [period] seconds started at [delay].
  static double _phase(double t, double period, [double delay = 0]) {
    final p = ((t - delay) / period) % 1;
    return p < 0 ? p + 1 : p;
  }

  /// 0 → 1 → 0 smoothly along a loop (an `ease-in-out` alternate).
  static double _wave(double p) => (1 - math.cos(2 * math.pi * p)) / 2;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void paint(Canvas canvas, Size size) {
    final t = _time.value;
    final k = identity.speed;
    final d = identity.delay;
    final s = size.width / 40;
    canvas.save();
    canvas.scale(s);

    var color = identity.color;
    if (pose == ActivityPose.sleep) {
      // `saturate(.2) brightness(.8)`.
      final g = color.computeLuminance();
      final gray = Color.from(alpha: 1, red: g, green: g, blue: g);
      color = Color.lerp(color, gray, .8)!;
      color = Color.lerp(color, _dark, .2)!;
    }

    if (selected) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFFF2A541);
      _dashedCircle(canvas, const Offset(20, 24), 21, 3, 2.4, ring);
    }

    // --- the whole body: bob, breathe, sway, fall ---------------------
    canvas.save();
    const bottom = Offset(20, 45);
    switch (pose) {
      case ActivityPose.read ||
          ActivityPose.edit ||
          ActivityPose.run ||
          ActivityPose.think:
        canvas.translate(0, -1.6 * _wave(_phase(t, 1.6 * k, d)));
      case ActivityPose.wave:
        canvas.translate(0, -1.6 * _wave(_phase(t, .55)));
      case ActivityPose.fix:
        canvas.translate(0, -1.6 * _wave(_phase(t, .45)));
      case ActivityPose.sleep:
        final b = _wave(_phase(t, 3.4 * k, d));
        canvas
          ..translate(bottom.dx, bottom.dy)
          ..scale(_lerp(1, 1.02, b), _lerp(1, .97, b))
          ..translate(-bottom.dx, -bottom.dy);
      case ActivityPose.wait:
        final a = _lerp(-3, 3, _wave(_phase(t, 5 * k, d)));
        _rotateAbout(canvas, bottom, a);
      case ActivityPose.error:
        canvas.translate(0, 2);
        _rotateAbout(canvas, bottom, -14);
      case ActivityPose.gate || ActivityPose.watch:
        break;
    }

    final fill = Paint()..style = PaintingStyle.fill;
    void rect(
      double x,
      double y,
      double w,
      double h,
      double r,
      Color c, [
      double opacity = 1,
    ]) {
      fill.color = c.withValues(alpha: c.a * opacity);
      canvas.drawRRect(
        RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r)),
        fill,
      );
    }

    // Legs.
    rect(14, 38, 4, 7, 1.6, color, .6);
    rect(22, 38, 4, 7, 1.6, color, .6);
    // Arms.
    var left = 0.0, right = 0.0;
    switch (pose) {
      case ActivityPose.edit:
        left = _lerp(-8, -38, _wave(_phase(t, .32)));
        right = _lerp(38, 8, _wave(_phase(t, .32, .16)));
      case ActivityPose.wait:
        left = -40;
        right = 40;
      case ActivityPose.wave:
        right = _lerp(-168, -128, _wave(_phase(t, .55)));
      default:
        break;
    }
    canvas.save();
    _rotateAbout(canvas, const Offset(8, 26.96), left);
    rect(6, 26, 4, 12, 2, color, .8);
    canvas.restore();
    canvas.save();
    _rotateAbout(canvas, const Offset(32, 26.96), right);
    rect(30, 26, 4, 12, 2, color, .8);
    canvas.restore();
    // Body.
    rect(11, 24, 18, 16, 4.5, color, .9);
    rect(15, 29, 10, 2, 1, _dark, .35);
    _head(canvas, color, t);
    _eyes(canvas, t, k, d);
    _props(canvas, t, k, d);
    canvas.restore();
    canvas.restore();
  }

  static void _rotateAbout(Canvas canvas, Offset o, double degrees) {
    if (degrees == 0) return;
    canvas
      ..translate(o.dx, o.dy)
      ..rotate(degrees * math.pi / 180)
      ..translate(-o.dx, -o.dy);
  }

  void _head(Canvas canvas, Color color, double t) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    RRect rr(double x, double y, double w, double h, double r) =>
        RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r));
    switch (identity.shape) {
      case RobotShape.antenna:
        canvas.drawLine(const Offset(20, 3), const Offset(20, 9), stroke);
        // The ball blinks while a command runs.
        final ball = pose == ActivityPose.run
            ? _lerp(1, .25, _wave(_phase(t, .5)))
            : 1.0;
        canvas
          ..drawCircle(
            const Offset(20, 3),
            2.2,
            Paint()..color = color.withValues(alpha: ball),
          )
          ..drawRRect(rr(9, 9, 22, 15, 5), fill);
      case RobotShape.round:
        canvas
          ..drawLine(const Offset(11, 10), const Offset(7, 5), stroke)
          ..drawLine(const Offset(29, 10), const Offset(33, 5), stroke)
          ..drawCircle(const Offset(20, 16), 10, fill);
      case RobotShape.visor:
        canvas
          ..drawRRect(rr(6, 12, 3, 7, 1.2), fill)
          ..drawRRect(rr(31, 12, 3, 7, 1.2), fill)
          ..drawRRect(rr(8, 8, 24, 16, 3.5), fill);
      case RobotShape.dome:
        canvas
          ..drawArc(
            Rect.fromCircle(center: const Offset(20, 19), radius: 11),
            math.pi,
            math.pi,
            true,
            fill,
          )
          ..drawRRect(
            rr(8, 18, 24, 6, 2.5),
            Paint()..color = color.withValues(alpha: .85),
          );
      case RobotShape.square:
        final ears = Paint()..color = color.withValues(alpha: .85);
        canvas
          ..drawRRect(rr(7, 11, 4, 8, 1.3), ears)
          ..drawRRect(rr(29, 11, 4, 8, 1.3), ears)
          ..drawRRect(rr(11, 7, 18, 17, 2.5), fill);
    }
  }

  void _eyes(Canvas canvas, double t, double k, double d) {
    if (robotEyesClosed(pose)) {
      final p = Paint()
        ..color = _dark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(13.5, 16)
        ..quadraticBezierTo(16, 18, 18.5, 16)
        ..moveTo(21.5, 16)
        ..quadraticBezierTo(24, 18, 26.5, 16);
      canvas.drawPath(path, p);
      return;
    }
    final shape = identity.shape;
    final cy = switch (shape) {
      RobotShape.dome => 14.0,
      RobotShape.square => 15.0,
      _ => 16.0,
    };
    // Blink: 93% open, closed at 96%, open again.
    final b = _phase(t, 4.2 * k, d);
    final open = b < .93
        ? 1.0
        : b < .96
        ? _lerp(1, .12, (b - .93) / .03)
        : _lerp(.12, 1, (b - .96) / .04);
    var dx = 0.0, dy = 0.0;
    switch (pose) {
      case ActivityPose.read:
        dx = -2.2 * math.cos(2 * math.pi * _phase(t, 1.3 * k, d));
      case ActivityPose.gate:
        dx = -2.2 * math.cos(2 * math.pi * _phase(t, 1.1));
      case ActivityPose.think:
        dx = 1.6;
        dy = -1.6;
      case ActivityPose.watch:
        final p = _phase(t, 6 * k, d);
        dx = p < .30
            ? -2.6
            : p < .45
            ? _lerp(-2.6, 2.6, (p - .30) / .15)
            : p < .80
            ? 2.6
            : p < .95
            ? _lerp(2.6, -2.6, (p - .80) / .15)
            : -2.6;
      default:
        break;
    }
    canvas
      ..save()
      ..translate(0, cy)
      ..scale(1, open)
      ..translate(0, -cy);
    final dark = Paint()..color = _dark;
    switch (shape) {
      case RobotShape.visor:
        canvas.drawRRect(
          RRect.fromLTRBR(11, 13, 29, 19, const Radius.circular(2)),
          dark,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(
            17 + dx,
            14.5 + dy,
            23 + dx,
            17.5 + dy,
            const Radius.circular(1.5),
          ),
          Paint()..color = const Color(0xFF4FD1B5),
        );
      case RobotShape.dome:
        canvas
          ..drawCircle(const Offset(20, 14), 3.2, dark)
          ..drawCircle(
            Offset(20 + dx * .5, 14 + dy * .5),
            1.3,
            Paint()..color = const Color(0xFFFF8A8A),
          );
      default:
        final pupil = Paint()..color = Colors.white;
        canvas
          ..drawCircle(Offset(16, cy), 2.6, dark)
          ..drawCircle(Offset(24, cy), 2.6, dark)
          ..drawCircle(Offset(16.6 + dx * .5, cy - .6 + dy * .5), 1, pupil)
          ..drawCircle(Offset(24.6 + dx * .5, cy - .6 + dy * .5), 1, pupil);
    }
    canvas.restore();
  }

  void _props(Canvas canvas, double t, double k, double d) {
    final props = robotProps(pose);
    if (props.contains(RobotProp.z)) {
      for (final (i, size) in [(0, 7.0), (1, 8.0), (2, 9.0)]) {
        final p = _phase(t, 2.6, d + i * .85);
        final opacity = p < .25 ? p / .25 : 1 - (p - .25) / .75;
        final scale = _lerp(.6, 1.15, p);
        final tp = _zText.putIfAbsent(
          size,
          () => TextPainter(
            text: TextSpan(
              text: 'z',
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: _gray,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
        );
        canvas
          ..save()
          ..translate(30 + 7 * p, 8 - 13 * p - size)
          ..scale(scale);
        canvas.saveLayer(
          const Rect.fromLTWH(-1, -1, 12, 14),
          Paint()..color = Colors.white.withValues(alpha: opacity.clamp(0, 1)),
        );
        tp.paint(canvas, Offset.zero);
        canvas
          ..restore()
          ..restore();
      }
    }
    if (props.contains(RobotProp.lupa)) {
      final dx = pose == ActivityPose.gate
          ? -4 * math.cos(2 * math.pi * _phase(t, 1.1))
          : -4 * math.cos(2 * math.pi * _phase(t, 2.2 * k, d));
      canvas
        ..save()
        ..translate(dx, 0)
        ..drawCircle(
          const Offset(31, 30),
          4.2,
          Paint()..color = const Color(0x406EA8FE),
        )
        ..drawCircle(
          const Offset(31, 30),
          4.2,
          Paint()
            ..color = _light
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        )
        ..drawLine(
          const Offset(34, 33),
          const Offset(37.5, 36.5),
          Paint()
            ..color = _light
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        )
        ..restore();
    }
    if (props.contains(RobotProp.spark)) {
      Paint spark(double delay) => Paint()
        ..color = const Color(0xFFFFD08A)
            .withValues(alpha: _wave(_phase(t, .5, delay)))
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      final s1 = spark(d), s2 = spark(d + .25);
      canvas
        ..drawLine(const Offset(3, 38), const Offset(1, 36), s1)
        ..drawLine(const Offset(4, 41), const Offset(1, 41.5), s1)
        ..drawLine(const Offset(37, 38), const Offset(39, 36), s2)
        ..drawLine(const Offset(36, 41), const Offset(39, 41.5), s2);
    }
    if (props.contains(RobotProp.gear)) {
      canvas.save();
      _rotateAbout(canvas, const Offset(34, 6), 360 * _phase(t, 1.4));
      _dashedCircle(
        canvas,
        const Offset(34, 6),
        3.6,
        2,
        1.6,
        Paint()
          ..color = _gray
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
      canvas
        ..drawCircle(const Offset(34, 6), 1.2, Paint()..color = _gray)
        ..restore();
    }
    if (props.contains(RobotProp.think)) {
      canvas.drawRRect(
        RRect.fromLTRBR(27, -4, 42, 4, const Radius.circular(4)),
        Paint()..color = _light,
      );
      for (final (i, x) in [(0, 31.0), (1, 34.5), (2, 38.0)]) {
        final o = _lerp(.15, 1, _wave(_phase(t, 1.2, i * .2)));
        canvas.drawCircle(
          Offset(x, 0),
          1.1,
          Paint()..color = _dark.withValues(alpha: o),
        );
      }
    }
    if (props.contains(RobotProp.clip)) {
      const line = Color(0xFF7C8595);
      final p = Paint()
        ..color = line
        ..strokeWidth = 1.1;
      canvas
        ..drawRRect(
          RRect.fromLTRBR(14, 27, 26, 40, const Radius.circular(1.5)),
          Paint()..color = _light,
        )
        ..drawRRect(
          RRect.fromLTRBR(17, 25.5, 23, 28.5, const Radius.circular(1)),
          Paint()..color = line,
        )
        ..drawLine(const Offset(16.5, 32), const Offset(23.5, 32), p)
        ..drawLine(const Offset(16.5, 35), const Offset(21.5, 35), p);
    }
    if (props.contains(RobotProp.wrench)) {
      canvas.save();
      _rotateAbout(
        canvas,
        const Offset(30.3, 36),
        _lerp(-24, 26, _wave(_phase(t, .45))),
      );
      const metal = Color(0xFFC9CED8);
      final head = Path()
        ..moveTo(29.5, 24.5)
        ..arcToPoint(
          const Offset(35.1, 24.5),
          radius: const Radius.circular(3.4),
          largeArc: true,
          clockwise: false,
        )
        ..relativeLineTo(-1.4, 2.4)
        ..relativeLineTo(-2.8, 0)
        ..close();
      canvas
        ..drawRRect(
          RRect.fromLTRBR(31, 27, 33.6, 38, const Radius.circular(1.2)),
          Paint()..color = metal,
        )
        ..drawPath(head, Paint()..color = metal)
        ..restore();
    }
    if (props.contains(RobotProp.smoke)) {
      for (final (i, c, r) in [
        (0, const Offset(27, 6), 2.6),
        (1, const Offset(30, 4), 2.0),
        (2, const Offset(25, 3), 2.2),
      ]) {
        final p = _phase(t, 1.8, i * .6);
        final o = p < .3 ? .85 * p / .3 : .85 * (1 - (p - .3) / .7);
        canvas.drawCircle(
          c.translate(0, -15 * p),
          r * _lerp(.5, 1.5, p),
          Paint()..color = const Color(0xFF8B93A3).withValues(alpha: o),
        );
      }
    }
  }

  static void _dashedCircle(
    Canvas canvas,
    Offset c,
    double r,
    double dash,
    double gap,
    Paint paint,
  ) {
    final rect = Rect.fromCircle(center: c, radius: r);
    final step = (dash + gap) / r;
    final sweep = dash / r;
    for (var a = 0.0; a < 2 * math.pi; a += step) {
      canvas.drawArc(rect, a, math.min(sweep, 2 * math.pi - a), false, paint);
    }
  }

  @override
  bool shouldRepaint(RobotPainter old) =>
      old.identity != identity ||
      old.pose != pose ||
      old.selected != selected ||
      old._time != _time;
}
