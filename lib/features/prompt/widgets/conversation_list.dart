import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../conversation_actions.dart';
import '../conversation_manager.dart';

/// "Hoje" / "Ontem" / "Anteriores" groups of [list] (already newest first).
List<(String, List<Conversation>)> groupConversations(
  List<Conversation> list, {
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final groups = <String, List<Conversation>>{
    'Hoje': [],
    'Ontem': [],
    'Anteriores': [],
  };
  for (final c in list) {
    final t = (c.updatedAt ?? c.createdAt).toLocal();
    final key = !t.isBefore(today)
        ? 'Hoje'
        : (!t.isBefore(yesterday) ? 'Ontem' : 'Anteriores');
    groups[key]!.add(c);
  }
  return [
    for (final MapEntry(:key, :value) in groups.entries)
      if (value.isNotEmpty) (key, value),
  ];
}

String conversationMeta(Conversation c, {DateTime? now}) {
  final at = c.archivedAt;
  if (at != null) {
    return '${modelLabel(c.model)} · arquivada ${archivedWhen(at, now: now)}';
  }
  final n = c.messageCount;
  return '${modelLabel(c.model)} · ${n == 1 ? '1 mensagem' : '$n mensagens'}';
}

/// Left column of the Prompt screen: conversation history, with the tabs
/// Ativas / Arquivadas when something is archived (SPEC-056 R6).
class ConversationListPanel extends ConsumerStatefulWidget {
  const ConversationListPanel({
    super.key,
    required this.lists,
    required this.selectedId,
  });

  final ConversationLists lists;
  final int? selectedId;

  @override
  ConsumerState<ConversationListPanel> createState() =>
      _ConversationListPanelState();
}

class _ConversationListPanelState extends ConsumerState<ConversationListPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_onTab);

  void _onTab() {
    ref
        .read(conversationTabProvider.notifier)
        .show(ConversationTab.values[_tabs.index]);
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTab)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lists = widget.lists;
    final hasArchived = lists.archived.isNotEmpty;
    final chosen = ref.watch(conversationTabProvider);
    final tab = hasArchived ? chosen : ConversationTab.active;
    if (!hasArchived && chosen == ConversationTab.archived) {
      // The last one left the archived tab: the next archive starts from
      // the active ones.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(conversationTabProvider.notifier)
              .show(ConversationTab.active);
        }
      });
    }
    if (_tabs.index != tab.index && !_tabs.indexIsChanging) {
      _tabs.index = tab.index;
    }
    final busy = ref.watch(conversationManagerProvider);
    final showArchived = tab == ConversationTab.archived;
    Widget tile(Conversation c) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      child: ConversationTile(
        key: ValueKey('conversation-tile-${c.id}'),
        conversation: c,
        selected: c.id == widget.selectedId,
        busy: busy.isBusy(c.id),
        active: lists.active,
      ),
    );
    return ColoredBox(
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasArchived)
            _Tabs(
              controller: _tabs,
              active: lists.active.length,
              archived: lists.archived.length,
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: Text('CONVERSAS', style: sectionTitleStyle),
            ),
          Expanded(
            child: ListView(
              key: ValueKey('conversation-list-${tab.name}'),
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                if (showArchived) ...[
                  const SizedBox(height: 6),
                  for (final c in lists.archived) tile(c),
                ] else ...[
                  if (lists.active.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                      child: Text(
                        hasArchived
                            ? 'Nenhuma conversa ativa. As arquivadas estão '
                                  'na outra aba.'
                            : 'Nenhuma conversa ainda. Escreva uma pergunta '
                                  'ao lado.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  for (final (name, items) in groupConversations(
                    lists.active,
                  )) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    for (final c in items) tile(c),
                  ],
                ],
              ],
            ),
          ),
          // R5: the way to the archived ones, from the active list.
          if (hasArchived && !showArchived)
            _ArchivedFooter(
              count: lists.archived.length,
              onTap: () => ref
                  .read(conversationTabProvider.notifier)
                  .show(ConversationTab.archived),
            ),
        ],
      ),
    );
  }
}

