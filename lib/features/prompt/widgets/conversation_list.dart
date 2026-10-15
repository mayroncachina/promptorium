import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
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

String conversationMeta(Conversation c) {
  final n = c.messageCount;
  return '${modelLabel(c.model)} · ${n == 1 ? '1 mensagem' : '$n mensagens'}';
}

/// Left column of the Prompt screen: conversation history.
class ConversationListPanel extends ConsumerWidget {
  const ConversationListPanel({
    super.key,
    required this.conversations,
    required this.selectedId,
  });

  final List<Conversation> conversations;
  final int? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = groupConversations(conversations);
    final busy = ref.watch(conversationManagerProvider);
    return ColoredBox(
      color: AppColors.panel,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Text('CONVERSAS', style: sectionTitleStyle),
          ),
          if (conversations.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text(
                'Nenhuma conversa ainda. Escreva uma pergunta ao lado.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          for (final (name, items) in groups) ...[
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
            for (final c in items)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
                child: _Tile(
                  conversation: c,
                  selected: c.id == selectedId,
                  busy: busy.isBusy(c.id),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({
    required this.conversation,
    required this.selected,
    required this.busy,
  });

  final Conversation conversation;
  final bool selected;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final radius = BorderRadius.circular(8);
    return Material(
      color: selected ? SessionColors.selectedBg : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: selected ? SessionColors.selectedBorder : Colors.transparent,
        ),
      ),
      child: InkWell(
        key: ValueKey('conversation-${c.id}'),
        borderRadius: radius,
        onTap: () =>
            ref.read(selectedConversationProvider.notifier).select(c.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (busy) ...[
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
    );
  }
}
