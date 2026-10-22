import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/widgets/spec_canvas.dart';

import 'canvas_fixture.dart';

/// SPEC-008 R2: nodes per wave, step dots, links and selection.
void main() {
  const specs = [
    CanvasSpec('SPEC-001', stage: SpecStage.done, steps: [StepStatus.done]),
    CanvasSpec('SPEC-002', steps: [StepStatus.pending], deps: ['SPEC-001']),
    CanvasSpec(
      'SPEC-003',
      stage: SpecStage.running,
      steps: [
        StepStatus.done,
        StepStatus.running,
        StepStatus.needsInput,
        StepStatus.verifying,
        StepStatus.pending,
      ],
      deps: ['SPEC-002'],
    ),
    CanvasSpec('SPEC-004', steps: [StepStatus.pending]),
  ];

  testWidgets('each spec sits in the column of its wave and every '
      'dependency is linked to the spec that waits for it', (tester) async {
    final (c, _) = await pumpCanvas(tester, specs);
    double x(String code) => tester.getTopLeft(byKey('board-open-$code')).dx;
    expect(x('SPEC-001'), x('SPEC-004')); // both in wave 1
    expect(x('SPEC-002'), greaterThan(x('SPEC-001')));
    expect(x('SPEC-003'), greaterThan(x('SPEC-002')));
    for (final w in [0, 1, 2]) {
      expect(byKey('board-wave-$w'), findsOneWidget);
    }
    final all = await tester.runAsync(
      () => c.read(specsRepoProvider).watchByWorkspace(1).first,
    );
    expect(dependencyLinks(all!), [
      ('SPEC-001', 'SPEC-002'),
      ('SPEC-002', 'SPEC-003'),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one dot per step in its state; waiting and verifying differ '
      'from pending and running also by shape', (tester) async {
    await pumpCanvas(tester, specs);
    StepStatus dot(String step) =>
        tester.widget<CanvasStepDot>(byKey('canvas-dot-SPEC-003-$step')).status;
    expect([
      for (final s in ['R1', 'R2', 'R3', 'R4', 'R5']) dot(s),
    ], specs[2].steps);
    expect(stepDotShape(StepStatus.needsInput), StepDotShape.diamond);
    expect(stepDotShape(StepStatus.verifying), StepDotShape.spinner);
    expect({
      for (final s in StepStatus.values) stepDotShape(s),
    }, hasLength(StepStatus.values.length));
  });

  testWidgets('hovering a step dot shows its id, state and requirement', (
    tester,
  ) async {
    await pumpCanvas(tester, specs);
    await hover(tester, byKey('canvas-dot-SPEC-003-R3'));
    expect(find.text(stepText('SPEC-003', 'R3')), findsOneWidget);
    expect(find.text('aguardando você'), findsWidgets);
  });

  testWidgets('selecting a spec dims what is not related; tapping the '
      'background clears the selection', (tester) async {
    final (c, _) = await pumpCanvas(tester, specs);
    double opacity(String code) =>
        tester.widget<AnimatedOpacity>(byKey('canvas-node-$code')).opacity;
    expect(opacity('SPEC-004'), 1);
    await selectSpec(tester, 'SPEC-002');
    expect(c.read(boardSelectedSpecProvider), isNotNull);
    expect(opacity('SPEC-002'), 1);
    expect(opacity('SPEC-001'), 1); // dependency
    expect(opacity('SPEC-003'), 1); // dependent
    expect(opacity('SPEC-004'), lessThan(1));
    await tester.tapAt(const Offset(700, 600));
    await pumpFor(tester, 20);
    expect(c.read(boardSelectedSpecProvider), isNull);
    expect(opacity('SPEC-004'), 1);
  });
}
