import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../../ui/widgets/diff_view.dart';
import '../edit_diff.dart';
import '../timeline.dart';
import '../timeline_provider.dart';
import '../tool_expanded.dart';
import 'session_style.dart';
import 'timeline_view.dart';

/// Layer of the Sessions screen that holds the expanded tool (SPEC-058).
/// Put over the whole area (list, sessions, panel) in a [Stack]: it grows
/// from the clicked card and shrinks back to it (R9), while the timeline
/// stays mounted below (R8).
class ToolExpandedOverlay extends ConsumerStatefulWidget {
  const ToolExpandedOverlay({super.key, required this.rootOf});

  /// Worktree of a session (tool targets are shown relative to it).
  final String? Function(String sessionId) rootOf;

  @override
  ConsumerState<ToolExpandedOverlay> createState() =>
      _ToolExpandedOverlayState();
}

class _ToolExpandedOverlayState extends ConsumerState<ToolExpandedOverlay>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this);
  late final _curve = CurvedAnimation(
    parent: _anim,
    curve: AppMotion.enter,
    reverseCurve: AppMotion.exit.flipped,
  );

  /// What is on screen: the open tool, or the last one while it shrinks.
  ToolExpanded? _shown;

  /// Rectangle the view grows from or shrinks to, in this layer (null =
  /// none: it fades).
  Rect? _edge;

  /// [global] in this layer's coordinates.
  Rect? _local(Rect? global) {
    final box = context.findRenderObject();
    if (global == null || box is! RenderBox || !box.hasSize) return null;
    return Rect.fromPoints(
      box.globalToLocal(global.topLeft),
      box.globalToLocal(global.bottomRight),
    );
  }

  @override
  void initState() {
    super.initState();
    final s = ref.read(toolExpandedProvider);
    if (s != null && s.open) {
      _shown = s;
      _anim.value = 1;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _onChange(ToolExpanded? prev, ToolExpanded? next) {
    final animate = AppMotion.animate(context);
    if (next != null && next.open) {
      final opening = _shown == null || !(prev?.open ?? false);
      setState(() => _shown = next);
      if (!opening) return;
      _edge = _local(next.origin);
      if (!animate) {
        _anim.value = 1;
        return;
      }
      _anim.duration = AppMotion.emphasis;
      _anim.forward(from: _anim.isAnimating ? _anim.value : 0);
      return;
    }
    final shown = _shown;
    if (shown == null) return;
    // Shrinks to the card it came back to, when it is in sight.
    final box = context.findRenderObject();
    final bounds = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final card = ref
        .read(toolExpandedProvider.notifier)
        .cards(shown.sessionId)
        .rectOf(next?.toolId ?? shown.toolId);
    _edge = _local(
      card != null && bounds != null && bounds.overlaps(card)
          ? card
          : shown.origin,
    );
    if (!animate) {
      setState(() => _shown = null);
      return;
    }
    _anim.reverseDuration = AppMotion.base;
    _anim.reverse().whenCompleteOrCancel(() {
      if (mounted && !_anim.isAnimating && _anim.value == 0) {
        setState(() => _shown = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ToolExpanded?>(toolExpandedProvider, _onChange);
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final open = ref.watch(
      toolExpandedProvider.select((s) => s?.open ?? false),
    );
    final view = ToolExpandedView(
      key: const ValueKey('tool-expanded'),
      sessionId: shown.sessionId,
      toolId: shown.toolId,
      root: widget.rootOf(shown.sessionId),
    );
    return IgnorePointer(
      ignoring: !open,
      child: LayoutBuilder(
        builder: (context, c) {
          final full = Offset.zero & c.biggest;
          final small = _edge;
          return AnimatedBuilder(
            animation: _curve,
            child: view,
            builder: (context, child) {
              final k = _curve.value;
              if (k >= 1 || small == null) {
                return Opacity(opacity: k >= 1 ? 1 : k, child: child);
              }
              final rect = Rect.lerp(small, full, k)!;
              // The text arrives after the box has mostly grown.
              final fade = ((k - .4) / .6).clamp(0.0, 1.0);
              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: Container(
                      key: const ValueKey('tool-expanded-motion'),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.panelSolid,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.amber),
                      ),
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: full.width,
                        maxWidth: full.width,
                        minHeight: full.height,
                        maxHeight: full.height,
                        child: Opacity(opacity: fade, child: child),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// `7,2 s` under a minute, `2m 05s` above.
String expandedDuration(Duration d) {
  if (d.inSeconds >= 60) return formatDuration(d);
  final tenths = (d.inMilliseconds / 100).round();
  final s = '${tenths ~/ 10},${tenths % 10}';
  return '$s s';
}

/// [rows] as a unified diff (`+`, `-`, space), for Copiar.
String diffText(List<DiffRow> rows) => [
  for (final r in rows)
    '${switch (r.op) {
      DiffOp.add => '+',
      DiffOp.del => '-',
      DiffOp.same => ' ',
    }}${r.text}',
].join('\n');

/// Text the expanded view shows for [t] and Copiar copies: the new content
/// of a Write, the result of anything else.
String expandedText(ToolItem t) {
  if (t.name == 'Write') {
    final c = t.input['content'];
    if (c is String) return c;
  }
  return t.result ?? '';
}

int _lineCount(String s) => s.isEmpty ? 0 : '\n'.allMatches(s).length + 1;

/// The expanded tool: header (name, target, result, Anterior / Próxima,
/// Copiar, Fechar) over its whole output (SPEC-058 R1–R3, R11).
class ToolExpandedView extends ConsumerStatefulWidget {
  const ToolExpandedView({
    super.key,
    required this.sessionId,
    required this.toolId,
    this.root,
  });

  final String sessionId;
  final String toolId;
  final String? root;

  @override
  ConsumerState<ToolExpandedView> createState() => _ToolExpandedViewState();
}

class _ToolExpandedViewState extends ConsumerState<ToolExpandedView> {
  final _body = FocusNode(debugLabel: 'tool expanded body');

  @override
  void initState() {
    super.initState();
    // R11: the text gets the focus on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _body.requestFocus();
    });
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  ToolExpandedController get _ctrl => ref.read(toolExpandedProvider.notifier);

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showAppToast(const SnackBar(content: Text('Copiado')));
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(sessionTimelineProvider(widget.sessionId));
    final tools = ref.watch(sessionToolsProvider(widget.sessionId));
    final i = tools.indexWhere((t) => t.id == widget.toolId);
    final t = i < 0 ? findTool(snap.items, widget.toolId) : tools[i];
    final hasPrevious = i > 0;
    final hasNext = i >= 0 && i < tools.length - 1;
    final diff = t == null || !isEditTool(t.name)
        ? null
        : (sessionEditDiffs(snap, widget.root)[t.id] ??
              editDiffOf(t.name, t.input));

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): _ctrl.close,
      const SingleActivator(LogicalKeyboardKey.arrowUp): _ctrl.previous,
      const SingleActivator(LogicalKeyboardKey.keyK): _ctrl.previous,
      const SingleActivator(LogicalKeyboardKey.arrowDown): _ctrl.next,
      const SingleActivator(LogicalKeyboardKey.keyJ): _ctrl.next,
    };

    final name = t?.name ?? 'Ferramenta';
    final showsDiff = diff != null && t != null && (t.denied || !t.isError);
    final copy = t == null
        ? null
        : (showsDiff && t.name != 'Write'
              ? diffText(diff.rows)
              : expandedText(t));
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: '$name ampliado',
      child: BlockSemantics(
        child: CallbackShortcuts(
          bindings: bindings,
          child: FocusScope(
            // R11: Tab goes around inside the view.
            child: FocusTraversalGroup(
              child: Material(
                color: AppColors.panelSolid,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      tool: t,
                      diff: diff,
                      root: widget.root,
                      lines: t == null || showsDiff
                          ? 0
                          : _lineCount(expandedText(t)),
                      onPrevious: hasPrevious ? _ctrl.previous : null,
                      onNext: hasNext ? _ctrl.next : null,
                      onCopy: copy == null ? null : () => _copy(copy),
                      onClose: _ctrl.close,
                    ),
                    Expanded(
                      child: Focus(
                        focusNode: _body,
                        child: t == null
                            ? const Center(
                                child: Text(
                                  'Este item não está mais na sessão.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              )
                            : _Body(
                                key: ValueKey('tool-expanded-body-${t.id}'),
                                tool: t,
                                diff: diff,
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
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.tool,
    required this.diff,
    required this.root,
    required this.lines,
    required this.onPrevious,
    required this.onNext,
    required this.onCopy,
    required this.onClose,
  });

  final ToolItem? tool;
  final EditDiff? diff;
  final String? root;

  /// Lines of the text shown (0 = none, or a diff).
  final int lines;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCopy;
  final VoidCallback onClose;

  static const _mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  /// "erro", "+9 −3", "+61 arquivo novo", "ok"… (R2).
  List<Widget> _result(ToolItem t) {
    const meta = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    if (t.denied) return const [Text('negada', style: meta)];
    if (!t.done) {
      return const [
        Dot(AppColors.teal, size: 6),
        SizedBox(width: 6),
        Text(
          'executando',
          style: TextStyle(fontSize: 12, color: AppColors.teal),
        ),
      ];
    }
    if (t.isError) {
      return const [
        Dot(AppColors.red, size: 6),
        SizedBox(width: 6),
        Text(
          'erro',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.red,
          ),
        ),
      ];
    }
    final d = diff;
    if (d != null) {
      return [
        Text(
          '+${d.added}',
          style: const TextStyle(fontSize: 12, color: AppColors.teal),
        ),
        if (d.removed > 0) ...[
          const SizedBox(width: 6),
          Text(
            '−${d.removed}',
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ],
        if (t.name == 'Write' && d.unknownBefore) ...[
          const SizedBox(width: 6),
          const Text('arquivo novo', style: meta),
        ],
      ];
    }
    return [Text(resultSummary(t), style: meta)];
  }

  @override
  Widget build(BuildContext context) {
    final t = tool;
    final start = t?.at, end = t?.doneAt;
    final took = start == null || end == null ? null : end.difference(start);
    const meta = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (t != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: toolColor(t.name).withValues(alpha: .14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                t.name,
                key: const ValueKey('tool-expanded-name'),
                style: _mono.copyWith(color: toolColor(t.name)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              t == null ? '' : toolTarget(t.name, t.input, root: root),
              key: const ValueKey('tool-expanded-target'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono,
            ),
          ),
          if (t != null) ...[
            const SizedBox(width: 12),
            ..._result(t),
            if (took != null && took.inMilliseconds >= 100) ...[
              const SizedBox(width: 12),
              const Icon(Icons.schedule, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(expandedDuration(took), style: meta),
            ],
            if (lines > 0) ...[
              const SizedBox(width: 12),
              Text(lines == 1 ? '1 linha' : '$lines linhas', style: meta),
            ],
          ],
          const SizedBox(width: 12),
          _NavPair(onPrevious: onPrevious, onNext: onNext),
          const SizedBox(width: 8),
          SmallButton(
            key: const ValueKey('tool-expanded-copy'),
            label: 'Copiar',
            icon: Icons.copy_outlined,
            onTap: onCopy,
          ),
          const SizedBox(width: 8),
          SmallButton(
            key: const ValueKey('tool-expanded-close'),
            label: 'Fechar',
            icon: Icons.close,
            color: AppColors.amber,
            border: SessionColors.approvalBorder,
            semanticLabel: 'Fechar (Esc)',
            trailing: const Text(
              'Esc',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

/// Anterior | Próxima, joined (R2, R3).
class _NavPair extends StatelessWidget {
  const _NavPair({required this.onPrevious, required this.onNext});

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  Widget _half(
    String key,
    String label,
    String hint,
    IconData icon,
    VoidCallback? onTap,
  ) {
    final on = onTap != null;
    final color = on ? AppColors.text : AppColors.textMuted;
    return Semantics(
      button: true,
      enabled: on,
      label: '$label ($hint)',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('tool-expanded-$key'),
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _half(
            'previous',
            'Anterior',
            '↑ ou K',
            Icons.keyboard_arrow_up,
            onPrevious,
          ),
          const SizedBox(
            height: 30,
            child: VerticalDivider(width: 1, color: AppColors.border),
          ),
          _half('next', 'Próxima', '↓ ou J', Icons.keyboard_arrow_down, onNext),
        ],
      ),
    );
  }
}

/// The whole output of the tool, no 40-line cut.
class _Body extends StatelessWidget {
  const _Body({super.key, required this.tool, required this.diff});

  final ToolItem tool;
  final EditDiff? diff;

  @override
  Widget build(BuildContext context) {
    final t = tool;
    final d = diff;
    if (d != null && (t.denied || !t.isError)) {
      return DiffView(rows: d.rows, muted: t.denied, scrollable: true);
    }
    final text = expandedText(t);
    final shown = text.isEmpty
        ? (t.done ? '(sem saída)' : 'executando…')
        : text;
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SelectionArea(
          child: Text(
            shown,
            key: const ValueKey('tool-expanded-text'),
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12.5,
              height: 1.6,
              color: AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
