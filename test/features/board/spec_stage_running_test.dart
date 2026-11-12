import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/widgets/spec_canvas.dart';
import 'package:promptorium/ui/theme/motion.dart';

import 'canvas_fixture.dart';

Finder row(String code) => byKey('folder-row-$code');
Finder node(String code) => byKey('stage-node-$code');

const specs = [
  CanvasSpec(
    'SPEC-001',
    stage: SpecStage.running,
    steps: [StepStatus.done, StepStatus.running, StepStatus.pending],
  ),
  CanvasSpec(
    'SPEC-002',
    stage: SpecStage.running,
    steps: [StepStatus.needsInput, StepStatus.pending],
  ),
  CanvasSpec('SPEC-003', deps: ['SPEC-001']),
  CanvasSpec('SPEC-004', stage: SpecStage.done, steps: [StepStatus.done]),
];

Future<(ProviderContainer, AppDatabase)> pumpRunning(
  WidgetTester tester, [
  List<CanvasSpec> list = specs,
]) => pumpCanvas(
  tester,
  list,
  size: const Size(1440, 1000),
  view: BoardView.focus,
);

/// The clock only starts on the frame after the flights are set.
Future<void> land(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> showRunning(WidgetTester tester) async {
  await tester.tap(byKey('stage-running'));
  await pumpFor(tester);
}

Future<void> setSteps(
  WidgetTester tester,
  AppDatabase db,
  StepStatus from,
  StepStatus to,
) async {
  await tester.runAsync(
    () => (db.update(db.specSteps)..where((s) => s.status.equals(from.name)))
        .write(SpecStepsCompanion(status: Value(to))),
  );
  await pumpFor(tester, 20);
}

String stepOf(WidgetTester tester, String code) =>
    tester.widget<Text>(byKey('stage-step-$code')).data!;

void main() {
  group('R12 · Executando', () {
    test(
      'counts a live session or a step under way, never a finished spec',
      () {
        Session session(SessionStatus status) => Session(
          provider: 'claude',
          id: 's',
          workspaceId: 1,
          worktreePath: '/w',
          branch: 'b',
          model: 'm',
          status: status,
          startedAt: DateTime(2026),
          costUsd: 0,
          tokensIn: 0,
          tokensOut: 0,
        );
        Spec spec(SpecStage stage) => Spec(
          hasPlan: false,
          id: 1,
          workspaceId: 1,
          code: 'SPEC-001',
          title: 't',
          status: SpecStatus.approved,
          path: 'p',
          stage: stage,
          requirements: const [],
          dependsOn: const [],
          autoAdvance: false,
          reviewRounds: 0,
          gateResends: 0,
          rejectedHunks: 0,
        );
        SpecCardData card({
          SpecStage stage = SpecStage.running,
          List<StepView> steps = const [],
          List<Session> sessions = const [],
        }) => SpecCardData(
          spec: spec(stage),
          steps: steps,
          sessions: sessions,
          blockers: const [],
        );
        bool alive(String _) => true;
        bool dead(String _) => false;
        final live = [session(SessionStatus.running)];
        expect(isSpecRunning(card(sessions: live), alive: alive), isTrue);
        expect(isSpecRunning(card(sessions: live), alive: dead), isFalse);
        expect(
          isSpecRunning(
            card(sessions: [session(SessionStatus.completed)]),
            alive: alive,
          ),
          isFalse,
        );
        const verifying = [
          StepView(id: 'R1', text: '', status: StepStatus.verifying),
        ];
        expect(isSpecRunning(card(steps: verifying), alive: dead), isTrue);
        expect(
          isSpecRunning(
            card(stage: SpecStage.done, steps: verifying),
            alive: dead,
          ),
          isFalse,
        );
      },
    );

    testWidgets('shows the specs in execution side by side', (tester) async {
      await pumpRunning(tester);
      expect(find.text('Executando · 2'), findsOneWidget);
      await showRunning(tester);
      expect(node('SPEC-001'), findsOneWidget);
      expect(node('SPEC-002'), findsOneWidget);
      expect(node('SPEC-003'), findsNothing);
      expect(row('SPEC-001'), findsNothing);
      expect(row('SPEC-003'), findsOneWidget);
      expect(
        tester.getTopLeft(node('SPEC-001')).dy,
        tester.getTopLeft(node('SPEC-002')).dy,
      );
      expect(
        tester.widget<Text>(byKey('stage-crumb')).data,
        '2 specs em execução',
      );
    });

    testWidgets('without any, the button is off and says why', (tester) async {
      await pumpRunning(tester, const [CanvasSpec('SPEC-001')]);
      expect(find.text('Executando · 0'), findsOneWidget);
      final button = tester.widget<CanvasBarButton>(byKey('stage-running'));
      expect(button.onTap, isNull);
      expect(button.tooltip, 'Nenhuma spec em execução');
    });

    testWidgets('a new click, "Voltar à pasta" and Esc give them back', (
      tester,
    ) async {
      await pumpRunning(tester);
      await showRunning(tester);
      await showRunning(tester);
      expect(row('SPEC-001'), findsOneWidget);
      expect(byKey('stage-hint'), findsOneWidget);

      await showRunning(tester);
      await tester.tap(byKey('stage-back'));
      await pumpFor(tester);
      expect(row('SPEC-001'), findsOneWidget);

      await showRunning(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFor(tester);
      expect(row('SPEC-001'), findsOneWidget);
    });

    testWidgets('a click on a spec opens it with its dependents', (
      tester,
    ) async {
      await pumpRunning(tester);
      await showRunning(tester);
      await tester.tap(byKey('board-open-SPEC-001'));
      await pumpFor(tester);
      expect(node('SPEC-003'), findsOneWidget);
      expect(row('SPEC-002'), findsOneWidget);
      expect(byKey('stage-step-SPEC-001'), findsNothing);
      expect(byKey('stage-panel'), findsNothing);
    });
  });

  group('R13 · the card', () {
    testWidgets('shows the current step and the activity bar', (tester) async {
      AppMotion.enabled = true;
      addTearDown(() => AppMotion.enabled = false);
      await pumpRunning(tester);
      await tester.tap(byKey('stage-running'));
      await land(tester);
      expect(stepOf(tester, 'SPEC-001'), 'Etapa 2 de 3 · rodando');
      final bar = tester.widget<LinearProgressIndicator>(
        byKey('stage-activity-SPEC-001'),
      );
      expect(bar.value, isNull);
    });

    testWidgets('waiting for the person, shows the balloon and stops', (
      tester,
    ) async {
      AppMotion.enabled = true;
      addTearDown(() => AppMotion.enabled = false);
      await pumpRunning(tester);
      await tester.tap(byKey('stage-running'));
      await land(tester);
      expect(stepOf(tester, 'SPEC-002'), 'Etapa 1 de 2 · aguardando você');
      expect(byKey('stage-balloon-SPEC-002'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        byKey('stage-activity-SPEC-002'),
      );
      expect(bar.value, isNotNull);
    });

    testWidgets('updates by itself', (tester) async {
      final (_, db) = await pumpRunning(tester);
      await showRunning(tester);
      expect(stepOf(tester, 'SPEC-001'), 'Etapa 2 de 3 · rodando');
      await setSteps(tester, db, StepStatus.running, StepStatus.needsInput);
      expect(stepOf(tester, 'SPEC-001'), 'Etapa 2 de 3 · aguardando você');
      expect(byKey('stage-balloon-SPEC-001'), findsOneWidget);
    });

    testWidgets('out of execution, goes back to the folder and the count '
        'falls', (tester) async {
      final (_, db) = await pumpRunning(tester);
      await showRunning(tester);
      await setSteps(tester, db, StepStatus.running, StepStatus.done);
      expect(find.text('Executando · 1'), findsOneWidget);
      expect(node('SPEC-001'), findsNothing);
      expect(row('SPEC-001'), findsOneWidget);
      expect(node('SPEC-002'), findsOneWidget);

      await setSteps(tester, db, StepStatus.needsInput, StepStatus.done);
      expect(find.text('Executando · 0'), findsOneWidget);
      expect(row('SPEC-002'), findsOneWidget);
      expect(byKey('stage-hint'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the card flies back when it leaves, with motion on', (
      tester,
    ) async {
      AppMotion.enabled = true;
      addTearDown(() => AppMotion.enabled = false);
      final (_, db) = await pumpRunning(tester);
      await tester.tap(byKey('stage-running'));
      await land(tester);
      await tester.runAsync(
        () =>
            (db.update(
              db.specSteps,
            )..where((s) => s.status.equals(StepStatus.running.name))).write(
              const SpecStepsCompanion(status: Value(StepStatus.done)),
            ),
      );
      await tester.pump();
      await tester.pump();
      expect(byKey('stage-flight-SPEC-001'), findsOneWidget);
      await land(tester);
      expect(byKey('stage-flight-SPEC-001'), findsNothing);
      expect(row('SPEC-001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
