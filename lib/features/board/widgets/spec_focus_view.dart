import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/session_manager.dart';
import '../board_rules.dart';
import '../board_screen.dart';
import 'canvas_view_controller.dart';
import 'spec_folder.dart';
import 'spec_node.dart';
import 'spec_stage.dart';

/// A card on its way between the folder and the stage.
class _Flight {
  _Flight(this.data, this.from, this.size);

  final SpecCardData data;

  /// Where it starts, on screen, and its size on the stage.
  final Rect from;
  final Size size;

  /// Null until the stage is laid out; the card waits at [from].
  Rect? to;
  int delayMs = 0, durationMs = AppMotion.stage.inMilliseconds;

  /// Goes back to the folder, and fades on the way.
  bool leaving = false;

  double _t(double ms) => ((ms - delayMs) / durationMs).clamp(0.0, 1.0);

  Rect at(double ms) =>
      Rect.lerp(from, to ?? from, AppMotion.enter.transform(_t(ms)))!;

  double opacity(double ms) {
    final t = _t(ms);
    return leaving ? 1 - math.max(0.0, t - .5) * 2 : math.min(1.0, t * 6 + .2);
  }
}

/// The Foco view of the Quadro (SPEC-036): the folder of specs on the left and
/// the stage on the rest of the screen.
///
/// As on the columns (`BoardFlights`, SPEC-034 R7), the stage is laid out in
/// its final state at once. A layer above the folder and the stage, which
/// takes no pointer, carries a copy of each card, and only painting follows
/// the animation: clicks and keys act on the real cards all the time (R15).
class SpecFocusView extends ConsumerStatefulWidget {
  const SpecFocusView({
    super.key,
    required this.cards,
    required this.all,
    required this.attention,
  });

  /// Cards that pass the filters of the Quadro: those of the folder.
  final List<SpecCardData> cards;

  /// Every card: a dependent is on the stage even when filtered out.
  final List<SpecCardData> all;
  final bool Function(SpecCardData) attention;

  @override
  ConsumerState<SpecFocusView> createState() => SpecFocusViewState();
}

