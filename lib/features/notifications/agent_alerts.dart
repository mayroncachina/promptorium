import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../activities/activities_state.dart';
import '../activities/activity.dart';
import '../activities/widgets/robot_avatar.dart' show RobotIdentity;
import '../activities/widgets/robot_snapshot.dart';
import '../home/home_inbox.dart' show approvalVerb;
import '../prompt/conversation_manager.dart';
import '../sessions/app_notifier.dart';
import '../sessions/session_manager.dart';
import '../sessions/timeline.dart' show toolTarget;
import 'alert_target.dart';

/// The notification with the robot (SPEC-086): when an agent needs the
/// person and the window is in the background, a system notification with
/// the robot of that agent waving. [planAlerts] holds the rules against spam
/// (R2, R9–R13); [AgentAlerts] runs it and talks to the [AppNotifier].

/// Wait before a notification (R11).
const alertDelay = Duration(seconds: 3);

/// Three or more agents within this window make one summary (R10).
const alertSummaryWindow = Duration(seconds: 15);
const alertSummaryMin = 3;

/// The single reminder (R13).
const alertReminderAfter = Duration(minutes: 15);

/// What ends the body when the server has no buttons (R5).
const alertNoActionsHint = 'Abra o Promptorium para responder';

/// One thing an agent waits for (R1).
@immutable
class AgentRequest {
  const AgentRequest({
    required this.key,
    required this.seed,
    required this.where,
    required this.what,
    required this.since,
    required this.target,
  });

  /// `session:<id>:<request>`, `conv:<id>:<request>`, `step:<spec>:<step>`.
  final String key;

  /// The robot (SPEC-076 R5).
  final String seed;

  /// `SPEC-031 · Pagamento com Stripe`.
  final String where;

  /// `quer executar flutter test`, `plano pronto para revisar`.
  final String what;
  final DateTime since;
  final AlertTarget target;

  AlertKind get kind => target.kind;
  String get agent => RobotIdentity.of(seed).name;
}

/// The preferences of Configurações › Notificações (R15), all on unless set
/// to `'false'` in `app_settings`.
@immutable
class AlertSettings {
  const AlertSettings({
    this.agents = true,
    this.robot = true,
    this.reminder = true,
    this.sessions = true,
  });

  factory AlertSettings.of(Map<String, String> settings) => AlertSettings(
    agents: settings[AlertSettingKeys.agents] != 'false',
    robot: settings[AlertSettingKeys.robot] != 'false',
    reminder: settings[AlertSettingKeys.reminder] != 'false',
    sessions: settings[AlertSettingKeys.sessions] != 'false',
  );

  /// "Avisar quando um agente precisa de você".
  final bool agents;

  /// "Mostrar o robô do agente".
  final bool robot;

  /// "Lembrar uma vez depois de 15 min".
  final bool reminder;

  /// "Avisar também quando uma sessão termina ou falha".
  final bool sessions;
}

/// Keys in `app_settings` (R15).
abstract final class AlertSettingKeys {
  static const agents = 'notificacoes.agentes';
  static const robot = 'notificacoes.robo';
  static const reminder = 'notificacoes.lembrete';
  static const sessions = 'notificacoes.sessoes';
}

final alertSettingsProvider = Provider<AlertSettings>(
  (ref) => AlertSettings.of(ref.watch(appSettingsProvider)),
);

/// What the planner remembers between two runs. Notification ids stay out:
/// [AgentAlerts] keeps them.
@immutable
class AlertsMemory {
  const AlertsMemory({
    this.firstSeen = const {},
    this.notified = const {},
    this.reminded = const {},
    this.open = const {},
    this.summary = const {},
    this.summaryKeys = const {},
  });

  /// When the planner first saw each pending request.
  final Map<String, DateTime> firstSeen;

  /// Requests already in a notification, or seen with the window in front:
  /// they do not notify again (only the reminder, R13).
  final Set<String> notified;

  /// Requests already reminded: never again (R13).
  final Set<String> reminded;

  /// The open notification of each agent (seed) and the requests in it.
  final Map<String, Set<String>> open;

  /// The agents of the open summary (empty = none) and its requests.
  final Set<String> summary;
  final Set<String> summaryKeys;

  bool get hasOpen => open.isNotEmpty || summary.isNotEmpty;
}

/// What [planAlerts] asks for.
sealed class AlertAction {
  const AlertAction();
}

/// Shows (or updates, [update]) the notification of the agent [seed]:
/// [requests] are its pending requests, the oldest first.
class ShowAgentAlert extends AlertAction {
  const ShowAgentAlert(
    this.seed,
    this.requests, {
    this.update = false,
    this.waiting,
  });

