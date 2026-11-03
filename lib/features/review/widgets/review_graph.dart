import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../../sessions/session_manager.dart' show sessionTitle;
import '../review_service.dart';
import '../review_stack.dart';
import 'merge_status_view.dart';

/// Graph of the merge branches (SPEC-032 R16): `main` as a trunk at the
/// bottom, each stack a branch going up from it (base first), each loose
/// spec a branch of one node; dashed red lines join specs of the queue that
/// change the same file. Read from the bottom up.

/// Session whose primary action the list runs once it opens (the graph's
/// action bar asks for it).
class ReviewPendingAction extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? sessionId) => state = sessionId;
}

final reviewPendingActionProvider =
    NotifierProvider<ReviewPendingAction, String?>(ReviewPendingAction.new);

/// "Lista" / "Grafo", kept per project (R16).
class ReviewModeTabs extends ConsumerWidget {
  const ReviewModeTabs({super.key, required this.workspaceId});

  final int workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(
      appSettingsProvider.select(
        (m) => m[reviewModeKey(workspaceId)] == 'grafo',
      ),
    );
    Widget tab(String label, IconData icon, bool on, String value) => Expanded(
      child: Semantics(
        selected: on,
        button: true,
        child: Material(
          color: on ? SessionColors.selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            key: ValueKey('review-mode-$value'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => ref
                .read(appSettingsProvider.notifier)
                .set(reviewModeKey(workspaceId), value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: on ? AppColors.text : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      color: on ? AppColors.text : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          tab('Lista', Icons.layers_outlined, !graph, 'lista'),
          tab('Grafo', Icons.account_tree_outlined, graph, 'grafo'),
        ],
      ),
    );
  }
}

/// Geometry of the graph.
const _nodeW = 176.0, _nodeH = 70.0, _colGap = 28.0, _rowGap = 34.0;
const _left = 24.0, _top = 56.0;

/// A node's place: column (branch) and row (0 = on the trunk).
typedef _Place = ({int col, int row});

class ReviewGraph extends ConsumerStatefulWidget {
  const ReviewGraph({
    super.key,
    required this.stacks,
    required this.workspaceId,
  });

  final List<ReviewStack> stacks;
  final int workspaceId;

  @override
  ConsumerState<ReviewGraph> createState() => _ReviewGraphState();
}

class _ReviewGraphState extends ConsumerState<ReviewGraph> {
  String? _focused, _selected;
  final _focus = FocusNode(debugLabel: 'review-graph');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Map<String, _Place> get _places => {
    for (final (c, s) in widget.stacks.indexed)
      for (final (r, i) in s.items.indexed) i.session.id: (col: c, row: r),
  };

  ReviewItem? _item(String? id) => id == null
      ? null
      : flatten(widget.stacks).where((i) => i.session.id == id).firstOrNull;

