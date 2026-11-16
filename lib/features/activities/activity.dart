import 'package:flutter/foundation.dart';

import '../../core/dev/dev_server.dart' show DevServerStatus;
import '../../data/providers.dart';
import '../board/board_rules.dart';
import '../home/home_inbox.dart' show approvalVerb, stepRef;
import '../project/project_planner.dart' show PlannerActivity;
import '../prompt/conversation_manager.dart';
import '../repository/releases/release_dispatcher.dart';
import '../review/ci_fixer.dart';
import '../review/pr_babysitter.dart';
import '../sessions/session_manager.dart';
import '../sessions/timeline.dart' show toolTarget;

/// The Atividades (SPEC-076): the live processes of every workspace — not
/// the work, which is the Quadro's. Pure data; [buildActivities] turns what
/// the app already knows into rows.

/// What runs.
enum ActivityKind {
  spec('SPEC'),
  vibe('VIBE'),
  prompt('PROMPT'),
  gate('GATE'),
  pr('PR'),
  ciFix('CI'),
  release('RELEASE'),
  planner('PLANNER'),
  dev('DEV'),
  queued('SPEC');

  const ActivityKind(this.tag);

  /// The badge of the row.
  final String tag;

  /// Release and dev server are not agents: an icon, not a robot (R12).
  bool get isAgent => this != release && this != dev;
}

/// The column of the Quadro the activity belongs to (R2). There is no
/// "Feito": what finished well leaves the list.
enum ActivityColumn { backlog, running, review }

/// What the robot does (R10).
enum ActivityPose {
  /// Backlog: the queue of the Autopilot or a scheduled start.
  sleep,

  /// Read, Grep, Glob…
  read,

  /// Edit, Write…
  edit,

  /// Bash, tests.
  run,

  /// Between tools.
  think,

  /// Waiting for the review.
  wait,

  /// Needs you.
  wave,

  /// The gate.
  gate,

  /// Corrigir CI.
  fix,

  /// Following the PR.
  watch,

  /// Stopped with an error.
  error,
}

/// The action of the row (R19).
enum ActivityAction {
  respond('Responder'),
  viewPlan('Ver plano'),
  resume('Retomar'),
  stop('Parar'),
  now('Agora'),
  none('');

  const ActivityAction(this.label);

  final String label;
}

/// How the state label reads.
enum ActivityTone { normal, attention, error }

/// One action of the agent ("14:32 Edit review_screen.dart").
typedef ActivityStep = ({DateTime at, String label});

/// A step of the spec in the panel (`t1 ✓ · t2 · t3`).
typedef ActivityTask = ({String id, bool done, bool current});

@immutable
class Activity {
  const Activity({
    required this.id,
    required this.workspaceId,
    required this.workspaceName,
    required this.kind,
    required this.column,
    required this.pose,
    required this.title,
    required this.subtitle,
    required this.status,
    this.tone = ActivityTone.normal,
    this.needsYou = false,
    this.error = false,
    this.progress,
    this.startedAt,
    this.lastAction,
    this.lastActionAt,
    this.calls,
    this.files,
    this.action = ActivityAction.none,
    this.sessionId,
    this.conversationId,
    this.specId,
    this.specCode,
    this.seed,
    this.model,
    this.mode,
    this.branch,
    this.agentName,
    this.tasks = const [],
    this.recent = const [],
    this.lastText,
    this.weight,
    this.devWorktree,
    this.robotLabel,
  });

  /// Unique in the list: `session:<id>`, `conv:<id>`, `gate:<spec>`…
  final String id;
  final int workspaceId;
  final String workspaceName;
  final ActivityKind kind;
  final ActivityColumn column;
  final ActivityPose pose;

  /// `SPEC-075 · Botões na largura`.
  final String title;

  /// `Em execução · etapa 2 de 3` (the robot's name goes in front).
  final String subtitle;

  /// `Editando · R3`, `quer executar`, `plano pronto`.
  final String status;
  final ActivityTone tone;

  /// Waits for an approval, has a plan ready, stopped with an error or at a
  /// step (R2).
  final bool needsYou;
  final bool error;

  /// 0–1 when it can be measured (R4), with [progressLabel].
  final ({double value, String label})? progress;
  final DateTime? startedAt;

