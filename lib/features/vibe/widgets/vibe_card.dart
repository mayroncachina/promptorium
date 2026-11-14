import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../prompt/conversation_manager.dart';
import '../../sessions/session_manager.dart' show vibeSessionPrefix;
import '../../sessions/widgets/session_style.dart';
import '../vibe_guard.dart';
import '../vibe_service.dart';
import 'vibe_widgets.dart';

/// Days without a message after which a VIBE is "parada" (R11).
const vibeStaleAfterDays = 7;

/// "parada há N dias" (R11): N when [last] is at least
/// [vibeStaleAfterDays] days before [now], else null. Nothing is discarded.
int? vibeStaleDays(DateTime last, DateTime now) {
  final days = now.difference(last).inDays;
  return days >= vibeStaleAfterDays ? days : null;
}

/// The conversation of a VIBE in the workspace's list (null = none).
Conversation? _conversationOf(WidgetRef ref, Spec spec) =>
    (ref.watch(conversationsProvider(spec.workspaceId)).value ??
            const <Conversation>[])
        .where((c) => c.specId == spec.id)
        .firstOrNull;

/// Opens the conversation of [spec] in the Prompt (R9).
void openVibeConversation(WidgetRef ref, Conversation? conv) {
  if (conv == null) return;
  ref.read(selectedConversationProvider.notifier).select(conv.id);
  ref.read(navigationProvider.notifier).go(AppSection.prompt);
}

/// A VIBE on the Quadro (R9, R10, R11): the purple "VIBE" mark (text), the
/// summary, the "parada há N dias" seal; a click opens its conversation.
class VibeCard extends ConsumerWidget {
  const VibeCard({super.key, required this.spec, this.now});

  final Spec spec;

  /// Clock of the seal (tests).
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = _conversationOf(ref, spec);
    final busy =
        conv != null &&
        ref.watch(conversationManagerProvider.select((m) => m.isBusy(conv.id)));
    final last = conv?.updatedAt ?? conv?.createdAt;
    final done = spec.stage == SpecStage.done;
    final stale = last == null || done || busy
        ? null
        : vibeStaleDays(last, now ?? DateTime.now());
    final size = spec.stage == SpecStage.running && spec.worktreePath != null
        ? ref.watch(vibeSizeProvider((spec.id, conv?.messageCount ?? 0))).value
        : null;
    final summary = switch (spec.stage) {
      _ when done => 'concluída',
      SpecStage.review => 'gate ok · aguardando review',
      _ when stale != null =>
        'última mensagem há $stale ${stale == 1 ? 'dia' : 'dias'}',
      _ =>
        '${busy ? 'respondendo' : 'conversando'}'
            '${size == null ? '' : ' · ${size.files} ${size.files == 1 ? 'arquivo' : 'arquivos'}'}',
    };
    return Semantics(
      label: 'VIBE ${spec.code}, ${spec.title}',
      child: Container(
        key: ValueKey('vibe-card-${spec.code}'),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: vibeColor.withValues(alpha: .55)),
        ),
        child: InkWell(
          key: ValueKey('board-open-${spec.code}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => openVibeConversation(ref, conv),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: vibeColor, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const VibeBadge(),
                    const SizedBox(width: 6),
                    Text(
                      spec.code,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    _VibeMenu(spec: spec, conversation: conv),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  spec.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (stale != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      key: ValueKey('vibe-stale-${spec.code}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: SessionColors.approvalBorder),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 12,
                            color: AppColors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'parada há $stale dias',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  summary,
                  key: ValueKey('board-meta-${spec.code}'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
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

class _VibeMenu extends ConsumerWidget {
  const _VibeMenu({required this.spec, required this.conversation});

  final Spec spec;
  final Conversation? conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      key: ValueKey('board-menu-${spec.code}'),
      tooltip: 'Ações da VIBE',
      icon: const Icon(Icons.more_horiz, size: 16),
      padding: EdgeInsets.zero,
      onSelected: (v) async {
        switch (v) {
          case 'open':
            openVibeConversation(ref, conversation);
          case 'review':
            try {
              final r = await ref
                  .read(vibeServiceProvider)
                  .sendToReview(spec.id);
              if (context.mounted && !r.ok) {
                ScaffoldMessenger.maybeOf(context)?.showAppToast(
                  SnackBar(
                    content: Text(
                      'O gate de ${spec.code} falhou: veja a conversa.',
                    ),
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)
                    ?.showAppToast(SnackBar(content: Text('$e')));
              }
            }
          case 'discard':
            await confirmDiscardVibe(context, ref, spec);
        }
      },
      itemBuilder: (_) => [
        if (conversation != null)
          const PopupMenuItem(value: 'open', child: Text('Abrir a conversa')),
        if (spec.stage == SpecStage.running)
          const PopupMenuItem(
            value: 'review',
            child: Text('Enviar para Review'),
          ),
        if (VibeService.canDiscard(spec))
          const PopupMenuItem(
            key: ValueKey('vibe-menu-discard'),
            value: 'discard',
            child: Text('Descartar VIBE'),
          ),
      ],
    );
  }
}

/// "Descartar VIBE" (R10): the confirmation says exactly what goes.
/// Returns whether it was discarded.
Future<bool> confirmDiscardVibe(
  BuildContext context,
  WidgetRef ref,
  Spec spec,
) async {
  final ok = await showAppDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => VibeDiscardDialog(spec: spec),
  );
  if (ok != true) return false;
  try {
    await ref.read(vibeServiceProvider).discard(spec.id);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showAppToast(SnackBar(content: Text('$e')));
    }
    return false;
  }
}

class VibeDiscardDialog extends ConsumerWidget {
  const VibeDiscardDialog({super.key, required this.spec});

  final Spec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = spec.worktreePath == null
        ? null
        : ref.watch(vibeSizeProvider((spec.id, 0))).value;
    final sessions =
        ref.watch(sessionsProvider(spec.workspaceId)).value ??
        const <Session>[];
    final reviewed = sessions.any(
      (s) => s.specId == spec.id && s.id.startsWith(vibeSessionPrefix),
    );
    final facts = [
      '“${spec.title}”',
      if (size != null)
        '${size.files} ${size.files == 1 ? 'arquivo mudado' : 'arquivos mudados'}',
      reviewed ? 'já foi para o Review' : 'nunca foi para o Review',
    ].join(' · ');
    return Align(
      alignment: const Alignment(0, -0.4),
      child: Material(
        key: const ValueKey('vibe-discard-dialog'),
        color: AppColors.panelSolid,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Descartar a ${spec.code}?',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            facts,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text.rich(
                  key: const ValueKey('vibe-discard-text'),
                  TextSpan(
                    style: const TextStyle(fontSize: 13, height: 1.5),
                    children: [
                      const TextSpan(text: 'Apaga o worktree, a branch '),
                      TextSpan(
                        text: spec.branch ?? 'vibe/…',
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          color: AppColors.teal,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' e a conversa. O número ${spec.code} não é '
                            'reutilizado. Não dá para desfazer.',
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SmallButton(
                      label: 'Cancelar',
                      height: 34,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                    const SizedBox(width: 8),
                    SmallButton(
                      key: const ValueKey('vibe-discard-confirm'),
                      label: 'Descartar',
                      height: 34,
                      color: Colors.white,
                      background: AppColors.red,
                      border: AppColors.red,
                      fontWeight: FontWeight.w600,
                      onTap: () => Navigator.of(context).pop(true),
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
