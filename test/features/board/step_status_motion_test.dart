import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/widgets/spec_steps_panel.dart';
import 'package:promptorium/features/board/widgets/step_status_motion.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../../helpers/test_db.dart';

void _motionOn() {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
}

Widget _dot(Color color, {bool done = false, bool reduced = false}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: StepStatusDot(color: color, done: done),
        ),
      ),
    );

StepCheckPainter _painter(WidgetTester tester, [Finder? within]) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: within ?? find.byType(StepStatusDot),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as StepCheckPainter;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(AppMotion.base);
}

/// The steps panel of a spec whose R1 is stored as done and R2 as running.
Future<(ProviderContainer, Spec)> _pumpPanel(WidgetTester tester) async {
  final db = memoryDatabase();
  final ws = await db
      .into(db.workspaces)
      .insertReturning(
        WorkspacesCompanion.insert(path: '/work/repo', name: 'repo'),
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
          requirements: const Value([
            (id: 'R1', text: 'Um'),
            (id: 'R2', text: 'Dois'),
          ]),
        ),
      );
  for (final (step, status) in [
    ('R1', StepStatus.done),
    ('R2', StepStatus.running),
  ]) {
    await db
        .into(db.specSteps)
        .insert(
          SpecStepsCompanion.insert(
            specId: spec.id,
            step: step,
            status: Value(status),
          ),
        );
  }
  final c = ProviderContainer(overrides: [databaseOverride(db)]);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 620,
            height: 560,
            child: SpecStepsPanel(specId: spec.id),
          ),
        ),
      ),
    ),
  );
  return (c, spec);
}

Finder _dotOf(String step) => find.byKey(ValueKey('step-dot-$step'));

void main() {
  testWidgets('R9 · the colour moves to the new status in base', (
    tester,
  ) async {
    _motionOn();
    await tester.pumpWidget(_dot(AppColors.textMuted));
    expect(_painter(tester).color, AppColors.textMuted);

    await tester.pumpWidget(_dot(AppColors.teal));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(AppMotion.base ~/ 2);
    final midway = _painter(tester).color;
    expect(midway, isNot(AppColors.textMuted));
    expect(midway, isNot(AppColors.teal));
    expect(_painter(tester).progress.value, 0);

    await _settle(tester);
    expect(_painter(tester).color, AppColors.teal);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R9 · on concluding, the check draws itself once in base', (
    tester,
  ) async {
    _motionOn();
    await tester.pumpWidget(_dot(AppColors.teal));
    await tester.pumpWidget(_dot(AppColors.blue, done: true));
    expect(_painter(tester).progress.value, 0);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(AppMotion.base ~/ 2);
    expect(_painter(tester).progress.value, inExclusiveRange(0, 1));

    await _settle(tester);
    expect(_painter(tester).progress.value, 1);
    expect(tester.hasRunningAnimations, isFalse);

    // Another rebuild of the same state does not draw it again.
    await tester.pumpWidget(_dot(AppColors.blue, done: true));
    await tester.pump();
    expect(_painter(tester).progress.value, 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R9 · a step already done when it mounts shows the finished '
      'check', (tester) async {
    _motionOn();
    await tester.pumpWidget(_dot(AppColors.blue, done: true));
    expect(_painter(tester).progress.value, 1);
    expect(_painter(tester).color, AppColors.blue);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R11 · with reduced motion the final state shows at once', (
    tester,
  ) async {
    _motionOn();
    await tester.pumpWidget(_dot(AppColors.teal, reduced: true));
    await tester.pumpWidget(_dot(AppColors.blue, done: true, reduced: true));
    await tester.pump();
    expect(_painter(tester).progress.value, 1);
    expect(_painter(tester).color, AppColors.blue);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R12 · a new status interrupts the check and starts from where '
      'it is', (tester) async {
    _motionOn();
    await tester.pumpWidget(_dot(AppColors.teal));
    await tester.pumpWidget(_dot(AppColors.blue, done: true));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(AppMotion.base ~/ 2);
    final reached = _painter(tester).progress.value;

    await tester.pumpWidget(_dot(AppColors.textMuted));
    expect(_painter(tester).progress.value, reached);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_painter(tester).progress.value, closeTo(reached, .1));
    await _settle(tester);
    expect(_painter(tester).progress.value, 0);
    expect(_painter(tester).color, AppColors.textMuted);
  });

  testWidgets('R9 · opening the panel does not draw the checks of steps '
      'already done; concluding one there does', (tester) async {
    _motionOn();
    final (c, spec) = await _pumpPanel(tester);

    // Before the rows load every step reads as pending; watch every frame.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (_dotOf('R1').evaluate().isEmpty) continue;
      final t = _painter(tester, _dotOf('R1')).progress.value;
      expect(t, anyOf(0, 1));
    }
    expect(_painter(tester, _dotOf('R1')).progress.value, 1);
    expect(_painter(tester, _dotOf('R2')).progress.value, 0);
    expect(tester.hasRunningAnimations, isFalse);

    await c.read(specStepsRepoProvider).set(spec.id, 'R2', StepStatus.done);
    var midway = false;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      final t = _painter(tester, _dotOf('R2')).progress.value;
      if (t > 0 && t < 1) midway = true;
    }
    expect(midway, isTrue);
    expect(_painter(tester, _dotOf('R2')).progress.value, 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R9 · the status label changes colour in base, on the same '
      'row', (tester) async {
    _motionOn();
    final (c, spec) = await _pumpPanel(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    Color? label() => tester
        .widget<Text>(find.byKey(const ValueKey('step-status-R2')))
        .style
        ?.color;
    expect(label(), stepStatusColor(StepStatus.running));

    await c
        .read(specStepsRepoProvider)
        .set(spec.id, 'R2', StepStatus.needsInput);
    final seen = <Color?>{};
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      seen.add(label());
    }
    expect(seen.length, greaterThan(2));
    expect(label(), stepStatusColor(StepStatus.needsInput));
  });
}
