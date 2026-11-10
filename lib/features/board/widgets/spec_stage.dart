import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../board_rules.dart';
import '../board_screen.dart';
import '../spec_references.dart';
import 'canvas_view_controller.dart';
import 'spec_canvas.dart';
import '../attention_shake.dart';
import 'spec_node.dart';
import '../../../ui/theme/ambient.dart';

/// Sizes of the stage (docs/mockups/spec-036/Main.dc.html).
const stageRootSize = Size(330, 150), stageCardSize = Size(250, 116);
const stageRunningSize = Size(320, 206);

/// A card that needs the person has one more line (SPEC-030 R4).
const _reasonHeight = 18.0;
const _levelGap = 44.0, _cardGap = 24.0, _pad = 40.0, _rootTop = 44.0;

/// Distance from the widest card to the first lane, and between lanes.
const _laneGap = 30.0, _laneStep = 14.0;

/// One arrow of the stage, in the coordinates of the world.
@immutable
class StageArrow {
  const StageArrow(this.edge, this.path, this.tip);

  final StageEdge edge;
  final Path path;

  /// Where the head goes.
  final Offset tip;
}

/// Where everything of a [StageLayout] goes.
@immutable
class StageGeometry {
  const StageGeometry(this.layout, this.rects, this.arrows, this.bounds);

  final StageLayout layout;
  final Map<int, Rect> rects;
  final List<StageArrow> arrows;

  /// All that must be seen, the arrows included.
  final Rect bounds;
}

/// Size of a card of the stage.
Size stageCardSizeOf({
  required bool root,
  required bool attention,
  bool running = false,
}) {
  final size = running
      ? stageRunningSize
      : root
      ? stageRootSize
      : stageCardSize;
  return attention ? Size(size.width, size.height + _reasonHeight) : size;
}

/// Polyline with rounded corners.
Path _rounded(List<Offset> points, {double radius = 10}) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length - 1; i++) {
    final (a, b, c) = (points[i - 1], points[i], points[i + 1]);
    final r = math.min(
      radius,
      math.min((b - a).distance, (c - b).distance) / 2,
    );
    final enter = b + (a - b) / (a - b).distance * r;
    final leave = b + (c - b) / (c - b).distance * r;
    path
      ..lineTo(enter.dx, enter.dy)
      ..quadraticBezierTo(b.dx, b.dy, leave.dx, leave.dy);
  }
  return path..lineTo(points.last.dx, points.last.dy);
}

