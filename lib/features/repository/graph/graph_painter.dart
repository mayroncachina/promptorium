import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import 'lane_layout.dart';
import 'spec_branch.dart';

/// Geometry of a row of the graph (docs/mockups/repositorio/GrafoLista.dc.html).
const graphRowHeight = 36.0;
const graphLaneStep = 16.0;
const graphLaneStart = 12.0;

/// Width of the GRAFO column: at least the mockup's 104 px.
double graphColumnWidth(int lanes) =>
    (graphLaneStart * 2 + (lanes - 1) * graphLaneStep).clamp(104.0, 400.0);

double laneX(int column) => graphLaneStart + column * graphLaneStep;

/// Column under [dx] (null between lanes).
int? laneAt(double dx) {
  final c = ((dx - graphLaneStart) / graphLaneStep).round();
  if (c < 0 || (dx - laneX(c)).abs() > graphLaneStep / 2) return null;
  return c;
}

/// Colour of a branch's lane (R2): the default branch in light grey, a spec
/// in its colour (its tasks lighter), the others neutral.
Color trackColor(String? track, String defaultBranch) {
  if (track == null) return SpecColors.other;
  if (track == defaultBranch || track.endsWith('/$defaultBranch')) {
    if (parseSpecBranch(track) == null) return SpecColors.defaultBranch;
  }
  final spec = parseSpecBranch(track);
  if (spec == null) return SpecColors.other;
  return spec.isTask
      ? SpecColors.task(spec.number)
      : SpecColors.of(spec.number);
}

/// What lights up together under the pointer (R8): a spec with its tasks,
/// or the branch alone.
Object? highlightKeyOf(String? track) {
  final spec = parseSpecBranch(track);
  return spec?.number ?? track;
}

/// Draws one row of the graph: the lanes that cross it and the commit's
/// node (R1). With [highlight], the lanes of other branches dim (R8).
class GraphRowPainter extends CustomPainter {
  GraphRowPainter({
    required this.row,
    required this.defaultBranch,
    this.highlight,
  });

  final LaneRow row;
  final String defaultBranch;

  /// [highlightKeyOf] of the lane under the pointer.
  final Object? highlight;

  static const _dimmed = 0.3;

  Color _color(String? track) {
    final c = trackColor(track, defaultBranch);
    if (highlight == null || highlightKeyOf(track) == highlight) return c;
    return c.withValues(alpha: _dimmed);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const mid = graphRowHeight / 2;
    final nx = laneX(row.column);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final s in row.segments) {
      stroke.color = _color(s.track);
      final x = laneX(s.column);
      final path = Path();
      switch (s.kind) {
        case SegmentKind.pass:
          path
            ..moveTo(x, 0)
            ..lineTo(x, graphRowHeight);
        case SegmentKind.into:
          path.moveTo(x, 0);
          if (s.column == row.column) {
            path.lineTo(nx, mid);
          } else {
            path.cubicTo(x, 12, nx, 6, nx, mid);
          }
        case SegmentKind.outOf:
          path.moveTo(nx, mid);
          if (s.column == row.column) {
            path.lineTo(x, graphRowHeight);
          } else {
            path.cubicTo(nx, 30, x, 24, x, graphRowHeight);
          }
      }
      canvas.drawPath(path, stroke);
    }
    final color = _color(row.track);
    final hollow = row.kind != NodeKind.commit;
    final r = hollow ? 5.0 : 4.0;
    canvas.drawCircle(
      Offset(nx, mid),
      r,
      Paint()..color = hollow ? AppColors.backgroundSolid : color,
    );
    canvas.drawCircle(
      Offset(nx, mid),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    if (row.kind == NodeKind.summary) {
      canvas.drawCircle(Offset(nx, mid), 1.8, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(GraphRowPainter old) =>
      old.row != row ||
      old.highlight != highlight ||
      old.defaultBranch != defaultBranch;
}
