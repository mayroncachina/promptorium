import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/tokens.dart';
import '../context_snapshot.dart';

/// One point of the Evolução chart: the last reading of a turn (or of the
/// part of a turn before a compaction).
@immutable
class ContextPoint {
  const ContextPoint(this.reading, this.index);

  final ContextReading reading;

  /// Position in [ContextSnapshot.readings].
  final int index;
}

/// The chart's points (R6): real readings only, one per turn segment.
List<ContextPoint> contextPoints(ContextSnapshot s) {
  final cuts = {for (final m in s.markers) m.readingsBefore};
  final out = <ContextPoint>[];
  final rs = s.readings;
  for (var i = 0; i < rs.length; i++) {
    final last = i == rs.length - 1;
    if (last || rs[i + 1].turn != rs[i].turn || cuts.contains(i + 1)) {
      out.add(ContextPoint(rs[i], i));
    }
  }
  return out;
}

/// Small line chart of the readings with compaction / model markers (R6).
/// Arrow keys move the selection; Enter goes to the turn (R12).
class ContextEvolution extends StatefulWidget {
  const ContextEvolution({
    super.key,
    required this.snapshot,
    this.onJump,
    this.height = 130,
  });

  final ContextSnapshot snapshot;

  /// "Ir ao turno": the reading's timeline position.
  final ValueChanged<ContextReading>? onJump;
  final double height;

  @override
  State<ContextEvolution> createState() => _ContextEvolutionState();
}

