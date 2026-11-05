import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';

import '../../../helpers/test_db.dart';

void main() {
  test('defaults are the table of R2 (Revisão = Sonnet · medium, D5)', () {
    const p = OrchestratorPrefs({});
    expect(
      {for (final k in StepKind.values) k: p.rule(k)},
      {
        StepKind.mecanica: const StepRule('haiku', 'low'),
        StepKind.implementacao: const StepRule('sonnet', 'medium'),
        StepKind.altoRisco: const StepRule('opus', 'high'),
        StepKind.documentacao: const StepRule('haiku', 'low'),
        StepKind.revisao: const StepRule('sonnet', 'medium'),
      },
    );
    expect(p.autoByDefault, isFalse);
    expect(p.maxEscalations, 2);
    expect(p.askBeforeOpus, isFalse);
    expect(p.classifierModel, 'haiku');
    expect(p.isDefault, isTrue);
    expect(const StepRule('opus', 'high').label, 'Opus · high');
  });

  test('invalid stored values fall back to the defaults', () {
    final p = OrchestratorPrefs({
      AppSettingKeys.orchestratorEffort('mecanica'): 'turbo',
      AppSettingKeys.orchestratorEscalations: '5',
      AppSettingKeys.orchestratorClassifierModel: 'opus',
      AppSettingKeys.orchestratorAutoByDefault: 'sim',
    });
    expect(p.rule(StepKind.mecanica), const StepRule('haiku', 'low'));
    expect(p.maxEscalations, 2);
    expect(p.classifierModel, 'haiku');
    expect(p.autoByDefault, isFalse);
  });

  test('StepKind.parse: an unknown kind is Implementação', () {
    expect(StepKind.parse('altoRisco'), StepKind.altoRisco);
    expect(StepKind.parse('refatoracao'), StepKind.implementacao);
    expect(StepKind.parse(null), StepKind.implementacao);
  });

  test('round-trip in app_settings and Restaurar padrão', () async {
    final db = memoryDatabase();
    final c = ProviderContainer(
      overrides: [databaseOverride(db)],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ctl = c.read(orchestratorPrefsProvider.notifier);
    await ctl.setModel(StepKind.mecanica, 'sonnet');
    await ctl.setEffort(StepKind.altoRisco, 'max');
    await ctl.setAutoByDefault(true);
    await ctl.setMaxEscalations(0);
    await ctl.setAskBeforeOpus(true);
    await ctl.setClassifierModel('sonnet');

    // A fresh read of the database sees the same values.
    final stored = await c.read(appSettingsRepoProvider).getAll();
    final p = OrchestratorPrefs(stored);
    expect(p.rule(StepKind.mecanica), const StepRule('sonnet', 'low'));
    expect(p.rule(StepKind.altoRisco), const StepRule('opus', 'max'));
    expect(p.autoByDefault, isTrue);
    expect(p.maxEscalations, 0);
    expect(p.askBeforeOpus, isTrue);
    expect(p.classifierModel, 'sonnet');
    expect(c.read(orchestratorPrefsProvider).isDefault, isFalse);

    await ctl.reset();
    expect(c.read(orchestratorPrefsProvider).isDefault, isTrue);
    final after = await c.read(appSettingsRepoProvider).getAll();
    expect(after.keys.where((k) => k.startsWith('orchestrator.')), isEmpty);
  });
}
