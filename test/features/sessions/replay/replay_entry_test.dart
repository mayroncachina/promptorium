import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart' show StepView;
import 'package:promptorium/features/board/widgets/spec_steps_panel.dart';
import 'package:promptorium/features/sessions/replay/replay_state.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/sessions_screen.dart';
import 'package:promptorium/features/specs/widgets/step_trace_panel.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../../helpers/test_db.dart';
import '../sessions_screen_test.dart' show pumpScreen, pumpFor;
import '../session_test_utils.dart';

/// A spec whose R1 ran in session s1, finished with [status].
Future<(ProviderContainer, Spec, Session)> _seed(SessionStatus status) async {
  final db = memoryDatabase();
  final ws = await db
      .into(db.workspaces)
      .insertReturning(
        WorkspacesCompanion.insert(path: '/work/repo', name: 'repo'),
      );
  await db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: AppSettingKeys.activeWorkspace,
          value: '${ws.id}',
        ),
      );
  final spec = await db
      .into(db.specs)
      .insertReturning(
        SpecsCompanion.insert(
          workspaceId: ws.id,
          code: 'SPEC-001',
          title: 'Base',
          path: 'specs/SPEC-001.md',
          status: const Value(SpecStatus.approved),
          requirements: const Value([(id: 'R1', text: 'Um')]),
        ),
      );
  final session = await db
      .into(db.sessions)
      .insertReturning(
        SessionsCompanion.insert(
          id: 's1',
          workspaceId: ws.id,
          worktreePath: '/work/repo-wt',
          branch: 'spec/001',
          model: 'sonnet',
          specId: Value(spec.id),
          status: Value(status),
        ),
      );
  await db
      .into(db.specSteps)
      .insert(
        SpecStepsCompanion.insert(
          specId: spec.id,
          step: 'R1',
          status: const Value(StepStatus.done),
          sessionId: const Value('s1'),
        ),
      );
  final c = ProviderContainer(
    overrides: sessionOverrides(
      db: db,
      cli: FakeCli(),
      notifier: FakeNotifier(),
    ),
  );
  addTearDown(c.dispose);
  await c.read(appSettingsProvider.notifier).load();
  return (c, spec, session);
}

Future<void> _pump(WidgetTester tester, ProviderContainer c, Widget body) =>
    tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: body),
        ),
      ),
    );

void _expectReplayOpened(ProviderContainer c) {
  expect(c.read(selectedSessionProvider), 's1');
  expect(c.read(sessionTabProvider('s1')), SessionTab.replay);
  expect(c.read(replayCursorProvider('s1')).index, isNull); // last step
  expect(c.read(navigationProvider), AppSection.sessions);
}

void main() {
  testWidgets('R12: session context menu opens Replay at its last step', (
    tester,
  ) async {
    await pumpScreen(tester);
    final tile = find.byKey(const ValueKey('session-tile-s1'));
    await tester.tap(tile, buttons: kSecondaryMouseButton);
    await pumpFor(tester);
    expect(find.text('Ver replay'), findsOneWidget);
    await tester.tap(find.text('Ver replay'));
    await pumpFor(tester, 20);
    expect(find.byKey(const ValueKey('replay-position')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-tab-replay')), findsOneWidget);
  });

  testWidgets('R12: "Ver replay" in the step menu of the board card', (
    tester,
  ) async {
    final (c, spec, _) = await tester.runAsync(
      () => _seed(SessionStatus.failed),
    ) as (ProviderContainer, Spec, Session);
    await _pump(
      tester,
      c,
      SizedBox(width: 620, height: 560, child: SpecStepsPanel(specId: spec.id)),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('step-menu-R1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver replay'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    _expectReplayOpened(c);
  });

  testWidgets('R12: "Ver replay" in the step trace of the Specs screen', (
    tester,
  ) async {
    final (c, spec, session) = await tester.runAsync(
      () => _seed(SessionStatus.failed),
    ) as (ProviderContainer, Spec, Session);
    await _pump(
      tester,
      c,
      SizedBox(
        width: 420,
        height: 800,
        child: StepTracePanel(
          spec: spec,
          step: const StepView(id: 'R1', text: 'Um', sessionId: 's1'),
          text: '# Base\n\n## Requisitos\n\n- R1 · Um\n',
          sessions: [session],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-trace-replay')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    _expectReplayOpened(c);
  });
}
