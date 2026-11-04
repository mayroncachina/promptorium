import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// Fades [child] in while it travels [dy] pixels up to its place (a negative
/// [dy] comes from above). Runs once, when mounted: a new key starts it over.
/// Only opacity and transform change, and it never blocks input (R12, R13).
class MotionEnter extends StatefulWidget {
  const MotionEnter({
    super.key,
    required this.child,
    this.duration = AppMotion.base,
    this.dy = 8,
    this.animate = true,
  });

  final Widget child;
  final Duration duration;
  final double dy;

  /// False shows [child] in place at once (a burst of events, history).
  final bool animate;

  @override
  State<MotionEnter> createState() => _MotionEnterState();
}

class _MotionEnterState extends State<MotionEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: AppMotion.enter,
  );
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final d = AppMotion.duration(context, widget.duration);
    if (!widget.animate || d == Duration.zero) {
      _c.value = 1;
    } else {
      _c.duration = d;
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _t,
    child: AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, widget.dy * (1 - _t.value)),
        child: child,
      ),
    ),
  );
}
