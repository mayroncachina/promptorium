import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/memory/ai_memory_cli.dart';
import '../../../core/memory/ai_memory_state.dart';
import '../../../core/memory/handoff.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../session_manager.dart';
import '../timeline_provider.dart';
import 'handoff_wait.dart';
import '../timeline.dart';
import '../widgets/session_style.dart';
import 'continue_link.dart';
import 'session_summary.dart' show providerWords;

/// The note "Continuada de …" and, below it, the card of what came with
/// the new session (SPEC-099 R8): the ai-memory handoff (short id, owner,
/// summary and whether it was accepted) or the summary built by the app.
/// The handoff text is shown as plain text only (SPEC-098 R13).
class HandoffCard extends ConsumerWidget {
  const HandoffCard({super.key, required this.item, this.sessionId});

  final HandoffItem item;

  /// The session of the timeline (null in views without one).
  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ContinuationRecord.fromJson(item.data);
    final note = Row(
      children: [
        const Dot(AppColors.textMuted, size: 6),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            item.text,
            key: const ValueKey('handoff-note'),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
        if (item.at != null)
          Text(
            formatClock(item.at),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
      ],
    );
    if (r == null) return note;
    final h = r.handoff;
    final state = h == null || sessionId == null
        ? null
        : handoffStateLabel(ref, sessionId!, r);
    const meta = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    final Widget card;
    if (r.path == ContinuePath.aiMemory) {
      card = Container(
        key: const ValueKey('handoff-card'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ReviewColors.acceptBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.call_split, size: 14, color: AppColors.teal),
                const Text(
                  'Passagem do ai-memory',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.teal,
                  ),
                ),
                if (h != null)
                  Tooltip(
                    message: h.id,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        h.shortId,
                        key: const ValueKey('handoff-card-id'),
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                Text(
                  h == null
                      ? 'sem passagem: a sessão foi cortada'
                      : 'de ${h.agentName}'
                            '${r.handoffOwner == null ? '' : ' · dono: ${r.handoffOwner}'}',
                  style: meta,
                ),
                ?state,
              ],
            ),
            if (h != null && h.summary.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                h.summary.trim(),
                key: const ValueKey('handoff-card-summary'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.text),
              ),
            ],
          ],
        ),
      );
    } else {
      card = Container(
        key: const ValueKey('handoff-card'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notes,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Resumo do app',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'de ${providerWords(r.fromProvider ?? 'claude')} · '
                    'montado pelo app, sem chamar modelo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta,
                  ),
                ),
              ],
            ),
            if (r.text != null) ...[
              const SizedBox(height: 6),
              Text(
                r.text!,
                key: const ValueKey('handoff-card-text'),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [note, const SizedBox(height: 8), card],
    );
  }
}

/// The check after the first turn (R4.5): one `memory_handoff_list` read
/// in the session's directory, by (session, handoff).
final handoffAcceptanceProvider = FutureProvider.autoDispose
    .family<({HandoffAcceptance state, DateTime? at})?, (String, String, String)>(
      (ref, key) async {
        final (_, handoffId, cwd) = key;
        final cli = await ref.watch(aiMemoryCliProvider.future);
        if (cli == null) return null;
        try {
          final list = HandoffList.parse(
            await cli.call('memory_handoff_list', const {}, cwd: cwd),
          );
          return handoffAcceptance(list, handoffId);
        } on AiMemoryException {
          return null;
        }
      },
    );

/// The state of the handoff in the card (R4.5): checked once the first
/// turn of the new session ended. Null while unknown.
Widget? handoffStateLabel(
  WidgetRef ref,
  String sessionId,
  ContinuationRecord r,
) {
  final h = r.handoff;
  if (h == null) return null;
  final turned = ref.watch(
    sessionTimelineProvider(sessionId).select(
      (t) => t.timeline.items.any((i) => i is UserItem),
    ),
  );
  final busy = ref.watch(
    sessionManagerProvider.select((m) => m.live[sessionId]?.busy ?? false),
  );
  if (!turned || busy) return null;
  final cwd = ref.watch(
    sessionsProvider(ref.watch(activeWorkspaceProvider)?.id ?? -1).select(
      (v) => v.value?.where((s) => s.id == sessionId).firstOrNull?.worktreePath,
    ),
  );
  if (cwd == null) return null;
  final v = ref.watch(handoffAcceptanceProvider((sessionId, h.id, cwd))).value;
  if (v == null) return null;
  final ok = v.state != HandoffAcceptance.unconfirmed;
  final text = switch (v.state) {
    HandoffAcceptance.accepted =>
      v.at == null ? 'aceita' : 'aceita às ${formatClock(v.at)}',
    final s => s.label,
  };
  return Container(
    key: const ValueKey('handoff-card-state'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: ok ? ReviewColors.acceptBorder : AppColors.amber,
      ),
    ),
    child: Text(
      ok ? '✓ $text' : text,
      style: TextStyle(
        fontSize: 11,
        color: ok ? AppColors.teal : AppColors.amber,
      ),
    ),
  );
}
