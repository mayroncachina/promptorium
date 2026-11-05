import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/widgets/spec_canvas.dart';
import 'package:promptorium/features/board/widgets/spec_folder.dart';
import 'package:promptorium/features/board/widgets/spec_stage.dart';
import 'package:promptorium/ui/theme/motion.dart';

import 'canvas_fixture.dart';

Finder row(String code) => byKey('folder-row-$code');
Finder node(String code) => byKey('stage-node-$code');
Finder flight(String code) => byKey('stage-flight-$code');

void motionOn() {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
}

Spec spec(int id, List<String> deps) => Spec(
  id: id,
  workspaceId: 1,
  code: 'SPEC-${id.toString().padLeft(3, '0')}',
  title: 'Spec $id',
  status: SpecStatus.approved,
  path: 'specs/$id.md',
  stage: SpecStage.backlog,
  requirements: const [],
  dependsOn: deps,
  autoAdvance: false,
  reviewRounds: 0,
  gateResends: 0,
  rejectedHunks: 0,
);

/// 1 ← 2 ← 3 ← 4, and 4 also depends on 1 straight away; 5 stands alone.
const chain = [
  CanvasSpec('SPEC-001', title: 'Raiz'),
  CanvasSpec('SPEC-002', deps: ['SPEC-001']),
  CanvasSpec('SPEC-003', deps: ['SPEC-002']),
  CanvasSpec('SPEC-004', deps: ['SPEC-003', 'SPEC-001']),
  CanvasSpec('SPEC-005', title: 'Solta'),
];

Future<(ProviderContainer, AppDatabase)> pumpStage(
  WidgetTester tester, [
  List<CanvasSpec> specs = chain,
  Size size = const Size(1440, 1000),
]) => pumpCanvas(tester, specs, size: size, view: BoardView.focus);

Future<void> open(WidgetTester tester, String code) async {
  await tester.tap(row(code));
  await pumpFor(tester);
}

Future<void> esc(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await pumpFor(tester);
}

double scaleOf(WidgetTester tester) => tester
    .widget<InteractiveViewer>(byKey('stage-view'))
    .transformationController!
    .value
    .getMaxScaleOnAxis();

