import '../secrets/secret_blocks.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/usage_tracker.dart';
import '../../core/dev/dev_server.dart';
import '../../data/providers.dart';
import '../board/autopilot.dart';
import '../board/board_rules.dart' show isOnBoard;
import '../board/board_screen.dart' show specStepsProvider;
import '../board/spec_runner.dart';
import '../project/project_config.dart';
import '../project/project_planner.dart';
import '../project/spec_auto_planner.dart';
import '../prompt/conversation_manager.dart';
import '../repository/releases/release_dispatcher.dart';
import '../review/ci_fixer.dart';
import '../review/pr_babysitter.dart';
import '../sessions/session_manager.dart';
import '../specs/spec_planner.dart';
import 'activity.dart';
import 'quota_forecast.dart';

/// The registry of the Atividades (SPEC-076 R1): every workspace, live.

/// The queue of the Autopilot of a workspace (R1): what "Executar tudo"
/// starts and what waits, when it is on; the same with a schedule.
List<QueuedSpec> autopilotQueue(
  List<Spec> specs, {
  required bool on,
  required AutopilotSchedule? schedule,
  Sprint? active,
  int? parallel,
  UnblockAt unblockAt = UnblockAt.review,
  bool Function(Spec)? locked,
  Set<int> starting = const {},
}) {
  if (!on && schedule == null) return const [];
  final plan = autopilotPlan(
    [
      for (final s in specs)
        if (isOnBoard(s)) s,
    ],
    active,
    parallel: parallel,
    unblockAt: unblockAt,
    locked: locked,
    starting: starting,
  );
  final when = on ? null : 'agendada · ${schedule!.label.split(' ').first}';
  return [
    for (final s in plan.start)
      (spec: s, label: when ?? 'próxima do Autopilot'),
    for (final w in plan.wait)
      (
        spec: w.spec,
        label:
            when ??
            (w.waitingFor.isEmpty
                ? (w.reason ?? 'espera uma vaga')
                : 'espera ${w.waitingFor.join(', ')}'),
      ),
  ];
}

