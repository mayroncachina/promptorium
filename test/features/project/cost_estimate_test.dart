import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/claude/usage_tracker.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/cost_estimate.dart';
import 'package:promptorium/features/project/widgets/plan_queue_view.dart';
import 'package:promptorium/features/project/widgets/usage_block.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// A `rate_limit_event` with both windows.
RateLimit rateLimit({
  double five = 0.34,
  double week = 0.12,
  required DateTime fiveResets,
  required DateTime weekResets,
}) => ClaudeEvent.fromJson({
  'type': 'rate_limit_event',
  'rate_limit_info': {
    'status': 'allowed',
    'unifiedWindows': {
      'five_hour': {
        'utilization': five,
        'resetsAt': fiveResets.millisecondsSinceEpoch ~/ 1000,
      },
      'seven_day': {
        'utilization': week,
        'resetsAt': weekResets.millisecondsSinceEpoch ~/ 1000,
      },
    },
  },
}) as RateLimit;

void main() {
  test('"O que acontece" has calls and the queue, never "1 s" or '
      '"US\$ 0,30" (R7)', () {
    final steps = startSteps(const QueueEstimate([]));
    expect(steps, hasLength(4));
    expect(steps.join('\n'), isNot(contains('1 s')));
    expect(steps.join('\n'), isNot(contains('0,30')));
    expect(steps[0], 'Pasta, git init e commit inicial · segundos');
    expect(steps[1], contains('3 chamadas (visão, stack e roadmap)'));
    expect(steps[1], contains('cada mensagem a mais na Visão é mais uma'));
    expect(steps[2], 'Fila de refino: 1 rodada por spec · 1–3 min cada');
    expect(steps[3], 'Revisar e criar: CLAUDE.md, config.yml, specs e Quadro');

    final known = startSteps(QueueEstimate(List.filled(14, 120)));
    expect(
      known[2],
      'Fila de refino: 1 rodada por spec · ~2 min cada '
      '(mediana de 14 rodadas)',
    );
    // The "Outro…" calls (R19).
    expect(
      startSteps(const QueueEstimate([]), customCalls: 2)[1],
      contains('+2 chamadas (a stack do Outro…)'),
    );
  });

  test('the queue uses the median with 3 rounds or more, and "1–3 min" '
      'without history (R9)', () {
    expect(refineMedian([60, 120]), isNull);
    expect(refineMedian([60, 300, 120]), 120);
    expect(refineMedian([60, 120, 180, 240]), 150);

    const none = QueueEstimate([60, 120]);
    expect(none.forSpecs(8), '8 specs × 1–3 min ≈ 8–24 min');
    expect(none.basis, isNull);
    expect(none.short(8), '8–24 min');

    final some = QueueEstimate([for (var i = 0; i < 14; i++) 110 + i]);
    expect(some.forSpecs(8), '8 specs × ~2 min ≈ 16 min');
    expect(some.basis, 'mediana de 14 rodadas');
    expect(some.short(8), '~16 min');
    expect(
      QueueEstimate(List.filled(3, 600)).forSpecs(8),
      contains('1 h 20 min'),
    );

    // Only the last 20 rounds are kept.
    var rounds = <int>[];
    for (var i = 1; i <= 25; i++) {
      rounds = addRefineRound(rounds, i);
    }
    expect(rounds, [for (var i = 6; i <= 25; i++) i]);
    expect(decodeRefineRounds(jsonEncode([10, 'x', -1, 20.4])), [10, 20]);
    expect(decodeRefineRounds('lixo'), isEmpty);

    expect(executionEstimate(const []), isNull);
    expect(
      executionEstimate(const [
        Duration(minutes: 30),
        Duration(minutes: 46),
        Duration.zero,
      ]),
      'depois, ~38 min por spec (média de 2 specs deste projeto)',
    );
  });

  test('planner calls by kind (R8, R10, R19)', () {
    var calls = const PlannerCalls();
    expect(calls.total, 0);
    calls = calls.add('visao').add('visao').add('stack').add('roadmap');
    expect(calls.label, '4 chamadas');
    expect(calls.detail, 'visão 2, stack 1, roadmap 1');
    expect(PlannerCalls.decode(calls.encode()).total, 4);
    expect(PlannerCalls.decode('{x').total, 0);
    expect(callsLabel(1), '1 chamada');
    expect(
      apiCeiling,
      'até US\$ 0,50 por chamada do planner, US\$ 1,00 no '
      'roadmap',
    );
  });

  test('recorded rounds and calls go to app_settings', () async {
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ref = c.read(_refProvider);
    await recordRefineRound(ref, const Duration(seconds: 95));
    await recordRefineRound(ref, const Duration(milliseconds: 10));
    expect(c.read(refineRoundsProvider), [95, 1]);
    await recordPlannerCalls(ref, 7, 'outro', 2);
    expect(c.read(plannerCallsProvider(7)).detail, 'stack do Outro… 2');
    expect(c.read(plannerCallsProvider(8)).total, 0);
  });

  test('the queue step of Revisar e criar has the estimate (R10)', () {
    final rows = planQueuePreview(
      specs: 8,
      writeClaudeMd: true,
      commit: true,
      firstRun: false,
      refineTime: '~16 min',
    );
    expect(
      rows.map((r) => r.title),
      contains('Refina e planeja as 8 specs · ~16 min'),
    );
  });

  test('renewal text: today, another day, renewed (R8)', () {
    final now = DateTime(2026, 11, 13, 15); // a Friday
    expect(renewText(DateTime(2026, 11, 13, 18, 40), now), 'renova às 18:40');
    expect(renewText(DateTime(2026, 11, 20, 9), now), 'renova sex. 09:00');
    expect(renewText(DateTime(2026, 11, 13, 14), now), 'renovada');
    expect(renewText(null, now), '');
  });

  Future<ProviderContainer> pumpUsage(
    WidgetTester tester,
    String? plan, {
    RateLimit? rate,
    DateTime? now,
  }) async {
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    await c.read(appSettingsProvider.notifier).load();
    if (rate != null) await c.read(rateLimitProvider.notifier).record(rate);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: UsageBlock(subscriptionType: plan, now: now),
            ),
          ),
        ),
      ),
    );
    return c;
  }

  Future<void> done(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(Duration.zero);
  }

  testWidgets('subscription: the quota of the 5-hour window and the week, '
      'and no charge per call; API key: the dollar ceiling (R8)', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 13, 15);
    var c = await pumpUsage(
      tester,
      'max',
      now: now,
      rate: rateLimit(
        fiveResets: DateTime(2026, 11, 13, 18, 40),
        weekResets: DateTime(2026, 11, 20, 9),
      ),
    );
    expect(find.text('USO · PLANO MAX'), findsOneWidget);
    expect(find.text('34%'), findsOneWidget);
    expect(find.text('12%'), findsOneWidget);
    expect(find.text('renova às 18:40'), findsOneWidget);
    expect(find.text('renova sex. 09:00'), findsOneWidget);
    expect(
      find.text(
        'No plano Max não há cobrança por chamada: o planner e a fila gastam '
        'da quota.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('US\$'), findsNothing);
    await done(tester, c);

    // A window that already reset shows "renovada".
    c = await pumpUsage(
      tester,
      'max',
      now: now,
      rate: rateLimit(
        fiveResets: DateTime(2026, 11, 13, 14),
        weekResets: DateTime(2026, 11, 20, 9),
      ),
    );
    expect(find.text('renovada'), findsOneWidget);
    await done(tester, c);

    // No data yet.
    c = await pumpUsage(tester, 'pro', now: now);
    expect(find.text('O uso aparece depois da primeira chamada.'), findsOne);
    await done(tester, c);

    // API key.
    c = await pumpUsage(tester, null, now: now);
    expect(find.text('USO · CHAVE DE API'), findsOneWidget);
    expect(find.textContaining('até US\$ 0,50 por chamada'), findsOneWidget);
    await done(tester, c);
  });
}

/// A [Ref] for the record functions.
final _refProvider = Provider<Ref>((ref) => ref);