class SpecFocusViewState extends ConsumerState<SpecFocusView>
    with SingleTickerProviderStateMixin {
  final _focus = FocusNode(debugLabel: 'spec-focus-view');
  final _folder = GlobalKey<SpecFolderState>();
  final _stage = GlobalKey<FocusStageState>();
  final _layer = GlobalKey();
  final _view = CanvasViewController();

  /// One clock for all: a new choice restarts everything from where it is.
  late final _clock = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _landed();
    });
  final _flights = <int, _Flight>{};

  /// When each card of the stage arrives, in ms of the clock.
  final _landing = <int, int>{};

  int? _rootId;

  /// "Executando" is on the stage (R12), with these specs.
  bool _running = false;
  Set<int> _runningShown = const {};

  @override
  void initState() {
    super.initState();
    // A card open in another view opens here.
    final selected = ref.read(boardSelectedSpecProvider);
    if (selected != null) _rootId = selected;
  }

  @override
  void dispose() {
    _clock.dispose();
    _view.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Focuses the search of the folder (R6).
  void focusSearch() => _folder.currentState?.focusSearch();

  double get _ms =>
      _clock.value * (_clock.duration?.inMilliseconds.toDouble() ?? 0);

  Map<int, SpecCardData> get _byId => {
    for (final d in widget.all) d.spec.id: d,
  };

  List<Spec> _runningSpecs() {
    final manager = ref.read(sessionManagerProvider);
    return [
      for (final d in widget.all)
        if (isSpecRunning(d, alive: manager.isAlive)) d.spec,
    ]..sort(compareNewestFirst);
  }

  StageGeometry? _geometryOf(
    int? rootId,
    bool running,
    Map<int, SpecCardData> byId,
  ) {
    if (running) {
      final specs = _runningSpecs();
      if (specs.isEmpty) return null;
      return stageGeometry(
        StageLayout.runningSpecs(specs),
        (s) => stageCardSizeOf(
          root: false,
          running: true,
          attention: widget.attention(byId[s.id]!),
        ),
      );
    }
    final root = byId[rootId];
    if (root == null) return null;
    final layout = stageLayout(root.spec, widget.all.map((d) => d.spec));
    return stageGeometry(
      layout,
      (s) => stageCardSizeOf(
        root: s.id == root.spec.id,
        attention: widget.attention(byId[s.id]!),
      ),
    );
  }

  void _select(int? id) =>
      ref.read(boardSelectedSpecProvider.notifier).select(id);

  /// A click on a spec: the one at the center opens its panel (R18), any other
  /// goes to the center (R8).
  void _open(int id) {
    if (id == _rootId) {
      _select(id);
    } else {
      _select(null);
      _show(id);
    }
    _focus.requestFocus();
  }

  void _back() {
    _select(null);
    _show(null);
    _focus.requestFocus();
  }

  void _toggleRunning() {
    _select(null);
    _show(null, running: !_running);
    _focus.requestFocus();
  }

  @override
  void didUpdateWidget(covariant SpecFocusView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_running) return;
    // A spec left execution: its card goes back to the folder (R13).
    final now = {for (final s in _runningSpecs()) s.id};
    if (!setEquals(now, _runningShown)) {
      _show(null, running: now.isNotEmpty, force: true);
    }
  }

  /// Everything goes from where it is on screen to its new place.
  void _show(int? rootId, {bool running = false, bool force = false}) {
    if (!force && rootId == _rootId && running == _running) return;
    final layer = _layer.currentContext?.findRenderObject() as RenderBox?;
    final stage = _stage.currentState, folder = _folder.currentState;
    if (layer == null ||
        stage == null ||
        folder == null ||
        !AppMotion.animate(context)) {
      _flights.clear();
      _clock.stop();
      setState(() {
        _rootId = rootId;
        _running = running;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _stage.currentState?.frame();
      });
      return;
    }
    final byId = _byId;
    final ms = _ms;
    final next = _geometryOf(rootId, running, byId);
    final was = stage.widget.geometry;
    final shown = stage.screenRects(layer);
    final flights = <int, _Flight>{};
    // In the air or on the stage: starts from where it is painted now.
    for (final e in _flights.entries) {
      final size = next?.rects[e.key]?.size ?? e.value.size;
      flights[e.key] = _Flight(e.value.data, e.value.at(ms), size);
    }
    for (final e in shown.entries) {
      final d = byId[e.key];
      if (d == null || flights.containsKey(e.key)) continue;
      final size = next?.rects[e.key]?.size ?? was!.rects[e.key]!.size;
      flights[e.key] = _Flight(d, e.value, size);
    }
    for (final spec in next?.layout.specs ?? const <Spec>[]) {
      if (flights.containsKey(spec.id)) continue;
      flights[spec.id] = _Flight(
        byId[spec.id]!,
        folder.listRect(spec.id, layer),
        next!.rects[spec.id]!.size,
      );
    }
    _clock.stop();
    _landing.clear();
    setState(() {
      _rootId = rootId;
      _running = running;
      _flights
        ..clear()
        ..addAll(flights);
      // Nothing of the new stage is painted before its flight is set.
      for (final id in next?.rects.keys ?? const <int>[]) {
        _landing[id] = 1 << 30;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _launch(next);
    });
  }

  void _launch(StageGeometry? next) {
    final layer = _layer.currentContext!.findRenderObject()! as RenderBox;
    final stage = _stage.currentState!, folder = _folder.currentState!;
    stage.frame();
    final target = stage.screenRects(layer);
    _landing.clear();
    final stageMs = AppMotion.stage.inMilliseconds;
    for (final (level, specs) in (next?.layout.levels ?? const []).indexed) {
      for (final (i, spec) in specs.indexed) {
        final delay = stageCardDelay(level, i).inMilliseconds;
        _landing[spec.id] = delay + stageMs;
        final f = _flights[spec.id];
        if (f == null) continue;
        f
          ..to = target[spec.id]
          ..delayMs = delay;
      }
    }
    for (final e in _flights.entries) {
      if (_landing.containsKey(e.key)) continue;
      e.value
        ..to = folder.listRect(e.key, layer)
        ..leaving = true
        ..durationMs = AppMotion.emphasis.inMilliseconds;
    }
    final drawMs = AppMotion.emphasis.inMilliseconds;
    final total = [
      ..._flights.values.map((f) => f.delayMs + f.durationMs),
      for (final v in _landing.values) v + drawMs,
      1,
    ].reduce(math.max);
    setState(() {});
    _clock
      ..duration = Duration(milliseconds: total)
      ..forward(from: 0);
  }

  void _landed() {
    if (!mounted) return;
    setState(() {
      _flights.clear();
      _landing.clear();
    });
  }

  bool _inFlight(int id) {
    final landing = _landing[id];
    return landing != null && _flights.containsKey(id) && _ms < landing;
  }

  /// The line comes after its card (R10).
  double _arrowProgress(StageArrow a) {
    final start = _landing[a.edge.to.id];
    if (start == null) return 1;
    return ((_ms - start) / AppMotion.emphasis.inMilliseconds).clamp(0.0, 1.0);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (ref.read(boardSelectedSpecProvider) != null) {
      _select(null);
    } else if (_rootId != null || _running) {
      _back();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _flightLayer() => IgnorePointer(
    child: ExcludeFocus(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _clock,
          builder: (_, _) {
            final ms = _ms;
            return Stack(
              clipBehavior: Clip.none,
              children: [for (final f in _flights.values) _flying(f, ms)],
            );
          },
        ),
      ),
    ),
  );

  Widget _flying(_Flight f, double ms) {
    final rect = f.at(ms);
    return Positioned(
      left: 0,
      top: 0,
      width: f.size.width,
      height: f.size.height,
      child: Transform(
        key: ValueKey('stage-flight-${f.data.spec.code}'),
        transform: Matrix4.translationValues(rect.left, rect.top, 0)
          ..scaleByDouble(
            rect.width / f.size.width,
            rect.height / f.size.height,
            1,
            1,
          ),
        child: Opacity(
          opacity: f.opacity(ms),
          child: RepaintBoundary(
            child: Consumer(
              builder: (_, ref, _) => SpecNode(
                data: f.data,
                selected: f.data.spec.id == _rootId,
                reason: widget.attention(f.data)
                    ? specAttentionReason(ref, f.data)
                    : null,
                footer: _running && !f.leaving
                    ? StageRunningLine(data: f.data)
                    : null,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(boardSelectedSpecProvider, (_, next) {
      // Selected elsewhere (the palette, a link): goes to the center.
      if (next != null && next != _rootId) _show(next);
    });
    ref.watch(sessionManagerProvider);
    final byId = _byId;
    final geometry = _geometryOf(_rootId, _running, byId);
    final onStage = geometry?.rects.keys.toSet() ?? const <int>{};
    _runningShown = _running ? onStage : const {};
    return CallbackShortcuts(
      bindings: geometry == null ? const {} : _view.zoomShortcuts,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: ColoredBox(
          color: AppColors.background,
          child: Stack(
            key: _layer,
            children: [
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SpecFolder(
                      key: _folder,
                      cards: [
                        for (final d in widget.cards)
                          if (!onStage.contains(d.spec.id)) d,
                      ],
                      attention: widget.attention,
                      onOpen: _open,
                      onSearchDone: _focus.requestFocus,
                    ),
                    Expanded(
                      child: FocusStage(
                        key: _stage,
                        view: _view,
                        geometry: geometry,
                        cards: byId,
                        attention: widget.attention,
                        onOpen: _open,
                        onBack: _back,
                        onBackgroundTap: () {
                          _select(null);
                          _focus.requestFocus();
                        },
                        runningCount: _runningSpecs().length,
                        onRunning: _toggleRunning,
                        clock: _clock,
                        inFlight: _inFlight,
                        arrowProgress: _landing.isEmpty ? null : _arrowProgress,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(child: _flightLayer()),
            ],
          ),
        ),
      ),
    );
  }
}
