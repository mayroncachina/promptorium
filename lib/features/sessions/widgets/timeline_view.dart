import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/diff_view.dart';
import '../../../ui/widgets/motion_enter.dart';
import '../edit_diff.dart';
import '../session_manager.dart';
import '../timeline.dart';
import '../timeline_provider.dart';
import 'session_activity.dart';
import 'session_style.dart';

/// Edit diffs of a session timeline, per snapshot.
final _sessionDiffs = Expando<Map<String, EditDiff>>('edit diffs');

/// Center column of the Sessions screen: user bubbles, Claude's text (live
/// while streaming), tool cards with results, subagent messages nested under
/// their Task card. Scrolls internally and sticks to the end (reversed list).
class TimelineView extends ConsumerWidget {
  const TimelineView({super.key, required this.sessionId, this.root});

  final String sessionId;

  /// Worktree path (tool targets are shown relative to it).
  final String? root;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(sessionTimelineProvider(sessionId));
    final waitingTools = {
      for (final a in ref.watch(
        sessionManagerProvider.select(
          (s) => s.live[sessionId]?.approvals ?? const <PendingApproval>[],
        ),
      ))
        ?a.request.toolUseId,
    };
    final since = ref.watch(
      sessionManagerProvider.select((s) => s.live[sessionId]?.busySince),
    );
    // SPEC-026 R3: a Write after an edit of the same file in this session
    // is compared with the text it knows.
    final diffs = _sessionDiffs[snap] ??= editDiffsOf(snap.items, root: root);
    return TimelineListView(
      key: ValueKey('timeline-$sessionId'),
      editInfo: (t) => diffs[t.id] == null ? null : EditInfo(diff: diffs[t.id]),
      footer: since == null
          ? null
          : SessionActivity(items: snap.items, since: since),
      items: snap.items,
      loading: snap.loading,
      root: root,
      waitingTools: waitingTools,
    );
  }
}

/// Scrollable list of timeline items (sessions and Prompt conversations).
/// Reversed, so the end stays visible while new items arrive. [footer] is
/// shown after the last item (inline approvals, answer actions). Items that
/// arrive after the list opened enter with motion (SPEC-034 R8).
class TimelineListView extends StatefulWidget {
  const TimelineListView({
    super.key,
    required this.items,
    this.loading = false,
    this.root,
    this.waitingTools = const {},
    this.footer,
    this.maxWidth,
    this.assistantName = 'Claude',
    this.emptyText = 'Nenhum evento ainda.',
    this.answerFooter,
    this.editInfo,
  });

  final List<TimelineItem> items;
  final bool loading;
  final String? root;
  final Set<String> waitingTools;
  final Widget? footer;

  /// Centers the content in a column of at most this width.
  final double? maxWidth;
  final String assistantName;
  final String emptyText;

  /// Shown under each finished top-level answer when it returns a widget
  /// (Prompt: "Spec detectada", SPEC-016).
  final Widget? Function(AssistantTextItem item)? answerFooter;

  /// Diff, target and marks of an edit card (Prompt refine, SPEC-026);
  /// null = the card works them out from the tool input.
  final EditInfo? Function(ToolItem tool)? editInfo;

  @override
  State<TimelineListView> createState() => _TimelineListViewState();
}

class _TimelineListViewState extends State<TimelineListView> {
  /// More than this many items inside [_burstWindow] enter without motion.
  static const _burstSize = 3;
  static const _burstWindow = Duration(milliseconds: 300);

  /// Items already accounted for. The list only grows, so the position of an
  /// item is its id: the only one every kind of item has.
  late int _seen;

  /// Items from this position on arrived in the frame [_arrivedAt]. One that
  /// is not built in that frame is off screen, and shows up later as history.
  late int _arrivedFrom;
  Duration? _arrivedAt;

  /// Items before this position were part of a burst.
  var _settled = 0;

  /// Frame of each recent arrival.
  final _recent = ListQueue<Duration>();

  Duration get _frame => SchedulerBinding.instance.currentSystemFrameTimeStamp;

  bool _isArriving(int idx) =>
      idx >= _arrivedFrom && idx >= _settled && _frame == _arrivedAt;

  @override
  void initState() {
    super.initState();
    _seen = _arrivedFrom = widget.items.length;
  }

