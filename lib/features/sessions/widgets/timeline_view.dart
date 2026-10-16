import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../session_manager.dart';
import '../timeline.dart';
import '../timeline_provider.dart';
import 'session_activity.dart';
import 'session_style.dart';

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
    return TimelineListView(
      key: ValueKey('timeline-$sessionId'),
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
/// shown after the last item (inline approvals, answer actions).
class TimelineListView extends StatelessWidget {
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

  Widget _wrap(Widget child) => maxWidth == null
      ? child
      : Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth!),
            child: child,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final foot = footer;
    if (items.isEmpty && foot == null) {
      return Center(
        child: Text(
          loading ? 'Carregando…' : emptyText,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    final extra = foot == null ? 0 : 1;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(20),
      itemCount: items.length + extra,
      itemBuilder: (context, i) {
        if (foot != null && i == 0) {
          return _wrap(
            Padding(
              padding: EdgeInsets.only(top: items.isEmpty ? 0 : 10),
              child: foot,
            ),
          );
        }
        final idx = items.length - 1 - (i - extra);
        final item = items[idx];
        final prev = idx > 0 ? items[idx - 1] : null;
        final gap = prev == null
            ? 0.0
            : (item is ToolItem && prev is ToolItem ? 4.0 : 14.0);
        return _wrap(
          Padding(
            padding: EdgeInsets.only(top: gap),
            child: TimelineItemView(
              item: item,
              root: root,
              waitingTools: waitingTools,
              assistantName: assistantName,
            ),
          ),
        );
      },
    );
  }
}

class TimelineItemView extends StatelessWidget {
  const TimelineItemView({
    super.key,
    required this.item,
    this.root,
    this.waitingTools = const {},
    this.nested = false,
    this.assistantName = 'Claude',
  });

  final TimelineItem item;
  final String? root;
  final Set<String> waitingTools;
  final bool nested;
  final String assistantName;

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
      ToolItem() => ToolCard(tool: it, root: root, waitingTools: waitingTools),
      NoticeItem() => _Notice(it),
    };
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
  });

  final ToolItem tool;
  final String? root;
  final Set<String> waitingTools;

  @override
  State<ToolCard> createState() => _ToolCardState();
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
    final waiting = widget.waitingTools.contains(t.id);
    final running = !t.done && !waiting;
    final stats = editStats(t.name, t.input);
    final border = running
        ? SessionColors.runningToolBorder
        : (waiting ? SessionColors.approvalBorder : AppColors.border);
    final bg = running
        ? SessionColors.runningToolBg
        : (waiting ? SessionColors.approvalBg : AppColors.panel);

    final List<Widget> trailing = [
      if (waiting)
        const Text(
          'aguardando aprovação',
          style: TextStyle(color: AppColors.amber),
        )
      else if (running)
        const Text('executando', style: TextStyle(color: AppColors.teal))
      else if (t.isError)
        const Text('erro', style: TextStyle(color: AppColors.red))
      else if (stats != null) ...[
        Text('+${stats.$1}', style: const TextStyle(color: AppColors.teal)),
        if (stats.$2 > 0)
          Text('−${stats.$2}', style: const TextStyle(color: AppColors.red)),
      ] else
        Text(
          resultSummary(t),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
    ];

    final header = InkWell(
      onTap: t.done ? () => setState(() => _open = !_open) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            if (running) ...[
              const Dot(AppColors.teal),
              const SizedBox(width: 10),
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
                toolTarget(t.name, t.input, root: widget.root),
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
    );

    final result = t.result ?? '';
    final lines = result.split('\n');
    final clipped = lines.length > 40
        ? '${lines.take(40).join('\n')}\n… (+${lines.length - 40} linhas)'
        : result;

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
              if (_open && t.done)
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
