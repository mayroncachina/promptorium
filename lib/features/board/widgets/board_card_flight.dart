import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';

/// A card on its way to another column.
class _Flight {
  _Flight({required this.from, required this.width, this.held = false})
    : to = from;

  Offset from;
  Offset to;
  final double width;

  /// Dropped, and still waiting for the database to confirm the new column.
  bool held;

  Offset at(double t) => Offset.lerp(from, to, t)!;
}

/// Cards changing column on the Quadro (SPEC-034 R7).
///
/// [child] is laid out in its final state at once. On top of it, a layer that
/// takes no pointer carries a copy of each moved card, and every other card is
/// painted displaced from where it was until the gap closes. Only painting
/// follows the animation: a click, a key or a drag acts on the real cards, and
/// losing this widget at any moment leaves the board as it should be (R12).
///
/// The layer lives here and not in the app's Overlay so that it stays under the
/// dialogs and goes away with the board. It is needed at all because a card
/// moved in place would be clipped by its new column's list, and painted under
/// the columns to its right.
///
/// All the state is by spec id and lives here: the column lists remount their
/// rows by index when a card leaves, and build them lazily.
class BoardFlights extends StatefulWidget {
  const BoardFlights({
    super.key,
    required this.stages,
    required this.cardOf,
    required this.child,
  });

  /// At most this many cards fly together; the others go straight there.
  static const maxFlights = 3;

  /// Column of each card shown.
  final Map<int, Object> stages;

  /// What a flight shows of a card, or null when it is no longer on the board.
  final Widget? Function(int id) cardOf;

  final Widget child;

  static BoardFlightsState of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_Scope>()!.state;

  @override
  State<BoardFlights> createState() => BoardFlightsState();
}