  final String seed;
  final List<AgentRequest> requests;
  final bool update;

  /// The reminder (R13): how long the oldest request has waited.
  final Duration? waiting;

  bool get reminder => waiting != null;

  @override
  String toString() =>
      'ShowAgentAlert($seed, ${requests.length}, update: $update, '
      'reminder: $reminder)';
}

/// Shows (or updates) the summary of several agents (R10).
class ShowSummaryAlert extends AlertAction {
  const ShowSummaryAlert(this.seeds, this.requests, {this.update = false});

  final List<String> seeds;
  final List<AgentRequest> requests;
  final bool update;

  @override
  String toString() => 'ShowSummaryAlert(${seeds.length}, update: $update)';
}

/// Closes the notification of the agent [seed] (R12).
class CloseAgentAlert extends AlertAction {
  const CloseAgentAlert(this.seed);
  final String seed;

  @override
  String toString() => 'CloseAgentAlert($seed)';
}

/// Closes the summary (R12).
class CloseSummaryAlert extends AlertAction {
  const CloseSummaryAlert();

  @override
  String toString() => 'CloseSummaryAlert()';
}

/// The rules of R2 and R9–R13, pure: from what was shown ([previous]) and
/// what waits now ([pending]), the notifications to show, update and close.
({AlertsMemory memory, List<AlertAction> actions}) planAlerts(
  AlertsMemory previous,
  List<AgentRequest> pending,
  DateTime now, {
  required bool windowActive,
  AlertSettings settings = const AlertSettings(),
}) {
  final actions = <AlertAction>[];
  final byKey = {for (final r in pending) r.key: r};
  final keys = byKey.keys.toSet();
  final firstSeen = {for (final k in keys) k: previous.firstSeen[k] ?? now};
  final notified = previous.notified.intersection(keys);
  final reminded = previous.reminded.intersection(keys);

  List<AgentRequest> ofSeed(String seed) =>
      pending.where((r) => r.seed == seed).toList()
        ..sort((a, b) => firstSeen[a.key]!.compareTo(firstSeen[b.key]!));

  /// Agents in the order they started to wait.
  List<String> byArrival(Iterable<String> seeds) {
    DateTime first(String seed) => firstSeen[ofSeed(seed).first.key]!;
    return seeds.toList()..sort((a, b) => first(a).compareTo(first(b)));
  }

  // R12: a request answered, a session stopped: what is left in each
  // notification; an empty one closes.
  final open = <String, Set<String>>{};
  for (final e in previous.open.entries) {
    final left = e.value.intersection(keys);
    if (left.isEmpty) {
      actions.add(CloseAgentAlert(e.key));
    } else {
      open[e.key] = left;
    }
  }
  var summary = previous.summary;
  var summaryKeys = previous.summaryKeys.intersection(keys);
  if (summary.isNotEmpty && summaryKeys.isEmpty) {
    actions.add(const CloseSummaryAlert());
    summary = const {};
  }

  AlertsMemory memory() => AlertsMemory(
    firstSeen: firstSeen,
    notified: notified,
    reminded: reminded,
    open: open,
    summary: summary,
    summaryKeys: summaryKeys,
  );

  void closeAll() {
    for (final seed in open.keys) {
      actions.add(CloseAgentAlert(seed));
    }
    open.clear();
    if (summary.isNotEmpty) actions.add(const CloseSummaryAlert());
    summary = const {};
    summaryKeys = const {};
  }

  // R2: with the window in front (or the option off) nothing goes out, what
  // is open closes and what waits now counts as seen.
  if (windowActive || !settings.agents) {
    closeAll();
    notified.addAll(keys);
    return (memory: memory(), actions: actions);
  }

  // R11: new requests older than the wait.
  final fresh = <String, List<AgentRequest>>{};
  for (final r in pending) {
    if (notified.contains(r.key)) continue;
    if (now.difference(firstSeen[r.key]!) < alertDelay) continue;
    (fresh[r.seed] ??= []).add(r);
  }

  if (fresh.isNotEmpty) {
    if (summary.isNotEmpty) {
      // The summary is open: new agents join it.
      final seeds = {...summary, ...fresh.keys};
      for (final seed in fresh.keys) {
        if (open.remove(seed) != null) actions.add(CloseAgentAlert(seed));
      }
      final order = byArrival(seeds);
      final requests = [for (final s in order) ...ofSeed(s)];
      actions.add(ShowSummaryAlert(order, requests, update: true));
      summary = seeds;
      summaryKeys = {for (final r in requests) r.key};
      notified.addAll(summaryKeys);
    } else {
      // R10: three or more agents within 15 s, counting the ones already
      // shown in that window.
      final recent = <String>{
        ...fresh.keys,
        for (final e in open.entries)
          if (e.value.any(
            (k) => now.difference(firstSeen[k]!) <= alertSummaryWindow,
          ))
            e.key,
      };
      if (recent.length >= alertSummaryMin) {
        for (final seed in recent) {
          if (open.remove(seed) != null) actions.add(CloseAgentAlert(seed));
        }
        final order = byArrival(recent);
        final requests = [for (final s in order) ...ofSeed(s)];
        actions.add(ShowSummaryAlert(order, requests));
        summary = recent;
        summaryKeys = {for (final r in requests) r.key};
        notified.addAll(summaryKeys);
      } else {
        // R9: one per agent, updated.
        for (final seed in fresh.keys) {
          final requests = ofSeed(seed);
          actions.add(
            ShowAgentAlert(seed, requests, update: open.containsKey(seed)),
          );
          open[seed] = {for (final r in requests) r.key};
          notified.addAll(open[seed]!);
        }
      }
    }
  }

  // R13: one reminder per request, 15 min after it started waiting.
  if (settings.reminder) {
    final due = <String>{
      for (final r in pending)
        if (!reminded.contains(r.key) &&
            now.difference(firstSeen[r.key]!) >= alertReminderAfter)
          r.seed,
    };
    for (final seed in due) {
      final requests = ofSeed(seed);
      actions.add(
        ShowAgentAlert(
          seed,
          requests,
          update: open.containsKey(seed),
          waiting: now.difference(firstSeen[requests.first.key]!),
        ),
      );
      open[seed] = {for (final r in requests) r.key};
      reminded.addAll(open[seed]!);
      notified.addAll(open[seed]!);
    }
  }
  return (memory: memory(), actions: actions);
}

