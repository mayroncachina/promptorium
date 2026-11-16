import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/activities_screen.dart';
import 'package:promptorium/features/activities/activities_state.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/activities/automation_pause.dart';
import 'package:promptorium/features/activities/quota_forecast.dart';
import 'package:promptorium/features/home/home_inbox.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

final t0 = DateTime.now().subtract(const Duration(minutes: 42));

Activity act(
  String id, {
  int ws = 1,
  String wsName = 'promptorium',
  ActivityKind kind = ActivityKind.spec,
  ActivityColumn column = ActivityColumn.running,
  ActivityPose pose = ActivityPose.edit,
  String title = 'SPEC-075 · Botões na largura',
  String status = 'Editando · R2',
  bool needsYou = false,
  bool error = false,
  ActivityAction action = ActivityAction.stop,
  String? sessionId,
  int? specId,
  String? seed = 'spec:1:SPEC-075',
  DateTime? startedAt,
}) => Activity(
  id: id,
  workspaceId: ws,
  workspaceName: wsName,
  kind: kind,
  column: column,
  pose: pose,
  title: title,
  subtitle: 'Em execução · etapa 2 de 3',
  status: status,
  tone: error
      ? ActivityTone.error
      : needsYou
      ? ActivityTone.attention
      : ActivityTone.normal,
  needsYou: needsYou,
  error: error,
  progress: (value: .5, label: 'etapa 2 de 3'),
  startedAt: startedAt ?? t0,
  lastAction: 'Edit lib/review_screen.dart',
  calls: 38,
  files: 7,
  action: action,
  sessionId: sessionId,
  specId: specId,
  specCode: title.split(' · ').first,
  seed: seed,
  model: 'opus',
  mode: 'acceptEdits',
  branch: 'spec/075-t2',
  tasks: const [
    (id: 'R1', done: true, current: false),
    (id: 'R2', done: false, current: true),
  ],
  recent: [(at: t0, label: 'Edit lib/review_screen.dart')],
  lastText: 'Comecei pelo componente.',
  weight: .09,
);

final sample = [
  act('session:a', sessionId: 'a', specId: 1),
  act(
    'session:b',
    sessionId: 'b',
    specId: 2,
    title: 'SPEC-073 · Corrigir CI',
    status: 'quer executar',
    pose: ActivityPose.wave,
    column: ActivityColumn.review,
    needsYou: true,
    action: ActivityAction.respond,
    seed: 'spec:1:SPEC-073',
  ),
  act(
    'pr:c',
    kind: ActivityKind.pr,
    sessionId: 'c',
    title: '#246 · Acompanhar PR',
    status: 'próxima conferência',
    pose: ActivityPose.watch,
    column: ActivityColumn.review,
    action: ActivityAction.now,
    seed: 'spec:1:SPEC-074',
  ),
  act(
    'dev:/r',
    ws: 2,
    wsName: 'loja-da-ana',
    kind: ActivityKind.dev,
    title: 'npm run dev',
    status: 'no ar',
    seed: null,
  ),
  act(
    'queue:9',
    ws: 3,
    wsName: 'api-frete',
    kind: ActivityKind.queued,
    column: ActivityColumn.backlog,
    pose: ActivityPose.sleep,
    title: 'SPEC-004 · Reenvio',
    status: 'espera SPEC-003',
    action: ActivityAction.none,
    seed: 'spec:3:SPEC-004',
  ),
  act(
    'session:e',
    ws: 3,
    wsName: 'api-frete',
    sessionId: 'e',
    title: 'SPEC-003 · Webhook',
    status: 'sessão falhou',
    pose: ActivityPose.error,
    needsYou: true,
    error: true,
    action: ActivityAction.resume,
    seed: 'spec:3:SPEC-003',
  ),
];

class _Pause extends AutomationPause {
  @override
  bool build() => false;

  @override
  Future<void> set(bool paused) async => state = paused;
}

class FakeSitter extends PrBabysitter {
  final checked = <String>[];

