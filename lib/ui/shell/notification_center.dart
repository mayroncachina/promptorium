import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../features/sessions/session_manager.dart';
import '../theme/tokens.dart';
import 'navigation.dart';

final _recentNotificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) {
      final repo = ref.watch(notificationsRepoProvider);
      final sub = repo.changes.listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      return repo.recent();
    });

/// Bell of the title bar (F13): unread count and the history of the
/// notifications, each with "Ir para".
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list =
        ref.watch(_recentNotificationsProvider).value ??
        const <AppNotification>[];
    final unread = list.where((n) => !n.read).length;
    return Tooltip(
      message: 'Notificações',
      child: InkWell(
        key: const ValueKey('notifications-open'),
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          await showDialog<void>(
            context: context,
            barrierColor: AppColors.scrim,
            builder: (_) => const _NotificationsDialog(),
          );
          await ref.read(notificationsRepoProvider).markAllRead();
        },
        child: SizedBox(
          width: 34,
          height: 30,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.notifications_none,
                size: 18,
                color: AppColors.textSecondary,
              ),
              if (unread > 0)
                Positioned(
                  right: 3,
                  top: 3,
                  child: Container(
                    key: const ValueKey('notifications-unread'),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.amber,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.onAmber,
                        fontWeight: FontWeight.w600,
                      ),
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

class _NotificationsDialog extends ConsumerWidget {
  const _NotificationsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list =
        ref.watch(_recentNotificationsProvider).value ??
        const <AppNotification>[];
    String when(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: const Alignment(0.9, -0.85),
      child: Material(
        key: const ValueKey('notifications-dialog'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          width: 420,
          height: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Notificações',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('notifications-clear'),
                      onPressed: list.isEmpty
                          ? null
                          : () => ref.read(notificationsRepoProvider).clear(),
                      child: const Text('Limpar'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhuma notificação.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) {
                          final n = list[i];
                          final section = AppSection.values
                              .asNameMap()[n.section ?? ''];
                          return ListTile(
                            key: ValueKey('notification-${n.id}'),
                            dense: true,
                            leading: Icon(
                              Icons.circle,
                              size: 8,
                              color: n.read
                                  ? Colors.transparent
                                  : AppColors.amber,
                            ),
                            title: Text(
                              n.title,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              '${n.body}\n${when(n.createdAt)}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            trailing: section == null
                                ? null
                                : TextButton(
                                    key: ValueKey('notification-go-${n.id}'),
                                    onPressed: () {
                                      if (n.sessionId != null) {
                                        ref
                                            .read(
                                              selectedSessionProvider.notifier,
                                            )
                                            .select(n.sessionId);
                                      }
                                      ref
                                          .read(navigationProvider.notifier)
                                          .go(section);
                                      Navigator.of(context).pop();
                                    },
                                    child: const Text('Ir para'),
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
