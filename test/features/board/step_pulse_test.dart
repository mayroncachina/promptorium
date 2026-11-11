import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/widgets/step_status_motion.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/theme/tokens.dart';

StepView step(StepStatus s, {bool failed = false}) => StepView(
  id: 'R1',
  text: 't',
  status: s,
  gate: failed
      ? GateReport(
          checks: const [GateCheck(name: 'testes', ok: false)],
          at: DateTime(2026),
        )
      : null,
);

/// SPEC-065: one colour per state and the pulse of the active step.
void main() {
  test('R1: the colour of each state', () {
    expect(stepSegmentColor(step(StepStatus.pending)), AppColors.border);
    expect(stepSegmentColor(step(StepStatus.running)), AppColors.amber);
    expect(stepSegmentColor(step(StepStatus.verifying)), AppColors.lilac);
    expect(stepSegmentColor(step(StepStatus.needsInput)), AppColors.amberLight);
    expect(stepSegmentColor(step(StepStatus.done)), AppColors.teal);
    final failed = step(StepStatus.needsInput, failed: true);
    expect(failed.gateFailed, isTrue);
    expect(stepSegmentColor(failed), AppColors.red);
    expect(isStepActive(failed), isFalse);
    // All different.
    final all = {
      for (final s in StepStatus.values) stepSegmentColor(step(s)),
      AppColors.red,
    };
    expect(all, hasLength(StepStatus.values.length + 1));
  });

  test('R2: only running and verifying are active', () {
    expect(isStepActive(step(StepStatus.running)), isTrue);
    expect(isStepActive(step(StepStatus.verifying)), isTrue);
    for (final s in [
      StepStatus.pending,
      StepStatus.needsInput,
      StepStatus.done,
    ]) {
      expect(isStepActive(step(s)), isFalse, reason: '$s');
    }
  });

  test('R5: the canvas paints verifying in purple too', () {
    expect(CanvasColors.verifying, AppColors.lilac);
  });

  group('StepPulse', () {
    setUp(() => AppMotion.enabled = true);
    tearDown(() => AppMotion.enabled = false);

    Widget host({required bool active, bool reduce = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: StepPulse(
          active: active,
          child: const SizedBox(width: 40, height: 5),
        ),
      ),
    );

    double opacity(WidgetTester tester) {
      final o = find.byType(Opacity);
      return o.evaluate().isEmpty ? 1 : tester.widget<Opacity>(o).opacity;
    }

    testWidgets('R2, R3: active it goes 1 → .4 → 1 in 1.2 s; off it stops '
        'fully opaque', (tester) async {
      await tester.pumpWidget(host(active: true));
      expect(opacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(opacity(tester), closeTo(.4, .01));
      await tester.pump(const Duration(milliseconds: 600));
      expect(opacity(tester), closeTo(1, .01));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity(tester), inExclusiveRange(.4, 1));

      await tester.pumpWidget(host(active: false));
      expect(find.byType(Opacity), findsNothing);
      // No ticker left running.
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('R4: with reduced motion nothing pulses', (tester) async {
      await tester.pumpWidget(host(active: true, reduce: true));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(Opacity), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
