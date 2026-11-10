import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../board_screen.dart' show BoardView, boardGraphViewProvider;

/// Colunas · Grafo · Foco as one segmented control (SPEC-053 R8): a glass
/// group whose indicator slides to the chosen view in 200 ms, announced as
/// "Visão do quadro", with the arrow keys moving between the views.
class BoardViewSwitch extends ConsumerStatefulWidget {
  const BoardViewSwitch({super.key});

  static const views = [
    (BoardView.columns, 'Colunas'),
    (BoardView.graph, 'Grafo'),
    (BoardView.focus, 'Foco'),
  ];

  /// Width of each option and height of the group.
  static const optionWidth = 76.0, height = 34.0;

  /// Width of the whole group: 3 options, 3 px of padding and 1 px of
  /// border on each side.
  static const width = optionWidth * 3 + 8;

  @override
  ConsumerState<BoardViewSwitch> createState() => _BoardViewSwitchState();
}

class _BoardViewSwitchState extends ConsumerState<BoardViewSwitch> {
  final _node = FocusNode(debugLabel: 'Visão do quadro');
  bool _focused = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final views = BoardViewSwitch.views;
    const optionWidth = BoardViewSwitch.optionWidth;
    final view = ref.watch(boardGraphViewProvider);
    final index = views.indexWhere((v) => v.$1 == view);
    void go(int i) => ref
        .read(boardGraphViewProvider.notifier)
        .set(views[(i + views.length) % views.length].$1);
    return Semantics(
      key: const ValueKey('board-view-switch'),
      container: true,
      label: 'Visão do quadro',
      // One tab stop for the group; the arrows move between the views,
      // as in a radio group (R8).
      child: Focus(
        focusNode: _node,
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
            go(index + 1);
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
            go(index - 1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: BoardViewSwitch.width,
          height: BoardViewSwitch.height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0x660A0C10),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: _focused
                  ? const Color(0xFFFFD08A)
                  : const Color(0x17FFFFFF),
            ),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                key: const ValueKey('board-view-indicator'),
                duration: AppMotion.duration(context, AppMotion.emphasis),
                curve: AppMotion.enter,
                left: index * optionWidth,
                top: 0,
                bottom: 0,
                width: optionWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.amber.withValues(alpha: .45),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (i, (v, label)) in views.indexed)
                    _Option(
                      key: ValueKey('board-view-${v.name}'),
                      label: label,
                      selected: i == index,
                      onTap: () {
                        _node.requestFocus();
                        go(i);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    inMutuallyExclusiveGroup: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: SizedBox(
      width: BoardViewSwitch.optionWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        canRequestFocus: false,
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected ? AppColors.amber : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The three zones of the Quadro's bar (SPEC-053 R7, R9): [left] at the
/// start, [actions] (Agendar, Executar tudo) at the end and never squeezed,
/// [center] in the middle of the whole bar (or right after [left] when the
/// middle would overlap it), and the autopilot [strip] in what is left
/// between the center and the actions, shortened with an ellipsis.
class BoardBarLayout extends MultiChildLayoutDelegate {
  BoardBarLayout({this.gap = 16});

  final double gap;

  static const left = 'left',
      center = 'center',
      strip = 'strip',
      actions = 'actions';

  @override
  void performLayout(Size size) {
    final w = size.width, h = size.height;
    final c = layoutChild(center, BoxConstraints.loose(size));
    final a = layoutChild(actions, BoxConstraints.loose(size));
    final l = layoutChild(
      left,
      BoxConstraints(
        maxWidth: math.max(0, w - c.width - a.width - 3 * gap),
        maxHeight: h,
      ),
    );
    var x = (w - c.width) / 2;
    if (x < l.width + gap) x = l.width + gap;
    if (x + c.width + gap > w - a.width) x = w - a.width - gap - c.width;
    final room = math.max(0.0, w - a.width - gap - (x + c.width + gap));
    final st = layoutChild(strip, BoxConstraints(maxWidth: room, maxHeight: h));
    positionChild(left, Offset(0, (h - l.height) / 2));
    positionChild(center, Offset(x, (h - c.height) / 2));
    positionChild(actions, Offset(w - a.width, (h - a.height) / 2));
    positionChild(
      strip,
      Offset(w - a.width - gap - st.width, (h - st.height) / 2),
    );
  }

  @override
  bool shouldRelayout(BoardBarLayout old) => old.gap != gap;
}
