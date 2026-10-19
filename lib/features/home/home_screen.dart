import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/shell/notification_center.dart'
    show recentNotificationsProvider;
import '../../ui/theme/tokens.dart';
import '../board/autopilot.dart';
import '../board/board_screen.dart' show openSession, openSessionIn;
import '../board/widgets/card_extras.dart' show LiveToolLine;
import '../project/project_config.dart';
import '../prompt/conversation_manager.dart';
import '../review/review_service.dart' show selectedReviewProvider;
import '../sessions/session_manager.dart';
import '../sessions/widgets/session_style.dart';
import '../sessions/widgets/side_panel.dart' show ApprovalCard;
import 'home_inbox.dart';

/// Início · "Para você" (UX v2, U1; docs/mockups/v2/Main.dc.html): one list
/// with everything that waits for the user, plus "Agora" (running sessions,
/// Autopilot, the day's numbers and the last notifications).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return const Center(
        child: Text(
          'Selecione um workspace na barra de título.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _Inbox(workspace: ws)),
        Container(
          width: 340,
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(left: BorderSide(color: AppColors.border)),
          ),
          child: _NowPanel(workspace: ws),
        ),
      ],
    );
  }
}

class _Inbox extends ConsumerWidget {
  const _Inbox({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(inboxProvider);
    final total = groups.fold(0, (a, g) => a + g.items.length);
    return ListView(
      key: const ValueKey('home-inbox'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        const Text(
          'Para você',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          total == 0
              ? 'Nada espera uma decisão sua. O resto está andando sozinho.'
              : '$total ${total == 1 ? 'item espera' : 'itens esperam'} uma '
                    'decisão sua. O resto está andando sozinho.',
          key: const ValueKey('home-summary'),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        for (final g in groups) ...[
          _GroupTitle(group: g),
          const SizedBox(height: 6),
          for (final it in g.items) ...[
            _InboxRow(item: it, color: _colorOf(g.kind)),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

Color _colorOf(InboxKind k) => switch (k) {
  InboxKind.approval => AppColors.amber,
  InboxKind.needsAnswer => AppColors.red,
  InboxKind.review => AppColors.blue,
  InboxKind.prProblem => AppColors.lilac,
  InboxKind.interrupted => AppColors.textMuted,
};

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.group});

  final InboxGroup group;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Dot(_colorOf(group.kind)),
      const SizedBox(width: 8),
      Text(
        group.title.toUpperCase(),
        key: ValueKey('home-group-${group.kind.name}'),
        style: sectionTitleStyle,
      ),
      const SizedBox(width: 6),
      Text(
        '· ${group.items.length}',
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );
}

/// One item: ref · title / detail · when · actions. An approval shows the
/// [ApprovalCard] itself (Aprovar / Negar / Sempre permitir).
class _InboxRow extends ConsumerWidget {
  const _InboxRow({required this.item, required this.color});

  final InboxItem item;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = item.approval;
    if (a != null) {
      final conv = item.conversationId;
      final manager = ref.read(conversationManagerProvider.notifier);
      return ApprovalCard(
        key: ValueKey('home-approval-${a.requestId}'),
        approval: a,
        onOpen: () {
          if (conv != null) {
            ref.read(selectedConversationProvider.notifier).select(conv);
            ref.read(navigationProvider.notifier).go(AppSection.prompt);
          } else {
            openSession(ref, a.sessionId);
          }
        },
        onApprove: conv == null
            ? null
            : ({required bool always, input}) => manager.approve(
                conv,
                a.requestId,
                always: always,
                updatedInput: input,
              ),
        onDeny: conv == null ? null : () => manager.deny(conv, a.requestId),
      );
    }
    final (primary, secondary) = _actions(context, ref);
    return Container(
      key: ValueKey(
        'home-item-${item.kind.name}-${item.sessionId ?? item.ref}',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              item.ref,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  item.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatAge(DateTime.now().difference(item.at)),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          if (secondary != null) ...[secondary, const SizedBox(width: 6)],
          primary,
        ],
      ),
    );
  }

  (Widget, Widget?) _actions(BuildContext context, WidgetRef ref) {
    final id = item.sessionId;
    void goReview() {
      if (id != null) ref.read(selectedReviewProvider.notifier).select(id);
      ref.read(navigationProvider.notifier).go(AppSection.review);
    }

    Widget open(String label) => SmallButton(
      key: ValueKey('home-open-${item.kind.name}-${id ?? item.ref}'),
      label: label,
      height: 28,
      background: AppColors.background,
      onTap: () => id == null
          ? ref.read(navigationProvider.notifier).go(AppSection.sessions)
          : openSession(ref, id),
    );
    final key = ValueKey('home-action-${item.kind.name}-${id ?? item.ref}');
    return switch (item.kind) {
      // Only a "plano pronto" of a conversation gets here (no approval).
      InboxKind.approval => (
        SmallButton(
          key: key,
          label: 'Ver plano',
          height: 28,
          background: SessionColors.selectedBg,
          border: SessionColors.selectedBorder,
          onTap: () {
            final conv = item.conversationId;
            if (conv != null) {
              ref.read(selectedConversationProvider.notifier).select(conv);
            }
            ref.read(navigationProvider.notifier).go(AppSection.prompt);
          },
        ),
        null,
      ),
      InboxKind.needsAnswer => (
        AmberButton(
          key: key,
          label: 'Responder na sessão',
          height: 28,
          onTap: () => id == null ? null : openSession(ref, id),
        ),
        SmallButton(
          label: 'Quadro',
          height: 28,
          background: AppColors.background,
          onTap: () =>
              ref.read(navigationProvider.notifier).go(AppSection.tasks),
        ),
      ),
      InboxKind.review || InboxKind.prProblem => (
        SmallButton(
          key: key,
          label: 'Abrir review',
          height: 28,
          background: SessionColors.selectedBg,
          border: SessionColors.selectedBorder,
          onTap: goReview,
        ),
        open('Ver sessão'),
      ),
      InboxKind.interrupted => (
        SmallButton(
          key: key,
          label: 'Retomar',
          height: 28,
          color: AppColors.teal,
          background: SessionColors.selectedBg,
          border: SessionColors.selectedBorder,
          onTap: () async {
            if (id == null) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            // The row leaves the inbox once the session is alive again, so
            // [ref] may be gone after the await.
            final container = ProviderScope.containerOf(context);
            try {
              await container
                  .read(sessionManagerProvider.notifier)
                  .send(id, 'Continue de onde parou.');
              openSessionIn(container, id);
            } catch (e) {
              messenger?.showSnackBar(SnackBar(content: Text('$e')));
            }
          },
        ),
        open('Abrir'),
      ),
    };
  }
}

/// Right column: running sessions, Autopilot, today and the last notices.
class _NowPanel extends ConsumerWidget {
  const _NowPanel({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = workspace;
    final manager = ref.watch(sessionManagerProvider);
    final sessions = ref.watch(sessionsProvider(ws.id)).value ?? const [];
    final running = [
      for (final s in sessions)
        if (manager.isAlive(s.id) &&
            (s.status == SessionStatus.running ||
                s.status == SessionStatus.waitingApproval))
          s,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final today = sessions.where((s) => !s.startedAt.isBefore(day)).toList();
    final cost = today.fold<double>(0, (a, s) => a + s.costUsd);
    final merges = sessions
        .where(
          (s) =>
              s.status == SessionStatus.merged &&
              s.endedAt != null &&
              !s.endedAt!.isBefore(day),
        )
        .length;
    final on = ref.watch(autopilotProvider).contains(ws.id);
    final config = ref.watch(projectConfigProvider(ws.path)).value;
    final parallel = config?.autopilot.parallel;
    final budget = config?.autopilot.dailyBudgetUsd;
    final spent = today
        .where((s) => s.specId != null)
        .fold<double>(0, (a, s) => a + s.costUsd);
    final schedule = AutopilotSchedule.decode(
      ref.watch(
        appSettingsProvider.select((m) => m[AutopilotSchedule.key(ws.id)]),
      ),
    );
    final notices =
        ref.watch(recentNotificationsProvider).value ??
        const <AppNotification>[];

    return ListView(
      key: const ValueKey('home-now'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      children: [
        _title('Em execução', '· ${running.length}'),
        if (running.isEmpty)
          const Text(
            'Nenhuma sessão rodando.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        for (final s in running) ...[
          InkWell(
            key: ValueKey('home-running-${s.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => openSession(ref, s.id),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Dot(
                        s.status == SessionStatus.waitingApproval
                            ? AppColors.amber
                            : AppColors.teal,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sessionTitle(s),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        formatCost(s.costUsd),
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 2),
                    child: LiveToolLine(session: s, specCode: 'home-${s.id}'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 14),
        Container(
          key: const ValueKey('home-autopilot'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: on ? SessionColors.runningToolBg : AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on ? SessionColors.runningToolBorder : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Dot(on ? AppColors.teal : AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      on ? 'Autopilot ligado' : 'Autopilot desligado',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SmallButton(
                    key: const ValueKey('home-autopilot-toggle'),
                    label: on ? 'Pausar' : 'Ligar',
                    height: 26,
                    fontSize: 11,
                    background: Colors.transparent,
                    border: on
                        ? SessionColors.runningToolBorder
                        : AppColors.border,
                    onTap: () => on
                        ? ref.read(autopilotProvider.notifier).stop(ws.id)
                        : ref.read(autopilotProvider.notifier).start(ws.id),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _kv(
                'Em paralelo',
                parallel == null
                    ? '${running.length}'
                    : '${running.length} de $parallel',
              ),
              _kv(
                'Orçamento do dia',
                budget == null
                    ? formatCost(spent)
                    : '${formatCost(spent)} / ${formatCost(budget)}',
              ),
              _kv('Agendado', schedule?.label ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _title('Hoje', ''),
        Row(
          children: [
            _stat('Custo', formatCost(cost)),
            const SizedBox(width: 8),
            _stat('Sessões', '${today.length}'),
            const SizedBox(width: 8),
            _stat('Merges', '$merges'),
          ],
        ),
        const SizedBox(height: 18),
        _title('Últimos avisos', ''),
        if (notices.isEmpty)
          const Text(
            'Nenhum aviso ainda.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        for (final n in notices.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatClock(n.createdAt),
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    n.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _title(String text, String count) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Text(text.toUpperCase(), style: sectionTitleStyle),
        if (count.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            count,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          v,
          style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _stat(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}