  @override
  void didUpdateWidget(covariant TimelineListView old) {
    super.didUpdateWidget(old);
    // The list is mutated in place, so old.items cannot tell what is new.
    final items = widget.items;
    final count = items.length;
    if (old.loading ||
        widget.loading ||
        !identical(items, old.items) ||
        count < _seen) {
      // The stored rows land all at once, when loading ends: that is history.
      _seen = _arrivedFrom = count;
      return;
    }
    if (count == _seen) return;
    final now = _frame;
    while (_recent.isNotEmpty && now - _recent.first > _burstWindow) {
      _recent.removeFirst();
    }
    _recent.addAll(List.filled(count - _seen, now));
    if (_recent.length > _burstSize) _settled = count;
    _arrivedFrom = _seen;
    _arrivedAt = now;
    _seen = count;
  }

  Widget _wrap(Widget child) => widget.maxWidth == null
      ? child
      : Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth!),
            child: child,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final foot = widget.footer;
    if (items.isEmpty && foot == null) {
      return Center(
        child: Text(
          widget.loading ? 'Carregando…' : widget.emptyText,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    final extra = foot == null ? 0 : 1;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(20),
      itemCount: items.length + extra,
      // A new item shifts every index: the keys keep each one on its element.
      findChildIndexCallback: (key) => null ??  switch ((key as ValueKey).value) {
        final int idx when idx < items.length => items.length - 1 - idx + extra,
        _footerKey when foot != null => 0,
        _ => null,
      },
      itemBuilder: (context, i) {
        if (foot != null && i == 0) {
          return KeyedSubtree(
            key: const ValueKey(_footerKey),
            child: _wrap(
              Padding(
                padding: EdgeInsets.only(top: items.isEmpty ? 0 : 10),
                child: foot,
              ),
            ),
          );
        }
        final idx = items.length - 1 - (i - extra);
        final item = items[idx];
        final prev = idx > 0 ? items[idx - 1] : null;
        final gap = prev == null
            ? 0.0
            : (item is ToolItem && prev is ToolItem ? 4.0 : 14.0);
        final view = TimelineItemView(
          item: item,
          root: widget.root,
          waitingTools: widget.waitingTools,
          assistantName: widget.assistantName,
          editInfo: widget.editInfo,
        );
        final extraBelow =
            item is AssistantTextItem &&
                item.parentToolUseId == null &&
                !item.live
            ? widget.answerFooter?.call(item)
            : null;
        return _ItemEntrance(
          key: ValueKey(idx),
          arriving: _isArriving(idx),
          settled: idx < _settled,
          child: _wrap(
            Padding(
              padding: EdgeInsets.only(top: gap),
              child: extraBelow == null
                  ? view
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [view, const SizedBox(height: 8), extraBelow],
                    ),
            ),
          ),
        );
      },
    );
  }
}

const _footerKey = 'timeline-footer';

/// One timeline item. The list remounts items as they scroll, so [arriving]
/// only counts on the first mount: an item that left and came back stays put.
class _ItemEntrance extends StatefulWidget {
  const _ItemEntrance({
    super.key,
    required this.arriving,
    required this.settled,
    required this.child,
  });

  final bool arriving;

  /// A burst caught up with this item: it stops moving, if it still is.
  final bool settled;
  final Widget child;

  @override
  State<_ItemEntrance> createState() => _ItemEntranceState();
}

class _ItemEntranceState extends State<_ItemEntrance> {
  late final bool _enters = widget.arriving;

  @override
  Widget build(BuildContext context) => _enters
      ? MotionEnter(dy: 6, animate: !widget.settled, child: widget.child)
      : widget.child;
}

class TimelineItemView extends StatelessWidget {
  const TimelineItemView({
    super.key,
    required this.item,
    this.root,
    this.waitingTools = const {},
    this.nested = false,
    this.assistantName = 'Claude',
    this.editInfo,
  });

  final TimelineItem item;
  final String? root;
  final Set<String> waitingTools;
  final bool nested;
  final String assistantName;
  final EditInfo? Function(ToolItem tool)? editInfo;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return switch (it) {
      UserItem() => _UserBubble(it),
      AssistantTextItem() => _AssistantText(
        it,
        nested: nested,
        name: assistantName,
      ),
      ToolItem() => ToolCard(
        tool: it,
        root: root,
        waitingTools: waitingTools,
        edit: editInfo?.call(it),
        editInfo: editInfo,
      ),
      ThinkingItem() => ThinkingCard(item: it),
      NoticeItem() => _Notice(it),
    };
  }
}

