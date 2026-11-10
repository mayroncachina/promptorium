import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Ambient loops (the mark's wave, attention pulses, spinners) tick at this
/// interval, not on every vsync. On Linux every frame redraws the whole
/// window, so a 60 Hz loop costs a full frame 60 times a second for as
/// long as a spec runs; at 24 Hz a slow loop looks the same.
const ambientFrameInterval = Duration(microseconds: 41667);

/// The [TickerProvider] of ambient loops: `vsync: AmbientVsync(context)`.
/// Create the controller where [context] may depend on inherited widgets
/// (build, didChangeDependencies): the ticker follows [TickerMode] there.
class AmbientVsync implements TickerProvider {
  const AmbientVsync(this.context);

  final BuildContext context;

  @override
  Ticker createTicker(TickerCallback onTick) => AmbientTicker(
    onTick,
    TickerMode.getValuesNotifier(context),
    debugLabel: kDebugMode ? 'ambient ${context.widget}' : null,
  );
}

/// A [Ticker] that waits [ambientFrameInterval] between ticks. The waits
/// line up on one clock, so every ambient loop on screen shares a frame.
class AmbientTicker extends Ticker {
  AmbientTicker(super.onTick, this._mode, {super.debugLabel}) {
    _mode.addListener(_applyMode);
    muted = !_mode.value.enabled;
    _active.add(this);
  }

  final ValueListenable<TickerModeData> _mode;

  /// Ambient tickers waiting for or running a tick (for tests: they hold
  /// no transient frame callback between ticks).
  @visibleForTesting
  static int get debugActive => _active.where((t) => t.isTicking).length;
  static final _active = <AmbientTicker>{};
  Timer? _wait;

  void _applyMode() => muted = !_mode.value.enabled;

  @override
  bool get scheduled => _wait != null || super.scheduled;

  @override
  void scheduleTick({bool rescheduling = false}) {
    if (!rescheduling) {
      super.scheduleTick();
      return;
    }
    // On the frame clock: every ambient loop ticked in this frame waits for
    // the same moment, so they share the next frame too.
    final step = ambientFrameInterval.inMicroseconds;
    final now = SchedulerBinding.instance.currentFrameTimeStamp.inMicroseconds;
    _wait = Timer(Duration(microseconds: step - now % step), () {
      _wait = null;
      // From a timer, not from the frame callback: a fresh request.
      if (shouldScheduleTick) super.scheduleTick();
    });
  }

  @override
  void unscheduleTick() {
    _wait?.cancel();
    _wait = null;
    super.unscheduleTick();
  }

  @override
  void dispose() {
    _wait?.cancel();
    _wait = null;
    _mode.removeListener(_applyMode);
    _active.remove(this);
    super.dispose();
  }
}

/// A small indeterminate spinner on the ambient clock, for what spins
/// while an agent works (minutes): an arc that turns.
class AmbientSpinner extends StatefulWidget {
  const AmbientSpinner({
    super.key,
    this.size = 12,
    this.strokeWidth = 1.6,
    this.color,
  });

  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  State<AmbientSpinner> createState() => _AmbientSpinnerState();
}

class _AmbientSpinnerState extends State<AmbientSpinner> {
  AnimationController? _turn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _turn?.dispose();
      _turn = null;
    } else {
      _turn ??= AnimationController(
        vsync: AmbientVsync(context),
        duration: const Duration(milliseconds: 1100),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _turn?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final arc = CircularProgressIndicator(
      value: .28,
      strokeWidth: widget.strokeWidth,
      color: color,
      backgroundColor: color.withValues(alpha: .18),
    );
    final turn = _turn;
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: turn == null
            ? arc
            : AnimatedBuilder(
                animation: turn,
                builder: (_, child) => Transform.rotate(
                  angle: turn.value * 2 * math.pi,
                  child: child,
                ),
                child: arc,
              ),
      ),
    );
  }
}
