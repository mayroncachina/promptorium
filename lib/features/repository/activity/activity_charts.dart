import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';

/// Whole days from [a] to [b] (local dates; DST does not shift them).
int daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Where each day goes on the map (R2): a column per week (Monday first),
/// a row per weekday.
@immutable
class HeatmapGeometry {
  const HeatmapGeometry({
    required this.start,
    required this.weeks,
    required this.cell,
    this.gap = 4,
    this.left = 34,
    this.top = 20,
  });

  /// Monday of the first column.
  final DateTime start;
  final int weeks;
  final double cell, gap, left, top;

  double get step => cell + gap;

  Size get size => Size(left + weeks * step - gap, top + 7 * step - gap);

  int columnOf(DateTime day) => daysBetween(start, day) ~/ 7;

  Rect rectOf(DateTime day) {
    final col = columnOf(day);
    final row = day.weekday - DateTime.monday;
    return Rect.fromLTWH(left + col * step, top + row * step, cell, cell);
  }

  /// The day under [p] (null between cells or outside the grid).
  DateTime? dayAt(Offset p) {
    final x = p.dx - left, y = p.dy - top;
    if (x < 0 || y < 0) return null;
    final col = x ~/ step, row = y ~/ step;
    if (col >= weeks || row >= 7) return null;
    if (x - col * step > cell || y - row * step > cell) return null;
    return DateTime(start.year, start.month, start.day + col * 7 + row);
  }
}

/// Colours of the map, from empty to the most commits (R2).
abstract final class HeatmapColors {
  static const empty = Color(0xFF1C2028);
  static const tones = [
    empty,
    Color(0xFF4A3A20),
    Color(0xFF7A5A26),
    Color(0xFFB27D33),
    AppColors.amber,
  ];

  /// Ring of a release day.
  static const release = Color(0xFFE7E9EE);
}

/// One cell of the map.
@immutable
class HeatCell {
  const HeatCell(this.day, this.level, {this.release = false});

  final DateTime day;
  final int level;
  final bool release;
}

/// Draws the map (R2): the cells, the release rings, the month and day
/// labels.
class HeatmapPainter extends CustomPainter {
  HeatmapPainter({
    required this.geometry,
    required this.cells,
    required this.months,
    this.hover,
  });

  final HeatmapGeometry geometry;
  final List<HeatCell> cells;

  /// Column → month label (`ago`).
  final Map<int, String> months;
  final DateTime? hover;

  static const _label = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 11,
    color: AppColors.textMuted,
  );

  void _text(Canvas canvas, String s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: _label),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    for (final e in months.entries) {
      _text(canvas, e.value, Offset(g.left + e.key * g.step, 0));
    }
    for (final (row, name) in [(0, 'seg'), (2, 'qua'), (4, 'sex')]) {
      _text(canvas, name, Offset(0, g.top + row * g.step + g.cell / 2 - 7));
    }
    final radius = Radius.circular(math.min(4, g.cell / 5));
    for (final c in cells) {
      final r = g.rectOf(c.day);
      final rr = RRect.fromRectAndRadius(r, radius);
      canvas.drawRRect(
        rr,
        Paint()..color = HeatmapColors.tones[c.level.clamp(0, 4)],
      );
      if (c.release) {
        canvas.drawRRect(
          rr.deflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = HeatmapColors.release,
        );
      }
      if (hover != null && c.day == hover) {
        canvas.drawRRect(
          rr.inflate(1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = AppColors.amber,
        );
      }
    }
  }

  @override
  bool shouldRepaint(HeatmapPainter old) =>
      old.cells != cells || old.hover != hover || old.geometry != geometry;
}

/// A piece of a stacked bar.
typedef BarPiece = ({Color color, int value});

/// Stacked bars, one per week (R3, R8), drawn bottom-up in the order of
/// each list; [max] is the top of the scale.
class StackedBarsPainter extends CustomPainter {
  StackedBarsPainter({
    required this.bars,
    required this.max,
    this.hover,
    this.gap = 8,
  });

  final List<List<BarPiece>> bars;
  final int max;
  final int? hover;
  final double gap;

  /// Width of one bar in [width].
  static double barWidth(double width, int count, double gap) =>
      count == 0 ? 0 : math.max(2, (width - gap * (count - 1)) / count);

  /// The bar under [dx] (null in a gap).
  static int? barAt(double dx, double width, int count, double gap) {
    if (count == 0 || dx < 0) return null;
    final w = barWidth(width, count, gap);
    final i = dx ~/ (w + gap);
    if (i >= count) return null;
    return dx - i * (w + gap) <= w ? i : null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = barWidth(size.width, bars.length, gap);
    final scale = max <= 0 ? 0.0 : size.height / max;
    for (final (i, pieces) in bars.indexed) {
      final x = i * (w + gap);
      var y = size.height;
      final nonEmpty = pieces.where((p) => p.value > 0).toList();
      for (final (k, p) in nonEmpty.indexed) {
        final h = p.value * scale;
        final top = k == nonEmpty.length - 1;
        final rect = Rect.fromLTWH(x, y - h, w, h);
        // A hair of gap between the pieces, as in the mockup.
        final r = Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          math.max(rect.top, rect.bottom - (k == 0 ? 0 : 1.5)),
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            r,
            topLeft: top ? const Radius.circular(3) : Radius.zero,
            topRight: top ? const Radius.circular(3) : Radius.zero,
          ),
          Paint()
            ..color = hover == null || hover == i
                ? p.color
                : p.color.withValues(alpha: .55),
        );
        y -= h;
      }
    }
  }

  @override
  bool shouldRepaint(StackedBarsPainter old) =>
      old.bars != bars || old.max != max || old.hover != hover;
}