void main() {
  group('stageLayout · R9', () {
    test('each dependent is in the level of the longest path', () {
      final a = spec(1, []);
      final b = spec(2, ['SPEC-001']);
      final c = spec(3, ['SPEC-002']);
      final d = spec(4, ['SPEC-003', 'SPEC-001']);
      final other = spec(5, []);
      final l = stageLayout(a, [a, b, c, d, other]);
      expect(
        [
          for (final level in l.levels) [for (final s in level) s.id],
        ],
        [
          [1],
          [2],
          [3],
          [4],
        ],
      );
      expect(l.dependents, 3);
      final skip = l.edges.singleWhere((e) => e.skips);
      expect((skip.from.id, skip.to.id), (1, 4));
    });

    test('specs of a level stay side by side, oldest first', () {
      final a = spec(1, []);
      final l = stageLayout(a, [
        a,
        spec(3, ['SPEC-001']),
        spec(2, ['SPEC-001']),
      ]);
      expect([for (final s in l.levels[1]) s.id], [2, 3]);
    });

    test('a cycle and an unknown code end, without looping', () {
      final a = spec(1, ['SPEC-002']);
      final b = spec(2, ['SPEC-001', 'SPEC-999']);
      final l = stageLayout(a, [a, b]);
      expect(l.levels.length, 2);
      expect(l.edges.length, 1);
    });

    test('a spec without dependents is alone', () {
      final a = spec(1, []);
      final l = stageLayout(a, [a, spec(2, [])]);
      expect(l.dependents, 0);
      expect(l.edges, isEmpty);
    });

    test('the cascade is 90 ms per level and 45 ms per card', () {
      expect(stageCardDelay(0, 0), Duration.zero);
      expect(stageCardDelay(1, 0), const Duration(milliseconds: 90));
      expect(stageCardDelay(2, 3), const Duration(milliseconds: 315));
    });
  });

  group('stageGeometry · R10', () {
    final a = spec(1, []);
    final b = spec(2, ['SPEC-001']);
    final c = spec(3, ['SPEC-001']);
    final d = spec(4, ['SPEC-002', 'SPEC-003', 'SPEC-001']);
    final e = spec(5, ['SPEC-004', 'SPEC-001', 'SPEC-002']);
    final g = stageGeometry(
      stageLayout(a, [a, b, c, d, e]),
      (_) => stageCardSize,
    );

    test('levels go down and the cards of a level do not touch', () {
      expect(g.rects[2]!.top, greaterThan(g.rects[1]!.bottom));
      expect(g.rects[2]!.top, g.rects[3]!.top);
      expect(g.rects[3]!.left, greaterThan(g.rects[2]!.right));
    });

    test('an arrow that skips a level goes around the cards in between', () {
      final skips = g.arrows.where((x) => x.edge.skips).toList();
      expect(skips, hasLength(3));
      for (final arrow in skips) {
        for (final PathMetric m in arrow.path.computeMetrics()) {
          for (var at = 0.0; at <= m.length; at += 2) {
            final p = m.getTangentForOffset(at)!.position;
            for (final entry in g.rects.entries) {
              if (entry.key == arrow.edge.from.id ||
                  entry.key == arrow.edge.to.id) {
                continue;
              }
              expect(
                entry.value.contains(p),
                isFalse,
                reason:
                    '${arrow.edge.from.code}→${arrow.edge.to.code} '
                    'crosses ${entry.key} at $p',
              );
            }
          }
        }
      }
    });

    test('each dependency has its arrow, ending on the top of the card', () {
      expect(g.arrows, hasLength(g.layout.edges.length));
      for (final arrow in g.arrows) {
        expect(arrow.tip.dy, g.rects[arrow.edge.to.id]!.top);
      }
      expect(g.bounds.contains(g.arrows.last.tip - const Offset(0, 1)), isTrue);
    });
  });

  group('R8 · to the stage', () {
    testWidgets('a click takes the spec and its dependents out of the folder', (
      tester,
    ) async {
      await pumpStage(tester);
      expect(tester.widget<Text>(byKey('folder-count')).data, '5');
      await open(tester, 'SPEC-001');
      for (final c in ['SPEC-001', 'SPEC-002', 'SPEC-003', 'SPEC-004']) {
        expect(node(c), findsOneWidget);
        expect(row(c), findsNothing);
      }
      expect(row('SPEC-005'), findsOneWidget);
      expect(node('SPEC-005'), findsNothing);
      expect(tester.widget<Text>(byKey('folder-count')).data, '1');
      expect(byKey('stage-hint'), findsNothing);
    });

    testWidgets('a dependent becomes the center, the old center goes back', (
      tester,
    ) async {
      await pumpStage(tester);
      await open(tester, 'SPEC-001');
      await tester.tap(byKey('board-open-SPEC-003'));
      await pumpFor(tester);
      expect(row('SPEC-001'), findsOneWidget);
      expect(row('SPEC-002'), findsOneWidget);
      expect(node('SPEC-003'), findsOneWidget);
      expect(node('SPEC-004'), findsOneWidget);
      expect(
        tester.getTopLeft(node('SPEC-003')).dy,
        lessThan(tester.getTopLeft(node('SPEC-004')).dy),
      );
    });

    testWidgets('the remaining lines close the gap', (tester) async {
      await pumpStage(tester, const [
        CanvasSpec('SPEC-003'),
        CanvasSpec('SPEC-002'),
        CanvasSpec('SPEC-001'),
      ]);
      final first = tester.getTopLeft(row('SPEC-003')).dy;
      await open(tester, 'SPEC-002');
      expect(tester.getTopLeft(row('SPEC-001')).dy, first + folderRowStride);
      await esc(tester);
      expect(row('SPEC-002'), findsOneWidget);
      expect(tester.getTopLeft(row('SPEC-003')).dy, first);
    });

    testWidgets('it flies from the folder, in 420 ms', (tester) async {
      motionOn();
      await pumpStage(tester);
      final start = tester.getCenter(row('SPEC-005'));
      await tester.tap(row('SPEC-005'));
      await tester.pump();
      await tester.pump();
      expect(flight('SPEC-005'), findsOneWidget);
      final transform = tester.widget<Transform>(flight('SPEC-005'));
      final x = transform.transform.getTranslation().x;
      expect(x, lessThan(start.dx));
      await tester.pump(const Duration(milliseconds: 400));
      expect(flight('SPEC-005'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 20));
      expect(flight('SPEC-005'), findsNothing);
      expect(AppMotion.stage, const Duration(milliseconds: 420));
    });
  });

  group('R9 · dependents', () {
    testWidgets('go down in levels under the center', (tester) async {
      await pumpStage(tester);
      await open(tester, 'SPEC-001');
      final tops = [
        for (final c in ['SPEC-001', 'SPEC-002', 'SPEC-003', 'SPEC-004'])
          tester.getTopLeft(node(c)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(
        tester.widget<Text>(byKey('stage-crumb')).data,
        '3 specs dependem de SPEC-001',
      );
    });

    testWidgets('without dependents, says so', (tester) async {
      await pumpStage(tester);
      await open(tester, 'SPEC-005');
      expect(find.text('Nenhuma spec depende de SPEC-005'), findsOneWidget);
    });

    testWidgets('a dependent hidden from the folder is still on the stage', (
      tester,
    ) async {
      await pumpStage(tester, const [
        CanvasSpec('SPEC-001'),
        CanvasSpec('SPEC-002', deps: ['SPEC-001'], stage: SpecStage.done),
      ]);
      await tester.tap(byKey('board-filter-hide-done'));
      await pumpFor(tester);
      await open(tester, 'SPEC-001');
      expect(node('SPEC-002'), findsOneWidget);
    });
  });

  group('R10 · arrows', () {
    testWidgets('are drawn after the card arrives', (tester) async {
      motionOn();
      await pumpStage(tester);
      await tester.tap(row('SPEC-001'));
      await tester.pump();
      await tester.pump();
      StageArrowsPainter painter() =>
          tester.widget<CustomPaint>(byKey('stage-arrows')).painter
              as StageArrowsPainter;
      final first = painter().arrows.first;
      expect(painter().progress(first), 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(painter().progress(first), 0, reason: 'the card is in the air');
      await tester.pump(const Duration(milliseconds: 300));
      expect(painter().progress(first), greaterThan(0));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(painter().progress(first), 1);
    });
  });

  group('R11 · what the Canvas has', () {
    testWidgets('zoom by the keyboard and "Ajustar"', (tester) async {
      await pumpStage(tester);
      await open(tester, 'SPEC-001');
      expect(scaleOf(tester), 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await pumpFor(tester);
      expect(scaleOf(tester), closeTo(.9, .001));
      await tester.tap(byKey('stage-fit'));
      await pumpFor(tester);
      expect(scaleOf(tester), 1);
    });

    testWidgets('frames all the cards when they do not fit', (tester) async {
      await pumpStage(tester, [
        const CanvasSpec('SPEC-001'),
        for (var i = 2; i < 12; i++)
          CanvasSpec(
            'SPEC-${i.toString().padLeft(3, '0')}',
            deps: const ['SPEC-001'],
          ),
      ]);
      await open(tester, 'SPEC-001');
      expect(scaleOf(tester), lessThan(1));
      final view = tester.getRect(byKey('stage-view'));
      for (var i = 2; i < 12; i++) {
        final r = tester.getRect(node('SPEC-${i.toString().padLeft(3, '0')}'));
        expect(view.contains(r.topLeft), isTrue);
        expect(view.contains(r.bottomRight), isTrue);
      }
    });

    testWidgets('"Voltar à pasta" and Esc empty the stage', (tester) async {
      await pumpStage(tester);
      await open(tester, 'SPEC-001');
      await tester.tap(byKey('stage-back'));
      await pumpFor(tester);
      expect(row('SPEC-001'), findsOneWidget);
      expect(byKey('stage-hint'), findsOneWidget);
      await open(tester, 'SPEC-001');
      await esc(tester);
      expect(byKey('stage-hint'), findsOneWidget);
    });

    testWidgets('keeps the balloon of the steps and the halo', (tester) async {
      await pumpStage(tester, const [
        CanvasSpec(
          'SPEC-001',
          stage: SpecStage.running,
          steps: [StepStatus.needsInput],
        ),
      ]);
      await open(tester, 'SPEC-001');
      expect(
        find.descendant(
          of: node('SPEC-001'),
          matching: find.byType(AttentionHalo),
        ),
        findsOneWidget,
      );
      expect(byKey('canvas-step-SPEC-001-R1'), findsOneWidget);
      expect(byKey('stage-attention-SPEC-001'), findsOneWidget);
      await tester.tap(byKey('canvas-step-SPEC-001-R1'));
      await pumpFor(tester, 20);
      expect(byKey('stage-panel'), findsNothing);
      expect(find.byType(Dialog), findsWidgets);
    });
  });

  group('R17 · depends on', () {
    testWidgets('lists the dependencies and each one goes to the center', (
      tester,
    ) async {
      await pumpStage(tester);
      await open(tester, 'SPEC-004');
      expect(byKey('stage-depends'), findsOneWidget);
      expect(find.text('Depende de'), findsOneWidget);
      expect(
        tester.getBottomLeft(byKey('stage-depends')).dy,
        lessThanOrEqualTo(tester.getTopLeft(node('SPEC-004')).dy),
      );
      await tester.tap(byKey('stage-dep-SPEC-003'));
      await pumpFor(tester);
      expect(row('SPEC-003'), findsNothing);
      expect(
        tester.getTopLeft(node('SPEC-003')).dy,
        lessThan(tester.getTopLeft(node('SPEC-004')).dy),
      );
    });

    testWidgets('does not show without dependencies', (tester) async {
      await pumpStage(tester);
      await open(tester, 'SPEC-001');
      expect(byKey('stage-depends'), findsNothing);
    });
  });

  group('R18 · panel', () {
    testWidgets('a click on the center opens it, Esc closes it first', (
      tester,
    ) async {
      await pumpStage(tester);
      await open(tester, 'SPEC-001');
      final center = tester.getCenter(node('SPEC-001')).dx;
      expect(byKey('stage-panel'), findsNothing);
      await tester.tap(byKey('board-open-SPEC-001'));
      await pumpFor(tester);
      expect(byKey('stage-panel'), findsOneWidget);
      expect(tester.getCenter(node('SPEC-001')).dx, lessThan(center));
      await esc(tester);
      expect(byKey('stage-panel'), findsNothing);
      expect(node('SPEC-001'), findsOneWidget);
      await esc(tester);
      expect(byKey('stage-hint'), findsOneWidget);
    });

    testWidgets('a card open in the columns comes open here', (tester) async {
      final (c, _) = await pumpCanvas(tester, chain, view: BoardView.columns);
      final ws = c.read(activeWorkspaceProvider)!.id;
      final id =
          (await c.read(specsRepoProvider).getByCode(ws, 'SPEC-001'))!.id;
      c.read(boardSelectedSpecProvider.notifier).select(id);
      await pumpFor(tester);
      await tester.tap(byKey('board-view-focus'));
      await pumpFor(tester);
      expect(node('SPEC-001'), findsOneWidget);
      expect(byKey('stage-panel'), findsOneWidget);
    });
  });

  group('R14 · animations off', () {
    testWidgets('everything goes straight to the final state', (tester) async {
      motionOn();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpStage(tester, [
        ...chain,
        const CanvasSpec('SPEC-006', stage: SpecStage.running),
      ]);
      expect(
        tester.widget<CircularProgressIndicator>(byKey('folder-spinner')).value,
        isNotNull,
      );
      await tester.tap(row('SPEC-001'));
      await tester.pump();
      expect(flight('SPEC-001'), findsNothing);
      expect(node('SPEC-001'), findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(byKey('stage-arrows')).painter
              as StageArrowsPainter;
      expect(painter.progress(painter.arrows.first), 1);
    });
  });

  group('R15 · interruptions', () {
    testWidgets('a card in the air takes the click', (tester) async {
      motionOn();
      await pumpStage(tester);
      await tester.tap(row('SPEC-001'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(flight('SPEC-003'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: node('SPEC-003'),
          matching: byKey('board-open-SPEC-003'),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(row('SPEC-001'), findsOneWidget);
      expect(
        tester.getTopLeft(node('SPEC-003')).dy,
        lessThan(tester.getTopLeft(node('SPEC-004')).dy),
      );
    });

    testWidgets('Esc in the air goes back from where the card is', (
      tester,
    ) async {
      motionOn();
      await pumpStage(tester);
      await tester.tap(row('SPEC-005'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      double x() => tester
          .widget<Transform>(flight('SPEC-005'))
          .transform
          .getTranslation()
          .x;
      final there = x();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(x(), closeTo(there, .5));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(flight('SPEC-005'), findsNothing);
      expect(row('SPEC-005'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving the view in the air breaks nothing', (tester) async {
      motionOn();
      final (c, _) = await pumpStage(tester);
      await tester.tap(row('SPEC-001'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      c.read(boardGraphViewProvider.notifier).set(BoardView.columns);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('R16 · no overflow at the minimum size', (tester) async {
    await tester.runAsync(loadAppFonts);
    await pumpStage(tester, chain, minimumBoard);
    await open(tester, 'SPEC-001');
    expect(tester.takeException(), isNull);
    await tester.tap(byKey('board-open-SPEC-001'));
    await pumpFor(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(byKey('folder-toggle'));
    await pumpFor(tester);
    expect(tester.takeException(), isNull);
  });
}
