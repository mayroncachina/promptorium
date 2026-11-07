import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/sprint_rules.dart';
import 'package:promptorium/features/board/sprint_state.dart';

import 'canvas_fixture.dart';

/// SPEC-001 and SPEC-002 in the active Sprint 1, SPEC-003 in the planned
/// Sprint 2, SPEC-004 without a sprint.
Future<(ProviderContainer, Sprint, Sprint)> pumpSprints(
  WidgetTester tester, {
  BoardView view = BoardView.focus,
  List<CanvasSpec>? specs,
}) async {
  final (c, db) = await pumpCanvas(
    tester,
    specs ??
        const [
          CanvasSpec('SPEC-001', title: 'Base'),
          CanvasSpec('SPEC-002', title: 'Custo por spec', deps: ['SPEC-003']),
          CanvasSpec('SPEC-003', title: 'Custo da sprint'),
          CanvasSpec('SPEC-004', title: 'Solta', stage: SpecStage.done),
        ],
    view: view,
    size: const Size(1440, 1000),
  );
  final repo = c.read(sprintsRepoProvider);
  final ws = (await db.select(db.workspaces).getSingle()).id;
  final a = await repo.create(workspaceId: ws, name: 'Sprint 1');
  final b = await repo.create(workspaceId: ws, name: 'Sprint 2');
  final all = await db.select(db.specs).get();
  int id(String code) => all.firstWhere((s) => s.code == code).id;
  await repo.moveSpecs([id('SPEC-001'), id('SPEC-002')], a.id);
  await repo.moveSpecs([id('SPEC-003')], b.id);
  await pumpFor(tester, 20);
  return (c, a, b);
}

Future<void> show(
  WidgetTester tester,
  ProviderContainer c,
  SprintFilter filter,
) async {
  await c.read(boardSprintProvider.notifier).set(filter);
  await pumpFor(tester, 20);
}

