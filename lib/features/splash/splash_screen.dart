import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_info.dart';
import '../../ui/theme/tokens.dart';
import 'splash_painter.dart';
import 'startup_controller.dart';

/// Splash (docs/mockups/Splash.dc.html): animated flask + progress bar bound
/// to the real startup steps of [StartupController].
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({
    super.key,
    required this.onFinished,
    this.minDuration = const Duration(milliseconds: 2600),
  });

  /// Called once startup succeeded and [minDuration] elapsed.
  final VoidCallback onFinished;

  /// Minimum time on screen so the intro animation can play.
  final Duration minDuration;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _elapsed = ValueNotifier<double>(0);
  final _clock = Stopwatch();
  Timer? _finishTimer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _clock.start();
    _ticker = createTicker((d) => _elapsed.value = d.inMicroseconds / 1e6)
      ..start();
    ref.listenManual(startupControllerProvider, (prev, next) {
      if (next.status == StartupStatus.done) _scheduleFinish();
    });
    // Start after the first frame so the splash is visible during the checks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(startupControllerProvider.notifier).run();
    });
  }

  void _scheduleFinish() {
    if (_finished) return;
    const showReady = Duration(milliseconds: 350);
    var wait = widget.minDuration - _clock.elapsed;
    if (wait < showReady) wait = showReady;
    _finishTimer?.cancel();
    _finishTimer = Timer(wait, () {
      if (!mounted || _finished) return;
      _finished = true;
      widget.onFinished();
    });
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  bool _reducedMotion = false;

  SplashTimeline _timeline() =>
      SplashTimeline(elapsed: _elapsed.value, reducedMotion: _reducedMotion);

  @override
  Widget build(BuildContext context) {
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final startup = ref.watch(startupControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Container(
          width: 720,
          height: 440,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            children: [
              // Scale down (never overflow) if the error text gets long.
              Positioned.fill(
                top: 30,
                bottom: 30,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Stage(elapsed: _elapsed, timeline: _timeline),
                        const SizedBox(height: 24),
                        _Progress(state: startup),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 14,
                child: DefaultTextStyle(
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                  child: Row(
                    children: [
                      Text('v${AppInfo.version} · ${AppInfo.platformName}'),
                      const Spacer(),
                      Text(
                        'Claude Code ${startup.claude?.version ?? '—'}',
                        key: const ValueKey('splash-claude-version'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + title, with the stage fade/scale-in.
class _Stage extends StatelessWidget {
  const _Stage({required this.elapsed, required this.timeline});

  final ValueNotifier<double> elapsed;
  final SplashTimeline Function() timeline;

  @override
  Widget build(BuildContext context) {
    final icon = RepaintBoundary(
      child: CustomPaint(
        size: const Size.square(168),
        painter: SplashPainter(timeline: timeline, repaint: elapsed),
      ),
    );
    const title = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Promptorium',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: AppColors.text,
            height: 1.2,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'o laboratório de onde operam seus agentes',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
    return ValueListenableBuilder<double>(
      valueListenable: elapsed,
      builder: (context, _, _) {
        final tl = timeline();
        return Opacity(
          opacity: tl.stageOpacity,
          child: Transform.scale(
            scale: tl.stageScale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 10),
                Opacity(
                  opacity: tl.titleOpacity,
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

/// Progress bar + step label (+ error details and retry).
class _Progress extends ConsumerWidget {
  const _Progress({required this.state});

  final StartupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = state.status == StartupStatus.failed;
    final done = state.status == StartupStatus.done;
    final color = failed
        ? AppColors.red
        : done
        ? AppColors.teal
        : AppColors.textSecondary;
    final err = state.error;

    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Carregando',
            value: '${(state.progress * 100).round()}%',
            child: Container(
              height: 4,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: state.progress),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: failed ? AppColors.red : AppColors.amber,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    state.label,
                    key: const ValueKey('splash-label'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (failed && err != null) ...[
            if (err.hint != null) ...[
              const SizedBox(height: 6),
              Text(
                err.hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (err.details != null) ...[
              const SizedBox(height: 4),
              Text(
                err.details!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 30,
              child: FilledButton(
                key: const ValueKey('splash-retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: AppColors.onAmber,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFonts.sans,
                  ),
                ),
                onPressed: () =>
                    ref.read(startupControllerProvider.notifier).run(),
                child: const Text('Tentar de novo'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