  /// `Edit review_screen.dart +12 −4` (mono).
  final String? lastAction;
  final DateTime? lastActionAt;

  /// Tool calls / files of the turn ("uso").
  final int? calls;
  final int? files;
  final ActivityAction action;
  final String? sessionId;
  final int? conversationId;
  final int? specId;
  final String? specCode;

  /// The robot's identity (R5); null = an icon (release, dev server).
  final String? seed;
  final String? model;
  final String? mode;
  final String? branch;

  /// The subagent (`agentName`) of the session, when there is one.
  final String? agentName;
  final List<ActivityTask> tasks;
  final List<ActivityStep> recent;
  final String? lastText;

  /// Part of the 5-hour window (0–1, R7).
  final double? weight;

  /// The worktree of a dev server (Parar).
  final String? devWorktree;

  /// What goes under the robot instead of its name ("na fila", "gate").
  final String? robotLabel;

  bool get hasRobot => seed != null;
}

/// A dev server of a workspace, as the list needs it.
typedef DevSnapshot = ({
  String worktree,
  DevServerStatus status,
  int? port,
  String? command,
  DateTime? startedAt,
  String? lastLog,
});

/// A spec in the queue of the Autopilot or of a scheduled start.
typedef QueuedSpec = ({Spec spec, String label});

/// What one workspace gives the list.
@immutable
class ActivityWorkspace {
  const ActivityWorkspace({
    required this.id,
    required this.name,
    this.path = '',
    this.sessions = const [],
    this.specs = const [],
    this.stepRows = const [],
    this.conversations = const [],
    this.devServers = const [],
    this.release,
    this.planner,
    this.specPlanner = false,
    this.queue = const [],
    this.autopilotLabel,
    this.autoFixCi = false,
  });

  final int id;
  final String name;
  final String path;
  final List<Session> sessions;
  final List<Spec> specs;
  final List<SpecStep> stepRows;
  final List<Conversation> conversations;
  final List<DevSnapshot> devServers;
  final ReleaseRun? release;
  final PlannerActivity? planner;

  /// A turn of the "Nova spec" conversation on its way.
  final bool specPlanner;
  final List<QueuedSpec> queue;

  /// `Autopilot 2/3`, `agendado 09:00` (the group header, R18).
  final String? autopilotLabel;

  /// `review: corrigir-ci: automatico`.
  final bool autoFixCi;
}

/// What is live in the whole app (not per workspace).
@immutable
class ActivityLive {
  const ActivityLive({
    this.sessions = const SessionManagerState(),
    this.conversations = const ConversationManagerState(),
    this.gates = const {},
    this.watchedPrs = const {},
    this.prs = const {},
    this.ci = const {},
    this.weights = const {},
  });

  final SessionManagerState sessions;
  final ConversationManagerState conversations;

  /// Specs whose gate runs.
  final Set<int> gates;

  /// Sessions in "Acompanhar PR".
  final Set<String> watchedPrs;
  final Map<String, PrWatch> prs;
  final Map<String, CiFixState> ci;

  /// Weight of each session in the 5-hour window.
  final Map<String, double> weights;
}

/// The robot's seed of what works on [spec] (R5, P7): the spec, not the
/// session, so the card keeps its robot from step to step.
String specSeed(int workspaceId, String code) => 'spec:$workspaceId:$code';

/// The pose of a running agent from its newest tool (R10): no tool, or one
/// already answered, is thinking.
ActivityPose poseOfTool(LiveTool? tool) {
  if (tool == null || tool.done) return ActivityPose.think;
  return switch (tool.name) {
    'Read' ||
    'Grep' ||
    'Glob' ||
    'LS' ||
    'NotebookRead' ||
    'WebFetch' ||
    'WebSearch' => ActivityPose.read,
    'Edit' || 'Write' || 'MultiEdit' || 'NotebookEdit' => ActivityPose.edit,
    'Bash' || 'BashOutput' || 'KillShell' || 'KillBash' => ActivityPose.run,
    _ => ActivityPose.think,
  };
}

