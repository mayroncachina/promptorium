import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../board/widgets/card_extras.dart' show LiveToolLine;
import '../session_manager.dart';
import '../sessions_screen.dart' show splitSessionProvider;
import 'session_activity.dart';
import 'session_style.dart';

enum SessionFilter { all, waiting, done }

class SessionFilterController extends Notifier<SessionFilter> {
  @override
  SessionFilter build() => SessionFilter.all;

  void set(SessionFilter f) => state = f;
}

final sessionFilterProvider =
    NotifierProvider<SessionFilterController, SessionFilter>(
      SessionFilterController.new,
    );

bool matchesFilter(Session s, SessionFilter f) => switch (f) {
  SessionFilter.all => true,
  SessionFilter.waiting => s.status == SessionStatus.waitingApproval,
  SessionFilter.done => s.status == SessionStatus.completed,
};

/// Left panel of the Sessions screen (mockup 1 · Sessões).
class SessionListPanel extends ConsumerWidget {
  const SessionListPanel({
    super.key,
    required this.sessions,
    required this.selectedId,
    this.splitId,
  });

  final List<Session> sessions;
  final String? selectedId;

  /// Session open in the second pane (UX v2, U3).
  final String? splitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(sessionFilterProvider);
    final manager = ref.watch(sessionManagerProvider);
    final active = sessions
        .where(
          (s) =>
              manager.isAlive(s.id) &&
              (s.status == SessionStatus.running ||
                  s.status == SessionStatus.waitingApproval),
        )
        .length;
    final waiting = sessions
        .where((s) => s.status == SessionStatus.waitingApproval)
        .length;
    final visible = sessions.where((s) => matchesFilter(s, filter)).toList();

    Widget chip(SessionFilter f, String label) {
      final on = filter == f;
      return Material(
        key: ValueKey('session-filter-${f.name}'),
        color: on ? AppColors.amberTint : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: on ? AppColors.amber : AppColors.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => ref.read(sessionFilterProvider.notifier).set(f),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: on ? AppColors.amber : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('SESSÕES', style: sectionTitleStyle),
                ),
                Text(
                  active == 1 ? '1 ativa' : '$active ativas',
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                chip(SessionFilter.all, 'Todas ${sessions.length}'),
                chip(
                  SessionFilter.waiting,
                  waiting == 0 ? 'Aguardando' : 'Aguardando $waiting',
                ),
                chip(SessionFilter.done, 'Concluídas'),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Nenhuma sessão.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, i) => _SessionTile(
                      session: visible[i],
                      selected: visible[i].id == selectedId,
                      pane: visible[i].id == selectedId && splitId != null
                          ? 'A'
                          : visible[i].id == splitId
                          ? 'B'
                          : null,
                      alive: manager.isAlive(visible[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.alive,
    this.pane,
  });

  final Session session;
  final bool selected;
  final bool alive;

  /// `A` / `B` while shown in a pane of "Lado a lado".
  final String? pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = SessionLook.of(session.status, alive: alive);
    final busy = ref.watch(
      sessionManagerProvider.select((s) => s.live[session.id]?.busy ?? false),
    );
    final radius = BorderRadius.circular(8);
    final end = session.endedAt ?? DateTime.now();
    return Material(
      key: ValueKey('session-tile-${session.id}'),
      color: selected ? SessionColors.selectedBg : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: selected ? SessionColors.selectedBorder : Colors.transparent,
        ),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: () =>
            ref.read(selectedSessionProvider.notifier).select(session.id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  busy ? BusyDot(look.color) : Dot(look.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sessionTitle(session),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (pane != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        pane!,
                        key: ValueKey('session-pane-${session.id}'),
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 10,
                          color: AppColors.amber,
                        ),
                      ),
                    ),
                  Text(
                    formatAge(end.difference(session.startedAt)),
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  // The selected session is pane A: opening it in B too
                  // would show nothing new.
                  if (!selected) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      key: ValueKey('session-split-${session.id}'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => ref
                          .read(splitSessionProvider.notifier)
                          .set(pane == 'B' ? null : session.id),
                      child: Tooltip(
                        message: pane == 'B'
                            ? 'Fechar o painel B'
                            : 'Abrir ao lado (painel B)',
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.vertical_split_outlined,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          session.agentName ?? 'sem agente',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('·'),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          look.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: look.color),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatCost(session.costUsd),
                        style: const TextStyle(fontFamily: AppFonts.mono),
                      ),
                    ],
                  ),
                ),
              ),
              if (alive && busy)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2),
                  child: LiveToolLine(
                    session: session,
                    specCode: 'list-${session.id}',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