// --- what waits (R1) --------------------------------------------------------

/// `flutter test` from the input of a `Bash`, `pubspec.yaml` from an edit:
/// short, one line.
String _target(String tool, Map<String, dynamic> input) {
  final t = toolTarget(tool, input);
  if (t.startsWith('/') && !t.contains(' ')) return t.split('/').last;
  return t;
}

/// What the agent wants, in the body of the notification.
String requestWhat(String tool, Map<String, dynamic> input) {
  switch (tool) {
    case 'ExitPlanMode':
      return 'plano pronto para revisar';
    case 'AskUserQuestion':
      final qs = input['questions'];
      final q = qs is List && qs.isNotEmpty && qs.first is Map
          ? '${(qs.first as Map)['question'] ?? ''}'.trim()
          : '';
      return q.isEmpty ? 'tem uma pergunta' : 'pergunta: $q';
  }
  final target = _target(tool, input);
  final verb = 'quer ${approvalVerb(tool)}';
  return target.isEmpty ? verb : '$verb $target';
}

AlertKind _kindOf(String tool) => switch (tool) {
  'ExitPlanMode' => AlertKind.plan,
  'AskUserQuestion' => AlertKind.question,
  _ => AlertKind.approval,
};

/// The requests of the agents that need the person (R1): approvals,
/// questions and plans of sessions and conversations, and steps stopped in
/// `needs_input`. Not the errors, the PRs or the CI (they keep their own
/// notifications, without a robot).
List<AgentRequest> agentRequests(
  List<Activity> activities, {
  required SessionManagerState sessions,
  required ConversationManagerState conversations,
}) {
  final out = <AgentRequest>[];
  for (final a in activities) {
    final seed = a.seed;
    if (!a.needsYou || a.error || seed == null) continue;
    if (a.pose != ActivityPose.wave) continue;
    if (a.id.startsWith('session:') && a.sessionId != null) {
      final sid = a.sessionId!;
      for (final p in sessions.live[sid]?.approvals ?? const []) {
        final r = p.request;
        out.add(
          AgentRequest(
            key: 'session:$sid:${p.requestId}',
            seed: seed,
            where: a.title,
            what: requestWhat(r.toolName, r.input),
            since: p.receivedAt,
            target: AlertTarget(
              workspaceId: a.workspaceId,
              kind: _kindOf(r.toolName),
              sessionId: sid,
              requestId: p.requestId,
              specId: a.specId,
            ),
          ),
        );
      }
    } else if (a.id.startsWith('conv:') && a.conversationId != null) {
      final cid = a.conversationId!;
      for (final p in conversations.live[cid]?.approvals ?? const []) {
        final r = p.request;
        out.add(
          AgentRequest(
            key: 'conv:$cid:${p.requestId}',
            seed: seed,
            where: a.specCode == null ? a.title : '${a.specCode} · ${a.title}',
            what: requestWhat(r.toolName, r.input),
            since: p.receivedAt,
            target: AlertTarget(
              workspaceId: a.workspaceId,
              kind: _kindOf(r.toolName),
              conversationId: cid,
              requestId: p.requestId,
              specId: a.specId,
            ),
          ),
        );
      }
    } else if (a.id.startsWith('secret:')) {
      // SPEC-085 R7: a commit, push or PR stopped by the Vigia de segredos.
      out.add(
        AgentRequest(
          key: a.id,
          seed: seed,
          where: a.title,
          what: 'Segredo encontrado: ${a.subtitle}',
          since: a.startedAt ?? DateTime.now(),
          target: AlertTarget(
            workspaceId: a.workspaceId,
            kind: AlertKind.needsInput,
            specId: a.specId,
            sessionId: a.sessionId,
            requestId: a.id,
          ),
        ),
      );
    } else if (a.id.startsWith('step:') && a.specId != null) {
      out.add(
        AgentRequest(
          key: a.id,
          seed: seed,
          where: a.title,
          what: a.status,
          since: a.startedAt ?? DateTime.now(),
          target: AlertTarget(
            workspaceId: a.workspaceId,
            kind: AlertKind.needsInput,
            specId: a.specId,
            sessionId: a.sessionId,
            requestId: a.id,
          ),
        ),
      );
    }
  }
  return out;
}