/// "Lendo código", "Editando", "Rodando testes", "Pensando".
String poseLabel(ActivityPose pose, {LiveTool? tool}) => switch (pose) {
  ActivityPose.read => 'Lendo código',
  ActivityPose.edit => 'Editando',
  ActivityPose.run =>
    '${tool?.input['command']}'.contains('test')
        ? 'Rodando testes'
        : 'Rodando comando',
  ActivityPose.think => 'Pensando',
  ActivityPose.sleep => 'Na fila',
  ActivityPose.wait => 'Esperando revisão',
  ActivityPose.wave => 'Precisa de você',
  ActivityPose.gate => 'Gate rodando',
  ActivityPose.fix => 'Corrigindo CI',
  ActivityPose.watch => 'Acompanhando',
  ActivityPose.error => 'Parou com erro',
};

/// `Edit lib/x.dart`, `Bash flutter test` (the target relative to [root]).
String toolLine(LiveTool t, {String? root}) {
  final target = toolTarget(t.name, t.input, root: root);
  return target.isEmpty ? t.name : '${t.name} $target';
}

List<ActivityStep> _recent(List<LiveTool> tools, String? root) => [
  for (final t in tools) (at: t.at, label: toolLine(t, root: root)),
];

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// The activities of [workspaces] (R1–R5). Pure.
List<Activity> buildActivities(
  List<ActivityWorkspace> workspaces,
  ActivityLive live, {
  required DateTime now,
}) => [for (final ws in workspaces) ..._ofWorkspace(ws, live, now)];

