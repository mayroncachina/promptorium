import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart'
    show boardSelectedSpecProvider;
import 'package:promptorium/features/cost/spec_cost.dart';
import 'package:promptorium/features/cost/widgets/spec_cost_ranking.dart';
import 'package:promptorium/features/project/widgets/spec_metrics_view.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

typedef Env = ({ProviderContainer c, AppDatabase db, Workspace a, Workspace b});

Future<Env> pumpRanking(
  WidgetTester tester, {
  bool dollars = false,
  Widget Function(Workspace)? body,
}) async {
  tester.view.physicalSize = const Size(1440, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final a = await db
      .into(db.workspaces)
      .insertReturning(WorkspacesCompanion.insert(path: '/a', name: 'alfa'));
  final b = await db
      .into(db.workspaces)
      .insertReturning(WorkspacesCompanion.insert(path: '/b', name: 'beta'));
  await db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: AppSettingKeys.activeWorkspace,
          value: '${a.id}',
        ),
      );
  final c = ProviderContainer(
    overrides: [
      databaseOverride(db),
      costInDollarsProvider.overrideWithValue(dollars),
    ],
  );
  addTearDown(c.dispose);
  await c.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body:
              body?.call(a) ??
              SingleChildScrollView(child: SpecCostRanking(workspace: a)),
        ),
      ),
    ),
  );
  await pumpFor(tester);
  return (c: c, db: db, a: a, b: b);
}

Future<int> addSpec(
  AppDatabase db,
  Workspace ws,
  String code,
  String title, {
  SpecStage stage = SpecStage.done,
}) => db
    .into(db.specs)
    .insert(
      SpecsCompanion.insert(
        workspaceId: ws.id,
        code: code,
        title: title,
        path: '$code.md',
        stage: Value(stage),
        status: const Value(SpecStatus.approved),
      ),
    );

Future<void> spend(
  AppDatabase db,
  Workspace ws,
  int spec, {
  required double week,
  UsageSource source = UsageSource.etapa,
  int daysAgo = 1,
  double cost = 1,
}) => db
    .into(db.usageEntries)
    .insert(
      UsageEntriesCompanion.insert(
        workspaceId: Value(ws.id),
        specId: Value(spec),
        source: source,
        at: DateTime.now().subtract(Duration(days: daysAgo)),
        tokensIn: const Value(1000),
        costUsd: Value(cost),
        weekPct: Value(week),
        fiveHourPct: Value(week * 22),
      ),
    );

List<String> order(WidgetTester tester) => [
  for (final e in tester.widgetList(
    find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('spec-cost-rank-'),
    ),
  ))
    (e.key! as ValueKey<String>).value.substring('spec-cost-rank-'.length),
];

