import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/cost/cost_format.dart';
import 'package:promptorium/features/cost/quota_ruler.dart';
import 'package:promptorium/features/cost/spec_cost.dart';
import 'package:promptorium/features/cost/usage_ledger.dart';
import 'package:promptorium/features/cost/widgets/spec_cost_section.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/codex/codex_replay.dart' show replayCodex;
import '../../helpers/test_db.dart';
import 'spec_cost_ranking_test.dart' show addSpec, pumpFor, pumpRanking, spend;

int _id = 0;

UsageEntry entry({
  String provider = 'claude',
  double cost = 0,
  double? week,
  int tokens = 1000,
  int reasoning = 0,
  int? specId = 1,
  String? step,
  UsageSource source = UsageSource.etapa,
}) => UsageEntry(
  id: ++_id,
  workspaceId: 1,
  specId: specId,
  source: source,
  step: step,
  at: DateTime(2026, 11, 20, 14),
  tokensIn: tokens,
  tokensCacheWrite: 0,
  tokensCacheRead: 0,
  tokensOut: 0,
  costUsd: cost,
  weekPct: week,
  estimated: false,
  provider: provider,
  tokensReasoning: reasoning,
);

/// The `result` of a Codex turn as the adapter emits it.
Result codexResult({int reasoning = 15}) => ClaudeEvent.fromJson({
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'cost_available': false,
  'num_turns': 1,
  'usage': {
    'input_tokens': 2672,
    'cache_read_input_tokens': 10112,
    'output_tokens': 145,
    'reasoning_output_tokens': reasoning,
  },
}) as Result;