/// Claude's reasoning, collapsed by default (UX v2, U3): a dashed line with
/// the size; click to read it.
class ThinkingCard extends StatefulWidget {
  const ThinkingCard({super.key, required this.item});

  final ThinkingItem item;

  @override
  State<ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<ThinkingCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final words = it.text.trim().isEmpty
        ? 0
        : it.text.trim().split(RegExp(r'\s+')).length;
    final label = it.live
        ? 'Pensando…'
        : 'Pensou · ${words == 1 ? '1 palavra' : '$words palavras'}';
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          key: const ValueKey('thinking-card'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: SessionColors.selectedBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: const ValueKey('thinking-toggle'),
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _open ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_open)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: SelectableText(
                    it.text,
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
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

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.item);

  final UserItem item;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: SessionColors.selectedBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SessionColors.selectedBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Você · ${formatClock(item.at)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                item.text,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantText extends StatelessWidget {
  const _AssistantText(this.item, {this.nested = false, this.name = 'Claude'});

  final AssistantTextItem item;
  final bool nested;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: const TextStyle(fontSize: 13, color: AppColors.text, height: 1.45),
      code: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 12,
        color: AppColors.amber,
        backgroundColor: Colors.transparent,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${nested ? 'Subagente' : name} · ${formatClock(item.at)}'
              '${item.live ? ' · escrevendo…' : ''}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            if (item.live)
              Text(
                '${item.text}▍',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.text,
                  height: 1.45,
                ),
              )
            else
              MarkdownBody(
                data: item.text,
                styleSheet: style,
                selectable: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.item);

  final NoticeItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.level) {
      NoticeLevel.info => AppColors.textMuted,
      NoticeLevel.success => AppColors.teal,
      NoticeLevel.error => AppColors.red,
    };
    return Row(
      children: [
        Dot(color, size: 6),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            item.text,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ),
        if (item.at != null)
          Text(
            formatClock(item.at),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
      ],
    );
  }
}

Color toolColor(String name) => switch (name) {
  'Read' || 'Glob' || 'Grep' || 'LS' => AppColors.blue,
  'Edit' || 'Write' || 'MultiEdit' || 'NotebookEdit' => AppColors.amber,
  'Bash' || 'Task' || 'Agent' => AppColors.lilac,
  _ => AppColors.textSecondary,
};

/// One tool call: name + target + summary; click expands the result.
/// Task / Agent cards show the subagent's messages indented below.
class ToolCard extends StatefulWidget {
  const ToolCard({
    super.key,
    required this.tool,
    this.root,
    this.waitingTools = const {},
    this.edit,
    this.editInfo,
  });

  final ToolItem tool;
  final String? root;
  final Set<String> waitingTools;

  /// Diff and target of an edit (SPEC-026 R2); null = from the input alone.
  final EditInfo? edit;

  /// Passed to the subagent's nested cards.
  final EditInfo? Function(ToolItem tool)? editInfo;

  @override
  State<ToolCard> createState() => _ToolCardState();
}

/// `3 ferramentas · 41 s` of a finished subagent card (UX v2, U3).
String _subagentSummary(ToolItem t) {
  final n = t.childToolCount;
  final tools = n == 1 ? '1 ferramenta' : '$n ferramentas';
  final start = t.at, end = t.doneAt;
  if (start == null || end == null) return tools;
  final secs = end.difference(start).inSeconds;
  return secs < 1 ? tools : '$tools · ${formatDuration(end.difference(start))}';
}

class _ToolCardState extends State<ToolCard> {
  bool _open = false;

  static const _mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12,
    color: AppColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final t = widget.tool;
    final info = widget.edit;
    final isEdit = isEditTool(t.name);
    final diff = isEdit ? (info?.diff ?? editDiffOf(t.name, t.input)) : null;
    final denied = t.denied;
    final waiting = !denied && widget.waitingTools.contains(t.id);
    final running = !t.done && !waiting && !denied;
    final stats = editStats(t.name, t.input);
    final canOpen = t.done || denied;
    final border = running
        ? SessionColors.runningToolBorder
        : (waiting ? SessionColors.approvalBorder : AppColors.border);
    final bg = running
        ? SessionColors.runningToolBg
        : (waiting ? SessionColors.approvalBg : AppColors.panel);

