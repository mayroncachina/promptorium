import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/activities_state.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/activities/widgets/board_robots.dart';
import 'package:promptorium/features/activities/widgets/robot_avatar.dart';

Activity act(
  String id, {
  int ws = 1,
  int? specId = 1,
  ActivityKind kind = ActivityKind.spec,
  ActivityPose pose = ActivityPose.edit,
  ActivityColumn column = ActivityColumn.running,
  bool needsYou = false,
  bool error = false,
  String status = 'Editando · R2',
  String? lastAction,
  ActivityAction action = ActivityAction.stop,
  String? seed = 'spec:1:SPEC-075',
  String? robotLabel,
}) => Activity(
  id: id,
  workspaceId: ws,
  workspaceName: 'w$ws',
  kind: kind,
  column: column,
  pose: pose,
  title: 'SPEC-075 · Botões',
  subtitle: '',
  status: status,
  needsYou: needsYou,
  error: error,
  lastAction: lastAction,
  action: action,
  specId: specId,
  specCode: 'SPEC-075',
  seed: seed,
  robotLabel: robotLabel,
);

Future<void> pump(WidgetTester tester, List<Activity> all, Widget child) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [activitiesProvider.overrideWith((ref) => all)],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );

void main() {
  test('the card shows a request first, then the turn, the gate, the PR, '
      'the queue; never a release or a server', () {
    final pr = act('pr:a', kind: ActivityKind.pr, pose: ActivityPose.watch);
    final gate = act(
      'gate:1',
      kind: ActivityKind.gate,
      pose: ActivityPose.gate,
    );
    final turn = act('session:a');
    final ask = act('session:b', needsYou: true, pose: ActivityPose.wave);
    expect(cardActivityOf([pr, gate], 1), gate);
    expect(cardActivityOf([pr, gate, turn], 1), turn);
    expect(cardActivityOf([pr, turn, ask], 1), ask);
    expect(cardActivityOf([pr], 2), isNull);
    expect(
      cardActivityOf([
        act('release:1', kind: ActivityKind.release, seed: null),
      ], 1),
      isNull,
    );
  });

  test('the bar counts the agents working and what needs you (R14)', () {
    final all = [
      act('a'),
      act('b', pose: ActivityPose.read),
      act('c', needsYou: true, pose: ActivityPose.wave),
      act('q', column: ActivityColumn.backlog, pose: ActivityPose.sleep),
      act('dev', kind: ActivityKind.dev, seed: null),
      act('other', ws: 2),
    ];
    expect(
      boardAgentsLabel(all, 1),
      '2 agentes trabalhando · 1 precisa de você',
    );
    expect(boardAgentsLabel(all, 2), '1 agente trabalhando');
    expect(boardAgentsLabel(const [], 1), '');
  });

  Widget robot(SpecStage stage) =>
      CardRobot(specId: 1, workspaceId: 1, code: 'SPEC-075', stage: stage);

  // One scope per test: a second ProviderScope in the same test keeps the
  // first one's override of the list.
  testWidgets('the robot of a running card, with its name (R13)', (
    tester,
  ) async {
    final a = act('session:a');
    await pump(tester, [a], robot(SpecStage.running));
    expect(find.byKey(const ValueKey('card-robot-SPEC-075')), findsOneWidget);
    expect(find.byKey(const ValueKey('robot-edit')), findsOneWidget);
    expect(find.text(RobotIdentity.of(a.seed!).name), findsOneWidget);
  });

  testWidgets('no robot in Feito (R12)', (tester) async {
    await pump(tester, [act('session:a')], robot(SpecStage.done));
    expect(find.byType(RobotAvatar), findsNothing);
  });

  testWidgets('no robot without an activity outside Review', (tester) async {
    await pump(tester, const [], robot(SpecStage.running));
    expect(find.byType(RobotAvatar), findsNothing);
  });

  testWidgets('Review with nothing live: waiting, with the clipboard', (
    tester,
  ) async {
    await pump(tester, const [], robot(SpecStage.review));
    expect(find.byKey(const ValueKey('robot-wait')), findsOneWidget);
  });

  testWidgets('the queue of the Autopilot: sleeping, "na fila"', (
    tester,
  ) async {
    await pump(tester, [
      act(
        'queue:1',
        kind: ActivityKind.queued,
        column: ActivityColumn.backlog,
        pose: ActivityPose.sleep,
        robotLabel: 'na fila',
      ),
    ], robot(SpecStage.backlog));
    expect(find.byKey(const ValueKey('robot-sleep')), findsOneWidget);
    expect(find.text('na fila'), findsOneWidget);
  });

  testWidgets('a request becomes a balloon with its button (R13)', (
    tester,
  ) async {
    await pump(
      tester,
      [
        act(
          'session:a',
          needsYou: true,
          pose: ActivityPose.wave,
          status: 'quer executar',
          lastAction: 'Bash flutter test',
          action: ActivityAction.respond,
        ),
      ],
      const SizedBox(
        width: 320,
        child: CardBalloon(specId: 1, code: 'SPEC-075'),
      ),
    );
    expect(find.byKey(const ValueKey('card-balloon-SPEC-075')), findsOneWidget);
    expect(find.textContaining('quer executar'), findsOneWidget);
    expect(find.textContaining('Bash flutter test'), findsOneWidget);
    expect(find.text('Responder'), findsOneWidget);
  });

  testWidgets('an error balloon has Retomar', (tester) async {
    await pump(
      tester,
      [
        act(
          'session:a',
          needsYou: true,
          error: true,
          pose: ActivityPose.error,
          status: 'sessão falhou',
          action: ActivityAction.resume,
        ),
      ],
      const SizedBox(
        width: 320,
        child: CardBalloon(specId: 1, code: 'SPEC-075'),
      ),
    );
    expect(find.textContaining('parou: sessão falhou'), findsOneWidget);
    expect(find.text('Retomar'), findsOneWidget);
  });

  testWidgets('no balloon without a request', (tester) async {
    await pump(tester, [
      act('session:a'),
    ], const CardBalloon(specId: 1, code: 'SPEC-075'));
    expect(find.byKey(const ValueKey('card-balloon-SPEC-075')), findsNothing);
  });

  testWidgets('the bar shows the count, the requests in amber', (tester) async {
    await pump(tester, [
      act('a'),
      act('c', needsYou: true, pose: ActivityPose.wave),
    ], const BoardAgentsCount(workspaceId: 1));
    final text = tester.widget<Text>(
      find.byKey(const ValueKey('board-agents')),
    );
    expect(
      text.textSpan!.toPlainText(),
      '1 agente trabalhando · 1 precisa de você',
    );
  });
}
