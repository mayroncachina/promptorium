import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/attention_shake.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/ui/theme/motion.dart';

import 'canvas_fixture.dart';

/// SPEC-054 R5: the card that needs the person shakes in the three views.
void main() {
  setUp(() => AppMotion.enabled = true);
  tearDown(() => AppMotion.enabled = false);

  const specs = [
    CanvasSpec(
      'SPEC-001',
      stage: SpecStage.running,
      steps: [StepStatus.done, StepStatus.needsInput],
    ),
    CanvasSpec(
      'SPEC-002',
      stage: SpecStage.running,
      steps: [StepStatus.running],
    ),
  ];

  /// Largest horizontal offset of each shaking card over one shake window.
  Future<Map<int, double>> window(WidgetTester tester) async {
    final most = <int, double>{};
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      for (final e in find.byType(AttentionShake).evaluate()) {
        final w = e.widget as AttentionShake;
        final t = find.descendant(
          of: find.byWidget(w),
          matching: find.byType(Transform),
        );
        for (final x in t.evaluate()) {
          final dx = (x.widget as Transform).transform.getTranslation().x;
          if (dx.abs() > (most[w.specId] ?? 0)) most[w.specId] = dx.abs();
        }
      }
    }
    return most;
  }

  for (final view in [BoardView.columns, BoardView.graph]) {
    testWidgets('${view.name}: only the card that needs the person shakes, '
        'every 5 s', (tester) async {
      final (_, db) = await pumpCanvas(tester, specs, view: view);
      final rows = (await tester.runAsync(() => db.select(db.specs).get()))!;
      final ids = {for (final s in rows) s.code: s.id};
      await tester.pump(attentionShakeInterval);
      final moved = await window(tester);
      expect(moved.keys, [ids['SPEC-001']]);
      expect(moved[ids['SPEC-001']], closeTo(3, .5));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('focus: the card on the stage shakes', (tester) async {
    final (_, db) = await pumpCanvas(tester, specs, view: BoardView.focus);
    final rows = (await tester.runAsync(() => db.select(db.specs).get()))!;
    final ids = {for (final s in rows) s.code: s.id};
    await tester.tap(find.byKey(const ValueKey('folder-row-SPEC-001')));
    await pumpFor(tester, 30);
    expect(find.byType(AttentionShake), findsWidgets);
    await tester.pump(attentionShakeInterval);
    final moved = await window(tester);
    expect(moved.keys, contains(ids['SPEC-001']));
    expect(moved.keys, isNot(contains(ids['SPEC-002'])));
    await tester.pumpWidget(const SizedBox());
  });
}
