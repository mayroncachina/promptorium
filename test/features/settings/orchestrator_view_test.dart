import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/settings/orchestrator_view.dart';
import 'package:promptorium/features/settings/settings_screen.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

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
    expect(find.text('Perguntar antes de escalar para Opus'), findsOneWidget);
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

    await tap('orchestrator-model-mecanica-sonnet');
    await tap('orchestrator-effort-mecanica-high');
    await tap('orchestrator-effort-revisao-max');
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
}
