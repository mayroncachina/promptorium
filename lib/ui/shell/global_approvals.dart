import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/prompt/conversation_manager.dart';
import '../../features/sessions/session_manager.dart';
import '../../features/sessions/widgets/side_panel.dart' show ApprovalCard;
import '../theme/tokens.dart';
import 'navigation.dart';

/// Pending permission requests of sessions and Prompt conversations, shown
/// on whatever screen the user is, so they do not have to go to the session
/// to answer. A request is hidden here while the screen already shows it
/// (the selected session in Sessões, the selected conversation in Prompt).
class GlobalApprovals extends ConsumerWidget {
  const GlobalApprovals({super.key, this.maxShown = 3});

  /// Cards shown at once; the rest are counted.
  final int maxShown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(navigationProvider);
    final selectedSession = ref.watch(selectedSessionProvider);
    final selectedConversation = ref.watch(selectedConversationProvider);
    final sessions = ref.watch(
      sessionManagerProvider.select((s) => s.approvals),
    );
    final conversations = ref.watch(conversationManagerProvider);

    final items = <_Item>[
      for (final a in sessions)
        if (!(section == AppSection.sessions && selectedSession == a.sessionId))
          _Item(a, sessionId: a.sessionId),
      for (final e in conversations.live.entries)
        if (!(section == AppSection.prompt && selectedConversation == e.key))
          for (final a in e.value.approvals) _Item(a, conversationId: e.key),
    ]..sort((a, b) => a.approval.receivedAt.compareTo(b.approval.receivedAt));
    if (items.isEmpty) return const SizedBox.shrink();

    final shown = items.take(maxShown).toList();
    final more = items.length - shown.length;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            key: const ValueKey('global-approvals'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final i in shown) ...[
                Material(
                  elevation: 8,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: _card(ref, i),
                ),
                const SizedBox(height: 8),
              ],
              if (more > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '+ $more ${more == 1 ? 'pendente' : 'pendentes'}',
                    key: const ValueKey('global-approvals-more'),
                    style: const TextStyle(
                      fontSize: 11,
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

  Widget _card(WidgetRef ref, _Item i) {
    final a = i.approval;
    final conv = i.conversationId;
    if (conv == null) {
      return ApprovalCard(
        approval: a,
        onOpen: () {
          ref.read(selectedSessionProvider.notifier).select(a.sessionId);
          ref.read(navigationProvider.notifier).go(AppSection.sessions);
        },
      );
    }
    final manager = ref.read(conversationManagerProvider.notifier);
    return ApprovalCard(
      approval: a,
      onOpen: () {
        ref.read(selectedConversationProvider.notifier).select(conv);
        ref.read(navigationProvider.notifier).go(AppSection.prompt);
      },
      onApprove: ({required bool always}) =>
          manager.approve(conv, a.requestId, always: always),
      onDeny: () => manager.deny(conv, a.requestId),
    );
  }
}

class _Item {
  const _Item(this.approval, {this.sessionId, this.conversationId});

  final PendingApproval approval;
  final String? sessionId;
  final int? conversationId;
}
