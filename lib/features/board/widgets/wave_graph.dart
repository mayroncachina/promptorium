import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../board_rules.dart';

/// Dependency wave of each spec: 0 = depends on nothing on the board, else
/// 1 + the highest wave of its dependencies (cycles stop at the first
/// repeat).
Map<int, int> dependencyWaves(List<Spec> specs) {
  final byCode = specsByCode(specs);
  final waves = <int, int>{};
  int wave(Spec s, Set<int> path) {
    final known = waves[s.id];
    if (known != null) return known;
    if (!path.add(s.id)) return 0;
    var w = 0;
    for (final c in s.dependsOn) {
      final d = byCode[c];
      if (d != null) w = math.max(w, wave(d, path) + 1);
    }
    path.remove(s.id);
    return waves[s.id] = w;
  }

  for (final s in specs) {
    wave(s, {});
  }
  return waves;
}

/// First wave that still has a spec not done (null = all done).
int? nextWave(List<Spec> specs, Map<int, int> waves) {
  int? best;
  for (final s in specs) {
    if (s.stage == SpecStage.done) continue;
    final w = waves[s.id] ?? 0;
    if (best == null || w < best) best = w;
  }
  return best;
}

/// "Grafo" view of the Quadro: one column per dependency wave, an arrow
/// from each dependency to the spec that waits for it; the next wave is
/// highlighted while the autopilot runs.
class WaveGraph extends StatelessWidget {
  const WaveGraph({
    super.key,
    required this.specs,
    required this.cardBuilder,
    this.highlightNext = false,
  });

  final List<Spec> specs;
  final Widget Function(Spec) cardBuilder;
  final bool highlightNext;

  static const cardW = 250.0;
  static const cardH = 170.0;
  static const gapX = 70.0;
  static const gapY = 16.0;
  static const pad = 20.0;
  static const headerH = 28.0;

  @override
  Widget build(BuildContext context) {
    final waves = dependencyWaves(specs);
    final columns = <int, List<Spec>>{};
    for (final s in specs) {
      columns.putIfAbsent(waves[s.id] ?? 0, () => []).add(s);
    }
    final count = columns.isEmpty ? 0 : columns.keys.reduce(math.max) + 1;
    final next = nextWave(specs, waves);
    final pos = <int, Offset>{};
    for (var w = 0; w < count; w++) {
      final list = columns[w] ?? const <Spec>[];
      for (final (i, s) in list.indexed) {
        pos[s.id] = Offset(
          pad + w * (cardW + gapX),
          pad + headerH + i * (cardH + gapY),
        );
      }
    }
    final rows = columns.values.fold(0, (m, l) => math.max(m, l.length));
    final width = pad * 2 + count * cardW + math.max(0, count - 1) * gapX;
    final height = pad * 2 + headerH + rows * (cardH + gapY);
    final byCode = specsByCode(specs);
    final edges = [
      for (final s in specs)
        for (final c in s.dependsOn)
          if (byCode[c] case final d?
              when pos[d.id] != null && pos[s.id] != null)
            (pos[d.id]!, pos[s.id]!, d.stage == SpecStage.done),
    ];
    return SingleChildScrollView(
      key: const ValueKey('board-graph'),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _EdgesPainter(edges)),
              ),
              for (var w = 0; w < count; w++)
                Positioned(
                  left: pad + w * (cardW + gapX),
                  top: pad,
                  width: cardW,
                  child: Text(
                    'ONDA ${w + 1}${highlightNext && w == next ? ' · PRÓXIMA' : ''}',
                    key: ValueKey('board-wave-$w'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: highlightNext && w == next
                          ? AppColors.amber
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              for (final s in specs)
                if (pos[s.id] case final p?)
                  Positioned(
                    left: p.dx,
                    top: p.dy,
                    width: cardW,
                    height: cardH,
                    child: Container(
                      decoration: highlightNext && (waves[s.id] ?? 0) == next
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: AppColors.amber),
                            )
                          : null,
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: cardBuilder(s),
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

class _EdgesPainter extends CustomPainter {
  _EdgesPainter(this.edges);

  /// (dependency card, dependent card, dependency done).
  final List<(Offset, Offset, bool)> edges;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (from, to, done) in edges) {
      final paint = Paint()
        ..color = done ? AppColors.teal : AppColors.textMuted
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      final a = from + const Offset(WaveGraph.cardW, WaveGraph.cardH / 2);
      final b = to + const Offset(0, WaveGraph.cardH / 2);
      final mid = (a.dx + b.dx) / 2;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
      canvas.drawPath(path, paint);
      final head = Path()
        ..moveTo(b.dx, b.dy)
        ..lineTo(b.dx - 7, b.dy - 4)
        ..lineTo(b.dx - 7, b.dy + 4)
        ..close();
      canvas.drawPath(head, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_EdgesPainter old) => old.edges != edges;
}