  @override
  Map<String, PrWatch> build() => const {};

  @override
  Future<void> check(String sessionId) async => checked.add(sessionId);
}

class FakeManager extends SessionManager {
  final stopped = <String>[];

  @override
  SessionManagerState build() => const SessionManagerState();

  @override
  Future<void> stop(String id) async => stopped.add(id);
}

late FakeSitter sitter;
late FakeManager manager;

Future<ProviderContainer> pumpScreen(
  WidgetTester tester, {
  List<Activity>? items,
  bool reduce = true,
}) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final all = items ?? sample;
  sitter = FakeSitter();
  manager = FakeManager();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseOverride(memoryDatabase()),
        activitiesSnapshotProvider.overrideWith(
          (ref) => (
            items: all,
            labels: const {1: 'Autopilot 2/3'},
            order: const [1, 2, 3],
          ),
        ),
        automationPausedProvider.overrideWith(_Pause.new),
        quotaSamplesProvider.overrideWith(_Samples.new),
        prBabysitterProvider.overrideWith(() => sitter),
        sessionManagerProvider.overrideWith(() => manager),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(1366, 768),
            disableAnimations: reduce,
          ),
          child: const Scaffold(body: ActivitiesScreen()),
        ),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(ActivitiesScreen)),
  );
}

class _Samples extends QuotaSamples {
  @override
  List<QuotaSample> build() {
    final now = DateTime.now();
    final resets = now.add(const Duration(hours: 3));
    return [
      (
        at: now.subtract(const Duration(minutes: 30)),
        used: .5,
        resetsAt: resets,
      ),
      (at: now, used: .62, resetsAt: resets),
    ];
  }
}

List<String> rowIds(WidgetTester tester) => [
  for (final e
      in find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('activity-') &&
                !(w.key! as ValueKey<String>).value.startsWith(
                  'activity-action',
                ) &&
                !(w.key! as ValueKey<String>).value.startsWith(
                  'activity-panel',
                ),
          )
          .evaluate())
    (e.widget.key! as ValueKey<String>).value.substring('activity-'.length),
];

