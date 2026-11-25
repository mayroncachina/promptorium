import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../conversation_events.dart';
import '../restore/restore_service.dart';
import '../session_manager.dart';
import '../timeline.dart';
import 'session_style.dart';
import 'undo_dialog.dart';

/// "fora da conversa do agente · revertido às 14:20" (SPEC-110 R10).
class RevertedBadge extends StatelessWidget {
  const RevertedBadge(this.mark, {super.key});

  final RevertMark mark;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.red.withValues(alpha: .6)),
    ),
    child: Text(
      'fora da conversa do agente · revertido às ${formatClock(mark.at)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11, color: AppColors.red),
    ),
  );
}

/// "revertido às 14 e 20" (R11): what the screen reader says.
String revertedSemantics(RevertMark mark) =>
    'revertido às ${mark.at.hour} e ${mark.at.minute}';

/// A timeline item that left the agent's conversation (R10, R11): dimmed,
/// announced as reverted, with the badge where [badge] says.
class RevertedItem extends StatelessWidget {
  const RevertedItem({
    super.key,
    required this.mark,
    required this.child,
    this.badge = false,
    this.right = false,
  });

  final RevertMark mark;
  final Widget child;
  final bool badge;

  /// The badge on the right (a message of the person).
  final bool right;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: revertedSemantics(mark),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (badge)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Align(
              alignment: right ? Alignment.centerRight : Alignment.centerLeft,
              child: ExcludeSemantics(
                child: RevertedBadge(
                  mark,
                  key: const ValueKey('timeline-reverted-badge'),
                ),
              ),
            ),
          ),
        Opacity(
          key: const ValueKey('timeline-reverted'),
          opacity: .45,
          child: child,
        ),
      ],
    ),
  );
}

/// What an undo did to the agent's conversation (R8): it went back, with
/// "Refazer" while it can be done; or it did not, with "Tentar voltar a
/// conversa".
class ConversationCard extends ConsumerStatefulWidget {
  const ConversationCard({
    super.key,
    required this.item,
    required this.sessionId,
  });

  final ConversationItem item;

  /// Null outside a session: only the text.
  final String? sessionId;

  @override
  ConsumerState<ConversationCard> createState() => _ConversationCardState();
}

class _ConversationCardState extends ConsumerState<ConversationCard> {
  bool _working = false;
  String? _error;

  Future<void> _redo(String sid, RestorePoint p) async {
    final s = await ref.read(sessionsRepoProvider).getById(sid);
    if (s == null || !mounted) return;
    await openUndoDialog(context, ref, session: s, point: p, redo: true);
  }

  Future<void> _retry(String sid, ConversationRevert r) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(restoreServiceProvider).retryConversation(sid, r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.item.data;
    final sid = widget.sessionId;
    final points = sid == null
        ? const <RestorePoint>[]
        : ref.watch(sessionRestorePointsProvider(sid)).value ??
              const <RestorePoint>[];
    final point = points.where((p) => p.id == r.pointId).firstOrNull;
    // The same rule of the "Refazer" of the panel (SPEC-084 R11), and only
    // the newest event of that point.
    final open =
        point != null &&
        point.state == RestoreState.undone &&
        point.undoneSha != null &&
        widget.item.current;
    final busy =
        sid != null &&
        ref.watch(
          sessionManagerProvider.select((s) => s.live[sid]?.busy ?? false),
        );
    final color = r.ok ? AppColors.teal : AppColors.red;
    return Container(
      key: ValueKey(
        r.ok ? 'conversation-reverted' : 'conversation-revert-failed',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              r.ok ? Icons.undo_rounded : Icons.error_outline_rounded,
              size: 15,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  widget.item.text,
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _error!,
                      key: const ValueKey('conversation-retry-error'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                if (!r.ok && open) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SmallButton(
                        key: const ValueKey('conversation-retry'),
                        label: _working
                            ? 'Voltando…'
                            : 'Tentar voltar a conversa',
                        height: 28,
                        onTap: busy || _working ? null : () => _retry(sid!, r),
                      ),
                      const Text(
                        'só a conversa; os arquivos não mudam',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (r.ok && open) ...[
            const SizedBox(width: 10),
            SmallButton(
              key: const ValueKey('conversation-redo'),
              label: 'Refazer',
              height: 28,
              onTap: busy ? null : () => _redo(sid!, point),
            ),
          ],
        ],
      ),
    );
  }
}
