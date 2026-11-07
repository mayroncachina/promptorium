import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/sprint_rules.dart';
import 'package:promptorium/features/board/sprint_state.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

Future<void> settle(WidgetTester tester, [int times = 12]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

/// Two sprints (the first active) and specs in each, plus one without.
Future<(ProviderContainer, AppDatabase, int)> pump(
  WidgetTester tester, {
  bool sprints = true,
  String? saved,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final ws = await db
      .into(db.workspaces)
      .insertReturning(WorkspacesCompanion.insert(path: '/r', name: 'r'));
  await db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: AppSettingKeys.activeWorkspace,
          value: '${ws.id}',
        ),
      );
  if (saved != null) {
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AppSettingKeys.boardSprint(ws.id),
            value: saved,
          ),
        );
  }
  Future<Sprint> sprint(String name, SprintState state, int position) => db
      .into(db.sprints)
      .insertReturning(
        SprintsCompanion.insert(
          workspaceId: ws.id,
          name: name,
          state: Value(state),
          position: Value(position),
        ),
      );
  final a = sprints ? await sprint('Sprint 1', SprintState.active, 1) : null;
  final b = sprints ? await sprint('Sprint 2', SprintState.planned, 2) : null;
  Future<void> spec(
    String code,
    Sprint? s, {
    SpecStage stage = SpecStage.backlog,
    List<String> deps = const [],
  }) => db
      .into(db.specs)
      .insert(
        SpecsCompanion.insert(
          workspaceId: ws.id,
          code: code,
          title: 'Título $code',
          path: 'specs/$code.md',
          status: const Value(SpecStatus.approved),
          stage: Value(stage),
          sprintId: Value(s?.id),
          dependsOn: Value(deps),
        ),
      );
  await spec('SPEC-001', a, stage: SpecStage.done);
  await spec('SPEC-002', a);
  await spec('SPEC-003', b);
  await spec('SPEC-004', null);
  final c = ProviderContainer(overrides: [databaseOverride(db)]);
  addTearDown(c.dispose);
  await c.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: BoardScreen()),
      ),
    ),
  );
  await settle(tester);
  return (c, db, ws.id);
}

Future<void> openSelector(WidgetTester tester) async {
  await tester.tap(byKey('board-sprint'));
  await settle(tester);
}

Future<void> pick(WidgetTester tester, String stored) async {
  await openSelector(tester);
  await tester.tap(byKey('sprint-option-$stored'));
  await settle(tester);
}

void expectCards(List<String> shown, List<String> hidden) {
  for (final c in shown) {
    expect(byKey('board-open-$c'), findsOneWidget, reason: c);
  }
  for (final c in hidden) {
    expect(byKey('board-open-$c'), findsNothing, reason: c);
  }
}

