import 'package:flutter/material.dart';

import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart' show SmallButton;
import '../../../ui/theme/ambient.dart';

/// The shape of a spec while its file is on the way (SPEC-034 R10): title,
/// section, line, section, line. The shine runs only while the skeleton is
/// mounted and stays still with reduced motion (R11).
class SpecSkeleton extends StatefulWidget {
  const SpecSkeleton({super.key});

  /// One pass of the shine (the approved prototype; not a transition, so it
  /// is not an [AppMotion] token).
  static const shinePeriod = Duration(milliseconds: 1400);

  @override
  State<SpecSkeleton> createState() => _SpecSkeletonState();
}

class _SpecSkeletonState extends State<SpecSkeleton> {
  late final AnimationController _shine = AnimationController(
    vsync: AmbientVsync(context),
    duration: SpecSkeleton.shinePeriod,
  );
  late final Animation<Offset> _pass = Tween(
    begin: const Offset(-1, 0),
    end: const Offset(1, 0),
  ).animate(_shine);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.animate(context)) {
      _shine.stop();
    } else if (!_shine.isAnimating) {
      _shine.repeat();
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shine = AppMotion.animate(context) ? _pass : null;
    Widget bar(double width, {double height = 12, double top = 0}) => Padding(
      padding: EdgeInsets.only(top: top),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: width,
        child: _Bar(height: height, shine: shine),
      ),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Carregando a spec',
      child: ExcludeSemantics(
        child: _Area(
          // Only the shine repaints, not what is around the skeleton (R13).
          child: RepaintBoundary(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                bar(.45, height: 22),
                bar(.16, top: 6),
                bar(.85),
                bar(.18, top: 10),
                bar(.60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.shine});

  final double height;

  /// Null keeps the bar still (R11).
  final Animation<Offset>? shine;

  @override
  Widget build(BuildContext context) {
    final shine = this.shine;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ColoredBox(
        color: CanvasColors.grid,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: shine == null
              ? null
              : SlideTransition(
                  position: shine,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x00FFFFFF),
                          Color(0x0DFFFFFF),
                          Color(0x00FFFFFF),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// The reason a spec did not open and "Tentar de novo" (R10), in the place
/// of the document.
class SpecOpenError extends StatelessWidget {
  const SpecOpenError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _Area(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            message,
            style: const TextStyle(fontSize: 14, color: AppColors.text),
          ),
        ),
        SmallButton(
          key: const ValueKey('spec-open-retry'),
          label: 'Tentar de novo',
          onTap: onRetry,
        ),
      ],
    ),
  );
}

/// The column the document text uses in the prototype.
class _Area extends StatelessWidget {
  const _Area({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: child,
      ),
    ),
  );
}

/// Fades [child] in each time [turn] changes (R10). The child stays mounted
/// and only its opacity changes (R13); an [AnimatedSwitcher] would keep the
/// old document on screen on top of a disposed controller. A change during
/// a fade carries on from the current opacity (R12).
class SpecTextFade extends StatefulWidget {
  const SpecTextFade({super.key, required this.turn, required this.child});

  final int turn;
  final Widget child;

  @override
  State<SpecTextFade> createState() => _SpecTextFadeState();
}

class _SpecTextFadeState extends State<SpecTextFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: 1,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: AppMotion.enter,
  );

  @override
  void didUpdateWidget(SpecTextFade old) {
    super.didUpdateWidget(old);
    if (old.turn == widget.turn) return;
    final d = AppMotion.duration(context, AppMotion.base);
    if (d == Duration.zero) {
      _c.value = 1;
    } else {
      _c.duration = d;
      _c.forward(from: _c.isAnimating ? null : 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _t, child: widget.child);
}