class BoardFlightsState extends State<BoardFlights>
    with SingleTickerProviderStateMixin {
  final _layer = GlobalKey();

  /// One clock for all: a new change restarts everything from where it is, so
  /// there is nothing to reconcile between animations (R12).
  late final _clock = AnimationController(
    vsync: this,
    duration: AppMotion.emphasis,
    value: 1,
  )..addStatusListener(_finished);
  late final _eased = CurvedAnimation(parent: _clock, curve: AppMotion.enter);
  late final _lift = ReverseAnimation(_eased);

  final _slots = <int, _RenderCardSlot>{};
  final _flights = <int, _Flight>{};

  /// How far each neighbour is painted from its place, at the clock's start.
  final _gaps = <int, Offset>{};

  /// Where each neighbour was seen before the change, until it is painted.
  final _before = <int, Offset>{};

  var _animate = false;

  RenderBox? get _layerBox {
    final box = _layer.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  Offset _at(RenderBox box, RenderBox layer) =>
      box.localToGlobal(Offset.zero, ancestor: layer);

  /// Whether any of [slot] shows, in its column and in the board (R7).
  bool _visible(_RenderCardSlot slot, RenderBox layer) {
    var area = Offset.zero & layer.size;
    final RenderObject? viewport = RenderAbstractViewport.maybeOf(slot);
    if (viewport is RenderBox) {
      area = area.intersect(_at(viewport, layer) & viewport.size);
    }
    return area.overlaps(_at(slot, layer) & slot.size);
  }

  /// Everything stops where it is and the clock goes back to its start.
  void _freeze() {
    final t = _eased.value;
    for (final flight in _flights.values) {
      flight.from = flight.at(t);
    }
    _gaps.updateAll((_, gap) => gap * (1 - t));
    _clock.value = 0;
  }

  /// A card dropped at [global] (the top left of what the pointer carried) on
  /// another column: it waits there for the change to arrive, so that it does
  /// not blink back to the old column. If the change never comes, the clock
  /// runs out and the card shows where it is.
  void drop(int id, Offset global, double width) {
    final layer = _layerBox;
    if (!_animate || layer == null) return;
    if (!_flights.containsKey(id) &&
        _flights.length >= BoardFlights.maxFlights) {
      return;
    }
    _freeze();
    setState(() {
      _flights[id] = _Flight(
        from: layer.globalToLocal(global),
        width: width,
        held: true,
      );
    });
    _clock.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = AppMotion.animate(context);
  }

  @override
  void didUpdateWidget(BoardFlights oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.stages;
    final moved = {
      for (final MapEntry(:key, :value) in widget.stages.entries)
        if (old.containsKey(key) && old[key] != value) key,
    };
    if (moved.isEmpty) return;
    final layer = _layerBox;
    if (!_animate || layer == null) {
      _clock.value = 1;
      return;
    }
    // The tree still holds the last layout here: this is the "before".
    _freeze();
    for (final id in moved) {
      _gaps.remove(id);
      final flight = _flights[id];
      if (flight != null) {
        flight.held = false;
        continue;
      }
      final slot = _slots[id];
      if (slot == null ||
          _flights.length >= BoardFlights.maxFlights ||
          !_visible(slot, layer)) {
        continue;
      }
      _flights[id] = _Flight(from: _at(slot, layer), width: slot.size.width);
    }
    _before
      ..clear()
      ..addAll({
        for (final MapEntry(key: id, value: slot) in _slots.entries)
          if (!moved.contains(id)) id: _at(slot, layer) + _shiftOf(id),
      });
    WidgetsBinding.instance.addPostFrameCallback(_launch);
  }

  /// First paint after a change: the new layout is known and nothing of it was
  /// shown yet, so a neighbour can still start from where it was.
  void _settle(_RenderCardSlot slot) {
    final before = _before.remove(slot.id);
    final layer = _layerBox;
    if (before == null || layer == null) return;
    final gap = before - _at(slot, layer);
    if (gap.distanceSquared < .25) {
      _gaps.remove(slot.id);
    } else {
      _gaps[slot.id] = gap;
    }
  }

  void _launch(Duration _) {
    if (!mounted) return;
    _before.clear();
    final layer = _layerBox;
    setState(() {
      _flights.removeWhere((id, flight) {
        if (flight.held) return false;
        final slot = _slots[id];
        if (layer == null || slot == null || !_visible(slot, layer)) {
          return true;
        }
        flight.to = _at(slot, layer);
        return false;
      });
    });
    if (_flights.isEmpty && _gaps.isEmpty) {
      _clock.value = 1;
    } else {
      _clock.forward(from: 0);
    }
  }

  void _finished(AnimationStatus status) {
    if (!status.isCompleted) return;
    setState(() {
      _flights.clear();
      _gaps.clear();
    });
  }

  Offset _shiftOf(int id) => (_gaps[id] ?? Offset.zero) * (1 - _eased.value);

  @override
  void dispose() {
    _eased.dispose();
    _clock.dispose();
    super.dispose();
  }

  Widget _flightOf(int id, _Flight flight, Widget card) {
    const radius = BorderRadius.all(Radius.circular(8));
    Widget lift(BoxDecoration decoration) => Positioned.fill(
      child: FadeTransition(
        opacity: _lift,
        child: DecoratedBox(decoration: decoration),
      ),
    );
    return Positioned(
      key: ValueKey(id),
      left: 0,
      top: 0,
      width: flight.width,
      child: AnimatedBuilder(
        animation: _eased,
        builder: (_, child) =>
            Transform.translate(offset: flight.at(_eased.value), child: child),
        child: Stack(
          key: ValueKey('board-flight-$id'),
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            lift(
              const BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 26,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
            ),
            card,
            lift(
              BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: AppColors.amber),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flights = [
      for (final MapEntry(key: id, value: flight) in _flights.entries)
        if (widget.cardOf(id) case final card?) _flightOf(id, flight, card),
    ];
    return _Scope(
      state: this,
      child: Stack(
        key: _layer,
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (flights.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeFocus(
                  child: ExcludeSemantics(child: Stack(children: flights)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Scope extends InheritedWidget {
  const _Scope({required this.state, required super.child});

  final BoardFlightsState state;

  @override
  bool updateShouldNotify(_Scope old) => false;
}

/// A card's place in a column: reports where it is, paints the card displaced
/// while its gap closes, and paints nothing while a copy of it is flying. The
/// card keeps its layout, focus and pointer all along.
class BoardCardSlot extends SingleChildRenderObjectWidget {
  const BoardCardSlot({super.key, required this.id, required super.child});

  final int id;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCardSlot(BoardFlights.of(context), id);
}

class _RenderCardSlot extends RenderProxyBox {
  _RenderCardSlot(this._board, this.id);

  final BoardFlightsState _board;
  final int id;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _board._slots[id] = this;
    _board._clock.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _board._clock.removeListener(markNeedsPaint);
    // The row of the new column can arrive before this one leaves.
    if (identical(_board._slots[id], this)) _board._slots.remove(id);
    super.detach();
  }

  // As in RenderTransform: a displaced card is hit where it is seen.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _board._shiftOf(id),
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _board._shiftOf(id);
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _board._settle(this);
    final card = child;
    if (card == null || _board._flights.containsKey(id)) return;
    context.paintChild(card, offset + _board._shiftOf(id));
  }
}