void main() {
  testWidgets('sem escolha salva abre a Ativa e mostra só ela (R2, R6)', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Sprint 1'), findsOneWidget);
    expect(tester.widget<Text>(byKey('board-sprint-detail')).data, '1 de 2');
    expectCards(['SPEC-001', 'SPEC-002'], ['SPEC-003', 'SPEC-004']);
  });

  testWidgets('escolher troca as specs e a escolha fica salva (R2)', (
    tester,
  ) async {
    final (c, db, ws) = await pump(tester);
    final second = (await db.select(db.sprints).get()).last;
    await pick(tester, '${second.id}');
    expectCards(['SPEC-003'], ['SPEC-001', 'SPEC-004']);
    await pick(tester, 'none');
    expectCards(['SPEC-004'], ['SPEC-001', 'SPEC-003']);
    await pick(tester, 'all');
    expectCards(['SPEC-001', 'SPEC-003', 'SPEC-004'], []);
    expect(c.read(appSettingsProvider)[AppSettingKeys.boardSprint(ws)], 'all');
  });

  testWidgets('a escolha salva volta ao abrir o app (R2)', (tester) async {
    await pump(tester, saved: 'none');
    expectCards(['SPEC-004'], ['SPEC-001']);
  });

  testWidgets('sprint salva que sumiu cai na Ativa (R2)', (tester) async {
    await pump(tester, saved: '999');
    expectCards(['SPEC-001'], ['SPEC-004']);
  });

  testWidgets('o seletor mostra o progresso de cada sprint (R3)', (
    tester,
  ) async {
    await pump(tester);
    await openSelector(tester);
    expect(find.text('Ativa'), findsOneWidget);
    expect(find.text('Planejada'), findsOneWidget);
    expect(find.text('1 de 2'), findsWidgets);
    expect(find.text('0 de 1'), findsOneWidget);
    expect(find.text('4 specs'), findsOneWidget);
  });

  testWidgets('sem sprints abre em Todas e oferece só Nova sprint (R13)', (
    tester,
  ) async {
    await pump(tester, sprints: false);
    expect(find.text('Sprints'), findsOneWidget);
    expectCards(['SPEC-001', 'SPEC-003', 'SPEC-004'], []);
    await openSelector(tester);
    expect(byKey('sprint-action-new'), findsOneWidget);
    expect(byKey('sprint-action-organize'), findsNothing);
    expect(byKey('sprint-option-all'), findsNothing);
  });

  testWidgets('a primeira sprint nasce Ativa, com o nome sugerido (R4)', (
    tester,
  ) async {
    final (c, db, _) = await pump(tester, sprints: false);
    await openSelector(tester);
    await tester.tap(byKey('sprint-action-new'));
    await settle(tester);
    expect(find.textContaining('já fica ativa'), findsOneWidget);
    expect(
      tester.widget<TextField>(byKey('sprint-name')).controller?.text,
      'Sprint 1',
    );
    await tester.tap(byKey('sprint-save'));
    await settle(tester);
    final sprint = (await db.select(db.sprints).get()).single;
    expect(sprint.state, SprintState.active);
    expect(c.read(boardSprintFilterProvider), SprintFilter.sprint(sprint.id));
    expect(find.text('Esta sprint ainda não tem specs.'), findsOneWidget);
    expect(byKey('board-sprint-organize'), findsOneWidget);
  });

  testWidgets('excluir confirma e deixa as specs em Sem sprint (R4)', (
    tester,
  ) async {
    final (_, db, _) = await pump(tester);
    await openSelector(tester);
    await tester.tap(byKey('sprint-action-delete'));
    await settle(tester);
    expect(find.textContaining('2 specs vão para Sem sprint'), findsOneWidget);
    await tester.tap(byKey('sprint-delete-confirm'));
    await settle(tester);
    expect(await db.select(db.sprints).get(), hasLength(1));
    expect(await db.select(db.specs).get(), hasLength(4));
    expect(find.text('Sprint 1'), findsNothing);
  });

  testWidgets('Ativar troca a sprint Ativa (R4)', (tester) async {
    final (_, db, _) = await pump(tester);
    final second = (await db.select(db.sprints).get()).last;
    await pick(tester, '${second.id}');
    await openSelector(tester);
    await tester.tap(byKey('sprint-action-activate'));
    await settle(tester);
    final all = await db.select(db.sprints).get();
    expect(all.first.state, SprintState.planned);
    expect(all.last.state, SprintState.active);
  });

  testWidgets('o menu do card move a spec, e Desfazer devolve (R5)', (
    tester,
  ) async {
    final (_, db, _) = await pump(tester);
    final second = (await db.select(db.sprints).get()).last;
    await tester.tap(byKey('board-menu-SPEC-002'));
    await settle(tester);
    await tester.tap(find.text('Mover para sprint'));
    await settle(tester);
    await tester.tap(byKey('card-sprint-${second.id}'));
    await settle(tester);
    expectCards(['SPEC-001'], ['SPEC-002']);
    expect(find.text('SPEC-002 foi para a Sprint 2'), findsOneWidget);
    await tester.tap(find.text('Desfazer'));
    await settle(tester);
    expectCards(['SPEC-001', 'SPEC-002'], []);
  });

  testWidgets('sem sprints o menu do card não oferece mover (R13)', (
    tester,
  ) async {
    await pump(tester, sprints: false);
    await tester.tap(byKey('board-menu-SPEC-002'));
    await settle(tester);
    expect(find.text('Mover para sprint'), findsNothing);
  });

  testWidgets('Organizar move várias specs de uma vez (R5)', (tester) async {
    final (_, db, _) = await pump(tester);
    await openSelector(tester);
    await tester.tap(byKey('sprint-action-organize'));
    await settle(tester);
    await tester.tap(byKey('sprint-organize-SPEC-004'));
    await settle(tester);
    expect(find.text('Mover 1 spec'), findsOneWidget);
    await tester.tap(byKey('sprint-organize-move'));
    await settle(tester);
    final specs = await db.select(db.specs).get();
    final active = (await db.select(db.sprints).get()).first;
    expect(specs.firstWhere((s) => s.code == 'SPEC-004').sprintId, active.id);
    expectCards(['SPEC-004'], []);
  });

  testWidgets('/ e Ctrl+F focam a busca do Organizar, e ela filtra (R5)', (
    tester,
  ) async {
    await pump(tester);
    await openSelector(tester);
    await tester.tap(byKey('sprint-action-organize'));
    await settle(tester);
    final field = tester.widget<TextField>(byKey('sprint-organize-search'));
    expect(field.focusNode!.hasFocus, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.enterText(byKey('sprint-organize-search'), 'zzz');
    await settle(tester);
    expect(find.text('Nenhuma spec para mostrar.'), findsOneWidget);
  });
}