void main() {
  testWidgets('groups with a request or an error go up; inside, what needs '
      'you first; the tabs count (R6, R17, R18)', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Atividades'), findsOneWidget);
    expect(rowIds(tester), [
      'session:b',
      'session:a',
      'pr:c',
      'session:e',
      'queue:9',
      'dev:/r',
    ]);
    expect(find.byKey(const ValueKey('activities-group-1')), findsOneWidget);
    expect(find.text('Autopilot 2/3'), findsOneWidget);
    expect(find.text('3 · 1 precisa de você'), findsOneWidget);
    String count(String tab) => tester
        .widget<Text>(find.byKey(ValueKey('activities-count-$tab')))
        .data!;
    expect(count('all'), '6');
    expect(count('needsYou'), '2');
    expect(count('backlog'), '1');
    expect(count('running'), '3');
    expect(count('review'), '2');
    // The quota with the forecast (R7, R16).
    expect(find.text('neste ritmo, acaba em 1 h 35'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
  });

  testWidgets('the tabs filter; "Agrupar por: Nenhum" drops the groups', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('activities-tab-needsYou')));
    await tester.pump();
    expect(rowIds(tester), ['session:b', 'session:e']);
    await tester.tap(find.byKey(const ValueKey('activities-tab-backlog')));
    await tester.pump();
    expect(rowIds(tester), ['queue:9']);
    await tester.tap(find.byKey(const ValueKey('activities-tab-all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('activities-group-by')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nenhum').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activities-group-1')), findsNothing);
    expect(rowIds(tester).first, 'session:b');
    expect(find.textContaining('loja-da-ana · '), findsOneWidget);
  });

  testWidgets('the panel shows the selected one; ↑/↓ move it (R20, R21)', (
    tester,
  ) async {
    await pumpScreen(tester);
    // Nothing picked: the first line.
    expect(
      find.byKey(const ValueKey('activity-panel-session:b')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('activity-session:a')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('activity-panel-session:a')),
      findsOneWidget,
    );
    expect(find.text('spec/075-t2'), findsOneWidget);
    expect(find.text('≈ 9%'), findsOneWidget);
    expect(find.text('38 chamadas · 7 arquivos'), findsOneWidget);
    expect(find.text('"Comecei pelo componente."'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-panel-tasks')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const ValueKey('activity-panel-pr:c')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('activity-panel-session:b')),
      findsOneWidget,
    );
    // Each line says what it is (R21).
    expect(
      find.bySemanticsLabel(
        RegExp('SPEC-075 · Botões na largura, em execução'),
      ),
      findsWidgets,
    );
  });

  testWidgets('Responder opens the session; Agora checks the PR; Parar asks '
      'first (R19, P9)', (tester) async {
    final c = await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('activity-action-pr:c')));
    await tester.pump();
    expect(sitter.checked, ['c']);

    await tester.tap(find.byKey(const ValueKey('activity-action-session:a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-stop-dialog')), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(manager.stopped, isEmpty);
    await tester.tap(find.byKey(const ValueKey('activity-action-session:a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-stop-confirm')));
    await tester.pumpAndSettle();
    expect(manager.stopped, ['a']);

    await tester.tap(find.byKey(const ValueKey('activity-action-session:b')));
    await tester.pumpAndSettle();
    expect(c.read(navigationProvider), AppSection.sessions);
    expect(c.read(selectedSessionProvider), 'b');
  });

  testWidgets('"Pausar automáticos" toggles the switch (R8, R16)', (
    tester,
  ) async {
    final c = await pumpScreen(tester);
    expect(find.text('Pausar automáticos'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('activities-pause')));
    await tester.pump();
    expect(c.read(automationPausedProvider), isTrue);
    expect(find.text('Retomar automáticos'), findsOneWidget);
  });

  testWidgets('nothing running: the empty state and the Quadro (R22)', (
    tester,
  ) async {
    final c = await pumpScreen(tester, items: const []);
    expect(find.byKey(const ValueKey('activities-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('activities-empty-board')));
    await tester.pump();
    expect(c.read(navigationProvider), AppSection.tasks);
  });

  testWidgets('the Quadro\'s robot opens the Atividades on its line (R23)', (
    tester,
  ) async {
    final c = await pumpScreen(tester);
    openActivitiesIn(c, 'pr:c');
    await tester.pump();
    expect(c.read(navigationProvider), AppSection.activities);
    expect(find.byKey(const ValueKey('activity-panel-pr:c')), findsOneWidget);
  });

  test('the menu badge counts what needs you in every workspace (R15)', () {
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        activitiesProvider.overrideWith((ref) => sample),
        activeWorkspaceProvider.overrideWithValue(
          Workspace(id: 1, path: '/r', name: 'r', createdAt: DateTime(2026)),
        ),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(navBadgesProvider)[AppSection.activities], 2);
    expect(AppSection.navItems[1], AppSection.activities);
    expect(AppSection.activities.shortcutLabel, isNull);
    expect(AppSection.agents.shortcutLabel, 'Ctrl 0');
  });

  testWidgets('screenshot (moving robots)', (tester) async {
    await pumpScreen(tester, reduce: false);
    await tester.pump(const Duration(milliseconds: 600));
    final file = Platform.environment['ATIVIDADES_PNG'];
    if (file == null) return;
    await tester.runAsync(() async {
      final b = tester.renderObject(find.byType(ActivitiesScreen)) as RenderBox;
      final rb = b is RenderRepaintBoundary
          ? b
          : tester.renderObject<RenderRepaintBoundary>(
              find
                  .ancestor(
                    of: find.byType(ActivitiesScreen),
                    matching: find.byType(RepaintBoundary),
                  )
                  .first,
            );
      final img = await rb.toImage();
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File(file).writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