/// What waits now, in every workspace.
final agentRequestsProvider = Provider.autoDispose<List<AgentRequest>>(
  (ref) => agentRequests(
    ref.watch(activitiesProvider),
    sessions: ref.watch(sessionManagerProvider),
    conversations: ref.watch(conversationManagerProvider),
  ),
);

// --- the texts (R3, R10, R16) -----------------------------------------------

/// `Ada precisa de você`, `Ada precisa de você · 2 pedidos`, `Ada ainda
/// esperando · há 15 min`.
String agentAlertTitle(ShowAgentAlert a) {
  final name = RobotIdentity.of(a.seed).name;
  if (a.waiting case final w?) {
    return '$name ainda esperando · há ${w.inMinutes} min';
  }
  final n = a.requests.length;
  return n > 1 ? '$name precisa de você · $n pedidos' : '$name precisa de você';
}

/// The newest request: `SPEC-031 · Pagamento com Stripe — quer executar
/// flutter test`; with more than one, `SPEC-031 · também quer editar
/// pubspec.yaml`.
String agentAlertBody(ShowAgentAlert a) {
  final newest = a.requests.last;
  if (a.requests.length > 1 && !a.reminder) {
    final where = newest.where.split(' · ').first;
    return '$where · também ${newest.what}';
  }
  return '${newest.where} — ${newest.what}';
}

/// `Ada, Bruno e Caio`.
String namesList(List<String> names) => names.length <= 1
    ? names.join()
    : '${names.take(names.length - 1).join(', ')} e ${names.last}';

String summaryAlertTitle(ShowSummaryAlert a) =>
    '${a.seeds.length} agentes precisam de você';

/// `Ada, Bruno e Caio · aprovação, plano pronto e uma pergunta`.
String summaryAlertBody(ShowSummaryAlert a) {
  final names = [for (final s in a.seeds) RobotIdentity.of(s).name];
  final kinds = <AlertKind, int>{};
  for (final r in a.requests) {
    kinds[r.kind] = (kinds[r.kind] ?? 0) + 1;
  }
  String label(AlertKind k, int n) => switch (k) {
    AlertKind.approval => n > 1 ? '$n aprovações' : 'aprovação',
    AlertKind.question => n > 1 ? '$n perguntas' : 'uma pergunta',
    AlertKind.plan => n > 1 ? '$n planos prontos' : 'plano pronto',
    AlertKind.needsInput => n > 1 ? '$n etapas paradas' : 'etapa parada',
    AlertKind.secret => n > 1 ? '$n segredos' : 'um segredo',
  };
  final parts = [
    for (final k in AlertKind.values)
      if (kinds[k] case final n?) label(k, n),
  ];
  return '${namesList(names)} · ${namesList(parts)}';
}

// --- the window -------------------------------------------------------------

/// Whether the window is in front (focused, not minimized, not hidden): the
/// app's lifecycle is `resumed` (R2). Fed by `main`.
class WindowActive extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool active) {
    if (state != active) state = active;
  }
}

final windowActiveProvider = NotifierProvider<WindowActive, bool>(
  WindowActive.new,
);

