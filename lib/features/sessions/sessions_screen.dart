import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import 'new_session_dialog.dart';
import 'session_changes.dart';
import 'session_manager.dart';
import 'timeline_provider.dart';
import 'widgets/composer.dart';
import 'widgets/diff_raw_views.dart';
import 'widgets/session_list_panel.dart';
import 'widgets/session_style.dart';
import 'widgets/session_terminal.dart';
import 'widgets/side_panel.dart';
import 'widgets/timeline_view.dart';

enum SessionTab { timeline, terminal, diff, raw }

class SessionTabController extends Notifier<SessionTab> {
  @override
  SessionTab build() => SessionTab.timeline;

  void set(SessionTab t) => state = t;
}

final sessionTabProvider = NotifierProvider<SessionTabController, SessionTab>(
  SessionTabController.new,
);

/// Sessions screen (docs/mockups/Main.dc.html): list · timeline · approvals
/// and details. Only inner panels scroll.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    final sessions = ws == null
        ? const <Session>[]
        : ref.watch(sessionsProvider(ws.id)).value ?? const <Session>[];
    final selectedId = ref.watch(selectedSessionProvider);
    Session? selected;
    for (final s in sessions) {
      if (s.id == selectedId) selected = s;
    }
    selected ??= sessions.isEmpty ? null : sessions.first;

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 1100;
        final left = narrow ? 240.0 : 280.0;
        final right = narrow ? 260.0 : 300.0;
        return ColoredBox(
          color: AppColors.background,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: left,
                child: SessionListPanel(
                  sessions: sessions,
                  selectedId: selected?.id,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? _Empty(hasWorkspace: ws != null)
                    : _SessionMain(
                        key: ValueKey('session-main-${selected.id}'),
                        session: selected,
                      ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: right,
                child: SessionSidePanel(session: selected),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.hasWorkspace});

  final bool hasWorkspace;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasWorkspace ? 'Nenhuma sessão ainda' : 'Nenhum workspace',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasWorkspace
                ? 'Crie uma em "Nova sessão" (Ctrl+N).'
                : 'Selecione ou adicione um workspace na barra de título.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          if (hasWorkspace) ...[
            const SizedBox(height: 14),
            AmberButton(
              key: const ValueKey('empty-new-session'),
              label: 'Nova sessão',
              onTap: () => showNewSessionDialog(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionMain extends ConsumerWidget {
  const _SessionMain({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(sessionTabProvider);
    final changes = ref.watch(sessionChangesProvider(session.id)).value;
    final s = session;

    Widget tabButton(SessionTab t, String label) {
      final on = t == tab;
      return InkWell(
        key: ValueKey('session-tab-${t.name}'),
        onTap: () => ref.read(sessionTabProvider.notifier).set(t),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: on ? AppColors.amber : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: on ? FontWeight.w500 : FontWeight.w400,
              color: on ? AppColors.text : AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    final body = switch (tab) {
      SessionTab.timeline => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TimelineView(sessionId: s.id, root: s.worktreePath),
          ),
          SessionComposer(
            sessionId: s.id,
            permissionMode: s.permissionMode,
            canSend: () =>
                ref.read(sessionTerminalsProvider.notifier).isRunning(s.id)
                ? 'Feche o terminal interativo desta sessão antes de enviar.'
                : null,
          ),
        ],
      ),
      SessionTab.terminal => SessionTerminalView(session: s),
      SessionTab.diff => SessionDiffView(sessionId: s.id),
      SessionTab.raw => RawLogView(sessionId: s.id),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(session: s),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                tabButton(SessionTab.timeline, 'Timeline'),
                const SizedBox(width: 2),
                tabButton(SessionTab.terminal, 'Terminal'),
                const SizedBox(width: 2),
                tabButton(
                  SessionTab.diff,
                  changes == null ? 'Diff' : 'Diff · ${changes.count}',
                ),
                const SizedBox(width: 2),
                tabButton(SessionTab.raw, 'Log bruto'),
              ],
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.session});

  final Session session;

  void _snack(BuildContext context, Object e) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$e')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session;
    final alive = ref.watch(
      sessionManagerProvider.select((m) => m.isAlive(s.id)),
    );
    final model = ref.watch(
      sessionTimelineProvider(s.id).select((t) => t.timeline.model),
    );
    final look = SessionLook.of(s.status, alive: alive);
    final manager = ref.read(sessionManagerProvider.notifier);
    final canResume = !alive;

    final agentModel = [
      s.agentName ?? 'sem agente',
      model ?? (s.model == 'inherit' ? 'modelo padrão' : s.model),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Dot(look.color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        sessionTitle(s),
                        key: const ValueKey('session-header-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        look.label,
                        key: const ValueKey('session-header-status'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: look.color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (s.specId != null)
                      InfoTag('SPEC${s.steps == null ? '' : ' ${s.steps}'}')
                    else if (s.taskId != null)
                      InfoTag('TASK #${s.taskId}'),
                    InfoTag(agentModel),
                    InfoTag('worktree: ${s.branch}', mono: true),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            flex: 0,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                SmallButton(
                  key: const ValueKey('session-open-terminal'),
                  label: 'Abrir terminal',
                  onTap: () {
                    ref
                        .read(sessionTabProvider.notifier)
                        .set(SessionTab.terminal);
                    if (!alive) {
                      ref.read(sessionTerminalsProvider.notifier).open(s);
                    }
                  },
                ),
                SmallButton(
                  key: const ValueKey('session-fork'),
                  label: 'Fork',
                  onTap: () => showForkDialog(context, s),
                ),
                if (canResume)
                  SmallButton(
                    key: const ValueKey('session-resume'),
                    label: 'Retomar',
                    color: AppColors.teal,
                    onTap: () async {
                      try {
                        if (s.status == SessionStatus.interrupted ||
                            s.status == SessionStatus.failed) {
                          await manager.send(s.id, 'Continue de onde parou.');
                        } else {
                          await manager.resume(s.id);
                        }
                      } catch (e) {
                        if (context.mounted) _snack(context, e);
                      }
                    },
                  )
                else
                  SmallButton(
                    key: const ValueKey('session-stop'),
                    label: 'Parar',
                    color: AppColors.red,
                    border: SessionColors.stopBorder,
                    onTap: () => manager.stop(s.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
