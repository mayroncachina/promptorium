import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/widgets/spec_canvas.dart';

import 'canvas_fixture.dart';

/// SPEC-030 R2, R5, R6, R9: one shared pulse for the cards that need the
/// person, until the step is resolved.
void main() {
  const specs = [
    CanvasSpec(
      'SPEC-001',
      stage: SpecStage.running,
      steps: [StepStatus.done, StepStatus.needsInput],
    ),
    CanvasSpec('SPEC-002', steps: [StepStatus.needsInput]),
    CanvasSpec(
      'SPEC-003',
      stage: SpecStage.running,
      steps: [StepStatus.running],
    ),
  ];

  Animation<double>? pulseOf(WidgetTester tester, String dot) =>
      tester.widget<CanvasStepDot>(byKey('canvas-dot-$dot')).pulse;

  testWidgets('two waiting cards share one 1.8 s clock; the bubble breathes '
      'with the ring and nothing else pulses (R2, R9)', (tester) async {
    await pumpCanvas(tester, specs);
    final a = pulseOf(tester, 'SPEC-001-R2');
    final b = pulseOf(tester, 'SPEC-002-R1');
    expect(a, isA<AnimationController>());
    expect(identical(a, b), isTrue);
    expect((a! as AnimationController).duration, attentionPulsePeriod);
    expect(attentionPulsePeriod, const Duration(milliseconds: 1800));
    expect((a as AnimationController).isAnimating, isTrue);
    // The bubble goes 1 → .55 → 1 over a cycle.
    expect(attentionBubbleOpacity(0), 1);
    expect(attentionBubbleOpacity(.5), closeTo(.55, 1e-9));
    expect(attentionBubbleOpacity(1), closeTo(1, 1e-9));
    // Running and pending steps are not on the attention clock.
    expect(pulseOf(tester, 'SPEC-003-R1'), isNull);
    expect(pulseOf(tester, 'SPEC-001-R1'), isNull);
    // No still glow while it pulses.
    expect(byKey('canvas-attention-still'), findsNothing);
  });

  testWidgets('selecting the spec does not stop the pulse; resolving the '
      'step does (R5)', (tester) async {
    final (_, db) = await pumpCanvas(tester, specs);
    await selectSpec(tester, 'SPEC-001');
    expect(pulseOf(tester, 'SPEC-001-R2'), isA<AnimationController>());
    expect(byKey('canvas-attention-SPEC-001'), findsOneWidget);

    await tester.runAsync(
      () =>
          (db.update(db.specSteps)
                ..where((s) => s.status.equals(StepStatus.needsInput.name)))
              .write(const SpecStepsCompanion(status: Value(StepStatus.done))),
    );
    await pumpFor(tester, 20);
    expect(byKey('canvas-attention-SPEC-001'), findsNothing);
    expect(byKey('canvas-attention-SPEC-002'), findsNothing);
    expect(pulseOf(tester, 'SPEC-001-R2'), isNull);
    expect(byKey('canvas-attention-still'), findsNothing);
  });

  testWidgets('with animations off no attention clock exists and the card '
      'keeps a still glow (R6)', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpCanvas(tester, specs);
    expect(pulseOf(tester, 'SPEC-001-R2'), isNull);
    expect(pulseOf(tester, 'SPEC-002-R1'), isNull);
    expect(byKey('canvas-attention-still'), findsNWidgets(2));
    expect(byKey('canvas-attention-SPEC-001'), findsOneWidget);
  });
}
