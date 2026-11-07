import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tray_service.dart';
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../board/board_screen.dart' show openSessionIn;
import '../prompt/conversation_manager.dart';
import '../review/review_service.dart' show selectedReviewProvider;
import '../sessions/session_manager.dart';
import 'home_inbox.dart';

/// The radar on the tray icon (SPEC-041): what the workspaces are doing and
/// what waits for the user, while the window is hidden. It only informs and
/// leads to the right place; nothing here acts on an item (R7).

/// Longest menu label; longer ones end in "…" (R5).
const radarLabelLimit = 48;

/// Items of "Precisa de você" and of "Rodando" before the "Mais N" line.
const radarInboxLimit = 6;
const radarRunningLimit = 3;

/// A session in the middle of a turn.
@immutable
class RadarSession {
  const RadarSession({
    required this.id,
    required this.ref,
    required this.title,
    required this.startedAt,
  });

  final String id;

  /// `SPEC-012 · R3`; empty for a session without a spec.
  final String ref;
  final String title;
  final DateTime startedAt;
}

/// What one workspace feeds the radar.
@immutable
class RadarWorkspace {
  const RadarWorkspace({
    required this.id,
    required this.name,
    this.inbox = const [],
    this.running = const [],
  });

  final int id;
  final String name;
  final List<InboxGroup> inbox;
  final List<RadarSession> running;
}

/// Where a menu item leads (R6).
@immutable
class RadarTarget {
  const RadarTarget({
    required this.workspaceId,
    required this.section,
    this.sessionId,
    this.conversationId,
  });

  final int workspaceId;
  final AppSection section;
  final String? sessionId;
  final int? conversationId;

  @override
  bool operator ==(Object other) =>
      other is RadarTarget &&
      other.workspaceId == workspaceId &&
      other.section == section &&
      other.sessionId == sessionId &&
      other.conversationId == conversationId;

  @override
  int get hashCode =>
      Object.hash(workspaceId, section, sessionId, conversationId);
}

/// The tray's status and the destination of each of its items.
@immutable
class TrayRadar {
  const TrayRadar({this.status = const TrayStatus(), this.targets = const {}});

  final TrayStatus status;
  final Map<String, RadarTarget> targets;
}

/// `2 rodando · 3 precisam de você`; empty with nothing to count (R4).
String radarSummary({required int running, required int waiting}) => [
  if (running > 0) '$running rodando',
  if (waiting == 1) '1 precisa de você',
  if (waiting > 1) '$waiting precisam de você',
].join(' · ');

/// `ref · title`, without repeating a ref equal to the title, with the
/// workspace in front when [workspace] is given, cut at [radarLabelLimit].
String radarLabel(String ref, String title, {String? workspace}) {
  final label = [
    ?workspace,
    if (ref.isNotEmpty && ref != title) ref,
    title,
  ].join(' · ');
  final runes = label.runes.toList();
  if (runes.length <= radarLabelLimit) return label;
  return '${String.fromCharCodes(runes.take(radarLabelLimit - 1))}…';
}

RadarTarget _targetOf(int workspaceId, InboxItem item) => switch (item.kind) {
  InboxKind.approval when item.conversationId != null => RadarTarget(
    workspaceId: workspaceId,
    section: AppSection.prompt,
    conversationId: item.conversationId,
  ),
  // Decidir needs a BuildContext: it is on Início, one click away.
  InboxKind.needsAnswer => RadarTarget(
    workspaceId: workspaceId,
    section: AppSection.home,
  ),
  InboxKind.review || InboxKind.prProblem => RadarTarget(
    workspaceId: workspaceId,
    section: AppSection.review,
    sessionId: item.sessionId,
  ),
  InboxKind.approval || InboxKind.interrupted => RadarTarget(
    workspaceId: workspaceId,
    section: AppSection.sessions,
    sessionId: item.sessionId,
  ),
};

String _itemId(InboxItem item) =>
    '${item.kind.name}:${item.sessionId ?? item.conversationId ?? item.ref}'
    ':${item.approval?.requestId ?? item.step?.id ?? ''}';