  /// Arrows move between nodes (up = toward the top of the branch), Enter
  /// or Space selects.
  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final places = _places;
    if (places.isEmpty) return KeyEventResult.ignored;
    final cur = places[_focused] ?? places.values.first;
    _Place? to;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      to = (col: cur.col, row: cur.row + 1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      to = (col: cur.col, row: cur.row - 1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      to = (col: cur.col - 1, row: 0);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      to = (col: cur.col + 1, row: 0);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      setState(() => _selected = _focused ?? places.keys.first);
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    final target = places.entries
        .where((p) => p.value.col == to!.col && p.value.row == to.row)
        .firstOrNull;
    if (_focused == null) {
      setState(() => _focused = places.keys.first);
    } else if (target != null) {
      setState(() => _focused = target.key);
    }
    return KeyEventResult.handled;
  }

  void _openReview(ReviewItem i, {bool runPrimary = false}) {
    if (runPrimary) {
      ref.read(reviewPendingActionProvider.notifier).set(i.session.id);
    }
    ref.read(selectedReviewProvider.notifier).select(i.session.id);
    ref
        .read(appSettingsProvider.notifier)
        .set(reviewModeKey(widget.workspaceId), 'lista');
  }

  @override
  Widget build(BuildContext context) {
    final items = flatten(widget.stacks);
    final places = _places;
    final rows = widget.stacks.fold(0, (n, s) => math.max(n, s.items.length));
    final trunkY = _top + rows * (_nodeH + _rowGap) + 10;
    final width =
        _left * 2 + widget.stacks.length * (_nodeW + _colGap) - _colGap;
    Offset topLeft(_Place p) => Offset(
      _left + p.col * (_nodeW + _colGap),
      trunkY - _rowGap - p.row * (_nodeH + _rowGap) - _nodeH,
    );

    // R16: conflicts between specs of the queue (small queues only).
    final conflicts = <(String, String, String)>[];
    if (items.length <= 12) {
      for (var a = 0; a < items.length; a++) {
        for (var b = a + 1; b < items.length; b++) {
          final x = items[a], y = items[b];
          if (places[x.session.id]!.col == places[y.session.id]!.col) {
            continue;
          }
          final files =
              ref
                  .watch(
                    pairConflictProvider((
                      widget.workspaceId,
                      x.session.branch,
                      y.session.branch,
                    )),
                  )
                  .value ??
              const <String>[];
          if (files.isNotEmpty) {
            conflicts.add((x.session.id, y.session.id, files.first));
          }
        }
      }
    }

    // Specs merged today, on the trunk with the time.
    final now = DateTime.now();
    final specs = {
      for (final s
          in ref.watch(specsProvider(widget.workspaceId)).value ?? <Spec>[])
        s.id: s,
    };
    final today = <(String, DateTime)>[];
    final seen = <int>{};
    for (final s
        in ref.watch(sessionsProvider(widget.workspaceId)).value ??
            <Session>[]) {
      final at = s.endedAt;
      if (s.status != SessionStatus.merged || at == null) continue;
      if (at.year != now.year || at.month != now.month || at.day != now.day) {
        continue;
      }
      final spec = s.specId == null ? null : specs[s.specId];
      if (spec != null && !seen.add(spec.id)) continue;
      today.add((spec?.code ?? sessionTitle(s), at));
    }
    today.sort((a, b) => b.$2.compareTo(a.$2));

    final selected = _item(_selected);
    final canvasH = trunkY + 44;
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GraphHeader(workspaceId: widget.workspaceId),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'Nada aguardando review.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : Focus(
                    focusNode: _focus,
                    autofocus: true,
                    onKeyEvent: _key,
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: SizedBox(
                            key: const ValueKey('review-graph'),
                            width: math.max(width, box.maxWidth),
                            height: math.max(canvasH, box.maxHeight),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  top: math.max(0, box.maxHeight - canvasH),
                                  child: CustomPaint(
                                    painter: _GraphPainter(
                                      stacks: widget.stacks,
                                      places: places,
                                      trunkY: trunkY,
                                      conflicts: conflicts,
                                      topLeft: topLeft,
                                    ),
                                  ),
                                ),
                                for (final i in items)
                                  Positioned(
                                    left: topLeft(places[i.session.id]!).dx,
                                    top:
                                        topLeft(places[i.session.id]!).dy +
                                        math.max(0, box.maxHeight - canvasH),
                                    width: _nodeW,
                                    height: _nodeH,
                                    child: _GraphNode(
                                      item: i,
                                      first: places[i.session.id]!.row == 0,
                                      position: places[i.session.id]!.row + 1,
                                      stackSize: widget
                                          .stacks[places[i.session.id]!.col]
                                          .items
                                          .length,
                                      focused:
                                          _focus.hasFocus &&
                                          _focused == i.session.id,
                                      selected: _selected == i.session.id,
                                      onTap: () => setState(() {
                                        _focused = _selected = i.session.id;
                                        _focus.requestFocus();
                                      }),
                                    ),
                                  ),
                                Positioned(
                                  left: _left,
                                  top:
                                      trunkY +
                                      10 +
                                      math.max(0, box.maxHeight - canvasH),
                                  right: _left,
                                  child: Row(
                                    children: [
                                      const Text(
                                        'main',
                                        style: TextStyle(
                                          fontFamily: AppFonts.mono,
                                          fontSize: 12,
                                          color: AppColors.teal,
                                        ),
                                      ),
                                      for (final (code, at) in today.take(6))
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 18,
                                          ),
                                          child: Text(
                                            '● $code entrou ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                for (final (a, b, file) in conflicts)
                                  Positioned(
                                    left:
                                        (topLeft(places[a]!).dx +
                                                topLeft(places[b]!).dx) /
                                            2 +
                                        _nodeW / 2 -
                                        80,
                                    width: 160,
                                    top:
                                        math.min(
                                          topLeft(places[a]!).dy,
                                          topLeft(places[b]!).dy,
                                        ) -
                                        38 +
                                        math.max(0, box.maxHeight - canvasH),
                                    child: Text(
                                      file.split('/').last,
                                      key: ValueKey(
                                        'review-graph-conflict-$a-$b',
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: AppFonts.mono,
                                        fontSize: 11,
                                        color: AppColors.red,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          if (selected != null)
            _ActionBar(
              item: selected,
              onOpen: () => _openReview(selected),
              onPrimary: () => _openReview(selected, runPrimary: true),
            ),
        ],
      ),
    );
  }
}

class _GraphHeader extends StatelessWidget {
  const _GraphHeader({required this.workspaceId});

  final int workspaceId;

  @override
  Widget build(BuildContext context) {
    Widget legend(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ramificações do merge',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Leia de baixo para cima: cada galho sai da main e só entra '
                  'depois do de baixo.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            key: const ValueKey('review-graph-legend'),
            spacing: 14,
            children: [
              legend(
                Container(width: 16, height: 2, color: AppColors.textMuted),
                'depende de',
              ),
              legend(
                const Text(
                  '- - -',
                  style: TextStyle(fontSize: 11, color: AppColors.red),
                ),
                'mexem no mesmo arquivo',
              ),
              legend(
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.amber, width: 1.5),
                  ),
                ),
                'pode entrar agora',
              ),
            ],
          ),
          const SizedBox(width: 16),
          SizedBox(width: 190, child: ReviewModeTabs(workspaceId: workspaceId)),
        ],
      ),
    );
  }
}