    final List<Widget> trailing = [
      if (info?.outside ?? false)
        Container(
          key: ValueKey('tool-outside-${t.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: SessionColors.approvalBorder),
          ),
          child: const Text(
            'fora da spec',
            style: TextStyle(color: AppColors.amber, fontSize: 11),
          ),
        ),
      if (denied)
        Row(
          key: ValueKey('tool-denied-${t.id}'),
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.block, size: 13, color: AppColors.textSecondary),
            SizedBox(width: 5),
            Text(
              'Negada, não aplicada',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        )
      else if (waiting)
        const Text(
          'aguardando aprovação',
          style: TextStyle(color: AppColors.amber),
        )
      else if (running)
        const Text('executando', style: TextStyle(color: AppColors.teal))
      else if (t.isError)
        const Text('erro', style: TextStyle(color: AppColors.red))
      else if (t.isSubagent) ...[
        Text(
          _subagentSummary(t),
          key: ValueKey('subagent-summary-${t.id}'),
          style: const TextStyle(color: AppColors.lilac),
        ),
      ] else if (diff != null) ...[
        Text('+${diff.added}', style: const TextStyle(color: AppColors.teal)),
        if (diff.removed > 0)
          Text(
            '−${diff.removed}',
            style: const TextStyle(color: AppColors.red),
          ),
      ] else if (stats != null) ...[
        Text('+${stats.$1}', style: const TextStyle(color: AppColors.teal)),
        if (stats.$2 > 0)
          Text('−${stats.$2}', style: const TextStyle(color: AppColors.red)),
      ] else
        Text(
          resultSummary(t),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
    ];

    final target = info?.outside ?? false
        ? (editFilePath(t.input) ?? toolTarget(t.name, t.input))
        : (info?.target ?? toolTarget(t.name, t.input, root: widget.root));

    final header = Semantics(
      container: true,
      button: canOpen,
      expanded: canOpen ? _open : null,
      child: InkWell(
        key: ValueKey('tool-toggle-${t.id}'),
        onTap: canOpen ? () => setState(() => _open = !_open) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              if (running) ...[
                const Dot(AppColors.teal),
                const SizedBox(width: 10),
              ] else if (isEdit && canOpen) ...[
                Icon(
                  _open ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44),
                child: Text(
                  t.name,
                  style: _mono.copyWith(color: toolColor(t.name)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  target,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono,
                ),
              ),
              for (final w in trailing) ...[
                const SizedBox(width: 10),
                DefaultTextStyle.merge(style: _mono, child: w),
              ],
            ],
          ),
        ),
      ),
    );

    final result = t.result ?? '';
    final lines = result.split('\n');
    final clipped = lines.length > 40
        ? '${lines.take(40).join('\n')}\n… (+${lines.length - 40} linhas)'
        : result;
    // SPEC-026 R2: an edit shows its diff; the tool output only on error.
    final showDiff = diff != null && (denied || !t.isError);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          key: ValueKey('tool-${t.id}'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (_open && canOpen && showDiff)
                Container(
                  key: ValueKey('tool-diff-${t.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (diff.unknownBefore)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(10, 2, 10, 4),
                          child: Text(
                            'Conteúdo anterior desconhecido',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      DiffView(rows: diff.rows, muted: denied, collapseSame: 3),
                    ],
                  ),
                )
              else if (_open && t.done)
                Container(
                  padding: const EdgeInsets.fromLTRB(64, 8, 10, 8),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: SelectableText(
                    clipped.isEmpty ? '(sem saída)' : clipped,
                    style: _mono.copyWith(
                      color: t.isError
                          ? AppColors.red
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              if (t.children.isNotEmpty)
                Container(
                  key: ValueKey('subagent-${t.id}'),
                  margin: const EdgeInsets.fromLTRB(12, 0, 10, 10),
                  padding: const EdgeInsets.only(left: 12),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: AppColors.lilac, width: 2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final c in t.children)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: TimelineItemView(
                            item: c,
                            root: widget.root,
                            waitingTools: widget.waitingTools,
                            nested: true,
                            editInfo: widget.editInfo,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
