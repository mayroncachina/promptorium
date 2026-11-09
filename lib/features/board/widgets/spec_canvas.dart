import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../specs/spec_service.dart';
import '../../review/widgets/spec_review_panel.dart'
    show pendingCriteriaProvider;
import '../../agents/agent_file.dart';
import '../board_rules.dart' show StepView, specStageLabel, specsByCode;
import '../board_screen.dart';
import '../spec_references.dart';
import 'canvas_view_controller.dart';
import 'canvas_detail_card.dart';
import 'spec_node.dart';
import 'wave_graph.dart';
import '../sprint_rules.dart';
import '../sprint_state.dart';

/// Node size, wave spacing and reference rows (Quadro-Canvas.dc.html).
const _cardSize = Size(250, 116);

/// A card that needs the person has one more line, the reason (SPEC-030 R4).
const _attentionCardSize = Size(250, 134);
const _waveX = 380.0, _originX = 60.0, _originY = 110.0, _rowGap = 54.0;
const _refRow = 56.0, _refHeight = 40.0, _refCap = 3, _refsPerRow = 3;
const canvasPanelWidth = 290.0;
const _externalSize = Size(240, 88);

class SpecCanvas extends ConsumerStatefulWidget {
  const SpecCanvas({
    super.key,
    required this.cards,
    required this.attention,
    required this.highlightNext,
    this.attentionCount,
    this.all = const [],
  });

  /// Every spec of the board: a dependency in another sprint is a dashed node
  /// (SPEC-042 R7).
  final List<Spec> all;
  final List<SpecCardData> cards;
  final bool Function(SpecCardData) attention;
  final bool highlightNext;

  /// Same N as the header of the Quadro (cards hidden by a filter count).
  final int? attentionCount;
  @override
  ConsumerState<SpecCanvas> createState() => _SpecCanvasState();
}

/// An agent or skill drawn under the selected node, or its "+N mais".
typedef _Ref = ({String name, String kind, bool more, Rect rect});

