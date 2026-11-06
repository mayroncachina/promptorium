import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../ui/theme/motion.dart';
import '../../ui/theme/tokens.dart';
import 'splash_painter.dart';

/// The opening animation: icon + title with the fade/scale-in, shared by the
/// splash and Sobre. It owns its ticker: with [loop] the ambient parts run
/// until it leaves the tree; without it the ticker stops at the end of the
/// intro. With animations off no ticker runs, and the final frame shows.
class SplashStage extends StatefulWidget {
  const SplashStage({
    super.key,
    this.loop = true,
    this.iconSize = 168,
    this.titleSize = 30,
    this.subtitleSize = 13,
    this.gap = 10,
  });

  final bool loop;
  final double iconSize;
  final double titleSize;
  final double subtitleSize;

  /// Between the icon and the title.
  final double gap;

  @override
  State<SplashStage> createState() => _SplashStageState();
}

class _SplashStageState extends State<SplashStage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _elapsed = ValueNotifier<double>(0);
  bool? _still;
  bool _introDone = false;

  void _tick(Duration d) {
    if (!widget.loop && d >= SplashTimeline.introDuration) {
      _ticker.stop();
      _introDone = true;
      _elapsed.value = SplashTimeline.introSeconds;
      return;
    }
    _elapsed.value = d.inMicroseconds / 1e6;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !AppMotion.animate(context);
    if (still == _still) return;
    _still = still;
    if (still) {
      _ticker.stop();
    } else if (!_introDone) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  SplashTimeline _timeline() => SplashTimeline(
    elapsed: _elapsed.value,
    reducedMotion: _still ?? false,
    loop: widget.loop,
  );

  @override
  Widget build(BuildContext context) {
    // The drawing has no meaning of its own: a reader gets the label only.
    final icon = Semantics(
      image: true,
      label: 'Ícone do Promptorium',
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.iconSize),
          painter: SplashPainter(timeline: _timeline, repaint: _elapsed),
        ),
      ),
    );
    final title = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Promptorium',
          style: TextStyle(
            fontSize: widget.titleSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: AppColors.text,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'o laboratório de onde operam seus agentes',
          style: TextStyle(
            fontSize: widget.subtitleSize,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
    return ValueListenableBuilder<double>(
      valueListenable: _elapsed,
      builder: (context, _, _) {
        final tl = _timeline();
        return Opacity(
          opacity: tl.stageOpacity,
          alwaysIncludeSemantics: true,
          child: Transform.scale(
            scale: tl.stageScale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                SizedBox(height: widget.gap),
                Opacity(
                  opacity: tl.titleOpacity,
                  alwaysIncludeSemantics: true,
                  child: Transform.translate(
                    offset: Offset(0, tl.titleDy),
                    child: title,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
