import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart'
    show SessionStatus, SpecStep, StepStatus;
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/activities/widgets/robot_avatar.dart';
import 'package:promptorium/features/notifications/agent_alerts.dart';
import 'package:promptorium/features/notifications/alert_target.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/sessions/app_notifier.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../activities/activity_test.dart' show approval, session, spec, step;

/// SPEC-086 R1–R3, R9–R13: when the notification with the robot goes out,
/// is updated, summed up, closed and repeated.

final t0 = DateTime(2026, 11, 16, 15, 20);

AgentRequest req(
  String seed,
  String id, {
  AlertKind kind = AlertKind.approval,
  String what = 'quer executar flutter test',
}) => AgentRequest(
  key: '$seed:$id',
  seed: seed,
  where: 'SPEC-031 · Pagamento com Stripe',
  what: what,
  since: t0,
  target: AlertTarget(
    workspaceId: 1,
    kind: kind,
    sessionId: 's-$seed',
    requestId: id,
  ),
);

const ada = 'spec:1:SPEC-031';
const bruno = 'spec:1:SPEC-033';
const caio = 'spec:1:SPEC-034';
const davi = 'spec:1:SPEC-035';

/// Runs the planner over [steps]: (seconds after [t0], pending, active).
List<List<AlertAction>> run(
  List<(int, List<AgentRequest>, bool)> steps, {
  AlertSettings settings = const AlertSettings(),
}) {
  var memory = const AlertsMemory();
  final out = <List<AlertAction>>[];
  for (final (s, pending, active) in steps) {
    final plan = planAlerts(
      memory,
      pending,
      t0.add(Duration(seconds: s)),
      windowActive: active,
      settings: settings,
    );
    memory = plan.memory;
    out.add(plan.actions);
  }
  return out;
}