class _SpecCanvasState extends ConsumerState<SpecCanvas>
    with TickerProviderStateMixin {
  final _view = CanvasViewController();
  bool _agents = true, _skills = true;
  final _expanded = <String>{};

  /// One clock for every card that needs the person (SPEC-030 R2): it only
  /// exists while one does and animations are on (R6).
  AnimationController? _pulse;
  void _syncPulse(bool wanted) {
    if (wanted && _pulse == null) {
      _pulse = AnimationController(vsync: this, duration: attentionPulsePeriod)
        ..repeat();
    } else if (!wanted && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    _view.dispose();
    super.dispose();
  }

  /// Rows of [names] centered under [card], from row [row0].
  List<_Ref> _place(Set<String> names, String kind, Rect card, int row0) {
    final open = _expanded.contains(kind);
    final items = [
      for (final n in open ? names : names.take(_refCap))
        (name: n, more: false),
      if (names.length > _refCap)
        (
          name: open ? 'recolher' : '+${names.length - _refCap} mais',
          more: true,
        ),
    ];
    final w = kind == 'agent' ? 168.0 : 150.0;
    const gap = 10.0;
    final out = <_Ref>[];
    for (var r = 0; r * _refsPerRow < items.length; r++) {
      final row = items.skip(r * _refsPerRow).take(_refsPerRow).toList();
      final total = row.length * w + (row.length - 1) * gap;
      final left = math.max(16.0, card.center.dx - total / 2);
      for (final (i, it) in row.indexed) {
        out.add((
          name: it.name,
          kind: kind,
          more: it.more,
          rect: Rect.fromLTWH(
            left + i * (w + gap),
            card.bottom + _refRow + (row0 + r) * _refRow,
            w,
            _refHeight,
          ),
        ));
      }
    }
    return out;
  }

  int _rows(int count, String kind) {
    if (count == 0) return 0;
    final shown = _expanded.contains(kind) ? count : math.min(count, _refCap);
    final items = shown + (count > _refCap ? 1 : 0);
    return (items / _refsPerRow).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    final selectedId = ref.watch(boardSelectedSpecProvider);
    final hideDone = ref.watch(boardHideDoneProvider);
    final selected = cards.where((d) => d.spec.id == selectedId).firstOrNull;
    final specs = cards.map((d) => d.spec).toList();
    final waves = dependencyWaves(specs);
    final columns = <int, List<SpecCardData>>{};
    for (final d in cards) {
      columns.putIfAbsent(waves[d.spec.id] ?? 0, () => []).add(d);
    }
    final references = {
      for (final d in cards)
        d.spec.id: ref.watch(specReferencesProvider(d.spec.id)),
    };
    final refs = selected == null ? null : references[selected.spec.id]?.value;
    final agentNames = _agents ? refs?.agents ?? const <String>{} : <String>{};
    final skillNames = _skills ? refs?.skills ?? const <String>{} : <String>{};
    final agentRows = _rows(agentNames.length, 'agent');
    final refRows = agentRows + _rows(skillNames.length, 'skill');

    final filter = ref.watch(boardSprintFilterProvider);
    final allByCode = specsByCode(widget.all);
    final externals = <Spec>{
      for (final s in specs) ...externalDependencies(s, allByCode, filter),
    }.toList()..sort((a, b) => a.code.compareTo(b.code));
    final sprints = externals.isEmpty
        ? const <Sprint>[]
        : ref.watch(sprintsProvider(externals.first.workspaceId)).value ??
              const <Sprint>[];
    // The nodes of other sprints get a column before the first wave.
    final shift = externals.isEmpty ? 0.0 : _waveX;
    final externalRects = <int, Rect>{
      for (final (i, s) in externals.indexed)
        s.id:
            Offset(_originX, _originY + i * (_externalSize.height + _rowGap)) &
            _externalSize,
    };

    final rects = <int, Rect>{};
    for (final entry in columns.entries) {
      var y = _originY;
      for (final d in entry.value) {
        final r =
            Offset(_originX + shift + entry.key * _waveX, y) &
            (widget.attention(d) ? _attentionCardSize : _cardSize);
        rects[d.spec.id] = r;
        y = r.bottom + _rowGap;
        if (d.spec.id == selectedId && refRows > 0) {
          y += refRows * _refRow + _refHeight;
        }
      }
    }
    final selectedRect = rects[selectedId];
    final sats = selectedRect == null
        ? const <_Ref>[]
        : [
            ..._place(agentNames, 'agent', selectedRect, 0),
            ..._place(skillNames, 'skill', selectedRect, agentRows),
          ];
    final bounds = [
      ...rects.values,
      ...externalRects.values,
    ].fold<Rect?>(null, (r, c) => r == null ? c : r.expandToInclude(c))!;
    final world = sats.fold(bounds, (r, s) => r.expandToInclude(s.rect));
    final byCode = {for (final s in specs) s.code: s};
    final unlocks = selected == null
        ? const <String>[]
        : [
            for (final s in specs)
              if (s.dependsOn.contains(selected.spec.code)) s.code,
          ];
    final related = <String>{
      if (selected != null) ...[
        selected.spec.code,
        ...selected.spec.dependsOn,
        ...unlocks,
      ],
    };
    final attention = cards.where(widget.attention).toList()
      ..sort((a, b) {
        final wave = (waves[a.spec.id] ?? 0).compareTo(waves[b.spec.id] ?? 0);
        return wave == 0 ? a.spec.code.compareTo(b.spec.code) : wave;
      });
    _syncPulse(
      attention.isNotEmpty && !MediaQuery.disableAnimationsOf(context),
    );
    final pulse = _pulse;
    final position = attention.indexWhere((d) => d.spec.id == selectedId);
    void select(int? id) =>
        ref.read(boardSelectedSpecProvider.notifier).select(id);
    void fitSelected() {
      if (rects[selectedId] case final r?) _view.fitSelection(r);
    }

    int uses(String kind, String name) => references.values
        .where(
          (r) =>
              (kind == 'agent' ? r.value?.agents : r.value?.skills)?.contains(
                name,
              ) ??
              false,
        )
        .length;

    final next = nextWave(specs, waves);
    final ws = ref.watch(activeWorkspaceProvider);
    return LayoutBuilder(
      builder: (context, box) {
        _view
          ..viewport = box.biggest
          ..padding = EdgeInsets.fromLTRB(
            24,
            80,
            selected == null ? 24 : canvasPanelWidth + 48,
            70,
          );
        return CallbackShortcuts(
          bindings: _view.zoomShortcuts,
          child: Focus(
            autofocus: true,
            child: ColoredBox(
              color: AppColors.background,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: CanvasDotGrid(_view)),
                    ),
                  ),
                  Positioned.fill(
                    child: Listener(
                      onPointerSignal: _view.onPointerSignal,
                      child: GestureDetector(
                        onTap: () => select(null),
                        child: InteractiveViewer(
                          key: const ValueKey('board-graph'),
                          transformationController: _view,
                          constrained: false,
                          minScale: .5,
                          maxScale: 1.5,
                          // Wheel and pinch go through _onPointerSignal: the
                          // plain wheel moves, Ctrl + wheel zooms.
                          scaleEnabled: false,
                          boundaryMargin: const EdgeInsets.all(600),
                          child: SizedBox(
                            width: world.right + 350,
                            height: world.bottom + 300,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _CanvasEdges(
                                      specs: specs,
                                      rects: rects,
                                      byCode: byCode,
                                      selected: selected?.spec.code,
                                      selectedRect: selectedRect,
                                      externals: [
                                        for (final s in specs)
                                          for (final dep in externals)
                                            if (s.dependsOn.contains(dep.code))
                                              (
                                                from: externalRects[dep.id]!,
                                                to: rects[s.id]!,
                                                blocking:
                                                    dep.stage != SpecStage.done,
                                              ),
                                      ],
                                      refs: [
                                        for (final s in sats)
                                          if (!s.more) s,
                                      ],
                                    ),
                                  ),
                                ),
                                for (final entry in columns.entries)
                                  Positioned(
                                    left: _originX + shift + entry.key * _waveX,
                                    top: _originY - 34,
                                    child: _WaveLabel(
                                      key: ValueKey('board-wave-${entry.key}'),
                                      wave: entry.key,
                                      next:
                                          widget.highlightNext &&
                                          entry.key == next,
                                    ),
                                  ),
                                for (final s in externals)
                                  Positioned.fromRect(
                                    rect: externalRects[s.id]!,
                                    child: _ExternalNode(
                                      spec: s,
                                      sprint: sprintNameOf(s, sprints),
                                      onTap: () {
                                        ref
                                            .read(boardSprintProvider.notifier)
                                            .set(sprintFilterOf(s));
                                        select(s.id);
                                      },
                                    ),
                                  ),
                                for (final d in cards)
                                  Positioned.fromRect(
                                    rect: rects[d.spec.id]!,
                                    child: AnimatedOpacity(
                                      key: ValueKey(
                                        'canvas-node-${d.spec.code}',
                                      ),
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      opacity:
                                          selected == null ||
                                              related.contains(d.spec.code)
                                          ? 1
                                          : .45,
                                      child: RepaintBoundary(
                                        child: AttentionHalo(
                                          enabled: widget.attention(d),
                                          pulse: pulse,
                                          child: SpecNode(
                                            data: d,
                                            selected: d.spec.id == selectedId,
                                            reason: widget.attention(d)
                                                ? specAttentionReason(ref, d)
                                                : null,
                                            pulse: pulse,
                                            onTap: () => select(d.spec.id),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                for (final d in cards)
                                  if (widget.attention(d))
                                    Positioned(
                                      left: rects[d.spec.id]!.left,
                                      top: rects[d.spec.id]!.top - 13,
                                      width: _cardSize.width - 12,
                                      child: IgnorePointer(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: AttentionBadge(
                                            key: ValueKey(
                                              'canvas-attention-${d.spec.code}',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                for (final s in sats)
                                  Positioned.fromRect(
                                    rect: s.rect,
                                    child: s.more
                                        ? _MoreNode(
                                            key: ValueKey(
                                              'canvas-more-${s.kind}',
                                            ),
                                            label: s.name,
                                            kind: s.kind,
                                            expanded: _expanded.contains(
                                              s.kind,
                                            ),
                                            onTap: () => setState(() {
                                              if (!_expanded.remove(s.kind)) {
                                                _expanded.add(s.kind);
                                              }
                                            }),
                                          )
                                        : _RefNode(
                                            key: ValueKey(
                                              'canvas-ref-${s.kind}-${s.name}',
                                            ),
                                            name: s.name,
                                            kind: s.kind,
                                            uses: uses(s.kind, s.name),
                                          ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 20,
                    child: CanvasFloating(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Specs',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.text,
                            ),
                          ),
                          Text(
                            '${ws?.name ?? ''} · ${cards.length} '
                            '${cards.length == 1 ? 'spec' : 'specs'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 20,
                    left: 24,
                    right: 24,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: CanvasFloating(
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CanvasBarButton(
                              key: const ValueKey('canvas-attention-next'),
                              leading: const AttentionBubble(size: 14),
                              // With the selected spec in the queue: its
                              // position and the size of the same list (R8).
                              label: position < 0
                                  ? 'Atenção · '
                                        '${widget.attentionCount ?? attention.length}'
                                  : 'Atenção · ${position + 1} de '
                                        '${attention.length}',
                              tooltip:
                                  'Ir para a próxima spec que precisa de você',
                              color: AppColors.amber,
                              active: attention.isNotEmpty,
                              onTap: attention.isEmpty
                                  ? null
                                  : () {
                                      final id =
                                          attention[(position + 1) %
                                                  attention.length]
                                              .spec
                                              .id;
                                      select(id);
                                      _view.fitSelection(rects[id]!);
                                    },
                            ),
                            const CanvasBarDivider(),
                            const Padding(
                              padding: EdgeInsets.only(left: 8, right: 6),
                              child: Text(
                                'Camadas',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            CanvasBarButton(
                              key: const ValueKey('canvas-layer-agents'),
                              label: 'Agentes',
                              color: CanvasColors.agent,
                              active: _agents,
                              toggle: true,
                              onTap: () => setState(() => _agents = !_agents),
                            ),
                            const SizedBox(width: 8),
                            CanvasBarButton(
                              key: const ValueKey('canvas-layer-skills'),
                              label: 'Skills',
                              color: CanvasColors.skill,
                              active: _skills,
                              toggle: true,
                              onTap: () => setState(() => _skills = !_skills),
                            ),
                            const SizedBox(width: 8),
                            // Same state as the header chip (SPEC-019 R7):
                            // on = concluded specs shown.
                            CanvasBarButton(
                              key: const ValueKey('canvas-hide-done'),
                              label: 'Concluídas',
                              icon: hideDone
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              tooltip: hideDone
                                  ? 'Mostrar specs concluídas'
                                  : 'Ocultar specs concluídas',
                              color: specStageColor(SpecStage.done),
                              active: !hideDone,
                              toggle: true,
                              onTap: () => ref
                                  .read(boardHideDoneProvider.notifier)
                                  .toggle(),
                            ),
                            const CanvasBarDivider(),
                            CanvasZoomMenu(
                              view: _view,
                              onFit: () => _view.fit(
                                Rect.fromLTRB(
                                  bounds.left,
                                  bounds.top - 34,
                                  bounds.right,
                                  bounds.bottom,
                                ).inflate(10),
                              ),
                              onFitSelection: selected == null
                                  ? null
                                  : fitSelected,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    bottom: 18,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(
                          200,
                          box.maxWidth -
                              48 -
                              (selected == null ? 0 : canvasPanelWidth + 24),
                        ),
                      ),
                      child: const _Legend(key: ValueKey('canvas-legend')),
                    ),
                  ),
                  if (selected != null)
                    Positioned(
                      top: 90,
                      right: 24,
                      width: canvasPanelWidth,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.max(120, box.maxHeight - 114),
                        ),
                        child: SpecInspector(
                          key: const ValueKey('canvas-panel'),
                          data: selected,
                          attention: widget.attention(selected)
                              ? specAttentionReason(ref, selected)
                              : null,
                          unlocks: unlocks,
                          references: references[selected.spec.id],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- estados

class _WaveLabel extends StatelessWidget {
  const _WaveLabel({super.key, required this.wave, required this.next});
  final int wave;
  final bool next;
  @override
  Widget build(BuildContext context) => Text(
    'ONDA ${wave + 1}${next ? ' · PRÓXIMA' : ''}',
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: .66,
      color: next ? AppColors.amber : AppColors.textSecondary,
    ),
  );
}

// -------------------------------------------------------------------- nós

Color _refColor(String kind) =>
    kind == 'agent' ? CanvasColors.agent : CanvasColors.skill;

BorderRadius _refRadius(String kind) =>
    BorderRadius.circular(kind == 'agent' ? 8 : 20);

class _RefNode extends StatelessWidget {
  const _RefNode({
    super.key,
    required this.name,
    required this.kind,
    required this.uses,
  });
  final String name, kind;
  final int uses;
  @override
  Widget build(BuildContext context) {
    final color = _refColor(kind);
    return CanvasDetailCard(
      details: _ReferenceDetails(name: name, kind: kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            color.withValues(alpha: .14),
            AppColors.surfaceRaised,
          ),
          borderRadius: _refRadius(kind),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(kind == 'agent' ? 2 : 4),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$uses ${uses == 1 ? 'spec' : 'specs'}',
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: .8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreNode extends StatelessWidget {
  const _MoreNode({
    super.key,
    required this.label,
    required this.kind,
    required this.expanded,
    required this.onTap,
  });
  final String label, kind;
  final bool expanded;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: expanded,
    child: CustomPaint(
      foregroundPainter: DashedBorderPainter(
        radius: kind == 'agent' ? 8 : 20,
        color: AppColors.textMuted,
      ),
      child: Material(
        color: AppColors.surfaceRaised,
        borderRadius: _refRadius(kind),
        child: InkWell(
          borderRadius: _refRadius(kind),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- bolinhas

const stepDotSize = 10.0, stepBubbleSize = 14.0;

/// Period of the shared attention pulse (SPEC-030 R2): well under one blink
/// per second, far from the 3 per second of WCAG 2.3.1 (R9).
const attentionPulsePeriod = Duration(milliseconds: 1800);

/// Opacity of the waiting step's bubble at [t] of the pulse: 1 → .55 → 1.
double attentionBubbleOpacity(double t) => 1 - .45 * math.sin(math.pi * t);

/// One step: filled circle (feita), pulsing circle (em execução), outline
/// (pendente), bubble (aguardando você) or spinning ring (verificando).
class CanvasStepDot extends StatefulWidget {
  const CanvasStepDot({
    super.key,
    required this.status,
    this.animate = true,
    this.pulse,
    this.semanticLabel,
  });
  final StepStatus status;

  /// False in the legend, which must not keep a ticker alive.
  final bool animate;

  /// The canvas's shared attention clock; the bubble breathes with it.
  final Animation<double>? pulse;
  final String? semanticLabel;
  @override
  State<CanvasStepDot> createState() => _CanvasStepDotState();
}

class _CanvasStepDotState extends State<CanvasStepDot>
    with TickerProviderStateMixin {
  AnimationController? _animation;
  StepStatus? _animated;
  void _sync() {
    final moving =
        widget.status == StepStatus.running ||
        widget.status == StepStatus.verifying;
    final active =
        widget.animate && moving && !MediaQuery.disableAnimationsOf(context);
    if (_animation != null && (!active || _animated != widget.status)) {
      _animation!.dispose();
      _animation = null;
      _animated = null;
    }
    if (active && _animation == null) {
      _animated = widget.status;
      _animation = widget.status == StepStatus.running
          ? (AnimationController(
              vsync: this,
              duration: const Duration(milliseconds: 700),
            )..repeat(reverse: true))
          : (AnimationController(
              vsync: this,
              duration: const Duration(milliseconds: 900),
            )..repeat());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant CanvasStepDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _animation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bubble = widget.status == StepStatus.needsInput;
    final Widget dot = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(bubble ? stepBubbleSize : stepDotSize),
        painter: _DotPainter(
          widget.status,
          bubble ? (widget.animate ? widget.pulse : null) : _animation,
        ),
      ),
    );
    if (widget.semanticLabel == null) return dot;
    return Semantics(label: widget.semanticLabel, child: dot);
  }
}

/// The speech bubble of "aguardando você", in a 16 × 16 box scaled to
/// [size]: a body with 2.5 px corners and a tail down on the left. Without
/// the dots, it does not read as "someone is typing" (SPEC-030 R1).
Path attentionBubblePath(double size) {
  final k = size / 16;
  return Path()
    ..addRRect(
      RRect.fromLTRBR(
        .5 * k,
        1.5 * k,
        15.5 * k,
        12 * k,
        Radius.circular(2.5 * k),
      ),
    )
    ..moveTo(4 * k, 11.5 * k)
    ..lineTo(7.2 * k, 11.5 * k)
    ..lineTo(4 * k, 14.8 * k)
    ..close();
}

/// The bubble as a widget: the badge, the bar button and step details.
class AttentionBubble extends StatelessWidget {
  const AttentionBubble({
    super.key,
    this.size = stepBubbleSize,
    this.color = CanvasColors.needsInput,
  });
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _BubblePainter(color));
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    attentionBubblePath(size.shortestSide),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(covariant _BubblePainter old) => old.color != color;
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.status, this.animation) : super(repaint: animation);
  final StepStatus status;
  final Animation<double>? animation;
  @override
  void paint(Canvas canvas, Size size) {
    final t = animation?.value ?? 0;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    switch (stepDotShape(status)) {
      case StepDotShape.filled:
        canvas.drawCircle(c, r, Paint()..color = CanvasColors.done);
      case StepDotShape.pulsing:
        canvas.drawCircle(
          c,
          r + 5 * t,
          Paint()..color = CanvasColors.running.withValues(alpha: .5 * (1 - t)),
        );
        canvas.drawCircle(
          c,
          r * (1 + .15 * t),
          Paint()..color = CanvasColors.running.withValues(alpha: 1 - .45 * t),
        );
      case StepDotShape.outline:
        canvas.drawCircle(
          c,
          r - .75,
          Paint()
            ..color = CanvasColors.pending
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      case StepDotShape.bubble:
        canvas.drawPath(
          attentionBubblePath(size.shortestSide),
          Paint()
            ..color = CanvasColors.needsInput.withValues(
              alpha: animation == null ? 1 : attentionBubbleOpacity(t),
            ),
        );
      case StepDotShape.spinner:
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(
          c,
          r - 1,
          ring..color = CanvasColors.verifying.withValues(alpha: .3),
        );
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r - 1),
          -math.pi / 2 + t * 2 * math.pi,
          math.pi / 2,
          false,
          ring..color = CanvasColors.verifying,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) =>
      old.status != status || old.animation != animation;
}

/// The card's ring while it needs the person: on the canvas's shared clock
/// it opens from 0 to 10 px while fading (R2); with no clock (animations
/// off, R6) it stays as a still 3 px glow.
class AttentionHalo extends StatelessWidget {
  const AttentionHalo({
    super.key,
    required this.enabled,
    required this.pulse,
    required this.child,
    this.radius = 12,
  });
  final bool enabled;
  final Animation<double>? pulse;
  final Widget child;
  final double radius;
  static const _curve = Cubic(.2, .6, .4, 1);

  /// Spread and alpha of the ring at [t] of the cycle: it opens over the
  /// first 70% and is gone for the rest.
  static (double, double) ring(double t) {
    if (t >= .7) return (0, 0);
    final e = _curve.transform(t / .7);
    return (10 * e, .55 * (1 - e));
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    BoxDecoration glow(double spread, double alpha) => BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: AppColors.amber.withValues(alpha: alpha),
          spreadRadius: spread,
        ),
      ],
    );
    final p = pulse;
    if (p == null) {
      return DecoratedBox(
        key: const ValueKey('canvas-attention-still'),
        decoration: glow(3, .28),
        child: child,
      );
    }
    return AnimatedBuilder(
      animation: p,
      child: child,
      builder: (_, child) {
        final (spread, alpha) = ring(p.value);
        return DecoratedBox(decoration: glow(spread, alpha), child: child);
      },
    );
  }
}

// --------------------------------------------------------------- pintores

/// Background dots that follow pan and zoom.
class CanvasDotGrid extends CustomPainter {
  CanvasDotGrid(this.view) : super(repaint: view);
  final CanvasViewController view;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = view.scale;
    final step = 24 * scale;
    final t = view.value.getTranslation();
    final paint = Paint()..color = CanvasColors.grid;
    final radius = 1.2 * scale.clamp(.75, 1.25);
    for (var x = t.x % step; x < size.width; x += step) {
      for (var y = t.y % step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CanvasDotGrid old) => old.view != view;
}

/// A dependency in another sprint: a click goes there (SPEC-042 R7).
class _ExternalNode extends StatelessWidget {
  const _ExternalNode({
    required this.spec,
    required this.sprint,
    required this.onTap,
  });

  final Spec spec;
  final String sprint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final blocking = spec.stage != SpecStage.done;
    return Material(
      key: ValueKey('canvas-external-${spec.code}'),
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: blocking ? AppColors.amber : AppColors.textMuted,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 2,
            children: [
              Text(
                '${spec.code} · ${specStageLabel(spec.stage)}',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                spec.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                sprint,
                style: TextStyle(
                  fontSize: 11,
                  color: blocking ? AppColors.amber : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One (dependency, dependent) pair per `depends-on` between specs on the
/// canvas; dependencies outside it are left out.
List<(String, String)> dependencyLinks(List<Spec> specs) {
  final codes = {for (final s in specs) s.code};
  return [
    for (final s in specs)
      for (final dep in s.dependsOn)
        if (codes.contains(dep)) (dep, s.code),
  ];
}

/// Shape of each step state, so it differs also without colour.
enum StepDotShape { filled, pulsing, outline, bubble, spinner }

StepDotShape stepDotShape(StepStatus s) => switch (s) {
  StepStatus.done => StepDotShape.filled,
  StepStatus.running => StepDotShape.pulsing,
  StepStatus.pending => StepDotShape.outline,
  StepStatus.needsInput => StepDotShape.bubble,
  StepStatus.verifying => StepDotShape.spinner,
};

class _CanvasEdges extends CustomPainter {
  _CanvasEdges({
    required this.specs,
    required this.rects,
    required this.byCode,
    required this.selected,
    required this.selectedRect,
    required this.refs,
    this.externals = const [],
  });
  final List<({Rect from, Rect to, bool blocking})> externals;
  final List<Spec> specs;
  final Map<int, Rect> rects;
  final Map<String, Spec> byCode;
  final String? selected;
  final Rect? selectedRect;
  final List<_Ref> refs;

  void _link(
    Canvas canvas,
    Offset a,
    Offset b, {
    required bool vertical,
    required Color color,
    required double width,
    bool dashed = false,
    bool arrow = false,
  }) {
    final path = Path()..moveTo(a.dx, a.dy);
    if (vertical) {
      final dy = (b.dy - a.dy) / 2;
      path.cubicTo(a.dx, a.dy + dy, b.dx, b.dy - dy, b.dx, b.dy);
    } else {
      final dx = (b.dx - a.dx) / 2;
      path.cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);
    }
    final stroke = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    canvas.drawPath(dashed ? _dash(path) : path, stroke);
    final dot = Paint()..color = color;
    canvas.drawCircle(a, 4, dot);
    if (arrow) {
      canvas.drawPath(
        Path()
          ..moveTo(b.dx + 1, b.dy)
          ..lineTo(b.dx - 8, b.dy - 5)
          ..lineTo(b.dx - 8, b.dy + 5)
          ..close(),
        dot,
      );
    } else {
      canvas.drawCircle(b, 4, dot);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final (dep, code) in dependencyLinks(specs)) {
      final from = rects[byCode[dep]!.id]!, to = rects[byCode[code]!.id]!;
      final hot = selected == code || selected == dep;
      _link(
        canvas,
        from.centerRight,
        to.centerLeft,
        vertical: false,
        arrow: true,
        color: hot
            ? AppColors.text
            : AppColors.textMuted.withValues(alpha: .55),
        width: hot ? 2.5 : 1.5,
      );
    }
    for (final e in externals) {
      _link(
        canvas,
        e.from.centerRight,
        e.to.centerLeft,
        vertical: false,
        arrow: true,
        dashed: true,
        color: e.blocking ? AppColors.amber : AppColors.textMuted,
        width: 1.5,
      );
    }
    if (selectedRect case final card?) {
      for (final r in refs) {
        _link(
          canvas,
          card.bottomCenter,
          r.rect.topCenter,
          vertical: true,
          color: _refColor(r.kind).withValues(alpha: .9),
          width: 2,
          dashed: true,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasEdges old) => true;
}

Path _dash(Path source, {double on = 6, double off = 6}) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += on + off) {
      out.addPath(metric.extractPath(d, d + on), Offset.zero);
    }
  }
  return out;
}

class DashedBorderPainter extends CustomPainter {
  DashedBorderPainter({required this.radius, required this.color});
  final double radius;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    _dash(
      Path()..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.75),
          Radius.circular(radius),
        ),
      ),
      on: 4,
      off: 3,
    ),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );

  @override
  bool shouldRepaint(covariant DashedBorderPainter old) =>
      old.radius != radius || old.color != color;
}

// ------------------------------------------------------- barra e legenda

class CanvasFloating extends StatelessWidget {
  const CanvasFloating({super.key, required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.panel,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}

class CanvasBarDivider extends StatelessWidget {
  const CanvasBarDivider({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: AppColors.border,
  );
}

class CanvasBarButton extends StatelessWidget {
  const CanvasBarButton({
    super.key,
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
    this.toggle = false,
    this.tooltip,
    this.icon,
    this.leading,
  });
  final String label;
  final IconData? icon;

  /// A drawn icon before the label (the attention bubble).
  final Widget? leading;
  final Color color;
  final bool active, toggle;
  final VoidCallback? onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    Widget button = Material(
      color: active
          ? Color.alphaBlend(color.withValues(alpha: .14), AppColors.panel)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: active
              ? color
              : toggle
              ? Colors.transparent
              : AppColors.border,
          width: active ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: active ? color : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
              ],
              if (leading != null) ...[leading!, const SizedBox(width: 7)],
              Text(
                label,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? color : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (toggle) {
      button = Semantics(toggled: active, child: button);
    }
    if (tooltip != null) button = Tooltip(message: tooltip, child: button);
    return button;
  }
}

class CanvasZoomMenu extends StatelessWidget {
  const CanvasZoomMenu({
    super.key,
    required this.view,
    required this.onFit,
    required this.onFitSelection,
  });
  final CanvasViewController view;
  final VoidCallback onFit;
  final VoidCallback? onFitSelection;

  Widget _item(String label, VoidCallback? onTap, [String? keys]) =>
      MenuItemButton(
        onPressed: onTap,
        style: MenuItemButton.styleFrom(
          minimumSize: const Size(238, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          foregroundColor: AppColors.text,
          textStyle: const TextStyle(fontSize: 13),
        ),
        trailingIcon: keys == null
            ? null
            : Text(
                keys,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: view,
    builder: (_, _) => MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.panelSolid),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
      builder: (context, controller, _) => Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(
              '${(view.scale * 100).round()}% ▾',
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
          ),
        ),
      ),
      menuChildren: [
        _item('Aproximar', view.zoomIn, 'Ctrl +'),
        _item('Afastar', view.zoomOut, 'Ctrl −'),
        _item('Tamanho real (100%)', view.reset, 'Ctrl 0'),
        const Divider(height: 9, color: AppColors.border),
        _item('Ajustar à tela', onFit),
        _item('Ajustar à seleção', onFitSelection),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({super.key});

  static Widget _entry(Widget mark, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [mark, const SizedBox(width: 6), Text(label)],
  );

  static Widget _line(Color color, {bool dashed = false}) => CustomPaint(
    size: const Size(14, 3),
    painter: _LegendLine(color, dashed: dashed),
  );

  static Widget _shape(Color color, {required bool circle}) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(circle ? 5 : 2),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        container: true,
        label: 'Legenda',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.panel,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 12, color: AppColors.text),
            child: Wrap(
              spacing: 18,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'ETAPAS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .55,
                    color: AppColors.textSecondary,
                  ),
                ),
                for (final (status, label) in [
                  (StepStatus.done, 'feita'),
                  (StepStatus.running, 'em execução'),
                  (StepStatus.pending, 'pendente'),
                  (StepStatus.needsInput, 'aguardando você'),
                  (StepStatus.verifying, 'verificando'),
                ])
                  _entry(CanvasStepDot(status: status, animate: false), label),
                Container(width: 1, height: 16, color: AppColors.border),
                _entry(_line(AppColors.text), 'dependência'),
                _entry(_line(CanvasColors.agent, dashed: true), 'referência'),
                _entry(_shape(CanvasColors.agent, circle: false), 'agente'),
                _entry(_shape(CanvasColors.skill, circle: true), 'skill'),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Clique numa spec para ver o que ela referencia; '
        'o zoom fica no menu da barra.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    ],
  );
}

class _LegendLine extends CustomPainter {
  _LegendLine(this.color, {this.dashed = false});
  final Color color;
  final bool dashed;
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final path = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);
    canvas.drawPath(
      dashed ? _dash(path, on: 4, off: 3) : path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = dashed ? 2 : 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _LegendLine old) =>
      old.color != color || old.dashed != dashed;
}

// ---------------------------------------------------------------- inspetor

class SpecInspector extends ConsumerWidget {
  const SpecInspector({
    super.key,
    required this.data,
    required this.attention,
    required this.unlocks,
    required this.references,
  });
  final SpecCardData data;

  /// Why the spec needs the user (null = it doesn't).
  final String? attention;
  final List<String> unlocks;
  final AsyncValue<SpecReferences>? references;

  static const _heading = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: .55,
    color: AppColors.textSecondary,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = data.spec;
    final refs = references?.value;
    final mono = const TextStyle(
      fontFamily: AppFonts.mono,
      color: AppColors.text,
    );
    return Semantics(
      container: true,
      label: 'Spec selecionada',
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.panel,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 24,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (attention != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.amberTint,
                      border: Border.all(color: AppColors.amber, width: 1.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Precisa de você',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.amber,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          attention!,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Text(
                      spec.code,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    StagePill(spec.stage),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  spec.title,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                _Objective(spec: spec),
                const SizedBox(height: 14),
                DefaultTextStyle.merge(
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  child: Table(
                    columnWidths: const {
                      0: IntrinsicColumnWidth(),
                      1: FlexColumnWidth(),
                    },
                    children: [
                      for (final (label, codes) in [
                        ('depende de', spec.dependsOn),
                        ('desbloqueia', unlocks),
                      ])
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 12,
                                bottom: 4,
                              ),
                              child: Text(label),
                            ),
                            Text(
                              codes.isEmpty ? 'nenhuma' : codes.join(', '),
                              style: mono,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('ETAPAS', style: _heading),
                const SizedBox(height: 6),
                for (final step in data.steps)
                  _StepRow(key: ValueKey('canvas-step-${step.id}'), step: step),
                const SizedBox(height: 14),
                const Text('REFERÊNCIAS', style: _heading),
                const SizedBox(height: 6),
                if (references?.hasError ?? false)
                  const Text(
                    'referências indisponíveis',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  )
                else if (refs != null &&
                    refs.agents.isEmpty &&
                    refs.skills.isEmpty)
                  const Text(
                    'nenhuma',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  )
                else if (refs != null)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final n in refs.agents) _RefChip(n, 'agent'),
                      for (final n in refs.skills) _RefChip(n, 'skill'),
                    ],
                  ),
                const SizedBox(height: 14),
                if (data.blockers.isNotEmpty && spec.stage != SpecStage.done)
                  Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Bloqueada por ${data.blockers.join(', ')}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                BoardSpecAction(data: data, height: 44),
                const SizedBox(height: 8),
                _FinishAction(spec: spec),
                Row(
                  children: [
                    Expanded(
                      child: _PanelButton(
                        label: 'Abrir spec',
                        onTap: () {
                          ref
                              .read(selectedSpecProvider.notifier)
                              .select(spec.id);
                          ref
                              .read(navigationProvider.notifier)
                              .go(AppSection.specs);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PanelButton(
                        label: 'Ver nas colunas',
                        onTap: () => ref
                            .read(boardGraphViewProvider.notifier)
                            .set(BoardView.columns),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({super.key, required this.step});
  final StepView step;
  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          CanvasStepDot(status: step.status),
          const SizedBox(width: 9),
          SizedBox(
            width: 32,
            child: Text(
              step.id,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              step.text.isEmpty ? stepStatusText(step) : step.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
    if (step.text.isEmpty) return row;
    return CanvasDetailCard(
      width: 254,
      details: StepDetails(step: step),
      child: row,
    );
  }
}

class _RefChip extends StatelessWidget {
  const _RefChip(this.name, this.kind);
  final String name, kind;
  @override
  Widget build(BuildContext context) {
    final color = _refColor(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(kind == 'agent' ? 8 : 12),
      ),
      child: Text(
        name,
        style: TextStyle(fontFamily: AppFonts.mono, fontSize: 12, color: color),
      ),
    );
  }
}

/// "Marcar como finalizada" / "Reabrir" of the inspector (SPEC-019 R8, R9).
/// Finishing with acceptance criteria unchecked asks first.
class _FinishAction extends ConsumerStatefulWidget {
  const _FinishAction({required this.spec});
  final Spec spec;
  @override
  ConsumerState<_FinishAction> createState() => _FinishActionState();
}

class _FinishActionState extends ConsumerState<_FinishAction> {
  bool _busy = false;

  Future<bool> _confirm(int pending) async {
    final ok = await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('inspector-mark-done-confirm'),
        backgroundColor: AppColors.panel,
        title: const Text('Finalizar a spec?'),
        content: Text(
          pending == 1
              ? '1 critério de aceite sem marcar. Finalizar mesmo assim?'
              : '$pending critérios de aceite sem marcar. Finalizar mesmo '
                    'assim?',
        ),
        actions: [
          TextButton(
            key: const ValueKey('inspector-mark-done-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('inspector-mark-done-yes'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _run(bool finish) async {
    final ws = ref.read(activeWorkspaceProvider);
    if (ws == null || _busy) return;
    final spec = widget.spec;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final service = ref.read(specServiceProvider);
      if (finish) {
        List<String> pending;
        try {
          pending = await ref.refresh(pendingCriteriaProvider(spec.id).future);
        } catch (_) {
          pending = const []; // unreadable criteria: the service decides
        }
        if (pending.isNotEmpty &&
            !(mounted && await _confirm(pending.length))) {
          return;
        }
        await service.markDone(ws, spec);
      } else {
        await service.reopen(ws, spec);
      }
    } catch (e) {
      messenger?.showAppToast(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.spec.stage;
    // A spec running or in review finishes through its own flow.
    if (stage != SpecStage.backlog && stage != SpecStage.done) {
      return const SizedBox.shrink();
    }
    final done = stage == SpecStage.done;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _PanelButton(
        key: ValueKey(done ? 'inspector-reopen' : 'inspector-mark-done'),
        label: done ? 'Reabrir' : 'Marcar como finalizada',
        onTap: _busy ? null : () => _run(!done),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: SessionColors.blockedBorder),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.text,
          ),
        ),
      ),
    ),
  );
}

class _Objective extends ConsumerWidget {
  const _Objective({required this.spec});
  final Spec spec;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(_objectiveProvider(spec.id)).value ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

final _objectiveProvider = FutureProvider.autoDispose.family<String, int>((
  ref,
  id,
) async {
  final spec = await ref.read(specsRepoProvider).getById(id);
  if (spec == null) return '';
  final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
  if (ws == null) return '';
  final text = await ref.read(specServiceProvider).read(ws, spec) ?? '';
  return RegExp(r'## Objetivo\s*\n([\s\S]*?)(?=\n## |$)')
          .firstMatch(text)
          ?.group(1)
          ?.trim() ??
      '';
});

// ---------------------------------------------- detalhes de agente e skill

typedef _RefInfo = ({
  String scope,
  String description,
  List<(String, String)> facts,
});

class _ReferenceDetails extends ConsumerWidget {
  const _ReferenceDetails({required this.name, required this.kind});
  final String name, kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(_referenceDetailsProvider((name, kind))).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${kind == 'agent' ? 'agente' : 'skill'}'
                '${info == null ? '' : ' · ${info.scope}'}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (info != null) ...[
          const SizedBox(height: 6),
          Text(
            info.description,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: [
              for (final (label, value) in info.facts)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        label,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                    Text(value),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

final _referenceDetailsProvider = FutureProvider.autoDispose
    .family<_RefInfo, (String, String)>((ref, key) async {
      final (name, kind) = key;
      final ws = ref.watch(activeWorkspaceProvider);
      final home = Platform.environment['HOME'];
      for (final (root, scope, shown) in [
        if (ws != null) (ws.path, 'Projeto', ''),
        if (home != null) (home, 'Global', '~/'),
      ]) {
        final relative = kind == 'agent'
            ? '.claude/agents/$name.md'
            : '.claude/skills/$name/SKILL.md';
        final file = File('$root/$relative');
        if (!await file.exists()) continue;
        final parsed = AgentFile.parse(await file.readAsString());
        final description = parsed.description ?? '';
        final model = parsed.value('model')?.toString();
        return (
          scope: scope,
          description: description.isEmpty
              ? 'sem descrição disponível'
              : description,
          facts: kind == 'agent'
              ? [
                  ('Modelo', model ?? 'padrão do CLI'),
                  (
                    'Ferramentas',
                    parsed.tools.isEmpty ? 'todas' : parsed.tools.join(', '),
                  ),
                ]
              : [
                  ('Chamada', '/$name'),
                  ('Origem', '$shown.claude/skills/$name'),
                ],
        );
      }
      return (
        scope: 'Embutida',
        description: 'sem descrição disponível',
        facts: kind == 'agent'
            ? [('Modelo', 'padrão do CLI')]
            : [('Chamada', '/$name'), ('Origem', 'embutida no Claude Code')],
      );
    });