/// The radar of [workspaces] (R1, R3, R4, R5). Pure: the provider below feeds
/// it and the tests call it directly.
TrayRadar buildTrayRadar(List<RadarWorkspace> workspaces) {
  final seen = <String>{};
  final inbox = <({RadarWorkspace ws, String id, InboxItem item})>[];
  for (final ws in workspaces) {
    for (final group in ws.inbox) {
      for (final item in group.items) {
        final id = _itemId(item);
        if (seen.add(id)) inbox.add((ws: ws, id: id, item: item));
      }
    }
  }
  // The order of buildInbox: by kind, then the newest first.
  inbox.sort((a, b) {
    final kind = a.item.kind.index.compareTo(b.item.kind.index);
    return kind != 0 ? kind : b.item.at.compareTo(a.item.at);
  });
  final running = [
    for (final ws in workspaces)
      for (final session in ws.running) (ws: ws, session: session),
  ]..sort((a, b) => b.session.startedAt.compareTo(a.session.startedAt));

  final kinds = {for (final e in inbox) e.item.kind};
  final state =
      kinds.contains(InboxKind.approval) ||
          kinds.contains(InboxKind.needsAnswer)
      ? TrayState.attention
      : kinds.contains(InboxKind.prProblem)
      ? TrayState.problem
      : running.isNotEmpty
      ? TrayState.working
      : TrayState.idle;

  final summary = radarSummary(running: running.length, waiting: inbox.length);
  final tooltip = summary.isEmpty
      ? TrayService.tooltip
      : '${TrayService.tooltip} · $summary';

  final shown = inbox.take(radarInboxLimit).toList();
  final shownRunning = running.take(radarRunningLimit).toList();
  final workspaceIds = {
    for (final e in shown) e.ws.id,
    for (final e in shownRunning) e.ws.id,
  };
  String? prefix(RadarWorkspace ws) => workspaceIds.length > 1 ? ws.name : null;

  final targets = <String, RadarTarget>{};
  final rows = <TrayRow>[];
  if (summary.isNotEmpty) {
    rows.add(TrayRow(summary));
  }
  if (inbox.isNotEmpty) {
    rows
      ..add(const TrayRow.separator())
      ..add(const TrayRow('Precisa de você'));
    for (final e in shown) {
      targets[e.id] = _targetOf(e.ws.id, e.item);
      rows.add(
        TrayRow(
          radarLabel(e.item.ref, e.item.title, workspace: prefix(e.ws)),
          id: e.id,
        ),
      );
    }
    if (inbox.length > shown.length) {
      const id = 'more:inbox';
      targets[id] = RadarTarget(
        workspaceId: inbox[shown.length].ws.id,
        section: AppSection.home,
      );
      rows.add(
        TrayRow('Mais ${inbox.length - shown.length} em Início', id: id),
      );
    }
  }
  if (running.isNotEmpty) {
    rows
      ..add(const TrayRow.separator())
      ..add(const TrayRow('Rodando'));
    for (final e in shownRunning) {
      final id = 'running:${e.session.id}';
      targets[id] = RadarTarget(
        workspaceId: e.ws.id,
        section: AppSection.sessions,
        sessionId: e.session.id,
      );
      rows.add(
        TrayRow(
          radarLabel(e.session.ref, e.session.title, workspace: prefix(e.ws)),
          id: id,
        ),
      );
    }
    if (running.length > shownRunning.length) {
      const id = 'more:running';
      targets[id] = RadarTarget(
        workspaceId: running[shownRunning.length].ws.id,
        section: AppSection.sessions,
      );
      rows.add(
        TrayRow(
          'Mais ${running.length - shownRunning.length} em Sessões',
          id: id,
        ),
      );
    }
  }
  return TrayRadar(
    status: TrayStatus(state: state, tooltip: tooltip, rows: rows),
    targets: targets,
  );
}

/// [groups] of a workspace with its own PRs only: the watched PRs are global,
/// and each one counts in the workspace of its session (R3).
List<InboxGroup> radarInbox(List<InboxGroup> groups, Set<String> ownSessions) =>
    [
      for (final group in groups)
        if (group.kind == InboxKind.prProblem)
          InboxGroup(group.kind, [
            for (final item in group.items)
              if (ownSessions.contains(item.sessionId)) item,
          ])
        else
          group,
    ];

/// In the middle of a turn. A session waiting for an approval is busy too,
/// but it is already in "Precisa de você"; an idle one only keeps its process.
bool isRadarRunning(LiveSession? session) =>
    session != null && session.busy && session.approvals.isEmpty;

/// The radar of every workspace (R3).
final trayRadarProvider = Provider.autoDispose<TrayRadar>((ref) {
  final manager = ref.watch(sessionManagerProvider);
  final workspaces = ref.watch(workspacesProvider).value ?? const [];
  return buildTrayRadar([
    for (final ws in workspaces)
      () {
        final sessions = ref.watch(sessionsProvider(ws.id)).value ?? const [];
        final specs = {
          for (final s in ref.watch(specsProvider(ws.id)).value ?? const [])
            s.id: s,
        };
        final own = {for (final s in sessions) s.id};
        return RadarWorkspace(
          id: ws.id,
          name: ws.name,
          inbox: radarInbox(ref.watch(workspaceInboxProvider(ws.id)), own),
          running: [
            for (final s in sessions)
              if (isRadarRunning(manager.live[s.id]))
                RadarSession(
                  id: s.id,
                  ref: stepRef(specs[s.specId], s.steps),
                  title: sessionTitle(s),
                  startedAt: s.startedAt,
                ),
          ],
        );
      }(),
  ]);
});

/// Opens the radar item [id]: its workspace, then its destination (R6). What
/// has left the radar since the menu was built opens Início. Only navigates.
Future<void> openRadarItem(ProviderContainer container, String id) async {
  final target = container.read(trayRadarProvider).targets[id];
  final navigation = container.read(navigationProvider.notifier);
  if (target == null) {
    navigation.go(AppSection.home);
    return;
  }
  await container.read(workspaceActionsProvider).select(target.workspaceId);
  final session = target.sessionId;
  final conversation = target.conversationId;
  if (conversation != null) {
    container.read(selectedConversationProvider.notifier).select(conversation);
  }
  if (target.section == AppSection.review) {
    container.read(selectedReviewProvider.notifier).select(session);
  } else if (target.section == AppSection.sessions && session != null) {
    openSessionIn(container, session);
    return;
  }
  navigation.go(target.section);
}