// SPEC-081 R10, R11, R12, R14.
void main() {
  testWidgets('lists the specs with the most weight in the period; 30 days '
      'and Tudo take the older ones; a click opens the spec in the Quadro', (
    tester,
  ) async {
    final env = await pumpRanking(tester);
    final db = env.db;
    final s74 = await addSpec(
      db,
      env.a,
      'SPEC-074',
      'Issues ↔ specs',
      stage: SpecStage.review,
    );
    final s76 = await addSpec(db, env.a, 'SPEC-076', 'Atividades');
    final s72 = await addSpec(db, env.a, 'SPEC-072', 'Criação confiável');
    await spend(db, env.a, s74, week: 0.21);
    await spend(db, env.a, s74, week: 0.10, source: UsageSource.revisor);
    await spend(db, env.a, s76, week: 0.18);
    await spend(db, env.a, s72, week: 0.11, daysAgo: 12);
    await spend(db, env.a, s72, week: 0.50, daysAgo: 60);
    await pumpFor(tester);

    expect(order(tester), ['SPEC-074', 'SPEC-076']);
    final row = find.byKey(const ValueKey('spec-cost-rank-SPEC-074'));
    expect(
      find.descendant(of: row, matching: find.text('≈ 31%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('≈ 6,8 jan.')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('etapas 68%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Review')),
      findsOneWidget,
    );
    expect(
      find.textContaining('2 specs somam ≈ 49% de uma semana'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('spec-cost-period-month')));
    await pumpFor(tester);
    expect(order(tester), ['SPEC-074', 'SPEC-076', 'SPEC-072']);
    await tester.tap(find.byKey(const ValueKey('spec-cost-period-all')));
    await pumpFor(tester);
    expect(order(tester), ['SPEC-072', 'SPEC-074', 'SPEC-076']);

    await tester.tap(row);
    await pumpFor(tester);
    expect(env.c.read(boardSelectedSpecProvider), s74);
    expect(env.c.read(navigationProvider), AppSection.tasks);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Todos os workspaces" joins the open workspaces, with the name '
      'of the workspace; opening one of another workspace makes it active', (
    tester,
  ) async {
    final env = await pumpRanking(tester);
    final db = env.db;
    final mine = await addSpec(db, env.a, 'SPEC-001', 'Daqui');
    final other = await addSpec(db, env.b, 'SPEC-009', 'De lá');
    await spend(db, env.a, mine, week: 0.05);
    await spend(db, env.b, other, week: 0.08);
    await pumpFor(tester);
    expect(order(tester), ['SPEC-001']);
    await tester.tap(find.byKey(const ValueKey('spec-cost-all-workspaces')));
    await pumpFor(tester);
    expect(order(tester), ['SPEC-009', 'SPEC-001']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spec-cost-rank-SPEC-009')),
        matching: find.text('beta'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('spec-cost-rank-SPEC-009')));
    await pumpFor(tester);
    expect(env.c.read(activeWorkspaceProvider)?.id, env.b.id);
    expect(env.c.read(boardSelectedSpecProvider), other);
  });

  testWidgets('the ranking is navigable by the keyboard: ↓ moves, Enter '
      'opens (R14)', (tester) async {
    final env = await pumpRanking(tester);
    final db = env.db;
    final first = await addSpec(db, env.a, 'SPEC-010', 'Primeira');
    final second = await addSpec(db, env.a, 'SPEC-011', 'Segunda');
    await spend(db, env.a, first, week: 0.2);
    await spend(db, env.a, second, week: 0.1);
    await pumpFor(tester);
    final firstRow = find.descendant(
      of: find.byKey(const ValueKey('spec-cost-rank-SPEC-010')),
      matching: find.byType(InkWell),
    );
    final focus = Focus.of(
      tester.element(
        find.descendant(of: firstRow, matching: find.byType(Padding)).first,
      ),
    );
    focus.requestFocus();
    await pumpFor(tester, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await pumpFor(tester, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFor(tester);
    expect(env.c.read(boardSelectedSpecProvider), second);
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('spec-cost-rank-SPEC-010')),
    );
    expect(semantics.label, startsWith('1, SPEC-010, Primeira'));
  });

  testWidgets('with an API key the ranking shows the US\$ (R12)', (
    tester,
  ) async {
    final env = await pumpRanking(tester, dollars: true);
    final s = await addSpec(env.db, env.a, 'SPEC-073', 'Corrigir CI');
    await spend(env.db, env.a, s, week: 0.1, cost: 4.12);
    await pumpFor(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spec-cost-rank-SPEC-073')),
        matching: find.text('US\$ 4,12'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('estimativa do CLI'), findsOneWidget);
    expect(find.text('Semana'), findsNothing);
  });

  testWidgets('Projeto → Métricas: the ranking on top and the column '
      '"Cota (semana)" with the number of the panel (R11)', (tester) async {
    final env = await pumpRanking(
      tester,
      body: (ws) => SpecMetricsView(workspace: ws),
    );
    final db = env.db;
    final s = await addSpec(
      db,
      env.a,
      'SPEC-074',
      'Issues',
      stage: SpecStage.review,
    );
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 's1',
            workspaceId: env.a.id,
            worktreePath: '/a',
            branch: 'b',
            model: 'sonnet',
            specId: Value(s),
            costUsd: const Value(9.99),
          ),
        );
    await spend(db, env.a, s, week: 0.31);
    await pumpFor(tester, 20);
    expect(find.byKey(const ValueKey('spec-cost-ranking')), findsOneWidget);
    expect(find.text('Cota (semana)'), findsOneWidget);
    expect(find.text('Custo'), findsNothing);
    expect(find.text('≈ 31%'), findsNWidgets(2));
    final summary = tester
        .widget<Text>(find.byKey(const ValueKey('metrics-summary')))
        .data!;
    expect(summary, contains('≈ 31% de uma semana'));
    expect(summary, isNot(contains('\$')));
  });
}
