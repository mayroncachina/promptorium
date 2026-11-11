import 'package:flutter/material.dart';

import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';

/// Takes a step's status colour to a new one in `base` (SPEC-034 R9). A change
/// midway starts from the colour on screen (R12).
class StepColorTransition extends StatelessWidget {
  const StepColorTransition({
    super.key,
    required this.color,
    required this.builder,
  });

  final Color color;
  final Widget Function(BuildContext context, Color color) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: color),
    duration: AppMotion.duration(context, AppMotion.base),
    curve: AppMotion.enter,
    builder: (context, value, _) => builder(context, value ?? color),
  );
}

/// The segment of an active step breathes (SPEC-065 R2): opacity 100% →
/// 40% → 100% in [period], while [active]. Off, or with reduced motion, it
/// is fully opaque and no ticker runs (R3, R4).
class StepPulse extends StatefulWidget {
  const StepPulse({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  static const period = Duration(milliseconds: 1200);

  /// Lowest opacity of the pulse.
  static const low = .4;

  @override
  State<StepPulse> createState() => _StepPulseState();
}

class _StepPulseState extends State<StepPulse>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  void _sync() {
    final run = widget.active && AppMotion.animate(context);
    if (run && _c == null) {
      _c = AnimationController(vsync: this, duration: StepPulse.period)
        ..repeat();
    } else if (!run && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StepPulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  /// Opacity at [t] of the period: 1 → [StepPulse.low] → 1, eased.
  static double opacityAt(double t) {
    final half = t < .5 ? t * 2 : (1 - t) * 2;
    return 1 - (1 - StepPulse.low) * Curves.easeInOut.transform(half);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (_, child) => Opacity(opacity: opacityAt(c.value), child: child),
    );
  }
}

/// The ball of a step: a ring in the status colour that fills while its check
/// draws itself, once, when the step is concluded (R9). A step already done
/// when this mounts shows the finished check.
class StepStatusDot extends StatefulWidget {
  const StepStatusDot({
    super.key,
    required this.color,
    required this.done,
    this.size = 14,
  });

  final Color color;
  final bool done;
  final double size;

  @override
  State<StepStatusDot> createState() => _StepStatusDotState();
}

class _StepStatusDotState extends State<StepStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _check = AnimationController(
    vsync: this,
    value: widget.done ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant StepStatusDot old) {
    super.didUpdateWidget(old);
    if (widget.done == old.done) return;
    _check.animateTo(
      widget.done ? 1 : 0,
      duration: AppMotion.duration(
        context,
        widget.done ? AppMotion.base : AppMotion.baseExit,
      ),
      curve: widget.done ? AppMotion.enter : AppMotion.exit,
    );
  }

  @override
  void dispose() {
    _check.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StepColorTransition(
    color: widget.color,
    builder: (_, color) => CustomPaint(
      size: Size.square(widget.size),
      painter: StepCheckPainter(color: color, progress: _check),
    ),
  );
}

/// Paints the ball and [progress] of the check's stroke; only paint changes
/// from frame to frame (R13).
class StepCheckPainter extends CustomPainter {
  StepCheckPainter({required this.color, required this.progress})
    : super(repaint: progress);

  final Color color;
  final Animation<double> progress;

  /// Size of the check in the 18 px ball of the prototype.
  static const _checkShare = 11 / 18;

  /// The prototype's check, in a 12 × 12 box scaled to [box].
  static Path _checkPath(double box) {
    final k = box / 12;
    return Path()
      ..moveTo(2 * k, 6.5 * k)
      ..lineTo(4.6 * k, 9.1 * k)
      ..lineTo(10 * k, 3.4 * k);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius - .75,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (t <= 0) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: color.a * t),
    );
    final box = size.shortestSide * _checkShare;
    final stroke = _checkPath(box).computeMetrics().first;
    canvas
      ..save()
      ..translate(center.dx - box / 2, center.dy - box / 2)
      ..drawPath(
        stroke.extractPath(0, stroke.length * t),
        Paint()
          ..color = AppColors.panel
          ..style = PaintingStyle.stroke
          ..strokeWidth = box / 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant StepCheckPainter old) =>
      old.color != color || old.progress != progress;
}