// --- the runner -------------------------------------------------------------

/// Runs [planAlerts] when what waits, the window or the clock change, and
/// turns its actions into system notifications.
class AgentAlerts extends Notifier<AlertsMemory> {
  Future<void> _effects = Future.value();
  bool _disposed = false;
  final _ids = <String, int>{};
  int? _summaryId;
  Timer? _timer;

  /// `now` of the planner (tests).
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  AlertsMemory build() {
    ref.listen(agentRequestsProvider, (_, _) => _run());
    ref.listen(windowActiveProvider, (_, _) => _run());
    ref.listen(alertSettingsProvider, (_, _) => _run());
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    Future.microtask(_run);
    return const AlertsMemory();
  }

  AppNotifier get _notifier => ref.read(appNotifierProvider);

  /// One pass of the rules; a timer of 1 s keeps them going while something
  /// waits (the wait of R11, the reminder of R13).
  void tick() => _run();

  void _run() {
    final pending = ref.read(agentRequestsProvider);
    final plan = planAlerts(
      state,
      pending,
      clock(),
      windowActive: ref.read(windowActiveProvider),
      settings: ref.read(alertSettingsProvider),
    );
    state = plan.memory;
    for (final a in plan.actions) {
      // DBus and robot rendering are asynchronous: preserve show/update/close
      // order so a late Notify cannot survive a resolved request (R12).
      _effects = _effects.then((_) => _disposed ? null : _apply(a)).catchError((
        Object error,
      ) {
        debugPrint('notificação: falha ao atualizar alerta — $error');
      });
    }
    final busy = pending.isNotEmpty || state.hasOpen;
    if (busy && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _run());
    } else if (!busy) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _apply(AlertAction a) async {
    final settings = ref.read(alertSettingsProvider);
    final notifier = _notifier;
    switch (a) {
      case ShowAgentAlert(:final seed):
        final image = settings.robot ? await _image(robotSnapshot(seed)) : null;
        if (_disposed || !state.open.containsKey(seed)) return;
        final id = await notifier.show(
          agentAlertTitle(a),
          agentAlertBody(a),
          image: image,
          replaces: _ids[seed],
          actions: const [clickAction, openAction],
          noActionsHint: alertNoActionsHint,
          category: 'im.received',
          onClick: () => _open(seed, a.requests.first),
        );
        if (id != null) {
          if (_disposed || !state.open.containsKey(seed)) {
            await notifier.close(id);
          } else {
            _ids[seed] = id;
          }
        }
      case ShowSummaryAlert(:final seeds):
        final image = settings.robot
            ? await _image(robotGroupSnapshot(seeds))
            : null;
        if (_disposed || state.summary.isEmpty) return;
        final id = await notifier.show(
          summaryAlertTitle(a),
          summaryAlertBody(a),
          image: image,
          replaces: _summaryId,
          actions: const [clickAction, openAction],
          noActionsHint: alertNoActionsHint,
          category: 'im.received',
          onClick: () => openNeedsYou(ref.read),
        );
        if (id != null) {
          if (_disposed || state.summary.isEmpty) {
            await notifier.close(id);
          } else {
            _summaryId = id;
          }
        }
      case CloseAgentAlert(:final seed):
        final id = _ids.remove(seed);
        if (id != null) await notifier.close(id);
      case CloseSummaryAlert():
        final id = _summaryId;
        _summaryId = null;
        if (id != null) await notifier.close(id);
    }
  }

  static Future<NotificationImage?> _image(Future<RobotPixels> pixels) async {
    try {
      final p = await pixels;
      return NotificationImage(width: p.width, height: p.height, rgba: p.rgba);
    } catch (e) {
      debugPrint('notificação: robô indisponível — $e');
      return null;
    }
  }

  /// R9: the click goes to the oldest request of the agent still waiting;
  /// [fallback] when none is left ("Esse pedido já foi respondido").
  Future<void> _open(String seed, AgentRequest fallback) async {
    final pending = ref.read(agentRequestsProvider);
    final mine = pending.where((r) => r.seed == seed).toList()
      ..sort(
        (a, b) => (state.firstSeen[a.key] ?? a.since).compareTo(
          state.firstSeen[b.key] ?? b.since,
        ),
      );
    final r = mine.firstOrNull ?? fallback;
    await openAlertTarget(
      ref.read,
      r.target,
      pending: mine.isNotEmpty,
      announce: '${r.agent}, ${r.where.split(' · ').first}: ${r.what}',
    );
  }
}

final agentAlertsProvider = NotifierProvider<AgentAlerts, AlertsMemory>(
  AgentAlerts.new,
);