/// "Ativas · n" / "Arquivadas · n" (R6, R11: a [TabBar], so the selected
/// state reaches the screen reader).
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.controller,
    required this.active,
    required this.archived,
  });

  final TabController controller;
  final int active;
  final int archived;

  @override
  Widget build(BuildContext context) {
    Widget label(String text, int n, {IconData? icon}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 6)],
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 6),
        Text(
          '$n',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      child: Container(
        height: 36,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: TabBar(
          key: const ValueKey('conversation-tabs'),
          controller: controller,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.6)),
          ),
          labelColor: AppColors.amber,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          labelPadding: EdgeInsets.zero,
          splashBorderRadius: BorderRadius.circular(6),
          tabs: [
            Tab(
              key: const ValueKey('conversation-tab-active'),
              height: 28,
              child: Semantics(
                label: 'Ativas, $active',
                excludeSemantics: true,
                child: label('Ativas', active),
              ),
            ),
            Tab(
              key: const ValueKey('conversation-tab-archived'),
              height: 28,
              child: Semantics(
                label: 'Arquivadas, $archived',
                excludeSemantics: true,
                child: label(
                  'Arquivadas',
                  archived,
                  icon: Icons.archive_outlined,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Arquivadas · n" at the bottom of the active list (R5).
class _ArchivedFooter extends StatelessWidget {
  const _ArchivedFooter({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
    child: Semantics(
      button: true,
      label: 'Arquivadas, $count. Abrir a aba de arquivadas',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('conversation-archived-footer'),
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.archive_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Arquivadas',
                  style: TextStyle(fontSize: 13, color: AppColors.text),
                ),
              ),
              Text(
                '$count',
                key: const ValueKey('conversation-archived-count'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 28 px icon button of a row (R1, R11: tooltip and label).
class RowAction extends StatelessWidget {
  const RowAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 28,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      iconSize: 16,
      color: AppColors.textSecondary,
      hoverColor: Colors.white.withValues(alpha: .08),
      focusColor: AppColors.amber.withValues(alpha: .25),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: Icon(icon),
    ),
  );
}

/// One conversation of the list: hover or focus shows its actions, the
/// selected one shows ⋯, right click opens its menu (R1).
class ConversationTile extends ConsumerStatefulWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.selected,
    required this.busy,
    required this.active,
  });

  final Conversation conversation;
  final bool selected;
  final bool busy;

  /// The active list, for the selection after archiving (R4).
  final List<Conversation> active;

  @override
  ConsumerState<ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends ConsumerState<ConversationTile> {
  bool _hover = false;
  bool _focus = false;

  void _menu(RelativeRect at) => showConversationMenu(
    context,
    ref,
    c: widget.conversation,
    position: at,
    active: widget.active,
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final selected = widget.selected;
    final archived = c.archivedAt != null;
    final radius = BorderRadius.circular(8);
    final actions = ref.read(conversationActionsProvider);
    final showActions = _hover || _focus;
    final buttons = (showActions ? 1 : 0) + (selected ? 1 : 0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) => setState(() => _focus = f),
        child: GestureDetector(
          onSecondaryTapDown: (d) =>
              _menu(menuPositionAt(context, d.globalPosition)),
          child: Material(
            color: selected
                ? SessionColors.selectedBg
                : (_hover
                      ? Colors.white.withValues(alpha: .04)
                      : Colors.transparent),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                color: selected
                    ? SessionColors.selectedBorder
                    : Colors.transparent,
              ),
            ),
            child: Stack(
              children: [
                InkWell(
                  key: ValueKey('conversation-${c.id}'),
                  borderRadius: radius,
                  onTap: () => ref
                      .read(selectedConversationProvider.notifier)
                      .select(c.id),
                  child: Padding(
                    // Room for the buttons over the row.
                    padding: EdgeInsets.fromLTRB(
                      10,
                      8,
                      buttons == 0 ? 10 : 10 + buttons * 28.0,
                      8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (widget.busy) ...[
                              const Dot(AppColors.teal, size: 6),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          conversationMeta(c),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  top: 0,
                  bottom: 0,
                  right: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showActions)
                        archived
                            ? RowAction(
                                key: ValueKey('conversation-unarchive-${c.id}'),
                                icon: Icons.unarchive_outlined,
                                tooltip: 'Desarquivar',
                                onPressed: () => actions.unarchive(c.id),
                              )
                            : RowAction(
                                key: ValueKey('conversation-archive-${c.id}'),
                                icon: Icons.archive_outlined,
                                tooltip: 'Arquivar',
                                onPressed: () => actions.archive(
                                  context,
                                  c,
                                  active: widget.active,
                                ),
                              ),
                      if (selected)
                        Builder(
                          builder: (context) => RowAction(
                            key: ValueKey('conversation-more-${c.id}'),
                            icon: Icons.more_horiz,
                            tooltip: 'Mais ações',
                            onPressed: () => _menu(menuPositionBelow(context)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Top of an archived conversation (R7): it is not among the active ones and
/// a message brings it back.
class ArchivedBanner extends StatelessWidget {
  const ArchivedBanner({super.key, required this.onUnarchive});

  final VoidCallback onUnarchive;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
    child: Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const ValueKey('archived-banner'),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.archive_outlined,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Conversa arquivada. ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    TextSpan(
                      text:
                          'Ela não aparece entre as ativas. Mandar uma '
                          'mensagem desarquiva.',
                    ),
                  ],
                ),
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 10),
            SmallButton(
              key: const ValueKey('archived-banner-unarchive'),
              label: 'Desarquivar',
              icon: Icons.unarchive_outlined,
              color: AppColors.amber,
              border: AppColors.amber.withValues(alpha: 0.5),
              background: AppColors.amber.withValues(alpha: 0.08),
              onTap: onUnarchive,
            ),
          ],
        ),
      ),
    ),
  );
}