List<Activity> _ofWorkspace(
  ActivityWorkspace ws,
  ActivityLive live,
  DateTime now,
) {
  final out = <Activity>[];
  final specById = {for (final s in ws.specs) s.id: s};
  final stepsBySpec = <int, List<StepView>>{};
  List<StepView> steps(Spec s) => stepsBySpec[s.id] ??= stepsOf(s, ws.stepRows);

  List<ActivityTask> tasks(Spec? s) {
    if (s == null) return const [];
    final all = steps(s);
    final current = all
        .where(
          (x) =>
              x.status == StepStatus.running ||
              x.status == StepStatus.verifying ||
              x.status == StepStatus.needsInput,
        )
        .map((x) => x.id)
        .toSet();
    return [
      for (final x in all)
        (id: x.id, done: x.isDone, current: current.contains(x.id)),
    ];
  }

  ({double value, String label})? stepProgress(Spec? s, String? stepIds) {
    if (s == null) return null;
    final all = steps(s);
    if (all.isEmpty) return null;
    final mine = (stepIds ?? '').split(',').map((e) => e.trim()).toSet();
    final i = all.indexWhere((x) => mine.contains(x.id));
    final done = all.where((x) => x.isDone).length;
    final at = i < 0 ? done + 1 : i + 1;
    return (
      value: (done / all.length).clamp(0, 1).toDouble(),
      label: 'etapa ${at.clamp(1, all.length)} de ${all.length}',
    );
  }

  ActivityColumn columnOf(Spec? s) => s?.stage == SpecStage.review
      ? ActivityColumn.review
      : ActivityColumn.running;

  final used = <String>{};

  // --- sessions (spec agents, CI fixes, free sessions) -----------------
  for (final s in ws.sessions) {
    final l = live.sessions.live[s.id];
    final spec = specById[s.specId];
    final ci = live.ci[s.id];
    final fixing = ci != null && ci.inFlight;
    final approvals = l?.approvals ?? const <PendingApproval>[];
    final busy = l != null && l.alive && l.busy;
    if (l == null || !l.alive || (!busy && approvals.isEmpty)) continue;
    used.add(s.id);
    final seed = spec == null ? 'session:${s.id}' : specSeed(ws.id, spec.code);
    final root = s.worktreePath;
    final ref = stepRef(spec, s.steps);
    final title = spec == null
        ? sessionTitle(s)
        : '${spec.code} · ${spec.title}';
    final kind = fixing ? ActivityKind.ciFix : ActivityKind.spec;
    final progress = fixing
        ? (value: 0.5, label: 'rodada ${ci.round}')
        : stepProgress(spec, s.steps);
    if (approvals.isNotEmpty) {
      final a = approvals.first;
      final target = toolTarget(
        a.request.toolName,
        a.request.input,
        root: root,
      );
      out.add(
        Activity(
          id: 'session:${s.id}',
          workspaceId: ws.id,
          workspaceName: ws.name,
          kind: kind,
          column: columnOf(spec),
          pose: ActivityPose.wave,
          title: title,
          subtitle: [
            if (fixing) 'Corrigir CI, rodada ${ci.round}' else 'Em execução',
            ?progress?.label,
          ].join(' · '),
          status: 'quer ${approvalVerb(a.request.toolName)}',
          tone: ActivityTone.attention,
          needsYou: true,
          startedAt: s.startedAt,
          lastAction: target.isEmpty
              ? a.request.toolName
              : '${a.request.toolName} $target',
          lastActionAt: a.receivedAt,
          calls: l.calls,
          files: l.files,
          action: ActivityAction.respond,
          sessionId: s.id,
          specId: spec?.id,
          specCode: spec?.code,
          seed: seed,
          model: s.model,
          mode: s.permissionMode,
          branch: s.branch,
          agentName: s.agentName,
          tasks: tasks(spec),
          recent: _recent(l.recent, root),
          lastText: l.lastText,
          weight: live.weights[s.id],
        ),
      );
      continue;
    }
    final pose = fixing ? ActivityPose.fix : poseOfTool(l.tool);
    out.add(
      Activity(
        id: 'session:${s.id}',
        workspaceId: ws.id,
        workspaceName: ws.name,
        kind: kind,
        column: columnOf(spec),
        pose: pose,
        title: title,
        subtitle: fixing
            ? 'Corrigir CI, rodada ${ci.round}${ci.auto ? ' · automático' : ''}'
            : ['Em execução', ?progress?.label].join(' · '),
        status: fixing
            ? 'Corrigindo CI'
            : [
                poseLabel(pose, tool: l.tool),
                if (ref.contains(' · ')) ref.split(' · ').last,
              ].join(' · '),
        progress: progress,
        startedAt: s.startedAt,
        lastAction: l.tool == null ? null : toolLine(l.tool!, root: root),
        lastActionAt: l.tool?.at,
        calls: l.calls,
        files: l.files,
        action: ActivityAction.stop,
        sessionId: s.id,
        specId: spec?.id,
        specCode: spec?.code,
        seed: seed,
        model: s.model,
        mode: s.permissionMode,
        branch: s.branch,
        agentName: s.agentName,
        tasks: tasks(spec),
        recent: _recent(l.recent, root),
        lastText: l.lastText,
        weight: live.weights[s.id],
      ),
    );
  }

  // --- CI fixes not running a turn (queued, CI running, stopped) --------
  final sessionById = {for (final s in ws.sessions) s.id: s};
  for (final e in live.ci.entries) {
    final s = sessionById[e.key];
    if (s == null || used.contains(s.id)) continue;
    final ci = e.value;
    final spec = specById[s.specId];
    final stuck = switch (ci.phase) {
      CiFixPhase.stopped ||
      CiFixPhase.noCommit ||
      CiFixPhase.external ||
      CiFixPhase.pushRefused => true,
      _ => false,
    };
    final status = switch (ci.phase) {
      CiFixPhase.queued => 'na fila: espera o turno',
      CiFixPhase.fixing => 'Corrigindo CI',
      CiFixPhase.running => 'CI rodando no commit da correção',
      CiFixPhase.rerunning => 'rodando de novo os jobs',
      CiFixPhase.stopped => 'CI ainda vermelho',
      CiFixPhase.noCommit => 'terminou sem commit',
      CiFixPhase.external => 'falha não é do código',
      CiFixPhase.pushRefused => 'push recusado',
      CiFixPhase.fixed || CiFixPhase.local => null,
    };
    if (status == null) continue;
    used.add('ci:${s.id}');
    out.add(
      Activity(
        id: 'ci:${s.id}',
        workspaceId: ws.id,
        workspaceName: ws.name,
        kind: ActivityKind.ciFix,
        column: ActivityColumn.review,
        pose: stuck
            ? ActivityPose.wave
            : ci.phase == CiFixPhase.queued || ci.phase == CiFixPhase.fixing
            ? ActivityPose.fix
            : ActivityPose.watch,
        title: spec == null ? sessionTitle(s) : '${spec.code} · Corrigir CI',
        subtitle:
            'Corrigir CI, rodada ${ci.round}${ci.auto ? ' · automático' : ''}',
        status: status,
        tone: stuck ? ActivityTone.attention : ActivityTone.normal,
        needsYou: stuck,
        startedAt: ci.since,
        lastAction: ci.detail,
        action: stuck ? ActivityAction.none : ActivityAction.stop,
        sessionId: s.id,
        specId: spec?.id,
        specCode: spec?.code,
        seed: spec == null ? 'session:${s.id}' : specSeed(ws.id, spec.code),
        model: s.model,
        mode: s.permissionMode,
        branch: s.branch,
        tasks: tasks(spec),
        weight: live.weights[s.id],
      ),
    );
  }

  // --- stopped agents: failed / interrupted sessions, steps waiting -----
  final stoppedSessions = <String>{};
  for (final spec in ws.specs) {
    if (!isOnBoard(spec) || spec.stage == SpecStage.done) continue;
    for (final st in steps(spec)) {
      if (st.status != StepStatus.needsInput) continue;
      final s = st.sessionId == null ? null : sessionById[st.sessionId];
      if (s != null && used.contains(s.id)) continue;
      if (s != null && !stoppedSessions.add(s.id)) continue;
      final failed =
          s != null &&
          (s.status == SessionStatus.failed ||
              s.status == SessionStatus.interrupted);
      final gate = st.gate;
      out.add(
        Activity(
          id: 'step:${spec.id}:${st.id}',
          workspaceId: ws.id,
          workspaceName: ws.name,
          kind: ActivityKind.spec,
          column: columnOf(spec),
          pose: failed ? ActivityPose.error : ActivityPose.wave,
          title: '${spec.code} · ${spec.title}',
          subtitle: 'parou em ${st.id}',
          status: failed
              ? (s.status == SessionStatus.interrupted
                    ? 'interrompida ao fechar o app'
                    : 'sessão falhou')
              : st.gateFailed
              ? 'gate recusou ${st.id}'
              : 'parou sem concluir ${st.id}',
          tone: failed ? ActivityTone.error : ActivityTone.attention,
          needsYou: true,
          error: failed,
          startedAt: s?.endedAt ?? s?.startedAt,
          lastAction: gate != null && !gate.ok ? gate.summary : st.text,
          action: s == null ? ActivityAction.none : ActivityAction.resume,
          sessionId: s?.id,
          specId: spec.id,
          specCode: spec.code,
          seed: specSeed(ws.id, spec.code),
          model: s?.model,
          mode: s?.permissionMode,
          branch: s?.branch,
          tasks: tasks(spec),
          weight: s == null ? null : live.weights[s.id],
        ),
      );
    }
  }
  for (final s in ws.sessions) {
    if (used.contains(s.id) || stoppedSessions.contains(s.id)) continue;
    if (s.status != SessionStatus.failed &&
        s.status != SessionStatus.interrupted) {
      continue;
    }
    if (live.sessions.isAlive(s.id)) continue;
    final spec = specById[s.specId];
    // Only the newest session of a spec not done, or a free session that
    // ended in the last day: an old failure is history, not a process.
    if (spec != null) {
      if (spec.stage == SpecStage.done || !isOnBoard(spec)) continue;
      final newest = ws.sessions
          .where((x) => x.specId == spec.id)
          .fold<Session?>(
            null,
            (a, x) => a == null || x.startedAt.isAfter(a.startedAt) ? x : a,
          );
      if (newest?.id != s.id) continue;
    } else if (now.difference(s.endedAt ?? s.startedAt) >
        const Duration(days: 1)) {
      continue;
    }
    out.add(
      Activity(
        id: 'session:${s.id}',
        workspaceId: ws.id,
        workspaceName: ws.name,
        kind: ActivityKind.spec,
        column: columnOf(spec),
        pose: ActivityPose.error,
        title: spec == null ? sessionTitle(s) : '${spec.code} · ${spec.title}',
        subtitle: 'parou com erro',
        status: s.status == SessionStatus.interrupted
            ? 'interrompida ao fechar o app'
            : 'sessão falhou',
        tone: ActivityTone.error,
        needsYou: true,
        error: true,
        startedAt: s.endedAt ?? s.startedAt,
        action: ActivityAction.resume,
        sessionId: s.id,
        specId: spec?.id,
        specCode: spec?.code,
        seed: spec == null ? 'session:${s.id}' : specSeed(ws.id, spec.code),
        model: s.model,
        mode: s.permissionMode,
        branch: s.branch,
        agentName: s.agentName,
        tasks: tasks(spec),
        weight: live.weights[s.id],
      ),
    );
  }

  // --- gates -------------------------------------------------------------
  for (final id in live.gates) {
    final spec = specById[id];
    if (spec == null) continue;
    final verifying = steps(spec)
        .where((x) => x.status == StepStatus.verifying)
        .map((x) => x.id)
        .toList();
    out.add(
      Activity(
        id: 'gate:${spec.id}',
        workspaceId: ws.id,
        workspaceName: ws.name,
        kind: ActivityKind.gate,
        column: columnOf(spec),
        pose: ActivityPose.gate,
        title: '${spec.code} · ${spec.title}',
        subtitle: verifying.isEmpty ? 'Gate' : 'Gate · ${verifying.join(', ')}',
        status: 'verificando',
        specId: spec.id,
        specCode: spec.code,
        seed: specSeed(ws.id, spec.code),
        tasks: tasks(spec),
        robotLabel: 'gate',
      ),
    );
  }

  // --- watched PRs ---------------------------------------------------------
  for (final s in ws.sessions) {
    if (!live.watchedPrs.contains(s.id)) continue;
    final watch = live.prs[s.id];
    final status = watch?.status;
    if (status != null && !status.open) continue;
    final spec = specById[s.specId];
    final problem = status != null && prHasProblemOf(status);
    final ci = live.ci[s.id];
    final handled = ci != null && ci.inFlight;
    out.add(
      Activity(
        id: 'pr:${s.id}',
        workspaceId: ws.id,
        workspaceName: ws.name,
        kind: ActivityKind.pr,
        column: ActivityColumn.review,
        pose: problem && !handled ? ActivityPose.wave : ActivityPose.watch,
        title: '${prLabel(s.prUrl).replaceFirst('PR ', '')} · Acompanhar PR',
        subtitle: [
          ?spec?.code,
          if (status != null)
            status.summary.split(' · ').skip(1).take(1).join(),
        ].where((e) => e.isNotEmpty).join(' · '),
        status: watch?.error != null
            ? 'gh falhou'
            : status == null
            ? 'conferindo'
            : problem
            ? (status.conflicting
                  ? 'PR com conflito'
                  : status.failedChecks.isNotEmpty
                  ? 'CI falhou'
                  : 'mudanças pedidas')
            : 'próxima conferência',
        tone: problem && !handled
            ? ActivityTone.attention
            : ActivityTone.normal,
        needsYou: problem && !handled,
        startedAt: s.endedAt ?? s.startedAt,
        lastAction: watch?.checkedAt == null
            ? null
            : 'gh pr view · ${_hhmm(watch!.checkedAt!)}',
        lastActionAt: watch?.checkedAt,
        action: ActivityAction.now,
        sessionId: s.id,
        specId: spec?.id,
        specCode: spec?.code,
        seed: spec == null ? 'session:${s.id}' : specSeed(ws.id, spec.code),
        branch: s.branch,
        tasks: tasks(spec),
        robotLabel: spec == null ? null : 'PR',
      ),
    );
  }

  // --- conversations (VIBE and Prompt) -----------------------------------
  for (final c in ws.conversations) {
    final l = live.conversations.live[c.id];
    if (l == null || !l.alive) continue;
    final busy = l.busy;
    if (!busy && l.approvals.isEmpty) continue;
    final spec = specById[c.specId];
    final vibe = spec?.kind == SpecKind.vibe;
    final plan = l.approvals
        .where((a) => a.request.toolName == 'ExitPlanMode')
        .firstOrNull;
    final ask = l.approvals.firstOrNull;
    final pose = ask != null ? ActivityPose.wave : poseOfTool(l.tool);
    out.add(
      Activity(
        id: 'conv:${c.id}',
        workspaceId: ws.id,
        workspaceName: ws.name,
        kind: vibe ? ActivityKind.vibe : ActivityKind.prompt,
        column: columnOf(spec),
        pose: pose,
        title: vibe ? spec!.title : c.title,
        subtitle: vibe ? '${spec!.code} · Prompt' : 'Prompt',
        status: plan != null
            ? 'plano pronto'
            : ask != null
            ? 'quer ${approvalVerb(ask.request.toolName)}'
            : poseLabel(pose, tool: l.tool),
        tone: ask != null ? ActivityTone.attention : ActivityTone.normal,
        needsYou: ask != null,
        startedAt: l.busySince ?? c.createdAt,
        lastAction: plan != null
            ? 'ExitPlanMode'
            : ask != null
            ? toolLine(
                LiveTool(
                  id: ask.requestId,
                  name: ask.request.toolName,
                  input: ask.request.input,
                  at: ask.receivedAt,
                ),
                root: ws.path,
              )
            : l.tool == null
            ? null
            : toolLine(l.tool!, root: ws.path),
        lastActionAt: ask?.receivedAt ?? l.tool?.at,
        calls: l.calls,
        action: plan != null
            ? ActivityAction.viewPlan
            : ask != null
            ? ActivityAction.respond
            : ActivityAction.stop,
        conversationId: c.id,
        specId: spec?.id,
        specCode: spec?.code,
        seed: 'conv:${c.id}',
        model: c.model,
        mode: c.mode,
        recent: _recent(l.recent, ws.path),
        lastText: l.lastText,
      ),
    );
  }

  // --- release -------------------------------------------------------------
  final r = ws.release;
  if (r != null &&
      (r.status == ReleaseRunStatus.finding ||
          r.status == ReleaseRunStatus.running ||
          r.status == ReleaseRunStatus.failure)) {
    final failed = r.status == ReleaseRunStatus.failure;
    out.add(
      Activity(
        id: 'release:${ws.id}',
        workspaceId: ws.id,
        workspaceName: ws.name,
        kind: ActivityKind.release,
        column: ActivityColumn.running,
        pose: failed ? ActivityPose.error : ActivityPose.run,
        title: r.tag,
        subtitle: r.workflowName.isEmpty ? 'Release' : r.workflowName,
        status: failed
            ? 'falhou${r.failedJob == null ? '' : ' em ${r.failedJob}'}'
            : r.status == ReleaseRunStatus.finding
            ? 'disparada'
            : 'rodando',
        tone: failed ? ActivityTone.error : ActivityTone.normal,
        needsYou: failed,
        error: failed,
        progress: r.jobs.isEmpty || failed
            ? null
            : (
                value: r.doneJobs / r.jobs.length,
                label: '${r.doneJobs} de ${r.jobs.length} jobs',
              ),
        startedAt: r.dispatchedAt,
        lastAction: failed ? r.failedStep : r.branch,
        action: failed ? ActivityAction.none : ActivityAction.stop,
      ),
    );
  }

  // --- planner -------------------------------------------------------------
  final busyText = ws.planner?.busy;
  if (busyText != null || ws.specPlanner) {
    out.add(
      Activity(
        id: 'planner:${ws.id}',
        workspaceId: ws.id,
        workspaceName: ws.name,
        kind: ActivityKind.planner,
        column: ActivityColumn.running,
        pose: ActivityPose.think,
        title: busyText != null ? 'Planejamento do projeto' : 'Nova spec',
        subtitle: busyText != null ? 'Projeto' : 'Specs',
        status: busyText ?? 'Pensando',
        seed: 'planner:${ws.id}',
      ),
    );
  }

  // --- dev servers ---------------------------------------------------------
  for (final d in ws.devServers) {
    if (d.status != DevServerStatus.running &&
        d.status != DevServerStatus.starting) {
      continue;
    }
    out.add(
      Activity(
        id: 'dev:${d.worktree}',
        workspaceId: ws.id,
        workspaceName: ws.name,
        kind: ActivityKind.dev,
        column: ActivityColumn.running,
        pose: ActivityPose.run,
        title: d.command ?? 'servidor de dev',
        subtitle: d.port == null
            ? 'Servidor'
            : 'Servidor · localhost:${d.port}',
        status: d.status == DevServerStatus.starting ? 'subindo' : 'no ar',
        startedAt: d.startedAt,
        lastAction: d.lastLog,
        action: ActivityAction.stop,
        devWorktree: d.worktree,
      ),
    );
  }

  // --- the queue of the Autopilot / scheduled -----------------------------
  for (final q in ws.queue) {
    out.add(
      Activity(
        id: 'queue:${q.spec.id}',
        workspaceId: ws.id,
        workspaceName: ws.name,
        kind: ActivityKind.queued,
        column: ActivityColumn.backlog,
        pose: ActivityPose.sleep,
        title: '${q.spec.code} · ${q.spec.title}',
        subtitle: 'Na fila do Autopilot',
        status: q.label,
        specId: q.spec.id,
        specCode: q.spec.code,
        seed: specSeed(ws.id, q.spec.code),
        tasks: tasks(q.spec),
        robotLabel: 'na fila',
      ),
    );
  }
  return out;
}

