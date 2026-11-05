import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/settings/orchestrator_history.dart';
import 'package:promptorium/features/settings/orchestrator_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../../helpers/test_db.dart';

var _id = 0;

StepRun _run(
  String step,
  StepKind? kind,
  StepRunResult result, {
  int spec = 1,
  String model = 'sonnet',
  double cost = 0.1,
  required DateTime at,
}) => StepRun(
  id: ++_id,
  specId: spec,
  step: step,
  kind: kind?.name,
  model: model,
  result: result,
  costUsd: cost,
  createdAt: at,
);

void main() {
  final t0 = DateTime(2026, 11, 1, 10);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));
  const passed = StepRunResult.passed;
  const escalated = StepRunResult.escalated;
  const failed = StepRunResult.failed;

  test('soma por tipo e período, e a sugestão só aparece com 5 etapas e 20% '
      'de escaladas [R17] [R18]', () {
    const impl = StepKind.implementacao;
    const mec = StepKind.mecanica;
    final runs = [
      // Implementação: 4 steps, one escalated (Sonnet → Opus).
      _run('R1', impl, escalated, at: at(0)),
      _run('R1', impl, passed, model: 'opus', cost: 0.5, at: at(5)),
      _run('R2', impl, passed, at: at(10)),
      _run('R3', impl, passed, at: at(20)),
      // Same step id in another spec counts apart.
      _run('R1', impl, passed, spec: 2, at: at(30)),
      // Mecânica: failed at first, passed later = not "de primeira".
      _run('R4', mec, failed, model: 'haiku', cost: 0.02, at: at(40)),
      _run('R4', mec, passed, model: 'haiku', cost: 0.02, at: at(50)),
      // Manual: no kind, left out.
      _run('R5', null, passed, at: at(60)),
    ];
    final h = orchestratorHistory(runs.reversed);
    expect(h.map((e) => e.kind), [mec, impl]);
    final i = h[1];
    expect((i.steps, i.firstPass, i.escalated), (4, 3, 1));
    expect(i.models, ['sonnet', 'opus']);
    expect(i.costUsd, closeTo(0.1 + 0.5 + 0.1 + 0.1 + 0.1, 1e-9));
    expect(i.lastEscalation, at(0));
    final m = h[0];
    expect((m.steps, m.firstPass, m.escalated), (1, 0, 0));
    expect(m.costUsd, closeTo(0.04, 1e-9));

    // 4 steps, 1 escalated (25%): fewer than 5 steps, no suggestion.
    expect(i.needsStrongerRule, isFalse);
    expect(showHistorySuggestion(i, null), isFalse);

    // 5 steps, 1 escalated: exactly 20%.
    final five = orchestratorHistory([
      ...runs,
      _run('R6', impl, passed, at: at(70)),
    ])[1];
    expect((five.steps, five.escalated), (5, 1));
    expect(five.needsStrongerRule, isTrue);
    expect(showHistorySuggestion(five, null), isTrue);

    // 6 steps, 1 escalated (17%): under 20%.
    final six = orchestratorHistory([
      ...runs,
      _run('R6', impl, passed, at: at(70)),
      _run('R7', impl, passed, at: at(80)),
    ])[1];
    expect(six.needsStrongerRule, isFalse);

    // "Ignorar" lasts until a newer escalation in the period.
    expect(showHistorySuggestion(five, at(0)), isFalse);
    final newer = orchestratorHistory([
      ...runs,
      _run('R6', impl, escalated, at: at(90)),
    ])[1];
    expect(newer.lastEscalation, at(90));
    expect(showHistorySuggestion(newer, at(0)), isTrue);
    expect(showHistorySuggestion(newer, at(90)), isFalse);
  });

  testWidgets('the Histórico reads step_runs of the period; "Ver regra" marks '
      'the rule and "Ignorar" hides the suggestion', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: '/r', name: 'r');
      final spec = await c
          .read(specsRepoProvider)
          .insert(
            workspaceId: ws.id,
            code: 'SPEC-001',
            title: 'x',
            path: 'specs/x.md',
          );
      final repo = c.read(stepRunsRepoProvider);
      Future<void> add(String step, StepRunResult r, int daysAgo) => repo
          .add(
            specId: spec.id,
            step: step,
            kind: StepKind.altoRisco.name,
            model: 'opus',
            effort: 'high',
            result: r,
            costUsd: 1,
            at: now.subtract(Duration(days: daysAgo)),
          )
          .then((_) {});
      // Last 7 days: 5 steps, 2 escalated.
      await add('R1', StepRunResult.escalated, 1);
      await add('R2', StepRunResult.escalated, 2);
      for (final s in ['R3', 'R4', 'R5']) {
        await add(s, StepRunResult.passed, 3);
      }
      // Only in 30 days.
      await add('R6', StepRunResult.passed, 20);
    });
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(child: OrchestratorView()),
          ),
        ),
      ),
    );
    await settle();
    Finder key(String k) => find.byKey(ValueKey(k));
    Finder inRow(String text) => find.descendant(
      of: key('orchestrator-history-altoRisco'),
      matching: find.text(text),
    );
    // 30 days by default: 6 steps, 2 escalated (33%).
    expect(inRow('6'), findsOneWidget);
    expect(inRow('US\$ 6.00'), findsOneWidget);
    expect(key('orchestrator-history-suggestion-altoRisco'), findsOneWidget);
    expect(find.textContaining('não é cobrança'), findsOneWidget);

    await tester.tap(key('orchestrator-history-days-7'));
    await settle();
    expect(inRow('5'), findsOneWidget);
    expect(inRow('3'), findsOneWidget);
    expect(inRow('2'), findsOneWidget);

    await tester.tap(key('orchestrator-history-show-altoRisco'));
    await tester.pumpAndSettle();
    final rule = tester.widget<Container>(
      find
          .ancestor(
            of: key('orchestrator-rule-altoRisco'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (rule.decoration! as BoxDecoration).border!.top.color,
      AppColors.amber,
    );

    await tester.tap(key('orchestrator-history-ignore-altoRisco'));
    await settle();
    expect(key('orchestrator-history-suggestion-altoRisco'), findsNothing);
    expect(
      c.read(appSettingsProvider)[AppSettingKeys.orchestratorHistoryIgnored(
        'altoRisco',
      )],
      isNotNull,
    );
  });
}
