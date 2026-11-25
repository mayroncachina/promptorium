import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../ui/theme/motion.dart';
import '../../../../ui/theme/tokens.dart';
import '../replay_step.dart';
import 'replay_style.dart';

/// Geometry of the scrubber: one unit per step (P4), a cut of [pauseUnits]
/// before a long pause.
class ReplayAxis {
  ReplayAxis(this.steps, {Map<int, Duration>? pauses})
    : pauses = pauses ?? longPauses(steps) {
    var gaps = 0.0;
    pos = List<double>.filled(steps.length, 0);
    for (var i = 0; i < steps.length; i++) {
      if (this.pauses.containsKey(i)) gaps += pauseUnits;
      pos[i] = i + gaps;
    }
    units = steps.isEmpty ? 1 : pos.last + 1;
  }

  static const pauseUnits = 1.5;

  final List<ReplayStep> steps;
  final Map<int, Duration> pauses;
  late final List<double> pos;
  late final double units;

  /// Step whose center is nearest to [unit], among [allowed] (null = all).
  int? nearest(double unit, {bool Function(int)? allowed}) {
    if (steps.isEmpty) return null;
    // Binary search for the first step at or after unit.
    var lo = 0, hi = pos.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (pos[mid] + .5 < unit) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (allowed == null) {
      if (lo > 0 && (unit - (pos[lo - 1] + .5)).abs() < (pos[lo] + .5 - unit)) {
        return lo - 1;
      }
      return lo;
    }
    int? best;
    var bestD = double.infinity;
    for (var d = 0; d < steps.length + 1; d++) {
      var closer = false;
      for (final i in {lo - d, lo + d}) {
        if (i < 0 || i >= steps.length) continue;
        final dist = (pos[i] + .5 - unit).abs();
        if (dist <= bestD) closer = true;
        if (allowed(i) && dist < bestD) {
          bestD = dist;
          best = i;
        }
      }
      // Positions grow away from lo: once a ring is no closer, none is.
      if (best != null && !closer) break;
      if (lo - d < 0 && lo + d >= steps.length) break;
    }
    return best;
  }
}

/// The draggable timeline of the whole session (SPEC-082 R3, R13).
class ReplayScrubber extends StatefulWidget {
  const ReplayScrubber({
    super.key,
    required this.axis,
    required this.current,
    required this.onSeek,
    this.visible,
    this.root,
    this.turnText = const {},
  });

  final ReplayAxis axis;

  /// Top-level step under the cursor.
  final int current;
  final ValueChanged<int> onSeek;

  /// Steps inside the filter (null = all); the others are dimmed and the
  /// cursor skips them (R8, R9).
  final bool Function(int index)? visible;
  final String? root;

  /// Turn → the start of the message that opened it (the turn's tip).
  final Map<int, String> turnText;

  static const labelWidth = 92.0;
  static const topRow = 18.0;
  static const laneHeight = 20.0;
  static const ticksRow = 16.0;
  static const barRow = 8.0;
  static const height = topRow + laneHeight * 4 + ticksRow + barRow + 6;

  @override
  State<ReplayScrubber> createState() => _ReplayScrubberState();
}

class _ReplayScrubberState extends State<ReplayScrubber> {
  /// Visible window, in units.
  double _start = 0;
  double? _span;
  Offset? _hover;
  bool _dragging = false;

  double get _units => widget.axis.units;
  double get _spanOrAll =>
      (_span ?? _units).clamp(4.0, _units < 4 ? 4.0 : _units).toDouble();

  @override
  void didUpdateWidget(ReplayScrubber old) {
    super.didUpdateWidget(old);
    if (!identical(old.axis, widget.axis)) {
      _start = 0;
      _span = null;
    }
    if (old.current != widget.current) _follow();
  }

