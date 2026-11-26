import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_probe.dart' show CodexModelInfo;
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/duel_attempt.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/board/widgets/duel_dialog.dart';
import 'package:promptorium/features/board/widgets/duel_start_dialog.dart';
import 'package:promptorium/ui/providers/provider_logos.dart';

import '../../helpers/test_db.dart';

/// SPEC-108 R11: "Executar em dobro (A/B)" asks for the provider of each
/// attempt, and the result says who did what, never in US$.
void main() {
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pumpFor(WidgetTester tester, [int n = 25]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  late Spec spec;

  Future<void> pump(
    WidgetTester tester, {
    ProviderAvailability codex = const ProviderAvailability(
      ProviderStatus.ready,
      'ok',
    ),
    ProviderFlows? flows,
    String? recorded,
    required void Function(BuildContext) open,
  }) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        providerAvailabilityProvider.overrideWith((ref, id) async => codex),
        if (flows != null) providerFlowsProvider.overrideWithValue(flows),
      ],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: '/work/repo', name: 'r');
      spec = await c
          .read(specsRepoProvider)
          .insert(
            workspaceId: ws.id,
            code: 'SPEC-073',
            title: 'Corrigir CI',
            path: 'docs/specs/SPEC-073.md',
          );
      await c.read(appSettingsProvider.notifier).load();
      final settings = c.read(appSettingsProvider.notifier);
      await settings.set(
        codexModelsCacheKey,
        CodexModelsCache(
          version: '0.170.0',
          readAt: DateTime(2026, 11, 20),
          models: const [
            CodexModelInfo('gpt-6.2-sol', ['low', 'medium'], ['text']),
          ],
        ).encode(),
      );
      if (recorded != null) {
        await settings.set('spec.${spec.id}.provider', recorded);
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => open(context),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await pumpFor(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await pumpFor(tester);
  }

  testWidgets('the default is the current configuration of both', (
    tester,
  ) async {
    DuelAttempts? got;
    await pump(
      tester,
      open: (ctx) async => got = await showDuelStartDialog(ctx, spec),
    );
    expect(key('duel-start-dialog'), findsOneWidget);
    expect(find.text('modelo da etapa'), findsNWidgets(2));
    await tester.tap(key('duel-start'));
    await pumpFor(tester);
    const same = DuelAttempt(provider: 'claude');
    expect(got, (a: same, b: same));
  });

  testWidgets('a spec begun on the Codex starts with it', (tester) async {
    DuelAttempts? got;
    await pump(
      tester,
      recorded: 'codex',
      open: (ctx) async => got = await showDuelStartDialog(ctx, spec),
    );
    await tester.tap(key('duel-start'));
    await pumpFor(tester);
    expect(got!.a.provider, 'codex');
    expect(got!.b.provider, 'codex');
  });

  testWidgets('"Claude × Codex", then model and effort of the Codex from its '
      'catalog', (tester) async {
    DuelAttempts? got;
    await pump(
      tester,
      open: (ctx) async => got = await showDuelStartDialog(ctx, spec),
    );
    await tester.tap(key('duel-claude-codex'));
    await pumpFor(tester);
    expect(
      find.descendant(of: key('duel-provider-B'), matching: find.text('Codex')),
      findsOneWidget,
    );
    expect(find.text('gpt-6.2-sol (padrão)'), findsOneWidget);
    await tester.tap(key('duel-effort-B'));
    await pumpFor(tester);
    expect(key('duel-effort-B-max'), findsNothing);
    await tester.tap(key('duel-effort-B-medium'));
    await pumpFor(tester);
    await tester.tap(key('duel-model-A'));
    await pumpFor(tester);
    await tester.tap(key('duel-model-A-haiku'));
    await pumpFor(tester);
    expect(
      tester.widget<Text>(key('duel-access-B')).data,
      'modo da etapa · escreve só no worktree',
    );
    await tester.tap(key('duel-start'));
    await pumpFor(tester);
    expect(got, (
      a: const DuelAttempt(provider: 'claude', model: 'haiku'),
      b: const DuelAttempt(provider: 'codex', effort: 'medium'),
    ));
  });

  testWidgets('without the sandbox the Codex attempt says it runs YOLO in '
      'its worktree', (tester) async {
    await pump(
      tester,
      codex: const ProviderAvailability(
        ProviderStatus.ready,
        'ok',
        sandboxWarning: 'bwrap',
      ),
      open: (ctx) => showDuelStartDialog(ctx, spec),
    );
    await tester.tap(key('duel-claude-codex'));
    await pumpFor(tester);
    expect(
      tester.widget<Text>(key('duel-access-B')).data,
      'sem sandbox: YOLO, só no worktree da tentativa',
    );
  });

  for (final (name, status, flows, reason) in [
    (
      'not installed',
      const ProviderAvailability(ProviderStatus.missing, 'x'),
      null,
      'Codex não está instalado.',
    ),
    (
      'without Executar spec (SPEC-101)',
      const ProviderAvailability(ProviderStatus.ready, 'ok'),
      ProviderFlows.defaults.copyWith('codex', const {AppFlow.prompt}),
      flowLockedMessage('Codex', AppFlow.runSpec),
    ),
  ]) {
    testWidgets('Codex $name: off, with the reason', (tester) async {
      await pump(
        tester,
        codex: status,
        flows: flows,
        open: (ctx) => showDuelStartDialog(ctx, spec),
      );
      expect(tester.widget<Text>(key('duel-codex-reason')).data, reason);
      await tester.tap(key('duel-claude-codex'));
      await pumpFor(tester);
      expect(find.text('modelo da etapa'), findsNWidgets(2));
      await tester.tap(key('duel-provider-B'));
      await pumpFor(tester);
      expect(
        tester
            .widget<PopupMenuItem<String>>(key('duel-provider-B-codex'))
            .enabled,
        isFalse,
      );
    });
  }

  testWidgets('the result shows provider, model, gate, time and tokens of '
      'each attempt, never US\$', (tester) async {
    final stats = {
      'sa': const DuelStats(
        provider: 'claude',
        model: 'sonnet',
        effort: 'medium',
        durationMs: 370000,
        tokensIn: 212000,
        tokensOut: 9800,
      ),
      'sb': const DuelStats(
        provider: 'codex',
        model: 'gpt-6.2-sol',
        effort: 'medium',
        durationMs: 272000,
        tokensIn: 168000,
        tokensOut: 12500,
        reasoning: 5400,
      ),
    };
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final report = GateReport(
      at: DateTime(2026, 11, 25),
      checks: const [GateCheck(name: 'testes', ok: true, output: '')],
    ).encode();
    final duel = SpecDuel(
      id: 1,
      specId: 1,
      steps: 'R4',
      baseSha: 'abc',
      worktreeA: '/nao/existe/a',
      worktreeB: '/nao/existe/b',
      branchA: 'a',
      branchB: 'b',
      sessionA: 'sa',
      sessionB: 'sb',
      reportA: report,
      reportB: report,
      state: 'pronto',
      createdAt: DateTime(2026, 11, 25),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseOverride(memoryDatabase()),
          duelStatsProvider.overrideWith((ref, id) async => stats[id]),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDuelDialog(context, duel),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await pumpFor(tester);
    expect(
      tester
          .widgetList<ProviderChip>(find.byType(ProviderChip))
          .map((p) => p.provider),
      ['claude', 'codex'],
    );
    expect(tester.widget<Text>(key('duel-model-A')).data, 'Sonnet · medium');
    expect(
      tester.widget<Text>(key('duel-model-B')).data,
      'gpt-6.2-sol · medium',
    );
    expect(
      tester.widget<Text>(key('duel-cost-A')).data,
      'Tempo 6 min 10 s · Tokens 212,0 mil → 9,8 mil',
    );
    expect(
      tester.widget<Text>(key('duel-cost-B')).data,
      'Tempo 4 min 32 s · Tokens 168,0 mil → 7,1 mil · raciocínio 5,4 mil',
    );
    expect(find.textContaining('testes'), findsWidgets);
    expect(key('duel-stats-B'), findsOneWidget);
    expect(key('duel-tokenizers'), findsOneWidget);
    expect(find.textContaining('US\$'), findsNothing);
  });
}