/// Whether a watched PR needs the user (as the Início).
bool prHasProblemOf(PrStatus s) =>
    s.open &&
    (s.conflicting ||
        s.reviewDecision == 'CHANGES_REQUESTED' ||
        s.checks.any((c) => c.state == 'FAILURE'));

// --- tabs, groups and order ---------------------------------------------------

/// The tabs (R17, P3): no "Feito".
enum ActivityTab {
  all('Todas'),
  needsYou('Precisa de você'),
  backlog('Backlog'),
  running('Em execução'),
  review('Review');

  const ActivityTab(this.label);

  final String label;

  bool accepts(Activity a) => switch (this) {
    all => true,
    needsYou => a.needsYou,
    backlog => a.column == ActivityColumn.backlog,
    running => a.column == ActivityColumn.running,
    review => a.column == ActivityColumn.review,
  };
}

/// Count of each tab.
Map<ActivityTab, int> activityTabCounts(List<Activity> all) => {
  for (final t in ActivityTab.values) t: all.where(t.accepts).length,
};

/// One workspace of the list.
@immutable
class ActivityGroup {
  const ActivityGroup({
    required this.workspaceId,
    required this.name,
    required this.items,
    this.label,
  });

  final int workspaceId;
  final String name;
  final List<Activity> items;