  /// Keeps the cursor inside the window when zoomed.
  void _follow() {
    if (_span == null || widget.current >= widget.axis.pos.length) return;
    final u = widget.axis.pos[widget.current];
    final span = _spanOrAll;
    if (u < _start || u + 1 > _start + span) {
      setState(
        () => _start = (u - span / 2).clamp(0.0, _units - span).toDouble(),
      );
    }
  }

  double _unitAt(double x, double width) {
    final w = width - ReplayScrubber.labelWidth;
    final rel = ((x - ReplayScrubber.labelWidth) / w).clamp(0.0, 1.0);
    return _start + rel * _spanOrAll;
  }

  void _seekAt(double x, double width) {
    final i = widget.axis.nearest(_unitAt(x, width), allowed: widget.visible);
    if (i != null && i != widget.current) widget.onSeek(i);
  }

  void _zoom(PointerScrollEvent e, double width) {
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed) {
      if (_span == null) return;
      // Plain wheel pans the zoomed window.
      final span = _spanOrAll;
      setState(() {
        _start = (_start + e.scrollDelta.dy / 40 * span / 10).clamp(
          0,
          math.max(0, _units - span),
        );
      });
      return;
    }
    final at = _unitAt(e.localPosition.dx, width);
    final span = _spanOrAll;
    final double next = (span * (e.scrollDelta.dy > 0 ? 1.25 : .8))
        .clamp(math.min(12.0, _units), _units)
        .toDouble();
    final rel = (at - _start) / span;
    setState(() {
      if (next >= _units) {
        _span = null;
        _start = 0;
      } else {
        _span = next;
        _start = (at - rel * next).clamp(0.0, _units - next);
      }
    });
  }

  ReplayStep? _hovered(double width) {
    final h = _hover;
    if (h == null || h.dx < ReplayScrubber.labelWidth) return null;
    final i = widget.axis.nearest(_unitAt(h.dx, width));
    return i == null ? null : widget.axis.steps[i];
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.axis.steps;
    final total = steps.length;
    final cur = total == 0 ? null : steps[widget.current.clamp(0, total - 1)];
    final animate = AppMotion.animate(context) && !_dragging;
    return Semantics(
      container: true,
      slider: true,
      label: 'Linha do tempo da sessão',
      value: cur == null ? '' : replaySemanticValue(cur, total),
      increasedValue: widget.current + 1 < total
          ? replaySemanticValue(steps[widget.current + 1], total)
          : null,
      decreasedValue: widget.current > 0
          ? replaySemanticValue(steps[widget.current - 1], total)
          : null,
      onIncrease: widget.current + 1 < total
          ? () => widget.onSeek(widget.current + 1)
          : null,
      onDecrease: widget.current > 0
          ? () => widget.onSeek(widget.current - 1)
          : null,
      child: LayoutBuilder(
        builder: (context, c) {
          final width = c.maxWidth;
          final hovered = _hovered(width);
          final cursorUnit = cur == null ? 0.0 : widget.axis.pos[cur.index];
          return Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) _zoom(e, width);
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onHover: (e) => setState(() => _hover = e.localPosition),
              onExit: (_) => setState(() => _hover = null),
              child: GestureDetector(
                key: const ValueKey('replay-scrubber'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _seekAt(d.localPosition.dx, width),
                onHorizontalDragStart: (d) {
                  setState(() => _dragging = true);
                  _seekAt(d.localPosition.dx, width);
                },
                onHorizontalDragUpdate: (d) {
                  _hover = d.localPosition;
                  _seekAt(d.localPosition.dx, width);
                },
                onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                child: SizedBox(
                  height: ReplayScrubber.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _TrackPainter(
                              axis: widget.axis,
                              start: _start,
                              span: _spanOrAll,
                              visible: widget.visible,
                              zoomed: _span != null,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: cursorUnit),
                          duration: animate ? AppMotion.quick : Duration.zero,
                          curve: AppMotion.enter,
                          builder: (_, u, _) => CustomPaint(
                            painter: _CursorPainter(
                              unit: u,
                              start: _start,
                              span: _spanOrAll,
                            ),
                          ),
                        ),
                      ),
                      if (hovered != null && _hover != null)
                        _Tip(
                          key: const ValueKey('replay-scrubber-tip'),
                          x: _hover!.dx,
                          width: width,
                          text: _hover!.dy < ReplayScrubber.topRow
                              ? _turnTip(hovered)
                              : replayStepTip(hovered, root: widget.root),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _turnTip(ReplayStep s) {
    final text = widget.turnText[s.turn];
    return text == null || text.isEmpty ? 'T${s.turn}' : 'T${s.turn} · "$text"';
  }
}

class _Tip extends StatelessWidget {
  const _Tip({
    super.key,
    required this.x,
    required this.width,
    required this.text,
  });

  final double x;
  final double width;
  final String text;

  @override
  Widget build(BuildContext context) {
    const maxW = 420.0;
    final left = (x + 12).clamp(0.0, math.max(0.0, width - maxW)).toDouble();
    return Positioned(
      left: left,
      top: -30,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxW),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: SessionColors.selectedBg,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.borderHover),
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _x(double unit, double start, double span, Size size) {
  final w = size.width - ReplayScrubber.labelWidth;
  return ReplayScrubber.labelWidth + (unit - start) / span * w;
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.axis,
    required this.start,
    required this.span,
    required this.visible,
    required this.zoomed,
  });

  final ReplayAxis axis;
  final double start;
  final double span;
  final bool Function(int)? visible;
  final bool zoomed;

  static const _laneTop = ReplayScrubber.topRow;

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    Color color = AppColors.textMuted,
    double size = 10,
    bool mono = true,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontFamily: mono ? AppFonts.mono : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final steps = axis.steps;
    final lanes = ReplayLane.values;
    final laneH = ReplayScrubber.laneHeight;
    final unitW = (size.width - ReplayScrubber.labelWidth) / span;
    final markW = (unitW * .72).clamp(1.0, 9.0);

    // Lane labels and backgrounds.
    for (var l = 0; l < lanes.length; l++) {
      final top = _laneTop + l * laneH;
      canvas.drawRect(
        Rect.fromLTWH(
          ReplayScrubber.labelWidth,
          top + 2,
          size.width - ReplayScrubber.labelWidth,
          laneH - 4,
        ),
        Paint()..color = ReplayColors.lane,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(6, top + laneH / 2 - 3.5, 7, 7),
          const Radius.circular(2),
        ),
        Paint()..color = ReplayColors.laneColor(lanes[l]),
      );
      _text(
        canvas,
        lanes[l].label,
        Offset(18, top + laneH / 2 - 7),
        color: AppColors.textSecondary,
        size: 11,
        mono: false,
      );
    }

    if (steps.isEmpty) return;
    final first = axis.nearest(start) ?? 0;
    final last = axis.nearest(start + span) ?? steps.length - 1;
    final from = math.max(0, first - 1);
    final to = math.min(steps.length - 1, last + 1);

    // Turn separators and labels.
    var lastTurnX = -1000.0;
    final sep = Paint()
      ..color = ReplayColors.turn
      ..strokeWidth = 1;
    for (var i = from; i <= to; i++) {
      final s = steps[i];
      final isStart = i == 0 || steps[i - 1].turn != s.turn;
      if (!isStart) continue;
      final x = _x(axis.pos[i], start, span, size);
      if (x < ReplayScrubber.labelWidth - 1) continue;
      for (var y = _laneTop; y < _laneTop + laneH * 4; y += 4) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 2), sep);
      }
      if (x - lastTurnX > 22) {
        _text(canvas, 'T${s.turn}', Offset(x + 2, 2));
        lastTurnX = x;
      }
    }

    // SPEC-110 R10: where the conversation went back to, with its label.
    for (var i = from; i <= to; i++) {
      final mark = steps[i].reverted;
      if (mark == null || (i > 0 && steps[i - 1].reverted?.key == mark.key)) {
        continue;
      }
      final x = _x(axis.pos[i], start, span, size);
      if (x < ReplayScrubber.labelWidth - 1) continue;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, _laneTop + laneH * 4),
        Paint()
          ..color = ReplayColors.error
          ..strokeWidth = 1.4,
      );
      _text(
        canvas,
        'conversa revertida antes do turno ${mark.turn}',
        Offset(x + 22, 2),
        color: ReplayColors.error,
        mono: false,
      );
    }

    // Long pauses: a cut "⋯ 2 h".
    for (final e in axis.pauses.entries) {
      if (e.key < from || e.key > to) continue;
      final x = _x(
        axis.pos[e.key] - ReplayAxis.pauseUnits / 2,
        start,
        span,
        size,
      );
      canvas.drawRect(
        Rect.fromLTWH(x - 3, _laneTop, 6, laneH * 4),
        Paint()..color = AppColors.backgroundSolid,
      );
      _text(
        canvas,
        '⋯ ${shortDuration(e.value)}',
        Offset(x - 12, _laneTop + laneH * 4 + 2),
      );
    }

    // Steps.
    final dim = Paint()..color = ReplayColors.dim;
    for (var i = from; i <= to; i++) {
      final s = steps[i];
      final x = _x(axis.pos[i] + .5, start, span, size);
      final on = visible == null || visible!(i);
      final lane = s.lane;
      if (lane == null) {
        // Marks: flags above the lanes, errors as a red "×".
        final color = on ? ReplayColors.markColor(s.mark) : ReplayColors.dim;
        if (s.mark?.isFlag ?? false) {
          final p = Paint()
            ..color = color
            ..strokeWidth = 1.2;
          canvas.drawLine(Offset(x, 4), Offset(x, 15), p);
          canvas.drawPath(
            Path()
              ..moveTo(x, 4)
              ..lineTo(x + 7, 6.5)
              ..lineTo(x, 9)
              ..close(),
            Paint()..color = color,
          );
        } else if (s.mark == ReplayMarkKind.error) {
          _text(canvas, '×', Offset(x - 3, 2), color: color, size: 11);
        }
        continue;
      }
      final top = _laneTop + lane.index * laneH + 4;
      final h = laneH - 8;
      final rect = Rect.fromLTWH(x - markW / 2, top, markW, h);
      if (!on) {
        canvas.drawRect(rect, dim);
        continue;
      }
      // SPEC-110 R10: what left the agent's conversation is dimmed.
      final gone = s.reverted != null;
      final color = gone
          ? ReplayColors.of(s).withValues(alpha: .3)
          : ReplayColors.of(s);
      if (s.outcome == ReplayOutcome.denied) {
        // Denied: a dash, not a block.
        canvas.drawLine(
          Offset(rect.left, rect.center.dy),
          Offset(rect.right + 2, rect.center.dy),
          Paint()
            ..color = ReplayColors.edit
            ..strokeWidth = 2,
        );
        // SPEC-110 R1: a denied approval is a mark too.
        _text(
          canvas,
          '–',
          Offset(x - 3, 2),
          color: ReplayColors.edit,
          size: 11,
        );
        continue;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()..color = color,
      );
      if (s.outcome == ReplayOutcome.error) {
        _text(
          canvas,
          '×',
          Offset(x - 3, 2),
          color: ReplayColors.error,
          size: 11,
        );
      }
    }

    // Hour ticks under the lanes, at least 70 px apart.
    final ticksTop = _laneTop + laneH * 4 + 2;
    var lastTick = -1000.0;
    for (var i = from; i <= to; i++) {
      final s = steps[i];
      if (s.at == null) continue;
      final x = _x(axis.pos[i], start, span, size);
      if (x < ReplayScrubber.labelWidth || x > size.width - 36) continue;
      if (x - lastTick < 90) continue;
      if (axis.pauses.containsKey(i) && x - lastTick < 130) continue;
      _text(canvas, clock(s.at), Offset(x, ticksTop));
      lastTick = x;
    }

    // Zoom bar: the visible part of the session.
    final barTop = ticksTop + ReplayScrubber.ticksRow;
    final full = size.width - ReplayScrubber.labelWidth;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(ReplayScrubber.labelWidth, barTop, full, 4),
        const Radius.circular(2),
      ),
      Paint()..color = ReplayColors.lane,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          ReplayScrubber.labelWidth + start / axis.units * full,
          barTop,
          math.max(6, span / axis.units * full),
          4,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = zoomed ? AppColors.textMuted : AppColors.border,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      !identical(old.axis, axis) ||
      old.start != start ||
      old.span != span ||
      old.visible != visible;
}

