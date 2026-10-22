import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/spec_references.dart';
import 'package:promptorium/features/board/widgets/canvas_view_controller.dart';
import 'package:promptorium/features/board/widgets/run_spec_dialog.dart';
import 'package:promptorium/features/board/widgets/spec_canvas.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/ui/shell/navigation.dart';

import 'canvas_fixture.dart';

double scaleOf(WidgetTester tester) => tester
    .widget<InteractiveViewer>(byKey('board-graph'))
    .transformationController!
    .value
    .getMaxScaleOnAxis();

Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await pumpFor(tester, 5);
}

Future<void> wheel(
  WidgetTester tester,
  double dy, {
  bool control = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  final mouse = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(mouse.hover(const Offset(700, 600)));
  await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await pumpFor(tester, 5);
}

/// Lets the real file reads of the details providers finish.
Future<void> settleFiles(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await pumpFor(tester, 2);
  }
}

void main() {
  test('zoom starts at 100%, clamps, resets and centers selection', () {
    final view = CanvasViewController()..viewport = const Size(1000, 700);
    addTearDown(view.dispose);
    expect(view.scale, 1);
    for (var i = 0; i < 20; i++) {
      view.zoomIn();
    }
    expect(view.scale, 1.5);
    for (var i = 0; i < 20; i++) {
      view.zoomOut();
    }
    expect(view.scale, .5);
    view.reset();
    expect(view.scale, 1);
    const rect = Rect.fromLTWH(300, 500, 250, 116);
    view.fitSelection(rect);
    expect(view.scale, 1.3);
    expect(
      view.toScene(const Offset(500, 350)).dx,
      closeTo(rect.center.dx, .001),
    );
    expect(
      view.toScene(const Offset(500, 350)).dy,
      closeTo(rect.center.dy, .001),
    );
  });

  test('only executed Skill tools count, not available init skills', () {
    expect(
      loadedSkills({
        'type': 'system',
        'skills': ['available'],
      }),
      isEmpty,
    );
    expect(
      loadedSkills({
        'message': {
          'content': [
            {
              'type': 'tool_use',
              'name': 'Skill',
              'input': {'skill': 'used'},
            },
            {
              'type': 'tool_use',
              'name': 'Read',
              'input': {'skill': 'wrong'},
            },
            {
              'type': 'tool_use',
              'name': 'Skill',
              'input': {'skill': 'used'},
            },
          ],
        },
      }),
      {'used'},
    );
  });

  group('R1 · movimento e zoom', () {
    final specs = [
      for (var i = 1; i <= 8; i++)
        CanvasSpec(
          'SPEC-00$i',
          deps: i > 1 && i.isEven ? ['SPEC-00${i - 1}'] : const [],
        ),
    ];

    testWidgets('opens at 100%; Ctrl + wheel zooms within 50–150% and the '
        'plain wheel moves', (tester) async {
      await pumpCanvas(tester, specs);
      expect(scaleOf(tester), 1);
      for (var i = 0; i < 15; i++) {
        await wheel(tester, -40, control: true);
      }
      expect(scaleOf(tester), closeTo(1.5, .001));
      for (var i = 0; i < 15; i++) {
        await wheel(tester, 40, control: true);
      }
      expect(scaleOf(tester), closeTo(.5, .001));
      final view = tester
          .widget<InteractiveViewer>(byKey('board-graph'))
          .transformationController!;
      final before = view.value.getTranslation().y;
      await wheel(tester, 120);
      expect(scaleOf(tester), closeTo(.5, .001));
      expect(view.value.getTranslation().y, before - 120);
    });

    testWidgets('the zoom menu has its five items; fit to screen shows every '
        'node and fit to selection centers it', (tester) async {
      await pumpCanvas(tester, specs);
      await tester.tap(find.text('100% ▾'));
      await pumpFor(tester);
      for (final item in [
        'Aproximar',
        'Afastar',
        'Tamanho real (100%)',
        'Ajustar à tela',
        'Ajustar à seleção',
      ]) {
        expect(find.text(item), findsOneWidget);
      }
      await tester.tap(find.text('Ajustar à tela'));
      await pumpFor(tester);
      final area = tester.getRect(byKey('board-graph'));
      for (final s in specs) {
        final r = tester.getRect(byKey('board-open-${s.code}'));
        expect(area.contains(r.topLeft) && area.contains(r.bottomRight), true);
      }
      await selectSpec(tester, 'SPEC-008');
      await tester.tap(find.textContaining('▾'));
      await pumpFor(tester);
      await tester.tap(find.text('Ajustar à seleção'));
      await pumpFor(tester);
      expect(scaleOf(tester), closeTo(1.3, .001));
      final node = tester.getRect(byKey('board-open-SPEC-008'));
      final panel = tester.getRect(byKey('canvas-panel'));
      expect(node.center.dx, lessThan(panel.left));
      expect(node.center.dy, greaterThan(area.top));
    });

    testWidgets('Ctrl+=, Ctrl+- and Ctrl+0 zoom the canvas and do nothing in '
        'the columns', (tester) async {
      final (c, _) = await pumpCanvas(tester, specs);
      await ctrl(tester, LogicalKeyboardKey.equal);
      expect(scaleOf(tester), closeTo(1.1, .001));
      await ctrl(tester, LogicalKeyboardKey.numpadAdd);
      expect(scaleOf(tester), closeTo(1.2, .001));
      await ctrl(tester, LogicalKeyboardKey.minus);
      expect(scaleOf(tester), closeTo(1.1, .001));
      await ctrl(tester, LogicalKeyboardKey.digit0);
      expect(scaleOf(tester), 1);
      c.read(boardGraphViewProvider.notifier).set(false);
      await pumpFor(tester);
      await ctrl(tester, LogicalKeyboardKey.equal);
      expect(byKey('board-graph'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('R3 · turning a layer off hides only its nodes', (tester) async {
    await pumpCanvas(tester, const [
      CanvasSpec('SPEC-001', agent: 'implementador', skills: ['simplify']),
    ]);
    await selectSpec(tester, 'SPEC-001');
    expect(byKey('canvas-ref-agent-implementador'), findsOneWidget);
    await tester.tap(byKey('canvas-layer-agents'));
    await pumpFor(tester);
    expect(byKey('canvas-ref-agent-implementador'), findsNothing);
    expect(byKey('canvas-ref-skill-simplify'), findsOneWidget);
    await tester.tap(byKey('canvas-layer-skills'));
    await pumpFor(tester);
    expect(byKey('canvas-ref-skill-simplify'), findsNothing);
    await tester.tap(byKey('canvas-layer-agents'));
    await pumpFor(tester);
    expect(byKey('canvas-ref-agent-implementador'), findsOneWidget);
  });

  group('R4 · cartão de detalhes', () {
    testWidgets('an agent shows name, scope, description, model and tools; '
        'keyboard focus opens the same card and Esc closes it', (tester) async {
      final root = Directory.systemTemp.createTempSync('canvas-agent');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/.claude/agents').createSync(recursive: true);
      File('${root.path}/.claude/agents/implementador.md').writeAsStringSync(
        '---\nname: implementador\ndescription: Implementa uma etapa.\n'
        'model: sonnet\ntools: Read, Edit\n---\n\nCorpo.\n',
      );
      await pumpCanvas(tester, const [
        CanvasSpec('SPEC-001', agent: 'implementador'),
      ], path: root.path);
      await selectSpec(tester, 'SPEC-001');
      final node = byKey('canvas-ref-agent-implementador');
      final mouse = await hover(tester, node);
      await settleFiles(tester);
      expect(find.text('agente · Projeto'), findsOneWidget);
      expect(find.text('Implementa uma etapa.'), findsOneWidget);
      expect(find.text('sonnet'), findsOneWidget);
      expect(find.text('Read, Edit'), findsOneWidget);

      await mouse.moveTo(const Offset(700, 600));
      await pumpFor(tester);
      expect(find.text('agente · Projeto'), findsNothing);

      Focus.of(
        tester.element(
          find.descendant(of: node, matching: find.text('implementador')),
        ),
      ).requestFocus();
      await settleFiles(tester);
      expect(find.text('agente · Projeto'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFor(tester);
      expect(find.text('agente · Projeto'), findsNothing);
    });

    testWidgets('a built-in skill shows "Embutida" and no invented text', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('canvas-skill');
      addTearDown(() => root.deleteSync(recursive: true));
      await pumpCanvas(tester, const [
        CanvasSpec('SPEC-001', skills: ['simplify-x']),
      ], path: root.path);
      await selectSpec(tester, 'SPEC-001');
      await hover(tester, byKey('canvas-ref-skill-simplify-x'));
      await settleFiles(tester);
      expect(find.text('skill · Embutida'), findsOneWidget);
      expect(find.text('sem descrição disponível'), findsOneWidget);
      expect(find.text('embutida no Claude Code'), findsOneWidget);
    });
  });

  group('R5 · painel da spec', () {
    const specs = [
      CanvasSpec('SPEC-001'),
      CanvasSpec('SPEC-002', steps: [StepStatus.done, StepStatus.pending]),
      CanvasSpec('SPEC-003', steps: [StepStatus.needsInput]),
      CanvasSpec('SPEC-004', stage: SpecStage.review, steps: [StepStatus.done]),
      CanvasSpec('SPEC-005', deps: ['SPEC-001']),
    ];

    testWidgets('the action of the moment matches the Columns card', (
      tester,
    ) async {
      // Tall enough that the legend covers no node of the first wave.
      await pumpCanvas(tester, specs, size: const Size(1440, 1100));
      Finder inPanel(Finder f) =>
          find.descendant(of: byKey('canvas-panel'), matching: f);

      await selectSpec(tester, 'SPEC-001');
      expect(inPanel(find.text('Executar')), findsOneWidget);
      await tester.tap(inPanel(byKey('board-run-SPEC-001')));
      await pumpFor(tester);
      expect(find.byType(RunSpecDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFor(tester);

      await selectSpec(tester, 'SPEC-002');
      expect(inPanel(find.text('Continuar · R2')), findsOneWidget);
      await selectSpec(tester, 'SPEC-003');
      expect(inPanel(find.text('Responder na sessão')), findsOneWidget);
      await selectSpec(tester, 'SPEC-004');
      expect(inPanel(find.text('Ver review')), findsOneWidget);
      await selectSpec(tester, 'SPEC-005');
      expect(inPanel(byKey('board-run-SPEC-005')), findsNothing);
      expect(inPanel(find.text('Bloqueada por SPEC-001')), findsOneWidget);
    });

    testWidgets('hovering or focusing a step shows its requirement; Esc '
        'closes it', (tester) async {
      await pumpCanvas(tester, specs);
      await selectSpec(tester, 'SPEC-002');
      final row = byKey('canvas-step-R2');
      expect(find.text(stepText('SPEC-002', 'R2')), findsOneWidget);
      final mouse = await hover(tester, row);
      expect(find.text(stepText('SPEC-002', 'R2')), findsNWidgets(2));
      expect(find.text('pendente'), findsWidgets);

      await mouse.moveTo(const Offset(700, 600));
      await pumpFor(tester);
      expect(find.text(stepText('SPEC-002', 'R2')), findsOneWidget);

      Focus.of(
        tester.element(find.descendant(of: row, matching: find.text('R2'))),
      ).requestFocus();
      await pumpFor(tester);
      expect(find.text(stepText('SPEC-002', 'R2')), findsNWidgets(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFor(tester);
      expect(find.text(stepText('SPEC-002', 'R2')), findsOneWidget);
    });

    testWidgets('the panel shows depends on and unlocks; "Abrir spec" goes '
        'to Specs and "Ver nas colunas" keeps the selection', (tester) async {
      final (c, _) = await pumpCanvas(tester, specs);
      await selectSpec(tester, 'SPEC-001');
      final panel = byKey('canvas-panel');
      Finder inPanel(String t) =>
          find.descendant(of: panel, matching: find.text(t));
      expect(inPanel('depende de'), findsOneWidget);
      expect(inPanel('nenhuma'), findsWidgets);
      expect(inPanel('desbloqueia'), findsOneWidget);
      expect(inPanel('SPEC-005'), findsOneWidget);
      expect(inPanel('ETAPAS'), findsOneWidget);
      expect(inPanel('REFERÊNCIAS'), findsOneWidget);
      final id = c.read(boardSelectedSpecProvider);

      await tester.tap(inPanel('Ver nas colunas'));
      await pumpFor(tester);
      expect(c.read(boardGraphViewProvider), false);
      expect(c.read(boardSelectedSpecProvider), id);

      c.read(boardGraphViewProvider.notifier).set(true);
      await pumpFor(tester);
      await tester.tap(inPanel('Abrir spec'));
      await pumpFor(tester);
      expect(c.read(navigationProvider), AppSection.specs);
      expect(c.read(selectedSpecProvider), id);
    });
  });

  group('R6 · pulso e legenda', () {
    testWidgets('a running step animates; without one, or with reduced '
        'motion, nothing keeps animating', (tester) async {
      await pumpCanvas(tester, const [
        CanvasSpec('SPEC-001', steps: [StepStatus.running]),
      ]);
      expect(tester.hasRunningAnimations, true);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpFor(tester);
      expect(tester.hasRunningAnimations, false);
    });

    testWidgets('no running step: no animation', (tester) async {
      await pumpCanvas(tester, const [
        CanvasSpec('SPEC-001', steps: [StepStatus.done, StepStatus.pending]),
      ]);
      await pumpFor(tester);
      expect(tester.hasRunningAnimations, false);
    });

    testWidgets('the legend has the five step states, both links, agent and '
        'skill', (tester) async {
      await pumpCanvas(tester, const [CanvasSpec('SPEC-001')]);
      for (final t in [
        'feita',
        'em execução',
        'pendente',
        'aguardando você',
        'verificando',
        'dependência',
        'referência',
        'agente',
        'skill',
      ]) {
        expect(
          find.descendant(of: byKey('canvas-legend'), matching: find.text(t)),
          findsOneWidget,
        );
      }
    });
  });

  group('R7 · atenção', () {
    const specs = [
      CanvasSpec(
        'SPEC-001',
        stage: SpecStage.running,
        steps: [StepStatus.done, StepStatus.needsInput, StepStatus.needsInput],
      ),
      CanvasSpec('SPEC-002', stage: SpecStage.done, steps: [StepStatus.done]),
      CanvasSpec('SPEC-003', steps: [StepStatus.needsInput]),
    ];

    testWidgets('waiting steps ring the node, list every step in the reason '
        'with one answer, and count the spec once', (tester) async {
      await pumpCanvas(tester, specs);
      expect(byKey('canvas-attention-SPEC-001'), findsOneWidget);
      expect(byKey('canvas-attention-SPEC-002'), findsNothing);
      expect(find.text('Atenção · 2'), findsOneWidget);
      expect(find.text('Precisam de mim · 2'), findsOneWidget); // header
      await selectSpec(tester, 'SPEC-001');
      final panel = byKey('canvas-panel');
      expect(
        find.descendant(
          of: panel,
          matching: find.text('R2 e R3 aguardam você'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Responder na sessão')),
        findsOneWidget,
      );
      for (final s in ['R2', 'R3']) {
        final dot = tester.widget<CanvasStepDot>(
          byKey('canvas-dot-SPEC-001-$s'),
        );
        expect(stepDotShape(dot.status), StepDotShape.diamond, reason: s);
      }
    });

    testWidgets('the ring goes away when the session runs again and comes '
        'back when it stops without finishing', (tester) async {
      final (c, db) = await pumpCanvas(tester, specs);
      Future<void> setSteps(StepStatus status) async {
        await tester.runAsync(
          () =>
              (db.update(db.specSteps)
                    ..where((s) => s.status.isNotIn([StepStatus.done.name])))
                  .write(SpecStepsCompanion(status: Value(status))),
        );
        await pumpFor(tester, 20);
      }

      await setSteps(StepStatus.running);
      expect(byKey('canvas-attention-SPEC-001'), findsNothing);
      expect(find.text('Atenção · 0'), findsOneWidget);
      await setSteps(StepStatus.needsInput);
      expect(byKey('canvas-attention-SPEC-001'), findsOneWidget);
      expect(c.read(boardGraphViewProvider), true);
    });

    testWidgets('"Atenção" selects the next spec in turn and is disabled '
        'with N = 0', (tester) async {
      final (c, _) = await pumpCanvas(tester, specs);
      final ids = {
        for (final s in (await tester.runAsync(
          () => c.read(specsRepoProvider).watchByWorkspace(1).first,
        ))!)
          s.code: s.id,
      };
      await tester.tap(byKey('canvas-attention-next'));
      await pumpFor(tester);
      expect(c.read(boardSelectedSpecProvider), ids['SPEC-001']);
      await tester.tap(byKey('canvas-attention-next'));
      await pumpFor(tester);
      expect(c.read(boardSelectedSpecProvider), ids['SPEC-003']);
      await tester.tap(byKey('canvas-attention-next'));
      await pumpFor(tester);
      expect(c.read(boardSelectedSpecProvider), ids['SPEC-001']);
    });

    testWidgets('"Atenção · 0" does nothing', (tester) async {
      final (c, _) = await pumpCanvas(tester, const [CanvasSpec('SPEC-001')]);
      expect(find.text('Atenção · 0'), findsOneWidget);
      await tester.tap(byKey('canvas-attention-next'));
      await pumpFor(tester);
      expect(c.read(boardSelectedSpecProvider), isNull);
    });

    test('the canvas never approves or denies a tool by itself', () {
      final source = File('lib/features/board/widgets/spec_canvas.dart')
          .readAsStringSync();
      for (final call in ['approve', 'deny', 'respondApproval', 'allowTool']) {
        expect(source.contains('.$call('), false, reason: call);
      }
    });
  });
}
