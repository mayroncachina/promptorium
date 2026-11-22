import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/cost/cost_format.dart';
import 'package:promptorium/features/cost/spec_cost.dart';

import '../board/board_screen_test.dart' show pumpBoard, pumpFor, text;

/// The current 5-hour window renews in two hours.
final resets = DateTime.now().add(const Duration(hours: 2));

String rateLimitJson({double five = 0.62}) => jsonEncode({
  'type': 'rate_limit_event',
  'rate_limit_info': {
    'status': 'allowed',
    'unifiedWindows': {
      'five_hour': {
        'utilization': five,
        'resetsAt': resets.millisecondsSinceEpoch / 1000,
      },
      'seven_day': {
        'utilization': 0.28,
        'resetsAt':
            DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch /
            1000,
      },
    },
  },
});

Future<void> addEntry(
  AppDatabase db,
  int specId, {
  required UsageSource source,
  String? step,
  String? sessionId,
  int? conversationId,
  double? week,
  double? five,
  int tokens = 1000,
  int cacheRead = 0,
  double cost = 0.1,
  DateTime? at,
  bool estimated = false,
}) => db
    .into(db.usageEntries)
    .insert(
      UsageEntriesCompanion.insert(
        workspaceId: const Value(1),
        specId: Value(specId),
        source: source,
        step: Value(step),
        sessionId: Value(sessionId),
        conversationId: Value(conversationId),
        model: const Value('claude-sonnet-4-5'),
        at: at ?? DateTime.now().subtract(const Duration(days: 1)),
        tokensIn: Value(tokens),
        tokensCacheRead: Value(cacheRead),
        costUsd: Value(cost),
        weekPct: Value(week),
        fiveHourPct: Value(five),
        estimated: Value(estimated),
      ),
    );

Future<int> specId(AppDatabase db, String code) async => (await (db.select(
  db.specs,
)..where((s) => s.code.equals(code))).getSingle()).id;

Future<void> session(
  AppDatabase db,
  int spec,
  String id, {
  SessionStatus status = SessionStatus.completed,
  String steps = 'R1',
}) => db
    .into(db.sessions)
    .insert(
      SessionsCompanion.insert(
        id: id,
        workspaceId: 1,
        worktreePath: '/work/repo',
        branch: 'b',
        model: 'sonnet',
        specId: Value(spec),
        steps: Value(steps),
        status: Value(status),
        costUsd: const Value(4.12),
      ),
    );

/// A plan with quota (the CLI is not asked in the tests).
final quota = [costInDollarsProvider.overrideWithValue(false)];

Future<void> openPanel(WidgetTester tester, String code) async {
  await tester.tap(find.byKey(ValueKey('board-open-$code')));
  await pumpFor(tester);
}