void main() {
  group('planAlerts', () {
    test('em segundo plano: sai depois de 3 s (R2, R11)', () {
      final a = req(ada, 'r1');
      final out = run([
        (0, [a], false),
        (2, [a], false),
        (3, [a], false),
        (4, [a], false),
      ]);
      expect(out[0], isEmpty);
      expect(out[1], isEmpty);
      final show = out[2].single as ShowAgentAlert;
      expect(show.seed, ada);
      expect(show.update, isFalse);
      expect(out[3], isEmpty, reason: 'não repete');
    });

    test('respondido antes de 3 s: nada sai (R11)', () {
      final a = req(ada, 'r1');
      final out = run([
        (0, [a], false),
        (2, [], false),
        (5, [], false),
      ]);
      expect(out.expand((e) => e), isEmpty);
    });

    test('com a janela em foco: nada sai, nem depois (R2)', () {
      final a = req(ada, 'r1');
      final out = run([
        (0, [a], true),
        (5, [a], true),
        // Minimized afterwards: it was seen in the app.
        (10, [a], false),
      ]);
      expect(out.expand((e) => e), isEmpty);
    });

    test('segundo pedido do mesmo agente atualiza: 2 pedidos (R9)', () {
      final a1 = req(ada, 'r1');
      final a2 = req(ada, 'r2', what: 'quer editar pubspec.yaml');
      final out = run([
        (0, [a1], false),
        (3, [a1], false),
        (10, [a1, a2], false),
        (13, [a1, a2], false),
      ]);
      expect(out[2], isEmpty, reason: 'a espera vale para o segundo também');
      final update = out[3].single as ShowAgentAlert;
      expect(update.update, isTrue);
      expect(update.requests.map((r) => r.key), [a1.key, a2.key]);
      expect(
        agentAlertTitle(update),
        '${RobotIdentity.of(ada).name} precisa de você · 2 pedidos',
      );
      expect(
        agentAlertBody(update),
        'SPEC-031 · também quer editar pubspec.yaml',
      );
    });

    test('dois agentes: cada um com a sua', () {
      final out = run([
        (0, [req(ada, 'r1'), req(bruno, 'r1')], false),
        (3, [req(ada, 'r1'), req(bruno, 'r1')], false),
      ]);
      expect(out[1].whereType<ShowAgentAlert>().map((a) => a.seed), {
        ada,
        bruno,
      });
    });

    test('três agentes em 15 s: um resumo, e as individuais fecham (R10)', () {
      final a = req(ada, 'r1');
      final b = req(bruno, 'r1', kind: AlertKind.plan, what: 'plano pronto');
      final c = req(caio, 'r1', kind: AlertKind.question, what: 'pergunta');
      final out = run([
        (0, [a], false),
        (3, [a], false), // Ada sai sozinha
        (6, [a, b], false),
        (9, [a, b], false), // Bruno sai sozinho
        (11, [a, b, c], false),
        (14, [a, b, c], false), // Caio: o terceiro em 15 s
      ]);
      expect((out[1].single as ShowAgentAlert).seed, ada);
      expect((out[3].single as ShowAgentAlert).seed, bruno);
      final last = out[5];
      expect(last.whereType<CloseAgentAlert>().map((e) => e.seed), {
        ada,
        bruno,
      });
      final summary = last.whereType<ShowSummaryAlert>().single;
      expect(summary.seeds.toSet(), {ada, bruno, caio});
      expect(last.whereType<ShowAgentAlert>(), isEmpty);
      expect(summaryAlertTitle(summary), '3 agentes precisam de você');
      expect(
        summaryAlertBody(summary),
        '${RobotIdentity.of(ada).name}, ${RobotIdentity.of(bruno).name} e '
        '${RobotIdentity.of(caio).name} · aprovação, uma pergunta e plano '
        'pronto',
      );
    });

    test('três agentes espalhados por mais de 15 s: sem resumo', () {
      final a = req(ada, 'r1');
      final b = req(bruno, 'r1');
      final c = req(caio, 'r1');
      final out = run([
        (0, [a], false),
        (3, [a], false),
        (10, [a, b], false),
        (13, [a, b], false),
        (30, [a, b, c], false),
        (33, [a, b, c], false),
      ]);
      expect(out[5].single, isA<ShowAgentAlert>());
    });

    test('com o resumo aberto, um agente novo entra nele', () {
      final all = [req(ada, '1'), req(bruno, '1'), req(caio, '1')];
      final out = run([
        (0, all, false),
        (3, all, false),
        (20, [...all, req(davi, '1')], false),
        (23, [...all, req(davi, '1')], false),
      ]);
      expect(out[1].single, isA<ShowSummaryAlert>());
      final update = out[3].single as ShowSummaryAlert;
      expect(update.update, isTrue);
      expect(update.seeds, hasLength(4));
    });

    test('respondido fecha; a janela em foco fecha tudo (R12)', () {
      final a1 = req(ada, 'r1');
      final a2 = req(ada, 'r2');
      final b = req(bruno, 'r1');
      final out = run([
        (0, [a1, a2, b], false),
        (3, [a1, a2, b], false),
        (5, [a2, b], false), // one of Ada's answered: still open
        (6, [b], false), // Ada done
        (7, [b], true), // the window comes to the front
      ]);
      expect(out[2], isEmpty);
      expect((out[3].single as CloseAgentAlert).seed, ada);
      expect((out[4].single as CloseAgentAlert).seed, bruno);
    });

    test('o resumo fecha quando tudo foi respondido', () {
      final all = [req(ada, '1'), req(bruno, '1'), req(caio, '1')];
      final out = run([
        (0, all, false),
        (3, all, false),
        (5, [all.first], false),
        (6, [], false),
      ]);
      expect(out[2], isEmpty);
      expect(out[3].single, isA<CloseSummaryAlert>());
    });

    test('um lembrete aos 15 min, uma vez só (R13)', () {
      final a = req(ada, 'r1');
      final out = run([
        (0, [a], false),
        (3, [a], false),
        (899, [a], false),
        (900, [a], false),
        (1800, [a], false),
        (3600, [a], false),
      ]);
      expect(out[2], isEmpty);
      final reminder = out[3].single as ShowAgentAlert;
      expect(reminder.reminder, isTrue);
      expect(reminder.update, isTrue);
      expect(
        agentAlertTitle(reminder),
        '${RobotIdentity.of(ada).name} ainda esperando · há 15 min',
      );
      expect(out[4], isEmpty);
      expect(out[5], isEmpty);
    });

    test('o lembrete vale para o pedido já visto no app', () {
      final a = req(ada, 'r1');
      final out = run([
        (0, [a], true),
        (60, [a], false),
        (900, [a], false),
      ]);
      expect(out[1], isEmpty);
      expect((out[2].single as ShowAgentAlert).reminder, isTrue);
    });

    test('sem o lembrete, ou com os avisos desligados (R15)', () {
      final a = req(ada, 'r1');
      final noReminder = run([
        (0, [a], false),
        (3, [a], false),
        (900, [a], false),
      ], settings: const AlertSettings(reminder: false));
      expect(noReminder[2], isEmpty);
      final off = run([
        (0, [a], false),
        (3, [a], false),
      ], settings: const AlertSettings(agents: false));
      expect(off.expand((e) => e), isEmpty);
    });
  });

  group('o que espera (R1)', () {
    final s = spec(1, 'SPEC-031');
    List<Activity> activities(ActivityLive live, {List<SpecStep>? steps}) =>
        buildActivities(
          [
            ActivityWorkspace(
              id: 1,
              name: 'loja-api',
              specs: [s],
              stepRows: steps ?? const [],
              sessions: [
                session('a', specId: 1, steps: 'R2'),
                session('f', status: SessionStatus.failed),
              ],
            ),
          ],
          live,
          now: t0,
        );

    test('aprovação de sessão: robô da spec, alvo na sessão', () {
      final live = SessionManagerState(
        live: {
          'a': LiveSession(
            busySince: t0,
            approvals: [
              approval('a', 'Bash', input: '{"command":"flutter test"}'),
            ],
          ),
        },
      );
      final list = agentRequests(
        activities(ActivityLive(sessions: live)),
        sessions: live,
        conversations: const ConversationManagerState(),
      );
      final r = list.single;
      expect(r.seed, specSeed(1, 'SPEC-031'));
      expect(r.agent, RobotIdentity.of(specSeed(1, 'SPEC-031')).name);
      expect(r.where, 'SPEC-031 · Título SPEC-031');
      expect(r.what, 'quer executar flutter test');
      expect(r.kind, AlertKind.approval);
      expect(r.target.sessionId, 'a');
      expect(r.target.requestId, 'r-a');
      expect(r.target.section.name, 'sessions');
    });

    test('pergunta e plano', () {
      expect(
        requestWhat('AskUserQuestion', {
          'questions': [
            {'question': 'Qual banco?'},
          ],
        }),
        'pergunta: Qual banco?',
      );
      expect(requestWhat('ExitPlanMode', {}), 'plano pronto para revisar');
      expect(
        requestWhat('Edit', {'file_path': '/wt/a/pubspec.yaml'}),
        'quer editar pubspec.yaml',
      );
    });

    test('etapa em needs_input vai para o Quadro; erro não notifica', () {
      final list = agentRequests(
        activities(
          const ActivityLive(),
          steps: [step(1, 'R1', StepStatus.needsInput)],
        ),
        sessions: const SessionManagerState(),
        conversations: const ConversationManagerState(),
      );
      // The failed free session is an error: no robot notification.
      final r = list.single;
      expect(r.kind, AlertKind.needsInput);
      expect(r.target.section.name, 'tasks');
      expect(r.target.specId, 1);
    });
  });

  group('AgentAlerts', () {
    late _Notifier notifier;
    late ProviderContainer c;
    late List<AgentRequest> pending;
    var now = t0;

    void start({AlertSettings settings = const AlertSettings()}) {
      c = ProviderContainer(
        overrides: [
          appNotifierProvider.overrideWithValue(notifier),
          agentRequestsProvider.overrideWith((ref) => pending),
          alertSettingsProvider.overrideWithValue(settings),
        ],
      );
      c.read(windowActiveProvider.notifier).set(false);
      c.read(agentAlertsProvider);
    }

    setUp(() {
      notifier = _Notifier();
      pending = [];
      now = t0;
      AgentAlerts.clock = () => now;
    });

    tearDown(() {
      c.dispose();
      AgentAlerts.clock = DateTime.now;
    });

    Future<void> tick(int seconds) async {
      now = t0.add(Duration(seconds: seconds));
      c.invalidate(agentRequestsProvider);
      c.read(agentAlertsProvider.notifier).tick();
      // The robot is drawn off the frame: give it time.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('mostra com o robô, atualiza pelo id e fecha ao responder', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      start();
      pending = [req(ada, 'r1')];
      await tick(0);
      await tick(3);
      expect(
        notifier.shown.single.title,
        '${RobotIdentity.of(ada).name} precisa de você',
      );
      expect(
        notifier.shown.single.body,
        'SPEC-031 · Pagamento com Stripe — quer executar flutter test',
      );
      expect(notifier.shown.single.image!.width, 128);
      expect(notifier.shown.single.actions, [clickAction, openAction]);
      expect(notifier.shown.single.category, 'im.received');
      pending = [req(ada, 'r1'), req(ada, 'r2')];
      await tick(5);
      await tick(8);
      expect(notifier.shown.last.replaces, 1);
      pending = [];
      await tick(9);
      expect(notifier.closed, [1]);
    });

    test('R12: a late Notify is closed when its request was answered during DBus await', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      start(settings: const AlertSettings(robot: false));
      final response = Completer<void>();
      notifier.response = response;
      pending = [req(ada, 'r1')];
      await tick(0);
      await tick(3);
      expect(notifier.shown, hasLength(1));
      pending = [];
      await tick(4);
      response.complete();
      await tick(5);
      expect(notifier.closed, [1]);
    });

    test('sem o robô: sai sem imagem (R15)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      start(settings: const AlertSettings(robot: false));
      pending = [req(ada, 'r1')];
      await tick(0);
      await tick(3);
      expect(notifier.shown.single.image, isNull);
    });
  });
}

class _Shown {
  _Shown(
    this.title,
    this.body,
    this.image,
    this.replaces,
    this.actions,
    this.category,
    this.onClick,
  );
  final String title;
  final String body;
  final NotificationImage? image;
  final int? replaces;
  final List<(String, String)> actions;
  final String? category;
  final VoidCallback? onClick;
}

class _Notifier implements AppNotifier {
  final shown = <_Shown>[];
  final closed = <int>[];
  var _next = 1;
  Completer<void>? response;

  @override
  Future<int?> show(
    String title,
    String body, {
    VoidCallback? onClick,
    NotificationImage? image,
    int? replaces,
    List<(String, String)> actions = const [clickAction],
    String? noActionsHint,
    String? category,
  }) async {
    shown.add(_Shown(title, body, image, replaces, actions, category, onClick));
    await response?.future;
    return replaces ?? _next++;
  }

  @override
  Future<void> close(int id) async => closed.add(id);
}