class _ContextEvolutionState extends State<ContextEvolution> {
  int? _selected;
  final _focus = FocusNode(debugLabel: 'context-evolution');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final points = contextPoints(s);
    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Sem leituras ainda: o gráfico começa na primeira medição.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    final sel = (_selected ?? points.length - 1).clamp(0, points.length - 1);
    final p = points[sel];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _PointTip(
            point: p,
            onJump: widget.onJump == null
                ? null
                : () => widget.onJump!(p.reading),
          ),
        ),
        const SizedBox(height: 6),
        Focus(
          focusNode: _focus,
          onKeyEvent: (_, e) {
            if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final k = e.logicalKey;
            if (k == LogicalKeyboardKey.arrowLeft) {
              setState(() => _selected = math.max(0, sel - 1));
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.arrowRight) {
              setState(() => _selected = math.min(points.length - 1, sel + 1));
              return KeyEventResult.handled;
            }
            if ((k == LogicalKeyboardKey.enter ||
                    k == LogicalKeyboardKey.numpadEnter) &&
                widget.onJump != null) {
              widget.onJump!(p.reading);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Semantics(
            label: evolutionSummary(s, points),
            value: pointLabel(p.reading),
            increasedValue: sel < points.length - 1
                ? pointLabel(points[sel + 1].reading)
                : null,
            decreasedValue: sel > 0
                ? pointLabel(points[sel - 1].reading)
                : null,
            onIncrease: sel < points.length - 1
                ? () => setState(() => _selected = sel + 1)
                : null,
            onDecrease: sel > 0
                ? () => setState(() => _selected = sel - 1)
                : null,
            child: AnimatedBuilder(
              animation: _focus,
              builder: (context, child) => Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _focus.hasFocus
                        ? AppColors.amber
                        : Colors.transparent,
                  ),
                ),
                child: child,
              ),
              child: LayoutBuilder(
                builder: (context, c) => GestureDetector(
                  key: const ValueKey('context-evolution-chart'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    _focus.requestFocus();
                    final i = _hit(d.localPosition.dx, c.maxWidth, points);
                    if (i != null) setState(() => _selected = i);
                  },
                  child: SizedBox(
                    height: widget.height,
                    child: CustomPaint(
                      painter: _ChartPainter(s, points, sel),
                      size: Size(c.maxWidth, widget.height),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  int? _hit(double x, double width, List<ContextPoint> points) {
    if (points.isEmpty) return null;
    var best = 0;
    var dist = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final px = _ChartPainter.xOf(i, points.length, width);
      if ((px - x).abs() < dist) {
        dist = (px - x).abs();
        best = i;
      }
    }
    return best;
  }
}

String pointLabel(ContextReading r) =>
    'Turno ${r.turn} · ${contextTokens(r.tokens)} · ${contextTime(r.at)}';

/// Text alternative of the chart (R12).
String evolutionSummary(ContextSnapshot s, List<ContextPoint> points) {
  final b = StringBuffer(
    'Evolução do contexto: ${points.length} '
    '${points.length == 1 ? 'leitura' : 'leituras'}',
  );
  for (final m in s.markers) {
    if (m.kind == ContextMarkerKind.compaction) {
      b.write('. Turno ${m.turn}: compactou');
      if (m.preTokens != null) {
        b.write(' (antes ${contextTokens(m.preTokens!)})');
      }
    } else {
      b.write('. Turno ${m.turn}: troca de modelo');
    }
  }
  return b.toString();
}

class _PointTip extends StatelessWidget {
  const _PointTip({required this.point, this.onJump});

  final ContextPoint point;
  final VoidCallback? onJump;

  @override
  Widget build(BuildContext context) {
    final r = point.reading;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.backgroundSolid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderHover),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Turno ${r.turn} · ${contextTokens(r.tokens)}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          Text(
            ' · ${contextTime(r.at)}',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (onJump != null) ...[
            const Text(
              ' · ',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
            InkWell(
              key: const ValueKey('context-jump'),
              onTap: onJump,
              child: const Text(
                'Ir ao turno ↲',
                style: TextStyle(fontSize: 11.5, color: AppColors.text),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.s, this.points, this.selected);

  final ContextSnapshot s;
  final List<ContextPoint> points;
  final int selected;

  static const _left = 28.0;
  static const _right = 12.0;
  static const _bottom = 18.0;
  static const _top = 8.0;

  static double xOf(int i, int n, double width) {
    final w = width - _left - _right;
    return n <= 1 ? _left + w : _left + w * i / (n - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    final maxReading = points.map((p) => p.reading.tokens).reduce(math.max);
    final t = s.threshold;
    final top = math.max(maxReading, t ?? 0) * 1.1;
    final h = size.height - _top - _bottom;
    double y(num v) => _top + h * (1 - v / top);
    double x(int i) => xOf(i, n, size.width);
    final label = TextPainter(textDirection: TextDirection.ltr);
    void text(String v, Offset at, {Color color = AppColors.textMuted}) {
      label
        ..text = TextSpan(
          text: v,
          style: TextStyle(
            fontSize: 9.5,
            color: color,
            fontFamily: AppFonts.mono,
          ),
        )
        ..layout();
      label.paint(canvas, at);
    }

    // Axis: 0 and the threshold (thousands, as in the mock).
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(_left, y(0)),
      Offset(size.width - _right, y(0)),
      grid,
    );
    text('0', Offset(4, y(0) - 6));
    if (t != null) {
      final ty = y(t);
      _dashed(
        canvas,
        Offset(_left, ty),
        Offset(size.width - _right, ty),
        Paint()
          ..color = AppColors.teal.withValues(alpha: .6)
          ..strokeWidth = 1,
      );
      text('${(t / 1000).round()}', Offset(2, ty - 6), color: AppColors.teal);
    }
    // Markers between the points.
    for (final m in s.markers) {
      final after = points.indexWhere((p) => p.index >= m.readingsBefore);
      final mx = after <= 0
          ? x(0)
          : after < 0
          ? x(n - 1)
          : (x(after - 1) + x(after)) / 2;
      if (m.kind == ContextMarkerKind.compaction) {
        canvas.drawLine(
          Offset(mx, _top),
          Offset(mx, y(0)),
          Paint()
            ..color = AppColors.teal
            ..strokeWidth = 1.5,
        );
        canvas.drawRect(
          Rect.fromCenter(center: Offset(mx, _top + 4), width: 8, height: 8),
          Paint()..color = AppColors.teal,
        );
      } else {
        _dashed(
          canvas,
          Offset(mx, _top),
          Offset(mx, y(0)),
          Paint()
            ..color = AppColors.lilac.withValues(alpha: .8)
            ..strokeWidth = 1,
        );
        final path = Path()
          ..moveTo(mx, _top)
          ..lineTo(mx + 5, _top + 5)
          ..lineTo(mx, _top + 10)
          ..lineTo(mx - 5, _top + 5)
          ..close();
        canvas.drawPath(path, Paint()..color = AppColors.lilac);
      }
    }
    // Line, broken at each compaction (no interpolation across it).
    final cuts = {
      for (final m in s.markers)
        if (m.kind == ContextMarkerKind.compaction) m.readingsBefore,
    };
    final line = Paint()
      ..color = AppColors.amber
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < n; i++) {
      final o = Offset(x(i), y(points[i].reading.tokens));
      if (i > 0) {
        final broken = cuts.any(
          (c) => c > points[i - 1].index && c <= points[i].index,
        );
        if (!broken) {
          canvas.drawLine(
            Offset(x(i - 1), y(points[i - 1].reading.tokens)),
            o,
            line,
          );
        }
      }
      canvas.drawCircle(o, 2.6, Paint()..color = AppColors.amber);
      if (n <= 16 || i % (n ~/ 12 + 1) == 0 || i == n - 1) {
        text('${points[i].reading.turn}', Offset(o.dx - 3, size.height - 13));
      }
    }
    final sp = Offset(x(selected), y(points[selected].reading.tokens));
    canvas.drawCircle(
      sp,
      6,
      Paint()
        ..color = AppColors.amberLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    final d = (b - a).distance;
    final dir = (b - a) / d;
    for (var s = 0.0; s < d; s += 6) {
      canvas.drawLine(a + dir * s, a + dir * math.min(s + 3, d), p);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      !identical(old.s, s) || old.selected != selected;
}