/// Levels top to bottom, centered on the root; the dependencies that skip a
/// level go through lanes to the right of the cards they would cross, and
/// change sides in the gaps between levels (R9, R10).
StageGeometry stageGeometry(StageLayout layout, Size Function(Spec) sizeOf) {
  final raw = <int, Rect>{};
  final levelOf = <int, int>{};
  final bottoms = <double>[];
  // The line of dependencies wraps when there are many (R17).
  final deps = layout.running ? 0 : layout.root.dependsOn.length;
  var y = _rootTop + 20.0 * math.max(0, deps - 1);
  for (final (i, level) in layout.levels.indexed) {
    final sizes = [for (final s in level) sizeOf(s)];
    final total =
        sizes.fold(0.0, (w, s) => w + s.width) + _cardGap * (level.length - 1);
    var x = -total / 2;
    for (final (j, spec) in level.indexed) {
      raw[spec.id] = Offset(x, y) & sizes[j];
      levelOf[spec.id] = i;
      x += sizes[j].width + _cardGap;
    }
    y += sizes.map((s) => s.height).reduce(math.max);
    bottoms.add(y);
    y += _levelGap;
  }
  final left = raw.values.map((r) => r.left).reduce(math.min);
  final rects = {
    for (final e in raw.entries) e.key: e.value.shift(Offset(_pad - left, 0)),
  };
  final arrows = <StageArrow>[];
  var bounds = rects.values.reduce((a, b) => a.expandToInclude(b));
  if (deps > 0) {
    bounds = bounds.expandToInclude(Rect.fromLTWH(bounds.left, 0, 1, 1));
  }
  var lane = 0;
  for (final e in layout.edges) {
    final from = rects[e.from.id]!, to = rects[e.to.id]!;
    if (!e.skips) {
      final a = from.bottomCenter, b = to.topCenter;
      final mid = (a.dy + b.dy) / 2;
      arrows.add(
        StageArrow(
          e,
          Path()
            ..moveTo(a.dx, a.dy)
            ..cubicTo(a.dx, mid, b.dx, mid, b.dx, b.dy),
          b,
        ),
      );
      continue;
    }
    final first = levelOf[e.from.id]!, last = levelOf[e.to.id]!;
    final widest = [
      for (final entry in rects.entries)
        if (levelOf[entry.key]! > first && levelOf[entry.key]! < last)
          entry.value.right,
    ].reduce(math.max);
    final x = widest + _laneGap + lane * _laneStep;
    final shift = (lane % 4) * 4.0;
    final out = bottoms[first] + _levelGap / 2 - shift;
    final into = to.top - _levelGap / 2 + shift;
    final start = Offset(from.center.dx + from.width / 4, from.bottom);
    final end = Offset(to.center.dx + to.width / 4, to.top);
    arrows.add(
      StageArrow(
        e,
        _rounded([
          start,
          Offset(start.dx, out),
          Offset(x, out),
          Offset(x, into),
          Offset(end.dx, into),
          end,
        ]),
        end,
      ),
    );
    bounds = bounds.expandToInclude(Rect.fromLTWH(x, out, 1, into - out));
    lane++;
  }
  return StageGeometry(layout, rects, arrows, bounds);
}

/// How much of [arrow] is drawn, from 0 to 1.
typedef ArrowProgress = double Function(StageArrow arrow);

/// The dependencies: each line draws itself and the head comes at the end;
/// amber between neighbours, grey when it skips a level (R10).
class StageArrowsPainter extends CustomPainter {
  StageArrowsPainter(this.arrows, this.progress, {super.repaint});