class _GraphNode extends ConsumerWidget {
  const _GraphNode({
    required this.item,
    required this.first,
    required this.position,
    required this.stackSize,
    required this.focused,
    required this.selected,
    required this.onTap,
  });

  final ReviewItem item;
  final bool first, focused, selected;
  final int position, stackSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = watchMergeStatus(ref, item);
    final (icon, color) = mergeStateLook(status.state);
    // Can go in now: ready and at the base of its branch.
    final next = first && status.state == MergeState.pronto;
    final code = item.spec?.code ?? item.task?.code ?? '';
    final title =
        item.spec?.title ?? item.task?.title ?? sessionTitle(item.session);
    final radius = BorderRadius.circular(8);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      label:
          '${queueSemanticLabel(title: code.isEmpty ? title : code, position: position, stackSize: stackSize, status: status)}'
          '${next ? ', próximo' : ''}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              color: selected ? SessionColors.selectedBg : AppColors.panel,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(
                  color: focused
                      ? AppColors.blue
                      : next
                      ? AppColors.amber
                      : AppColors.border,
                  width: focused || next ? 1.5 : 1,
                ),
              ),
              child: InkWell(
                key: ValueKey('review-graph-node-${item.session.id}'),
                borderRadius: radius,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(icon, size: 12, color: color),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              status.text,
                              key: ValueKey(
                                'review-graph-state-${item.session.id}',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: color),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (next)
            Positioned(
              right: 8,
              top: -9,
              child: Container(
                key: ValueKey('review-graph-next-${item.session.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text(
                  'próximo',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onAmber,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bar of the selected node: its state, "Abrir o review" and the primary
/// action (R8), which opens the list and runs it there.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({
    required this.item,
    required this.onOpen,
    required this.onPrimary,
  });

  final ReviewItem item;
  final VoidCallback onOpen, onPrimary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = watchMergeStatus(ref, item);
    final (icon, color) = mergeStateLook(status.state);
    final primary = primaryActionOf(status, hasPr: item.session.prUrl != null);
    return Container(
      key: const ValueKey('review-graph-bar'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            item.spec?.code ?? item.task?.code ?? '',
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              item.spec?.title ??
                  item.task?.title ??
                  sessionTitle(item.session),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(status.text, style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
          const Spacer(),
          SmallButton(
            key: const ValueKey('review-graph-open'),
            label: 'Abrir o review',
            icon: Icons.visibility_outlined,
            onTap: onOpen,
          ),
          if (primary != PrimaryAction.nenhuma) ...[
            const SizedBox(width: 8),
            AmberButton(
              key: const ValueKey('review-graph-primary'),
              label: primaryLabel(primary, status),
              onTap: onPrimary,
            ),
          ],
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.stacks,
    required this.places,
    required this.trunkY,
    required this.conflicts,
    required this.topLeft,
  });

  final List<ReviewStack> stacks;
  final Map<String, _Place> places;
  final double trunkY;
  final List<(String, String, String)> conflicts;
  final Offset Function(_Place) topLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final branch = Paint()
      ..color = AppColors.textMuted
      ..strokeWidth = 1.5;
    for (final s in stacks) {
      final ids = [for (final i in s.items) i.session.id];
      final base = topLeft(places[ids.first]!);
      final x = base.dx + _nodeW / 2;
      // From the trunk to the top node of the branch.
      final top = topLeft(places[ids.last]!).dy + _nodeH;
      canvas.drawLine(Offset(x, trunkY), Offset(x, top), branch);
    }
    canvas.drawLine(
      Offset(_left - 8, trunkY),
      Offset(size.width - _left + 8, trunkY),
      Paint()
        ..color = AppColors.teal
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    final dash = Paint()
      ..color = AppColors.red
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final (a, b, _) in conflicts) {
      final pa = topLeft(places[a]!), pb = topLeft(places[b]!);
      final y = math.min(pa.dy, pb.dy) - 18;
      final xa = pa.dx + _nodeW / 2, xb = pb.dx + _nodeW / 2;
      final path = Path()
        ..moveTo(xa, pa.dy)
        ..lineTo(xa, y)
        ..lineTo(xb, y)
        ..lineTo(xb, pb.dy);
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 9) {
          canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), dash);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.stacks != stacks ||
      old.trunkY != trunkY ||
      old.conflicts.length != conflicts.length;
}
