import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/motion.dart';

/// The shake of the cards that need the person (SPEC-054).

/// One card shakes every [attentionShakeInterval], in turns (R2).
const attentionShakeInterval = Duration(seconds: 5);

/// Length of one shake (R1).
const attentionShakeDuration = Duration(milliseconds: 420);

/// Shakes in a row before a card keeps only the halo (R3).
const attentionShakeMax = 6;

/// "Tremer cards que precisam de você" in Aparência (R7): on unless set to
/// `'false'`.
final attentionShakeEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(appSettingsProvider)[AppSettingKeys.attentionShake] != 'false',
);

/// Horizontal offset (px) and turn (degrees) of a shake at [t] (0–1):
/// −3, +3, −2, +2, −1, 0 px, one step per sixth (R1).
({double dx, double deg}) attentionShakeAt(double t) {
  const xs = [0.0, -3.0, 3.0, -2.0, 2.0, -1.0, 0.0];
  const rs = [0.0, -0.6, 0.6, -0.4, 0.4, 0.0, 0.0];
  final p = t.clamp(0.0, 1.0) * 6;
  final i = p.floor().clamp(0, 5);
  final f = Curves.easeInOut.transform(p - i);
  double lerp(List<double> v) => v[i] + (v[i + 1] - v[i]) * f;
  return (dx: lerp(xs), deg: lerp(rs));
}

/// Who shakes next: turns in queue order, at most [attentionShakeMax]
/// shakes per card in a row, never a card the person has seen (R2–R4).
/// Pure logic; [AttentionShakeHost] drives it with a timer.
class AttentionShakeQueue {
  List<int> _queue = const [];
  Map<int, String> _reasons = const {};
  final _count = <int, int>{};
  final _seen = <int>{};
  int _cursor = 0;

  /// The current queue, for tests.
  @visibleForTesting
  List<int> get queue => _queue;

  /// Takes the new queue (ids in the order of the attention queue) and the
  /// reason of each. Returns the ids that just started to need the person
  /// or whose reason changed: they shake at once and start a fresh count.
  List<int> update(List<int> queue, Map<int, String> reasons) {
    final entered = <int>[];
    for (final id in queue) {
      final before = _reasons[id];
      if (before == null || before != reasons[id]) {
        _count.remove(id);
        _seen.remove(id);
        entered.add(id);
      }
    }
    final gone = _reasons.keys.where((id) => !queue.contains(id)).toList();
    for (final id in gone) {
      _count.remove(id);
      _seen.remove(id);
    }
    _queue = List.unmodifiable(queue);
    _reasons = Map.unmodifiable(reasons);
    if (_cursor >= _queue.length) _cursor = 0;
    return entered;
  }

  /// Hover or focus on the card: out of the turns until the reason changes
  /// (R4).
  void seen(int id) => _seen.add(id);

  bool eligible(int id) =>
      _queue.contains(id) &&
      !_seen.contains(id) &&
      (_count[id] ?? 0) < attentionShakeMax;

  /// Shakes of [id] so far.
  int count(int id) => _count[id] ?? 0;

  /// Counts a shake of [id] now, if it may shake; returns whether it did.
  bool shake(int id) {
    if (!eligible(id)) return false;
    _count[id] = count(id) + 1;
    // The turn moves on past it, as if [next] had picked it.
    _cursor = _queue.indexOf(id) + 1;
    return true;
  }

  /// The next card in turn, skipping [skip] (the selected one); null when
  /// nobody may shake. Counts the shake.
  int? next({Set<int> skip = const {}}) {
    final n = _queue.length;
    for (var k = 0; k < n; k++) {
      final i = (_cursor + k) % n;
      final id = _queue[i];
      if (skip.contains(id) || !eligible(id)) continue;
      _cursor = i + 1;
      _count[id] = count(id) + 1;
      return id;
    }
    return null;
  }
}

/// A shake request: which card, and a serial so the same card can shake
/// again.
@immutable
class ShakeTick {
  const ShakeTick(this.specId, this.serial);

  final int specId;
  final int serial;
}