  /// `Autopilot 2/3`, `Corrigir CI automático`.
  final String? label;

  int get needsYou => items.where((a) => a.needsYou).length;
  bool get hasError => items.any((a) => a.error);
}

int _rank(Activity a) => a.needsYou
    ? 0
    : switch (a.column) {
        ActivityColumn.running => 1,
        ActivityColumn.review => 2,
        ActivityColumn.backlog => 3,
      };

/// Order inside a group (R6): what needs you first, then Em execução,
/// Review and Backlog; the oldest first.
int compareActivities(Activity a, Activity b) {
  final r = _rank(a).compareTo(_rank(b));
  if (r != 0) return r;
  final at = a.startedAt, bt = b.startedAt;
  if (at != null && bt != null) {
    final c = at.compareTo(bt);
    if (c != 0) return c;
  } else if (at != null || bt != null) {
    return at == null ? 1 : -1;
  }
  return a.id.compareTo(b.id);
}

/// The groups of [all] filtered by [tab] (R6): groups with a request or an
/// error go up, then the order of [order] (the workspaces' order).
List<ActivityGroup> groupActivities(
  List<Activity> all,
  ActivityTab tab, {
  List<int> order = const [],
  Map<int, String> labels = const {},
}) {
  final byWs = <int, List<Activity>>{};
  final names = <int, String>{};
  for (final a in all.where(tab.accepts)) {
    (byWs[a.workspaceId] ??= []).add(a);
    names[a.workspaceId] = a.workspaceName;
  }
  final groups = [
    for (final e in byWs.entries)
      ActivityGroup(
        workspaceId: e.key,
        name: names[e.key]!,
        items: e.value..sort(compareActivities),
        label: labels[e.key],
      ),
  ];
  int pos(int id) {
    final i = order.indexOf(id);
    return i < 0 ? order.length : i;
  }

  groups.sort((a, b) {
    final ua = a.needsYou > 0 || a.hasError ? 0 : 1;
    final ub = b.needsYou > 0 || b.hasError ? 0 : 1;
    if (ua != ub) return ua.compareTo(ub);
    final p = pos(a.workspaceId).compareTo(pos(b.workspaceId));
    return p != 0 ? p : a.name.compareTo(b.name);
  });
  return groups;
}

/// The flat list ("Agrupar por: Nenhum"): the same order without groups.
List<Activity> flatActivities(List<Activity> all, ActivityTab tab) =>
    all.where(tab.accepts).toList()..sort(compareActivities);
