import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/settings/orchestrator_view.dart';
import 'package:promptorium/features/settings/settings_screen.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../board/orchestrator/orchestrator_fixture.dart' show codexCatalog;

void main() {
  test('Orquestrador sits between "Modelo e consumo" and "Execução de '
      'specs" and is found by its words', () {
    const v = SettingsSection.values;
    expect(v.indexOf(SettingsSection.orchestrator), 1);
    expect(v[0], SettingsSection.consumption);
    expect(v[2], SettingsSection.specRuns);
    expect(filterSections('escalada'), [SettingsSection.orchestrator]);
    expect(sectionChanged(SettingsSection.orchestrator, const {}, null), false);
    expect(
      sectionChanged(SettingsSection.orchestrator, {
        AppSettingKeys.orchestratorModel('revisao'): 'opus',
      }, null),
      isTrue,
    );
  });

  test('the effect box tells what the values do', () {
    final text = orchestratorEffect(const OrchestratorPrefs({}));
    expect(text, contains('Executar abre em Manual'));
    expect(text, contains('Alto risco em Opus · high'));
    expect(text, contains('sobe até 2 degraus'));
    expect(text, contains('classificação usa Haiku'));
  });

  testWidgets('A seção Orquestrador edita regras, opções e "Restaurar '
      'padrão", e a mudança não altera execuções já iniciadas [R6] [R7]', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await tester.runAsync(() => c.read(appSettingsProvider.notifier).load());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('settings-nav-orchestrator')));
    await tester.pump();
    expect(find.byType(OrchestratorView), findsOneWidget);
    for (final k in StepKind.values) {
      expect(find.text(k.label), findsOneWidget);
    }
    expect(find.text('Abrir Executar em Automático'), findsOneWidget);
    expect(find.text('Escaladas por etapa'), findsOneWidget);
    expect(find.text('Perguntar antes do degrau mais alto'), findsOneWidget);
    expect(find.text('Classificar as etapas com'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-changed-orchestrator')),
      findsNothing,
    );

    // A plan made with the rules of now (T5 copies them to spec_steps when
    // the execution starts).
    final ws = await tester.runAsync(
      () => c.read(workspacesRepoProvider).add(path: '/r', name: 'r'),
    );
    final spec = await tester.runAsync(
      () => c
          .read(specsRepoProvider)
          .insert(
            workspaceId: ws!.id,
            code: 'SPEC-001',
            title: 'x',
            path: 'specs/SPEC-001.md',
          ),
    );
    final before = c.read(orchestratorPrefsProvider).rule(StepKind.mecanica);
    await tester.runAsync(
      () => c
          .read(specStepsRepoProvider)
          .setPlan(
            spec!.id,
            'R1',
            kind: StepKind.mecanica.name,
            model: before.model,
            effort: before.effort,
          ),
    );

    // Rules.
    Future<void> tap(String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pump();
    }

    Future<void> pick(String key, String text) async {
      await tap(key);
      await tester.pumpAndSettle();
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    await pick('orchestrator-model-mecanica', 'Sonnet');
    await pick('orchestrator-effort-mecanica', 'high');
    await pick('orchestrator-effort-revisao', 'max');
    var p = c.read(orchestratorPrefsProvider);
    expect(p.rule(StepKind.mecanica), const StepRule('sonnet', 'high'));
    expect(p.rule(StepKind.revisao), const StepRule('sonnet', 'max'));
    expect(p.rule(StepKind.altoRisco), const StepRule('opus', 'high'));

    // Options.
    await tap('orchestrator-auto-by-default');
    await tap('orchestrator-escalations-0');
    await tap('orchestrator-ask-opus');
    await tap('orchestrator-classifier-sonnet');
    p = c.read(orchestratorPrefsProvider);
    expect(p.autoByDefault, isTrue);
    expect(p.maxEscalations, 0);
    expect(p.askBeforeOpus, isTrue);
    expect(p.classifierModel, 'sonnet');
    expect(
      c.read(appSettingsProvider)[AppSettingKeys.orchestratorEscalations],
      '0',
    );
    expect(
      find.byKey(const ValueKey('settings-changed-orchestrator')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('settings-orchestrator-effect')),
              matching: find.byType(Text),
            ),
          )
          .data,
      contains('Executar abre em Automático'),
    );

    // The plan already written keeps the rule it started with (R7).
    final row = await tester.runAsync(
      () => c.read(specStepsRepoProvider).byStep(spec!.id, 'R1'),
    );
    expect((row!.planModel, row.planEffort), ('haiku', 'low'));

    // Restaurar padrão.
    await tap('settings-reset-orchestrator');
    p = c.read(orchestratorPrefsProvider);
    expect(p.isDefault, isTrue);
    expect(p.rule(StepKind.mecanica), const StepRule('haiku', 'low'));
    expect(p.autoByDefault, isFalse);
    expect(p.maxEscalations, 2);
    expect(
      find.byKey(const ValueKey('settings-changed-orchestrator')),
      findsNothing,
    );
    final stored = await tester.runAsync(
      () => c.read(appSettingsRepoProvider).getAll(),
    );
    expect(stored!.keys.where((k) => k.startsWith('orchestrator.')), isEmpty);
  });

  group('SPEC-109', () {
    late ProviderContainer c;

    Future<void> open(
      WidgetTester tester, {
      Map<String, String> settings = const {},
      ProviderAvailability codex = const ProviderAvailability(
        ProviderStatus.ready,
        'ok',
      ),
    }) async {
      tester.view.physicalSize = const Size(1366, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          providerAvailabilityProvider.overrideWith(
            (ref, id) async => id == 'codex'
                ? codex
                : const ProviderAvailability(ProviderStatus.ready, 'ok'),
          ),
        ],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      await tester.runAsync(() async {
        final n = c.read(appSettingsProvider.notifier);
        await n.load();
        for (final MapEntry(:key, :value) in {
          ...codexCatalog(),
          ...settings,
        }.entries) {
          await n.set(key, value);
        }
      });
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
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String key, String text) async {
      await tap(tester, key);
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    OrchestratorPrefs prefs() => c.read(orchestratorPrefsProvider);

    List<String> items(WidgetTester tester, String key) => [
      for (final i
          in tester
              .widget<DropdownButton<String>>(find.byKey(ValueKey(key)))
              .items!)
        i.value!,
    ];

    testWidgets('R1: a rule picks provider, model and effort; the ones of '
        'the Codex come from model/list; the default is all Claude', (
      tester,
    ) async {
      await open(tester);
      for (final k in StepKind.values) {
        expect(prefs().rule(k).isClaude, isTrue);
      }
      expect(find.textContaining('Codex indisponível'), findsNothing);
      await pick(tester, 'orchestrator-provider-mecanica', 'Codex');
      expect(items(tester, 'orchestrator-model-mecanica'), [
        'gpt-6.2-sol',
        'gpt-6-luna',
      ]);
      await pick(tester, 'orchestrator-model-mecanica', 'gpt-6-luna');
      expect(items(tester, 'orchestrator-effort-mecanica'), [
        'default',
        'low',
        'medium',
        'high',
      ]);
      await pick(tester, 'orchestrator-effort-mecanica', 'low');
      expect(
        prefs().rule(StepKind.mecanica),
        const StepRule('gpt-6-luna', 'low', provider: 'codex'),
      );
      // The other lines did not move.
      expect(prefs().rule(StepKind.altoRisco), const StepRule('opus', 'high'));
      expect(items(tester, 'orchestrator-model-altoRisco'), [
        'haiku',
        'sonnet',
        'opus',
      ]);
    });

    testWidgets('R1: a rule on the Codex says when it cannot run', (
      tester,
    ) async {
      await open(
        tester,
        settings: {AppSettingKeys.orchestratorProvider('mecanica'): 'codex'},
        codex: const ProviderAvailability(
          ProviderStatus.loginRequired,
          'rode codex login',
        ),
      );
      expect(find.text('Codex indisponível: login pendente'), findsOneWidget);
    });

    testWidgets('R2: the reserve is edited behind "Se a cota acabar"', (
      tester,
    ) async {
      await open(tester);
      expect(
        find.text('Codex · gpt-6.2-sol · high'),
        findsOneWidget,
        reason: 'Alto risco',
      );
      await tap(tester, 'orchestrator-fallback-toggle-altoRisco');
      await pick(tester, 'orchestrator-fallback-model-altoRisco', 'gpt-6-luna');
      await pick(tester, 'orchestrator-fallback-effort-altoRisco', 'medium');
      expect(
        prefs().fallback(StepKind.altoRisco),
        const StepRule('gpt-6-luna', 'medium', provider: 'codex'),
      );
      await pick(tester, 'orchestrator-fallback-on-altoRisco', 'sem reserva');
      expect(prefs().fallback(StepKind.altoRisco), isNull);
      await tap(tester, 'orchestrator-fallback-toggle-altoRisco');
      expect(find.text('sem reserva'), findsOneWidget);
      expect(prefs().rule(StepKind.altoRisco), const StepRule('opus', 'high'));
    });

    testWidgets('R3–R6: the ladder of the Codex and the options of the '
        'quota, all off by default', (tester) async {
      await open(tester);
      expect(
        find.text('low → medium → high → ultra · do model/list de gpt-6.2-sol'),
        findsOneWidget,
      );
      await tap(tester, 'orchestrator-ladder-models');
      await tap(tester, 'orchestrator-ladder-add-gpt-6.2-sol');
      await tap(tester, 'orchestrator-ladder-add-gpt-6-luna');
      await tap(tester, 'orchestrator-ladder-up-gpt-6-luna');
      expect(prefs().codexLadder, CodexLadder.models);
      expect(prefs().codexLadderModels, ['gpt-6-luna', 'gpt-6.2-sol']);

      expect(prefs().divertOnQuota, isFalse);
      expect(prefs().divertAbovePercent, isNull);
      expect(prefs().secondOpinion, isFalse);
      expect(
        find.byKey(const ValueKey('orchestrator-divert-no-sandbox')),
        findsNothing,
      );
      await tap(tester, 'orchestrator-divert-quota');
      await tap(tester, 'orchestrator-divert-above');
      await tester.tap(
        find.byKey(const ValueKey('orchestrator-divert-percent')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('80%').last);
      await tester.pumpAndSettle();
      await tap(tester, 'orchestrator-second-opinion');
      await tap(tester, 'orchestrator-ask-opus');
      expect(prefs().divertOnQuota, isTrue);
      expect(prefs().divertAbovePercent, 80);
      expect(prefs().secondOpinion, isTrue);
      expect(prefs().askBeforeOpus, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('decision 15: without the sandbox, the diversion says the '
        'Codex runs in YOLO', (tester) async {
      await open(
        tester,
        settings: {AppSettingKeys.orchestratorDivertOnQuota: '1'},
        codex: const ProviderAvailability(
          ProviderStatus.ready,
          'ok',
          sandboxWarning: 'x',
        ),
      );
      expect(
        find.byKey(const ValueKey('orchestrator-divert-no-sandbox')),
        findsOneWidget,
      );
    });

    testWidgets('R11: "Classificar as etapas com" takes a Codex model', (
      tester,
    ) async {
      await open(tester);
      await pick(tester, 'orchestrator-classifier-codex', 'gpt-6-luna');
      expect(
        prefs().classifier,
        const StepRule('gpt-6-luna', 'low', provider: 'codex'),
      );
      await tap(tester, 'orchestrator-classifier-haiku');
      expect(prefs().classifier, const StepRule('haiku', 'low'));
    });
  });
}