void main() {
  group('R7 · Grafo', () {
    testWidgets('as ondas são da sprint, e a dependência externa aparece', (
      tester,
    ) async {
      await pumpSprints(tester, view: BoardView.graph);
      expect(byKey('canvas-node-SPEC-001'), findsOneWidget);
      expect(byKey('canvas-node-SPEC-002'), findsOneWidget);
      expect(byKey('canvas-node-SPEC-003'), findsNothing);
      expect(byKey('canvas-node-SPEC-004'), findsNothing);
      expect(byKey('canvas-external-SPEC-003'), findsOneWidget);
      expect(find.text('Sprint 2'), findsOneWidget);
      // The dependency is out of the waves: both specs start the first one.
      expect(byKey('board-wave-0'), findsOneWidget);
      expect(byKey('board-wave-1'), findsNothing);
    });

    testWidgets('clicar no nó externo troca a sprint e seleciona a spec', (
      tester,
    ) async {
      final (c, _, b) = await pumpSprints(tester, view: BoardView.graph);
      await tester.tap(byKey('canvas-external-SPEC-003'));
      await pumpFor(tester, 20);
      expect(c.read(boardSprintFilterProvider), SprintFilter.sprint(b.id));
      expect(byKey('canvas-node-SPEC-003'), findsOneWidget);
      expect(c.read(boardSelectedSpecProvider), isNotNull);
    });

    testWidgets('em Todas fica como hoje', (tester) async {
      final (c, _, _) = await pumpSprints(tester, view: BoardView.graph);
      await show(tester, c, const SprintFilter.all());
      expect(byKey('canvas-external-SPEC-003'), findsNothing);
      expect(byKey('canvas-node-SPEC-003'), findsOneWidget);
      expect(byKey('board-wave-1'), findsOneWidget);
    });
  });

  group('R8 · Foco', () {
    testWidgets('a pasta mostra só a sprint, com o nome e a contagem', (
      tester,
    ) async {
      await pumpSprints(tester);
      expect(tester.widget<Text>(byKey('folder-title')).data, 'Sprint 1');
      expect(tester.widget<Text>(byKey('folder-count')).data, '2');
      expect(byKey('folder-row-SPEC-001'), findsOneWidget);
      expect(byKey('folder-row-SPEC-003'), findsNothing);
    });

    testWidgets('em Todas agrupa na ordem do seletor e recolhe', (
      tester,
    ) async {
      final (c, a, b) = await pumpSprints(tester);
      await c.read(sprintsRepoProvider).complete(b.id);
      await show(tester, c, const SprintFilter.all());
      final y = [
        for (final k in ['${a.id}', 'none', '${b.id}'])
          tester.getTopLeft(byKey('folder-section-$k')).dy,
      ];
      expect(y, orderedEquals([...y]..sort()));
      expect(find.text('Ativa'), findsOneWidget);
      expect(find.text('Concluída'), findsOneWidget);
      // Only the active one starts open.
      expect(byKey('folder-row-SPEC-001'), findsOneWidget);
      expect(byKey('folder-row-SPEC-004'), findsNothing);
      await tester.tap(byKey('folder-section-none'));
      await pumpFor(tester);
      expect(byKey('folder-row-SPEC-004'), findsOneWidget);
      await tester.tap(byKey('folder-section-${a.id}'));
      await pumpFor(tester);
      expect(byKey('folder-row-SPEC-001'), findsNothing);
    });

    testWidgets('sem sprints a pasta é a de hoje', (tester) async {
      await pumpCanvas(tester, const [
        CanvasSpec('SPEC-001'),
      ], view: BoardView.focus);
      expect(tester.widget<Text>(byKey('folder-title')).data, 'specs/');
      expect(find.byKey(const ValueKey('folder-section-none')), findsNothing);
    });

    testWidgets('a busca mostra o atalho no campo', (tester) async {
      await pumpSprints(tester);
      expect(byKey('folder-search-hint'), findsOneWidget);
    });

    testWidgets(
      'busca sem resultado conta as outras sprints e busca em todas',
      (tester) async {
        final (c, _, _) = await pumpSprints(tester);
        await tester.enterText(byKey('folder-search'), 'sprint');
        await pumpFor(tester);
        expect(
          find.text('Nenhuma spec com "sprint" em Sprint 1'),
          findsOneWidget,
        );
        expect(find.text('1 em outra sprint'), findsOneWidget);
        await tester.tap(byKey('folder-search-all'));
        await pumpFor(tester, 20);
        expect(c.read(boardSprintFilterProvider), const SprintFilter.all());
        expect(byKey('folder-row-SPEC-003'), findsOneWidget);
      },
    );

    testWidgets('Enter em uma busca sem resultado busca em todas', (
      tester,
    ) async {
      final (c, _, _) = await pumpSprints(tester);
      await tester.tap(byKey('folder-search'));
      await tester.enterText(byKey('folder-search'), 'sprint');
      await pumpFor(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await pumpFor(tester, 20);
      expect(c.read(boardSprintFilterProvider), const SprintFilter.all());
    });

    testWidgets('sem resultado em lugar nenhum não oferece buscar em todas', (
      tester,
    ) async {
      await pumpSprints(tester);
      await tester.enterText(byKey('folder-search'), 'zzz');
      await pumpFor(tester);
      expect(byKey('folder-search-all'), findsNothing);
    });

    testWidgets('o palco mostra a sprint da dependente de fora', (
      tester,
    ) async {
      await pumpSprints(
        tester,
        specs: const [
          CanvasSpec('SPEC-001', title: 'Base'),
          CanvasSpec('SPEC-002', title: 'Mesma sprint', deps: ['SPEC-001']),
          CanvasSpec('SPEC-003', title: 'Outra', deps: ['SPEC-001']),
          CanvasSpec('SPEC-004', title: 'Solta'),
        ],
      );
      await tester.tap(byKey('folder-row-SPEC-001'));
      await pumpFor(tester, 60);
      expect(byKey('stage-node-SPEC-003'), findsOneWidget);
      expect(byKey('stage-sprint-SPEC-003'), findsOneWidget);
      expect(byKey('stage-sprint-SPEC-002'), findsNothing);
    });
  });
}