class _CursorPainter extends CustomPainter {
  _CursorPainter({required this.unit, required this.start, required this.span});

  final double unit;
  final double start;
  final double span;

  @override
  void paint(Canvas canvas, Size size) {
    final x = _x(unit + .5, start, span, size);
    if (x < ReplayScrubber.labelWidth - 2 || x > size.width + 2) return;
    final bottom = ReplayScrubber.topRow + ReplayScrubber.laneHeight * 4 + 8;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, bottom),
      Paint()
        ..color = AppColors.amber
        ..strokeWidth = 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, bottom + 4), width: 10, height: 10),
        const Radius.circular(2),
      ),
      Paint()..color = AppColors.amber,
    );
  }

  @override
  bool shouldRepaint(_CursorPainter old) =>
      old.unit != unit || old.start != start || old.span != span;
}

/// The lane of an open subagent, below the main one (P7, R5).
class ReplaySubagentLane extends StatelessWidget {
  const ReplaySubagentLane({
    super.key,
    required this.step,
    required this.child,
    required this.onSeek,
    required this.onClose,
  });

  /// The subagent step.
  final ReplayStep step;

  /// Its step under the cursor (null = the subagent itself).
  final int? child;
  final ValueChanged<int> onSeek;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final children = step.children;
    final input = step.tool?.input ?? const {};
    final type = input['subagent_type'];
    final desc = input['description'];
    final took = step.duration;
    return Container(
      key: ValueKey('replay-subagent-${step.index}'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: SessionColors.selectedBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReplayKindBadge(step),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    'Passo ${step.index + 1} · Subagente',
                    if (type is String && type.isNotEmpty) type,
                    if (desc is String && desc.isNotEmpty) '"$desc"',
                    '${children.length} passos',
                    if (took != null) formatDurationShort(took),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                ),
              ),
              TextButton(
                key: const ValueKey('replay-subagent-close'),
                onPressed: onClose,
                child: const Text('Recolher', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          SizedBox(
            height: 26,
            child: LayoutBuilder(
              builder: (context, c) {
                final n = math.max(1, children.length);
                final w = c.maxWidth / n;
                return GestureDetector(
                  key: const ValueKey('replay-subagent-lane'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      onSeek((d.localPosition.dx / w).floor().clamp(0, n - 1)),
                  child: Stack(
                    children: [
                      for (var i = 0; i < children.length; i++)
                        Positioned(
                          left: i * w + w * .1,
                          width: math.max(2, w * .8),
                          top: children[i].lane == ReplayLane.talk ? 15 : 3,
                          height: 8,
                          child: Tooltip(
                            message: replayStepTip(children[i]),
                            child: Container(
                              decoration: BoxDecoration(
                                color: ReplayColors.of(children[i]),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            ),
                          ),
                        ),
                      if (child != null && child! < children.length)
                        Positioned(
                          left: child! * w + w / 2 - 1,
                          width: 2,
                          top: 0,
                          bottom: 0,
                          child: const ColoredBox(color: AppColors.amber),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
