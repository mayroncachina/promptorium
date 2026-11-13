import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../ui/theme/motion.dart';
import '../../ui/theme/tokens.dart';
import 'splash_painter.dart';

/// The opening animation: icon + title with the fade/scale-in, shared by the
/// splash and Sobre. It owns its ticker: with an ambient rhythm the flask
/// stays alive until it leaves the tree; with [SplashAmbient.none] the ticker
/// stops at the end of the intro. With animations off no ticker runs, and the
/// final frame shows.
class SplashStage extends StatefulWidget {
  const SplashStage({
    super.key,
    this.loop = true,
    this.ambient,
    this.excited = false,
    this.paused = false,
    this.level,
    this.iconBuilder,
    this.iconSize = 168,
    this.titleSize = 30,
    this.subtitleSize = 13,
    this.gap = 10,
  });

  /// Shorthand for [ambient]: `true` is the splash rhythm, `false` stops.
  final bool loop;

  /// What the flask does after the intro; overrides [loop].
  final SplashAmbient? ambient;

  /// Mouse over the logo (SPEC-066 R4): the calm rhythm turns agitated.
  final bool excited;

  /// Stops where it is, as with the window out of focus (R7).
  final bool paused;

  /// Level of the liquid while an update downloads (R10), or null (full).
  final double? level;

  /// Wraps the icon (not the title): Sobre makes it a button.
  final Widget Function(BuildContext context, Widget icon)? iconBuilder;

  final double iconSize;
  final double titleSize;
  final double subtitleSize;

  /// Between the icon and the title.
  final double gap;

  SplashAmbient get effectiveAmbient =>
      ambient ?? (loop ? SplashAmbient.lively : SplashAmbient.none);

  @override
  State<SplashStage> createState() => SplashStageState();
}

class SplashStageState extends State<SplashStage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  bool? _still;
  bool _windowActive = true;
  Duration _last = Duration.zero;

  /// Seconds since the intro (re)started, the ambient clock, the wave in
  /// cycles, the blended agitation, the shown level and the burst.
  double _intro = 0, _clock = 0, _wave = 0, _excite = 0;
  double? _level, _burst;
  bool _replaying = false;

  /// Mixing time between the calm and the agitated rhythms (R4).
  static const exciteSeconds = 0.4;

  /// Time the liquid takes to cross the whole flask (R10): a cancel goes
  /// back to full in at most this.
  static const levelSeconds = 0.4;

  bool get _introRunning => _intro < SplashTimeline.introSeconds;

  /// Whether the intro is playing (a replay included).
  bool get introPlaying => _introRunning && !(_still ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _windowActive = state == null || state == AppLifecycleState.resumed;
    _level = widget.level;
    _excite = widget.excited ? 1 : 0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _windowActive = state == AppLifecycleState.resumed;
    _sync();
  }

  /// Plays the intro again (R5); ignored while it plays or with animations
  /// off.
  void replay() {
    if (_still ?? true) return;
    if (_introRunning) return;
    _intro = 0;
    _replaying = true;
    _sync();
  }

  /// Sends the three bubbles up together once (R10).
  void celebrate() {
    if (_still ?? true) return;
    _burst = 0;
    _sync();
  }

  bool get _settled {
    final targetLevel = widget.level ?? 1;
    final levelDone = ((_level ?? 1) - targetLevel).abs() < 1e-3;
    final exciteDone = _excite == (widget.excited ? 1 : 0);
    final burstDone = _burst == null || _burst! >= SplashTimeline.burstSeconds;
    return levelDone && exciteDone && burstDone;
  }

  /// Whether the ticker should run now.
  bool get _shouldRun {
    if (_still ?? true) return false;
    if (widget.paused || !_windowActive) return false;
    if (widget.effectiveAmbient != SplashAmbient.none) return true;
    return _introRunning || !_settled;
  }

  void _sync() {
    if (!mounted) return;
    if (_shouldRun) {
      if (!_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration d) {
    final dt = (d - _last).inMicroseconds / 1e6;
    _last = d;
    final ambient = widget.effectiveAmbient;
    _intro = (_intro + dt).clamp(0.0, SplashTimeline.introSeconds);
    _clock += dt;
    final target = widget.excited ? 1.0 : 0.0;
    final step = dt / exciteSeconds;
    _excite = target > _excite
        ? (_excite + step).clamp(0.0, target)
        : (_excite - step).clamp(target, 1.0);
    _wave += dt / SplashTimeline.wavePeriod(ambient, _excite);
    final wantLevel = widget.level ?? 1.0;
    final from = _level ?? 1.0;
    final maxStep = dt / levelSeconds;
    final next = from + (wantLevel - from).clamp(-maxStep, maxStep);
    _level = next == 1.0 && widget.level == null ? null : next;
    if (_burst != null) _burst = _burst! + dt;
    if (ambient == SplashAmbient.none && !_introRunning && _settled) {
      _ticker.stop();
    }
    _frame.value++;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !AppMotion.animate(context);
    if (still == _still) return;
    _still = still;
    if (still) {
      _level = widget.level;
      _excite = 0;
    }
    _sync();
  }

  @override
  void didUpdateWidget(SplashStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_still ?? false) {
      _level = widget.level;
      _frame.value++;
    }
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  SplashTimeline _timeline() => SplashTimeline(
    elapsed: _intro,
    reducedMotion: _still ?? false,
    ambient: widget.effectiveAmbient,
    ambientClock: _clock,
    wavePhase: _wave,
    excite: _excite,
    level: _level,
    burst: _burst,
    replaying: _replaying,
  );

  @override
  Widget build(BuildContext context) {
    // The drawing has no meaning of its own: a reader gets the label only.
    Widget icon = Semantics(
      image: true,
      label: 'Ícone do Promptorium',
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.iconSize),
          painter: SplashPainter(timeline: _timeline, repaint: _frame),
        ),
      ),
    );
    final builder = widget.iconBuilder;
    if (builder != null) icon = builder(context, icon);
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
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
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