/// `Autopilot 2/3`, `Autopilot · próxima SPEC-009`, `agendado 09:00`,
/// `Corrigir CI automático` (the group header, R18).
String? autopilotGroupLabel({
  required bool on,
  required AutopilotSchedule? schedule,
  required int running,
  int? parallel,
  List<QueuedSpec> queue = const [],
  bool autoFixCi = false,
}) {
  final parts = <String>[
    if (on)
      [
        parallel == null ? 'Autopilot' : 'Autopilot $running/$parallel',
        if (queue.isNotEmpty) 'próxima ${queue.first.spec.code}',
      ].join(' · ')
    else if (schedule != null)
      'agendado ${schedule.label.split(' ').first}',
    if (autoFixCi) 'Corrigir CI automático',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Dev servers whose worktree is the workspace's root or one of its
/// sessions' / specs' worktrees.
List<DevSnapshot> devServersOf(
  Iterable<DevServer> servers,
  Workspace ws,
  List<Session> sessions,
  List<Spec> specs,
) {
  final paths = {
    ws.path,
    for (final s in sessions) s.worktreePath,
    for (final s in specs) ?s.worktreePath,
  };
  return [
    for (final d in servers)
      if (paths.contains(d.worktree))
        (
          worktree: d.worktree,
          status: d.status,
          port: d.port,
          command: d.command,
          startedAt: d.startedAt,
          lastLog: d.logs.lines.lastOrNull?.text,
        ),
  ];
}

/// The list and what its group headers say.
typedef ActivitiesSnapshot = ({
  List<Activity> items,

  /// `Autopilot 2/3`… by workspace.
  Map<int, String> labels,

  /// The workspaces' order.
  List<int> order,
});

/// Everything the Atividades lists, of every workspace (R1). It follows
/// the providers it reads; the dev servers have no app-wide change stream,
/// so the Atividades screen refreshes it every few seconds while open
/// ([refreshActivities]).
final activitiesProvider = Provider.autoDispose<List<Activity>>(
  (ref) => ref.watch(activitiesSnapshotProvider).items,
);

final activitiesSnapshotProvider = Provider.autoDispose<ActivitiesSnapshot>((
  ref,
) {
  final now = DateTime.now();
  final workspaces = ref.watch(workspacesProvider).value ?? const [];
  final manager = ref.watch(sessionManagerProvider);
  final conversations = ref.watch(conversationManagerProvider);
  final settings = ref.watch(appSettingsProvider);
  final watched = {
    for (final s in (settings[PrBabysitter.settingKey] ?? '').split(','))
      if (s.isNotEmpty) s,
  };
  final pilots = ref.watch(autopilotProvider);
  final pilot = ref.read(autopilotProvider.notifier);
  final releases = ref.watch(releaseDispatcherProvider);
  final planners = ref.watch(projectPlannerProvider);
  final specPlanners = ref.watch(specPlannerProvider);
  final servers = ref.watch(devServerRegistryProvider).servers;
  final autoPlanner = ref.watch(specAutoPlannerProvider);
  final starting = ref.read(specRunnerProvider).starting;

  final rate = ref.watch(rateLimitProvider);
  final windowStart = rate?.fiveHourResetsAt?.subtract(
    const Duration(hours: 5),
  );
  final costs = <String, double>{};

  final list = <ActivityWorkspace>[];
  for (final ws in workspaces) {
    final sessions = ref.watch(sessionsProvider(ws.id)).value ?? const [];
    final specs = ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    final config = ref.watch(projectConfigProvider(ws.path)).value;
    final sprints = ref.watch(sprintsProvider(ws.id)).value ?? const [];
    final active = sprints
        .where((s) => s.state == SprintState.active)
        .firstOrNull;
    final on = pilots.contains(ws.id);
    final schedule = AutopilotSchedule.decode(
      settings[AutopilotSchedule.key(ws.id)],
    );
    final queue = autopilotQueue(
      specs,
      on: on,
      schedule: schedule,
      active: active,
      parallel: config?.autopilot.parallel,
      unblockAt: pilot.unblockAtOf(ws.id),
      locked: (s) => autoPlanner.lockOf(s.id) != null,
      starting: starting,
    );
    for (final s in sessions) {
      if (s.costUsd <= 0) continue;
      final inWindow =
          windowStart == null ||
          s.endedAt == null ||
          s.endedAt!.isAfter(windowStart);
      if (inWindow && (s.endedAt == null || manager.isAlive(s.id))) {
        costs[s.id] = s.costUsd;
      }
    }
    list.add(
      ActivityWorkspace(
        id: ws.id,
        name: ws.name,
        path: ws.path,
        sessions: sessions,
        specs: specs,
        stepRows: ref.watch(specStepsProvider(ws.id)).value ?? const [],
        conversations:
            ref.watch(conversationsProvider(ws.id)).value ?? const [],
        devServers: devServersOf(servers, ws, sessions, specs),
        release: releases[ws.id],
        planner: planners[ws.id],
        specPlanner: specPlanners.contains(ws.id),
        queue: queue,
        autopilotLabel: autopilotGroupLabel(
          on: on,
          schedule: schedule,
          running: specs.where((s) => s.stage == SpecStage.running).length,
          parallel: config?.autopilot.parallel,
          queue: queue,
          autoFixCi: config?.autoFixCi ?? false,
        ),
        autoFixCi: config?.autoFixCi ?? false,
      ),
    );
  }
  final items = buildActivities(
    list,
    ActivityLive(
      sessions: manager,
      conversations: conversations,
      gates: ref.watch(gateRunningProvider),
      watchedPrs: watched,
      prs: ref.watch(prBabysitterProvider),
      ci: ref.watch(ciFixerProvider),
      weights: sessionQuotaWeights(costs, rate?.fiveHourUtilization),
      secrets: ref.watch(secretBlocksProvider),
    ),
    now: now,
  );
  return (
    items: items,
    labels: {for (final w in list) w.id: ?w.autopilotLabel},
    order: [for (final w in list) w.id],
  );
});

/// What needs you, in every workspace: the badge of the sidebar (R15).
final activitiesNeedingYouProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(activitiesProvider).where((a) => a.needsYou).length,
);

/// Reads the list again (the dev servers and the times).
void refreshActivities(WidgetRef ref) =>
    ref.invalidate(activitiesSnapshotProvider);
