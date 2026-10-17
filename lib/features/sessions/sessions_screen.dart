import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../project/project_config.dart' show projectConfigProvider;
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

/// Tab of one session's pane (kept per session: two panes side by side can
/// show different tabs; UX v2, U3).
class SessionTabController extends Notifier<SessionTab> {
  SessionTabController(this.sessionId);

  final String sessionId;

  @override
  SessionTab build() => SessionTab.timeline;

  void set(SessionTab t) => state = t;
}

final sessionTabProvider =
    NotifierProvider.family<SessionTabController, SessionTab, String>(
      SessionTabController.new,
    );

/// Session shown in the second pane ("Lado a lado"; null = one pane).
class SplitSessionController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

final splitSessionProvider = NotifierProvider<SplitSessionController, String?>(
  SplitSessionController.new,
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
    final splitId = ref.watch(splitSessionProvider);
    Session? second;
    for (final s in sessions) {
      if (s.id == splitId && s.id != selected?.id) second = s;
    }

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
                  splitId: second?.id,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? _Empty(hasWorkspace: ws != null)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PanesBar(
                            sessions: sessions,
                            selected: selected,
                            second: second,
                          ),
                          Expanded(
                            child: second == null
                                ? _SessionMain(
                                    key: ValueKey(
                                      'session-main-${selected.id}',
                                    ),
                                    session: selected,
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: _SessionMain(
                                          key: ValueKey(
                                            'session-main-${selected.id}',
                                          ),
                                          session: selected,
                                          pane: 'A',
                                        ),
                                      ),
                                      const VerticalDivider(width: 1),
                                      Expanded(
                                        child: _SessionMain(
                                          key: ValueKey(
                                            'session-main-${second.id}',
                                          ),
                                          session: second,
                                          pane: 'B',
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
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

/// "Uma · Lado a lado" above the panes (UX v2, U3). Side by side opens the
/// next session of the list in a second pane; Ctrl+\ does the same.
class _PanesBar extends ConsumerWidget {
  const _PanesBar({
    required this.sessions,
    required this.selected,
    required this.second,
  });

  final List<Session> sessions;
  final Session selected;
  final Session? second;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = second != null;
    Widget seg(String label, bool on, VoidCallback onTap, String keyName) =>
        InkWell(
          key: ValueKey('session-panes-$keyName'),
          onTap: onTap,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            color: on ? AppColors.amberTint : Colors.transparent,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: on ? AppColors.amber : AppColors.textSecondary,
              ),
            ),
          ),
        );
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Text(
            'Visão',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                seg(
                  'Uma',
                  !split,
                  () => ref.read(splitSessionProvider.notifier).set(null),
                  'one',
                ),
                seg(
                  'Lado a lado',
                  split,
                  () => toggleSplit(ref, sessions, selected.id),
                  'split',
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              split
                  ? 'Clique numa sessão da lista para trocá-la no painel A · '
                        'Ctrl+\\ fecha'
                  : 'Ctrl+\\ divide · ⫿ na lista abre ao lado',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the next session of the list (after [selectedId]) in the second
/// pane, or closes the pane if it is open.
void toggleSplit(WidgetRef ref, List<Session> sessions, String selectedId) {
  final split = ref.read(splitSessionProvider.notifier);
  if (ref.read(splitSessionProvider) != null) return split.set(null);
  final i = sessions.indexWhere((s) => s.id == selectedId);
  final next = [...sessions.skip(i + 1), ...sessions.take(i)].firstOrNull;
  if (next != null) split.set(next.id);
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
  const _SessionMain({super.key, required this.session, this.pane});

  final Session session;

  /// `A` / `B` when side by side (null = single pane).
  final String? pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(sessionTabProvider(session.id));
    final changes = ref.watch(sessionChangesProvider(session.id)).value;
    final s = session;

    Widget tabButton(SessionTab t, String label) {
      final on = t == tab;
      return InkWell(
        key: ValueKey('session-tab-${t.name}'),
        onTap: () => ref.read(sessionTabProvider(s.id).notifier).set(t),
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
            root: s.worktreePath,
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
        _Header(session: s, pane: pane),
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

/// `PROMPTORIUM_PORT` of a spec session (`worktree.porta-base` + the
/// worktree index; null = no port) — "Abrir preview" (UX v2, U3).
final previewPortProvider = Provider.autoDispose.family<int?, String>((
  ref,
  sessionId,
) {
  final ws = ref.watch(activeWorkspaceProvider);
  if (ws == null) return null;
  final base = ref
      .watch(projectConfigProvider(ws.path))
      .value
      ?.worktree
      .basePort;
  if (base == null) return null;
  final session = (ref.watch(sessionsProvider(ws.id)).value ?? const [])
      .where((s) => s.id == sessionId)
      .firstOrNull;
  if (session?.specId == null) return null;
  final spec = (ref.watch(specsProvider(ws.id)).value ?? const [])
      .where((x) => x.id == session!.specId)
      .firstOrNull;
  return spec?.worktreeIndex == null ? null : base + spec!.worktreeIndex!;
});

/// Opens `http://localhost:[port]` in the browser (`xdg-open`).
Future<void> openPreview(int port) async {
  try {
    await Process.run('xdg-open', ['http://localhost:$port']);
  } catch (e) {
    debugPrint('xdg-open preview: $e');
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.session, this.pane});

  final Session session;
  final String? pane;

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
    final previewPort = ref.watch(previewPortProvider(s.id));

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
            flex: 2,
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
                        .read(sessionTabProvider(s.id).notifier)
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
                if (previewPort != null)
                  SmallButton(
                    key: ValueKey('session-preview-${s.id}'),
                    label: 'Abrir preview :$previewPort',
                    onTap: () => openPreview(previewPort),
                  ),
                if (pane == 'B')
                  SmallButton(
                    key: const ValueKey('session-pane-close'),
                    label: '×',
                    onTap: () =>
                        ref.read(splitSessionProvider.notifier).set(null),
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
