import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// A cascade entrance (SPEC-066 R1): one controller for a group of parts,
/// each a [StaggeredItem] with its index. Part `i` starts at [delayFor] and
/// takes [AppMotion.emphasis], fading in while it rises [StaggeredItem.dy]
/// px. The whole cascade fits in [AppMotion.section]. Runs once, when
/// mounted; with animations off everything is in place at once. Only opacity
/// and transform change: focus and input work from the first frame.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.child});

  final Widget child;

  /// Start of part [index]: 0, 60 and 120 ms for the first three, then 40 ms
  /// apart up to the sixth line; the later ones start with the sixth.
  static Duration delayFor(int index) {
    final ms = index <= 2 ? 60 * index : 120 + 40 * math.min<int>(index - 2, 6);
    return Duration(milliseconds: ms);
  }

  /// The whole cascade.
  static const total = AppMotion.section;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: StaggeredEntrance.total,
  );
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.animate(context)) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _Cascade(animation: _c, child: widget.child);
}

class _Cascade extends InheritedWidget {
  const _Cascade({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_Cascade old) => old.animation != animation;
}

/// One part of a [StaggeredEntrance]. With [reveal], a block of lines (the
/// news, one Markdown) is uncovered from the top down at the pace of the
/// lines, 40 ms each, instead of moving as one piece. Outside a
/// [StaggeredEntrance] it shows [child] as is.
class StaggeredItem extends StatelessWidget {
  const StaggeredItem({
    super.key,
    required this.index,
    required this.child,
    this.dy = 8,
    this.reveal = false,
  });

  final int index;
  final Widget child;
  final double dy;
  final bool reveal;

  /// Progress 0→1 of part [index] at the cascade's [value] (0→1).
  static double progressAt(int index, double value, {bool reveal = false}) {
    final total = StaggeredEntrance.total.inMicroseconds;
    final start = StaggeredEntrance.delayFor(index).inMicroseconds;
    final end = reveal
        ? StaggeredEntrance.delayFor(index + 5).inMicroseconds +
              AppMotion.emphasis.inMicroseconds
        : start + AppMotion.emphasis.inMicroseconds;
    final t = ((value * total - start) / (end - start)).clamp(0.0, 1.0);
    return AppMotion.enter.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final cascade = context.dependOnInheritedWidgetOfExactType<_Cascade>();
    if (cascade == null) return child;
    return AnimatedBuilder(
      animation: cascade.animation,
      child: child,
      builder: (context, child) {
        final v = cascade.animation.value;
        if (v >= 1) return child!;
        if (reveal) {
          final p = progressAt(index, v, reveal: true);
          return ShaderMask(
            key: const ValueKey('staggered-reveal'),
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
              stops: [p * 0.85, math.min(1, p * 0.85 + 0.15)],
            ).createShader(rect),
            child: Transform.translate(
              offset: Offset(0, dy * (1 - p)),
              child: child,
            ),
          );
        }
        final p = progressAt(index, v);
        return Opacity(
          opacity: p,
          alwaysIncludeSemantics: true,
          child: Transform.translate(
            offset: Offset(0, dy * (1 - p)),
            child: child,
          ),
        );
      },
    );
  }
}