  final List<StageArrow> arrows;
  final ArrowProgress progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in arrows) {
      final done = progress(a);
      if (done <= 0) continue;
      final color = a.edge.skips ? AppColors.textMuted : AppColors.amber;
      final line = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      if (done >= 1) {
        canvas.drawPath(a.path, line);
      } else {
        for (final PathMetric m in a.path.computeMetrics()) {
          canvas.drawPath(m.extractPath(0, m.length * done), line);
        }
      }
      if (done >= 1) {
        final t = a.tip;
        canvas.drawPath(
          Path()
            ..moveTo(t.dx, t.dy)
            ..lineTo(t.dx - 6, t.dy - 9)
            ..lineTo(t.dx + 6, t.dy - 9)
            ..close(),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant StageArrowsPainter old) =>
      old.arrows != arrows || old.progress != progress;
}

/// The stage of the Foco view (SPEC-036 R8–R11, R17, R18): a spec at the top,
/// what depends on it below, with the pan and zoom of the Canvas.
class FocusStage extends ConsumerStatefulWidget {
  const FocusStage({
    super.key,
    required this.view,
    required this.geometry,
    required this.cards,
    required this.attention,
    required this.onOpen,
    required this.onBack,
    required this.onBackgroundTap,
    required this.runningCount,
    required this.onRunning,
    this.clock,
    this.inFlight,
    this.arrowProgress,
    this.sprintLabel,
  });

  /// Name of the sprint of a spec outside the one on the Quadro (SPEC-042 R8).
  final String? Function(Spec)? sprintLabel;

  /// Owned by the Foco view, where its shortcuts are.
  final CanvasViewController view;

  /// Null = nothing on the stage.
  final StageGeometry? geometry;

  /// Every card of the Quadro, by spec id.
  final Map<int, SpecCardData> cards;
  final bool Function(SpecCardData) attention;
  final ValueChanged<int> onOpen;
  final VoidCallback onBack, onBackgroundTap;

  /// N of "Executando"; at zero the button is off (R12).
  final int runningCount;
  final VoidCallback onRunning;

  /// Ticks during the flights.
  final Listenable? clock;

  /// The card is still in the air: its place on the stage takes clicks and
  /// keys, and only the painting is left to the flight (R15).
  final bool Function(int id)? inFlight;

  /// Null = the arrows are all there.
  final ArrowProgress? arrowProgress;

  @override
  ConsumerState<FocusStage> createState() => FocusStageState();
}

class FocusStageState extends ConsumerState<FocusStage>
    with TickerProviderStateMixin {
  CanvasViewController get _view => widget.view;
  Rect? _framed;

  /// One clock for the balloons and halos (SPEC-030 R2).
  AnimationController? _pulse;

  void _syncPulse(bool wanted) {
    if (wanted && _pulse == null) {
      _pulse = AnimationController(
        vsync: AmbientVsync(context),
        duration: attentionPulsePeriod,
      )..repeat();
    } else if (!wanted && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  /// Shows all that is on the stage; zooms out only when it does not fit
  /// (R11).
  void frame() {
    final g = widget.geometry;
    if (g != null) _view.frame(g.bounds, middle: g.layout.running);
  }

  /// The cards on screen, in the coordinates of [layer].
  Map<int, Rect> screenRects(RenderBox layer) {
    final g = widget.geometry;
    if (g == null) return {};
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: layer);
    return {
      for (final e in g.rects.entries)
        e.key: MatrixUtils.transformRect(_view.value, e.value).shift(origin),
    };
  }

  /// The free area changed (the folder, the panel, the window): recentralizes.
  void _keepFramed(Size size, EdgeInsets padding) {
    final free = padding.deflateRect(Offset.zero & size);
    if (free == _framed) return;
    _framed = free;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) frame();
    });
  }

  Widget _card(StageGeometry g, Spec spec, int? selectedId) {
    final d = widget.cards[spec.id]!;
    final root = !g.layout.running && spec.id == g.layout.root.id;
    final attention = widget.attention(d);
    final node = AttentionShake(
      specId: spec.id,
      child: AttentionHalo(
        enabled: attention,
        pulse: _pulse,
        child: SpecNode(
          data: d,
          selected: root,
          reason: attention ? specAttentionReason(ref, d) : null,
          pulse: _pulse,
          footer: g.layout.running ? StageRunningLine(data: d) : null,
          onTap: () => widget.onOpen(spec.id),
        ),
      ),
    );
    final clock = widget.clock;
    final inFlight = widget.inFlight;
    final label = widget.sprintLabel?.call(spec);
    final card = label == null
        ? node
        : Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: node),
              Positioned(
                right: 10,
                bottom: -9,
                child: Container(
                  key: ValueKey('stage-sprint-${spec.code}'),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: AppColors.textMuted),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          );
    return KeyedSubtree(
      key: ValueKey('stage-node-${spec.code}'),
      child: clock == null || inFlight == null
          ? card
          : ListenableBuilder(
              listenable: clock,
              child: card,
              builder: (_, child) =>
                  Opacity(opacity: inFlight(spec.id) ? 0 : 1, child: child),
            ),
    );
  }

  Widget _dependsOn(Spec root) => Wrap(
    key: const ValueKey('stage-depends'),
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 4,
    children: [
      const Text(
        'Depende de',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      for (final (i, code) in root.dependsOn.indexed)
        _DependencyLink(
          code: code,
          last: i == root.dependsOn.length - 1,
          onTap: _idOf(code) == null ? null : () => widget.onOpen(_idOf(code)!),
        ),
    ],
  );

  int? _idOf(String code) => widget.cards.values
      .where((d) => d.spec.code == code)
      .firstOrNull
      ?.spec
      .id;

  Widget _world(StageGeometry g, int? selectedId) {
    final running = g.layout.running;
    final root = g.layout.root;
    final rootRect = g.rects[root.id]!;
    final width = g.bounds.right + _pad;
    final height = g.bounds.bottom + _pad + (g.layout.dependents == 0 ? 40 : 0);
    final clock = widget.clock;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              key: const ValueKey('stage-arrows'),
              painter: StageArrowsPainter(
                g.arrows,
                widget.arrowProgress ?? (_) => 1,
                repaint: clock,
              ),
            ),
          ),
          if (!running && root.dependsOn.isNotEmpty)
            Positioned(
              left: rootRect.left,
              width: rootRect.width,
              bottom: height - rootRect.top + 8,
              child: _dependsOn(root),
            ),
          for (final spec in g.layout.specs)
            Positioned.fromRect(
              rect: g.rects[spec.id]!,
              child: _card(g, spec, selectedId),
            ),
          for (final spec in g.layout.specs)
            if (widget.attention(widget.cards[spec.id]!))
              Positioned(
                left: g.rects[spec.id]!.left,
                top: g.rects[spec.id]!.top - 13,
                width: g.rects[spec.id]!.width - 12,
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AttentionBadge(
                      key: ValueKey('stage-attention-${spec.code}'),
                    ),
                  ),
                ),
              ),
          if (!running && g.layout.dependents == 0)
            Positioned(
              left: rootRect.left,
              width: rootRect.width,
              top: rootRect.bottom + 16,
              child: Text(
                'Nenhuma spec depende de ${root.code}',
                key: const ValueKey('stage-no-dependents'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _crumb(StageLayout layout) {
    if (layout.running) {
      final n = layout.levels.first.length;
      return n == 1 ? '1 spec em execução' : '$n specs em execução';
    }
    final n = layout.dependents;
    final code = layout.root.code;
    return switch (n) {
      0 => code,
      1 => '1 spec depende de $code',
      _ => '$n specs dependem de $code',
    };
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.geometry;
    final selectedId = ref.watch(boardSelectedSpecProvider);
    final root = g == null || g.layout.running
        ? null
        : widget.cards[g.layout.root.id];
    final panel = root != null && selectedId == root.spec.id ? root : null;
    _syncPulse(
      g != null &&
          g.layout.specs.any((s) => widget.attention(widget.cards[s.id]!)) &&
          !MediaQuery.disableAnimationsOf(context),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final padding = EdgeInsets.fromLTRB(
          24,
          96,
          panel == null ? 24 : canvasPanelWidth + 48,
          24,
        );
        _view
          ..viewport = box.biggest
          ..padding = padding;
        _keepFramed(box.biggest, padding);
        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: CanvasDotGrid(_view)),
              ),
            ),
            if (g == null)
              const _StageHint()
            else ...[
              Positioned.fill(
                child: Listener(
                  onPointerSignal: _view.onPointerSignal,
                  child: GestureDetector(
                    onTap: widget.onBackgroundTap,
                    child: InteractiveViewer(
                      key: const ValueKey('stage-view'),
                      transformationController: _view,
                      constrained: false,
                      minScale: .2,
                      maxScale: 1.5,
                      scaleEnabled: false,
                      boundaryMargin: const EdgeInsets.all(1200),
                      child: _world(g, selectedId),
                    ),
                  ),
                ),
              ),
            ],
            Positioned(
              top: 16,
              left: 24,
              right: panel == null ? 24 : canvasPanelWidth + 48,
              child: Center(child: _bar(g)),
            ),
            if (panel != null)
              Positioned(
                top: 16,
                right: 24,
                width: canvasPanelWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(120, box.maxHeight - 40),
                  ),
                  child: SpecInspector(
                    key: const ValueKey('stage-panel'),
                    data: panel,
                    attention: widget.attention(panel)
                        ? specAttentionReason(ref, panel)
                        : null,
                    unlocks: [
                      for (final d in widget.cards.values)
                        if (d.spec.dependsOn.contains(panel.spec.code))
                          d.spec.code,
                    ],
                    references: ref.watch(
                      specReferencesProvider(panel.spec.id),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _bar(StageGeometry? g) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        CanvasFloating(
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              CanvasBarButton(
                key: const ValueKey('stage-running'),
                label: 'Executando · ${widget.runningCount}',
                tooltip: widget.runningCount == 0
                    ? 'Nenhuma spec em execução'
                    : 'Ver as specs em execução',
                color: AppColors.amber,
                active: g?.layout.running ?? false,
                toggle: true,
                onTap: widget.runningCount == 0 ? null : widget.onRunning,
              ),
              if (g != null) ...[
                const CanvasBarDivider(),
                CanvasBarButton(
                  key: const ValueKey('stage-fit'),
                  label: 'Ajustar',
                  tooltip: 'Enquadrar o que está no palco',
                  color: AppColors.textSecondary,
                  active: false,
                  onTap: frame,
                ),
                CanvasZoomMenu(view: _view, onFit: frame, onFitSelection: null),
              ],
            ],
          ),
        ),
        if (g != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              OutlinedButton(
                key: const ValueKey('stage-back'),
                onPressed: widget.onBack,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.text,
                  side: const BorderSide(color: AppColors.border),
                ),
                child: const Text.rich(
                  TextSpan(
                    text: 'Voltar à pasta ',
                    style: TextStyle(fontSize: 13),
                    children: [
                      TextSpan(
                        text: 'Esc',
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                _crumb(g.layout),
                key: const ValueKey('stage-crumb'),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

/// "Etapa 3 de 8 · rodando" and the activity bar of a card of "Executando". A
/// step that waits for the person stops the bar (R13).
class StageRunningLine extends StatelessWidget {
  const StageRunningLine({super.key, required this.data});

  final SpecCardData data;

  @override
  Widget build(BuildContext context) {
    final code = data.spec.code;
    final step = data.current;
    final waiting = step?.status == StepStatus.needsInput;
    final moving = !waiting && AppMotion.animate(context);
    final at = step == null ? 0 : data.steps.indexOf(step) + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Row(
          spacing: 6,
          children: [
            if (waiting)
              AttentionBubble(key: ValueKey('stage-balloon-$code'), size: 14),
            Expanded(
              child: Text(
                'Etapa $at de ${data.steps.length} · '
                '${stepStatusLabel(step?.status ?? StepStatus.running)}',
                key: ValueKey('stage-step-$code'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.amber),
              ),
            ),
          ],
        ),
        LinearProgressIndicator(
          key: ValueKey('stage-activity-$code'),
          minHeight: 3,
          borderRadius: BorderRadius.circular(2),
          // Stopped when it waits and with animations off (R14).
          value: moving ? null : .34,
          color: waiting ? AppColors.textMuted : AppColors.amber,
          backgroundColor: AppColors.border,
        ),
      ],
    );
  }
}

class _DependencyLink extends StatelessWidget {
  const _DependencyLink({
    required this.code,
    required this.last,
    required this.onTap,
  });

  final String code;
  final bool last;

  /// Null when the spec is not on the Quadro.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      code,
      style: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 12,
        color: onTap == null ? AppColors.textSecondary : AppColors.amber,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onTap == null)
          text
        else
          InkWell(
            key: ValueKey('stage-dep-$code'),
            borderRadius: BorderRadius.circular(4),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: text,
            ),
          ),
        if (!last)
          const Text(
            ',',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

class _StageHint extends StatelessWidget {
  const _StageHint();

  @override
  Widget build(BuildContext context) => const Center(
    key: ValueKey('stage-hint'),
    child: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Escolha uma spec na pasta',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Passe o mouse para ver os detalhes. Clique para abrir, com as '
            'specs que dependem dela.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );
}