// SPEC-081 R6–R9, R12–R14.
void main() {
  group('formats (R13)', () {
    test('weights, windows and tokens', () {
      expect(formatQuota(0.004), '≈ 0,4%');
      expect(formatQuota(0.23), '≈ 23%');
      expect(formatQuota(0.0004), '< 0,1%');
      expect(formatQuota(0.0999), '≈ 10%');
      expect(formatQuota(0.09), '≈ 9%');
      expect(formatQuota(null), '—');
      expect(formatFiveHour(0.86), '≈ 86%');
      expect(formatFiveHour(1.4), '≈ 1,4 janela de 5 h');
      expect(formatFiveHour(1.4, short: true), '≈ 1,4 jan.');
      expect(formatFiveHourValue(1.4), '≈ 1,4');
      expect(formatTokens(812000), '812 k');
      expect(formatTokens(1800000), '1,8 M');
      expect(formatTokens(640), '640');
      expect(formatTokens(41000000), '41 M');
      expect(formatUsd(4.12), 'US\$ 4,12');
    });
  });

  test('specCostOf: totals, by origin, by step and this window; entries '
      'without weight keep only the tokens', () {
    var id = 0;
    final now = DateTime(2026, 11, 17, 12);
    UsageEntry e(
      UsageSource s, {
      String? step,
      String? sid,
      double? week,
      double? five,
      int tokens = 100,
      DateTime? at,
    }) => UsageEntry(
      id: ++id,
      workspaceId: 1,
      specId: 1,
      source: s,
      step: step,
      sessionId: sid,
      at: at ?? now.subtract(Duration(hours: id)),
      tokensIn: tokens,
      tokensCacheWrite: 0,
      tokensCacheRead: 1000,
      tokensOut: 0,
      costUsd: 0.1,
      fiveHourPct: five,
      weekPct: week,
      estimated: false,
      provider: 'claude',
      tokensReasoning: 0,
    );
    final cost = specCostOf([
      e(UsageSource.etapa, step: 'R2', sid: 'a', week: 0.02, five: 0.4),
      e(UsageSource.etapa, step: 'R1', sid: 'a', week: 0.01, five: 0.2),
      e(UsageSource.etapa, step: 'REV1', sid: 'b', week: 0.01, five: 0.2),
      e(UsageSource.revisor, step: 'rodada 1', week: 0.01, five: 0.1),
      e(UsageSource.ci, step: 'R2', sid: 'a', week: 0.005, five: 0.05),
      e(UsageSource.vibe, tokens: 50),
    ], windowStart: now.subtract(const Duration(hours: 2, minutes: 30)));
    expect(cost.total.turns, 6);
    expect(cost.total.week, closeTo(0.055, 1e-9));
    expect(cost.total.fiveHour, closeTo(0.95, 1e-9));
    expect(cost.total.tokens, 550);
    expect(cost.total.cacheRead, 6000);
    expect(cost.bySource.keys, [
      UsageSource.etapa,
      UsageSource.revisor,
      UsageSource.ci,
      UsageSource.vibe,
    ]);
    expect(cost.bySource[UsageSource.etapa]!.units, 2, reason: '2 sessions');
    expect(cost.bySource[UsageSource.vibe]!.week, isNull);
    expect(cost.bySource[UsageSource.vibe]!.tokens, 50);
    expect([for (final (s, _) in cost.bySteps) s], ['R1', 'R2', 'REV1']);
    expect(cost.bySteps[1].$2.turns, 2, reason: 'R2 of the step and the CI');
    // The two newest (1 h and 2 h ago) are in the window.
    expect(cost.thisWindow, closeTo(0.6, 1e-9));
    expect(
      cost.share(cost.bySource[UsageSource.etapa]!),
      closeTo(0.04 / 0.055, 1e-9),
    );
  });

  testWidgets('the card shows no cost; its click opens the panel with the '
      'section Cota: totals, by origin, by step, this window and the turns', (
    tester,
  ) async {
    final (c, db) = await pumpBoard(tester, overrides: quota);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AppSettingKeys.lastRateLimit,
            value: rateLimitJson(),
          ),
        );
    await c.read(appSettingsProvider.notifier).load();
    final spec = await specId(db, 'SPEC-002');
    await session(db, spec, 's1');
    await addEntry(
      db,
      spec,
      source: UsageSource.etapa,
      step: 'R1',
      sessionId: 's1',
      week: 0.034,
      five: 0.77,
      tokens: 980000,
      cacheRead: 22000000,
    );
    await addEntry(
      db,
      spec,
      source: UsageSource.etapa,
      step: 'R2',
      sessionId: 's1',
      week: 0.01,
      five: 0.31,
      tokens: 20000,
      at: DateTime.now().subtract(const Duration(minutes: 30)),
    );
    await addEntry(
      db,
      spec,
      source: UsageSource.refino,
      conversationId: null,
      week: 0.004,
      five: 0.09,
      tokens: 120000,
    );
    await pumpFor(tester);

    // R6: no "US$", no "$", no badge or number of cost on the card.
    final card = find.byKey(const ValueKey('board-card-SPEC-002'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.textContaining('\$')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('%')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('tokens')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('spec-cost-section')), findsNothing);

    await openPanel(tester, 'SPEC-002');
    expect(find.byKey(const ValueKey('board-side-panel')), findsOneWidget);
    // R8: the "US$" beside the steps goes away.
    expect(text(tester, 'steps-progress'), '1/3 etapas');
    expect(find.byKey(const ValueKey('spec-cost-section')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spec-cost-week')),
        matching: find.text('≈ 4,8%'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spec-cost-five')),
        matching: find.text('≈ 1,2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spec-cost-tokens')),
        matching: find.text('tokens · + 22 M do cache'),
      ),
      findsOneWidget,
    );
    expect(find.text('1,1 M'), findsOneWidget);
    // By origin, the bar has the list beside it.
    expect(
      find.byKey(const ValueKey('spec-cost-source-etapa')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('spec-cost-source-refino')),
      findsOneWidget,
    );
    expect(find.text('1 sessão'), findsOneWidget);
    // By step.
    expect(find.byKey(const ValueKey('spec-cost-step-R1')), findsOneWidget);
    expect(find.byKey(const ValueKey('spec-cost-step-R2')), findsOneWidget);
    // R9: this window (only the entry of 30 min ago) and when it renews.
    final window = text(tester, 'spec-cost-window');
    expect(window, startsWith('nesta janela: ≈ 31%'));
    expect(window, contains('renova às'));
    expect(window, contains('a janela está em 62%'));
    // Nothing running: no "agora".
    expect(find.byKey(const ValueKey('spec-cost-now-text')), findsNothing);

    // R14: the section is announced with the totals.
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('spec-cost-section')),
    );
    expect(
      semantics.label.trim(),
      'Cota da spec: cerca de 4,8% da semana, 1,2 janela de 5 horas, '
      '1,1 milhão de tokens',
    );

    // "Ver turnos": newest first.
    await tester.ensureVisible(find.byKey(const ValueKey('spec-cost-turns')));
    await tester.tap(find.byKey(const ValueKey('spec-cost-turns')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('spec-turns-dialog')), findsOneWidget);
    expect(find.text('Turnos da spec (3)'), findsOneWidget);
    final rows = tester
        .widgetList<InkWell>(
          find.descendant(
            of: find.byKey(const ValueKey('spec-turns-dialog')),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is InkWell &&
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('spec-turn-'),
            ),
          ),
        )
        .toList();
    expect(rows.first.key, const ValueKey('spec-turn-2'));
    expect(find.text('Etapa R2'), findsOneWidget);
    expect(find.text('sonnet'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with the spec running, the section shows "agora" with the '
      'weight in the current 5-hour window, in teal with "rodando" (R7)', (
    tester,
  ) async {
    final (_, db) = await pumpBoard(
      tester,
      overrides: [
        ...quota,
        liveQuotaWeightsProvider.overrideWithValue(const {'s-live': 0.09}),
      ],
    );
    final spec = await specId(db, 'SPEC-002');
    await session(db, spec, 's-live', status: SessionStatus.running);
    await addEntry(
      db,
      spec,
      source: UsageSource.etapa,
      step: 'R2',
      sessionId: 's-live',
      week: 0.01,
      five: 0.2,
    );
    await pumpFor(tester);
    await openPanel(tester, 'SPEC-002');
    expect(text(tester, 'spec-cost-now-text'), 'agora ≈ 9% · 5 h, rodando');
    final style = tester
        .widget<Text>(find.byKey(const ValueKey('spec-cost-now-text')))
        .style!;
    expect(style.color, const Color(0xFF4FD1B5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a ruler yet: "—" and the % after the first reading; '
      'the history of before is marked as estimated (R3, R5)', (tester) async {
    final (_, db) = await pumpBoard(tester, overrides: quota);
    final spec = await specId(db, 'SPEC-001');
    await addEntry(db, spec, source: UsageSource.etapa, tokens: 1200000);
    await addEntry(
      db,
      spec,
      source: UsageSource.vibe,
      tokens: 1000,
      estimated: true,
    );
    await pumpFor(tester);
    await openPanel(tester, 'SPEC-001');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spec-cost-week')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('spec-cost-no-ruler')), findsOneWidget);
    expect(find.byKey(const ValueKey('spec-cost-estimated')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spec-cost-tokens')),
        matching: find.text('1,2 M'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('with an API key the panel shows the US\$ with "estimativa do '
      'CLI" and keeps the divisions; the card still has no cost (R12)', (
    tester,
  ) async {
    final (_, db) = await pumpBoard(
      tester,
      overrides: [costInDollarsProvider.overrideWithValue(true)],
    );
    final spec = await specId(db, 'SPEC-002');
    await addEntry(
      db,
      spec,
      source: UsageSource.etapa,
      step: 'R1',
      cost: 3.0,
      tokens: 1000000,
    );
    await addEntry(db, spec, source: UsageSource.revisor, cost: 0.62);
    await addEntry(db, spec, source: UsageSource.ci, step: 'R1', cost: 0.5);
    await pumpFor(tester);
    final card = find.byKey(const ValueKey('board-card-SPEC-002'));
    expect(
      find.descendant(of: card, matching: find.textContaining('US\$')),
      findsNothing,
    );
    await openPanel(tester, 'SPEC-002');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spec-cost-usd')),
        matching: find.text('US\$ 4,12'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('spec-cost-cli-estimate')),
      findsOneWidget,
    );
    expect(
      text(tester, 'spec-cost-cli-estimate'),
      contains('estimativa do CLI'),
    );
    expect(find.byKey(const ValueKey('spec-cost-week')), findsNothing);
    expect(
      find.byKey(const ValueKey('spec-cost-source-revisor')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('spec-cost-step-R1')), findsOneWidget);
    expect(find.text('Custo'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