/// Runs the turns of the board in view (R2–R4, R6–R8). Put it around the
/// board; [queue] is the attention queue in order, [reasons] the reason of
/// each card, [selected] the selected spec. A new host (the Quadro opened
/// again) starts a fresh count (R3).
class AttentionShakeHost extends ConsumerStatefulWidget {
  const AttentionShakeHost({
    super.key,
    required this.queue,
    required this.reasons,
    this.selected,
    required this.child,
  });

  final List<int> queue;
  final Map<int, String> reasons;
  final int? selected;
  final Widget child;

  @override
  ConsumerState<AttentionShakeHost> createState() => AttentionShakeHostState();
}

class AttentionShakeHostState extends ConsumerState<AttentionShakeHost>
    with WidgetsBindingObserver {
  final _queue = AttentionShakeQueue();
  final _tick = ValueNotifier<ShakeTick?>(null);
  Timer? _timer;
  int _serial = 0;
  int _pointers = 0;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _active = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _tick.dispose();
    super.dispose();
  }

  bool get _on =>
      ref.read(attentionShakeEnabledProvider) && AppMotion.animate(context);

  /// R4: no shake without the window's focus, while a pointer is down (a
  /// drag) or while a dialog, menu or the palette covers the board.
  bool get _paused =>
      !_active || _pointers > 0 || !(ModalRoute.of(context)?.isCurrent ?? true);

  void _fire(int id) {
    _tick.value = ShakeTick(id, ++_serial);
  }

  void _onTimer() {
    if (!mounted || !_on || _paused) return;
    final id = _queue.next(
      skip: {if (widget.selected != null) widget.selected!},
    );
    if (id != null) _fire(id);
  }

  void _sync() {
    final entered = _queue.update(widget.queue, widget.reasons);
    final on = _on;
    if (on && widget.queue.isNotEmpty) {
      _timer ??= Timer.periodic(attentionShakeInterval, (_) => _onTimer());
    } else {
      _timer?.cancel();
      _timer = null;
    }
    if (!on || _paused || entered.isEmpty) return;
    // R2: a card shakes as soon as it needs the person; one at a time.
    final first = entered.firstWhere(
      (id) => id != widget.selected,
      orElse: () => -1,
    );
    if (first >= 0 && _queue.shake(first)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fire(first);
      });
    }
  }

  /// Hover or focus on [specId]: seen (R4).
  void seen(int specId) => _queue.seen(specId);

  @override
  Widget build(BuildContext context) {
    ref.watch(attentionShakeEnabledProvider);
    _sync();
    return Listener(
      onPointerDown: (_) => _pointers++,
      onPointerUp: (_) => _pointers = math.max(0, _pointers - 1),
      onPointerCancel: (_) => _pointers = math.max(0, _pointers - 1),
      child: _AttentionShakeScope(host: this, child: widget.child),
    );
  }
}

class _AttentionShakeScope extends InheritedWidget {
  const _AttentionShakeScope({required this.host, required super.child});

  final AttentionShakeHostState host;

  @override
  bool updateShouldNotify(_AttentionShakeScope old) => old.host != host;
}

/// A card that shakes when its turn comes (R1, R5). Without a host above, with
/// the option off or with reduced motion, it is just [child] (R6, R7).
class AttentionShake extends StatefulWidget {
  const AttentionShake({super.key, required this.specId, required this.child});

  final int specId;
  final Widget child;

  @override
  State<AttentionShake> createState() => _AttentionShakeState();
}

class _AttentionShakeState extends State<AttentionShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: attentionShakeDuration,
  );
  AttentionShakeHostState? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = context
        .dependOnInheritedWidgetOfExactType<_AttentionShakeScope>()
        ?.host;
    if (host != _host) {
      _host?._tick.removeListener(_onTick);
      _host = host;
      _host?._tick.addListener(_onTick);
    }
  }

  void _onTick() {
    final t = _host?._tick.value;
    if (t == null || t.specId != widget.specId || !mounted) return;
    if (!AppMotion.animate(context)) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _host?._tick.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    if (host == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => host.seen(widget.specId),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) {
          if (f) host.seen(widget.specId);
        },
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              if (!_c.isAnimating) return child!;
              final s = attentionShakeAt(_c.value);
              return Transform.translate(
                offset: Offset(s.dx, 0),
                child: Transform.rotate(
                  angle: s.deg * math.pi / 180,
                  child: child,
                ),
              );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