// SPEC-097 R8–R10.
void main() {
  group('ledger (R8, R10)', () {
    late AppDatabase db;
    late ProviderContainer c;
    late int ws;

    setUp(() async {
      db = memoryDatabase();
      c = ProviderContainer(overrides: [databaseOverride(db)]);
      await c.read(appSettingsProvider.notifier).load();
      ws = await db
          .into(db.workspaces)
          .insert(WorkspacesCompanion.insert(path: '/r', name: 'r'));
    });
    tearDown(() => c.dispose());

    test('a Codex turn records the provider, the tokens with reasoning and '
        'no cost nor weight', () async {
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'cx',
              workspaceId: ws,
              worktreePath: '/r',
              branch: 'b',
              model: 'gpt-5.5',
              provider: const Value('codex'),
            ),
          );
      // A ruler exists: a Claude turn would get a weight.
      c.read(quotaRulerProvider.notifier).state = const QuotaRuler(
        fiveHour: RulerTrack(divisions: [0.5, 0.5, 0.5]),
        sevenDay: RulerTrack(divisions: [0.05, 0.05, 0.05]),
      );
      expect(c.read(quotaRulerProvider).ready, isTrue);
      final ledger = c.read(usageLedgerProvider);
      // Even a cost that came by mistake is not recorded as measured.
      await ledger.recordSessionTurn('cx', codexResult(), costUsd: 0.3);
      final e = (await db.select(db.usageEntries).get()).single;
      expect(e.provider, 'codex');
      expect(e.tokensIn, 2672);
      expect(e.tokensCacheRead, 10112);
      expect(e.tokensOut, 145);
      expect(e.tokensReasoning, 15);
      expect(e.costUsd, 0);
      expect(e.weekPct, isNull);
      expect(e.fiveHourPct, isNull);
      expect(entryHasCost(e), isFalse);

      // The pending weights skip it: it has nothing to weigh.
      await ledger.applyPendingWeights();
      final again = (await db.select(db.usageEntries).get()).single;
      expect(again.weekPct, isNull);
    });

    test('a Claude turn still records claude with its cost', () async {
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'cl',
              workspaceId: ws,
              worktreePath: '/r',
              branch: 'b',
              model: 'sonnet',
            ),
          );
      await c
          .read(usageLedgerProvider)
          .recordSessionTurn(
            'cl',
            ClaudeEvent.fromJson({
              'type': 'result',
              'subtype': 'success',
              'total_cost_usd': 0.2,
              'usage': {'input_tokens': 10, 'output_tokens': 5},
            }) as Result,
            costUsd: 0.2,
          );
      final e = (await (db.select(
        db.usageEntries,
      )..orderBy([(e) => OrderingTerm.asc(e.id)])).get()).single;
      expect(e.provider, 'claude');
      expect(e.costUsd, 0.2);
      expect(e.tokensReasoning, 0);
    });

    test('the Codex adapter emits the reasoning tokens of the turn', () async {
      final events = await replayCodex('edicao');
      final r = events.whereType<Result>().last;
      expect(r.json['cost_available'], isFalse);
      expect(reasoningTokensOf(r), greaterThan(0));
    });
  });

  group('cost of a spec (R9)', () {
    test('a mixed spec sums the US\$ of the Claude and the Codex tokens', () {
      final cost = specCostOf([
        entry(provider: 'codex', tokens: 612000, reasoning: 20, step: 't1'),
        entry(provider: 'codex', tokens: 588000, step: 't2'),
        entry(cost: 4.2, week: 0.06, tokens: 402000, step: 'REV1'),
      ]);
      final t = cost.total;
      expect(t.costUsd, closeTo(4.2, 1e-9));
      expect(t.week, closeTo(0.06, 1e-9));
      expect(t.tokens, 1602000);
      expect(t.unpricedTokens, 1200000);
      expect(t.pricedTokens, 402000);
      expect(t.reasoning, 20);
      expect(t.hasUnpriced, isTrue);
      expect(t.onlyUnpriced, isFalse);
      expect(
        formatMixedCost(t.costUsd, t.unpricedTokens),
        'US\$ 4,20 (Claude Code) + 1,2 mi tokens (Codex)',
      );
      final step = cost.bySteps.firstWhere((s) => s.$1 == 't1').$2;
      expect(step.onlyUnpriced, isTrue);
    });

    test('the ranking orders only what has a cost; token-only specs go '
        'apart', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final ws = await db
          .into(db.workspaces)
          .insertReturning(WorkspacesCompanion.insert(path: '/r', name: 'r'));
      final specs = <int, (Spec, Workspace)>{};
      for (final code in ['SPEC-081', 'SPEC-084', 'SPEC-090']) {
        final s = await db
            .into(db.specs)
            .insertReturning(
              SpecsCompanion.insert(
                workspaceId: ws.id,
                code: code,
                title: code,
                path: '$code.md',
              ),
            );
        specs[s.id] = (s, ws);
      }
      final ids = specs.keys.toList();
      final entries = [
        entry(specId: ids[0], cost: 18.4, week: 0.2),
        entry(specId: ids[1], cost: 0.01, week: 0.001),
        entry(specId: ids[2], provider: 'codex', tokens: 820000),
      ];
      final ranked = rankSpecCosts(entries, specs: specs);
      expect([for (final r in ranked) r.spec.code], ['SPEC-081', 'SPEC-084']);
      final apart = rankTokenOnlySpecs(entries, specs: specs);
      expect([for (final r in apart) r.spec.code], ['SPEC-090']);
    });

    test('a run without cost never shows \$0.00', () {
      expect(formatRunCost('codex', 0), 'custo indisponível');
      expect(formatRunCost('claude', 1.5), '\$1.50');
      expect(formatTokenWords(1200000), '1,2 mi');
      expect(formatTokenWords(820000), '820 mil');
    });
  });

  group('widgets (R9)', () {
    Future<void> pumpSection(
      WidgetTester tester,
      List<UsageEntry> entries, {
      required bool dollars,
    }) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          costInDollarsProvider.overrideWithValue(dollars),
          liveQuotaWeightsProvider.overrideWithValue(const {}),
          specCostProvider.overrideWith((ref, id) => specCostOf(entries)),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: SingleChildScrollView(child: SpecCostSection(specId: 1)),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final dollars in [true, false]) {
      testWidgets('a mixed spec shows the mixed total, never US\$ 0,00 '
          '(${dollars ? 'chave de API' : 'plano'})', (tester) async {
        await pumpSection(tester, [
          entry(provider: 'codex', tokens: 612000, step: 't1'),
          entry(provider: 'codex', tokens: 588000, step: 't2'),
          entry(cost: 4.2, week: 0.06, tokens: 402000, step: 'REV1'),
        ], dollars: dollars);
        expect(
          find.text('US\$ 4,20 (Claude Code) + 1,2 mi tokens (Codex)'),
          findsOneWidget,
        );
        expect(find.textContaining('US\$ 0,00'), findsNothing);
        expect(find.text(costUnavailableShort), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a spec only of the Codex: custo indisponível and tokens', (
      tester,
    ) async {
      await pumpSection(tester, [
        entry(provider: 'codex', tokens: 1200000, step: 't1'),
      ], dollars: true);
      expect(
        find.text('custo indisponível · 1,2 mi tokens (Codex)'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('spec-cost-usd')),
          matching: find.text('indisponível'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('US\$ 0,00'), findsNothing);
      expect(
        find.byKey(const ValueKey('spec-cost-unpriced-note')),
        findsOneWidget,
      );
    });

    testWidgets('the ranking lists the token-only specs apart, not as the '
        'cheapest', (tester) async {
      final env = await pumpRanking(tester, dollars: true);
      final a = await addSpec(env.db, env.a, 'SPEC-081', 'Custo por spec');
      final mixed = await addSpec(env.db, env.a, 'SPEC-086', 'Notificação');
      final codex = await addSpec(env.db, env.a, 'SPEC-090', 'Título único');
      await spend(env.db, env.a, a, week: 0.2, cost: 18.4);
      await spend(env.db, env.a, mixed, week: 0.05, cost: 4.2);
      for (final s in [mixed, codex]) {
        await env.db
            .into(env.db.usageEntries)
            .insert(
              UsageEntriesCompanion.insert(
                workspaceId: Value(env.a.id),
                specId: Value(s),
                source: UsageSource.etapa,
                at: DateTime.now().subtract(const Duration(days: 1)),
                tokensIn: const Value(820000),
                provider: const Value('codex'),
              ),
            );
      }
      await pumpFor(tester);
      expect(
        find.byKey(const ValueKey('spec-cost-rank-SPEC-081')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-cost-rank-SPEC-090')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('spec-cost-token-only')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-cost-token-SPEC-090')),
        findsOneWidget,
      );
      // The mixed one stays in the ranking with the mark of its tokens.
      expect(find.text('US\$ 4,20 +'), findsOneWidget);
      expect(find.textContaining('US\$ 0,00'), findsNothing);
    });
  });
}
