import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';

import '../../../helpers/test_db.dart';
import 'orchestrator_fixture.dart' show codexCatalog;

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

  group('SPEC-109', () {
    OrchestratorPrefs prefs([Map<String, String> extra = const {}]) =>
        OrchestratorPrefs({...codexCatalog(), ...extra});

    test('R1: with everything at the default no rule leaves the Claude Code '
        'and nothing diverts', () {
      for (final p in [const OrchestratorPrefs({}), prefs()]) {
        expect(StepKind.values.every((k) => p.rule(k).isClaude), isTrue);
        expect(p.usesCodex, isFalse);
        expect(p.divertOnQuota, isFalse);
        expect(p.divertAbovePercent, isNull);
        expect(p.divertPercent, 90);
        expect(p.secondOpinion, isFalse);
        expect(p.codexLadder, CodexLadder.effort);
        expect(p.classifier, const StepRule('haiku', 'low'));
        expect(p.isDefault, isTrue);
      }
    });

    test('R1: a rule on the Codex takes model and effort from model/list', () {
      final p = prefs({
        AppSettingKeys.orchestratorProvider('mecanica'): 'codex',
        AppSettingKeys.orchestratorModel('mecanica'): 'gpt-6-luna',
        AppSettingKeys.orchestratorEffort('mecanica'): 'low',
        // `max` exists only in the Claude levels; luna does not take it.
        AppSettingKeys.orchestratorProvider('documentacao'): 'codex',
        AppSettingKeys.orchestratorModel('documentacao'): 'opus',
        AppSettingKeys.orchestratorEffort('documentacao'): 'max',
      });
      expect(
        p.rule(StepKind.mecanica),
        const StepRule('gpt-6-luna', 'low', provider: 'codex'),
      );
      expect(p.rule(StepKind.mecanica).fullLabel, 'Codex · gpt-6-luna · low');
      // A Claude alias never goes to the Codex: the first of the catalog.
      final doc = p.rule(StepKind.documentacao);
      expect((doc.model, doc.effort), ('gpt-6.2-sol', 'default'));
      expect(doc.label, 'gpt-6.2-sol · esforço padrão');
      expect(p.usesCodex, isTrue);
      expect(p.isDefault, isFalse);
    });

    test('R2, P6: the reserve by default, edited and "sem reserva"', () {
      var p = prefs();
      expect(
        p.fallback(StepKind.implementacao),
        const StepRule('gpt-6.2-sol', 'medium', provider: 'codex'),
      );
      expect(
        p.fallback(StepKind.altoRisco),
        const StepRule('gpt-6.2-sol', 'high', provider: 'codex'),
      );
      p = prefs({'codex.model.session': 'gpt-6-luna'});
      expect(p.fallback(StepKind.mecanica)?.model, 'gpt-6-luna');
      p = prefs({
        AppSettingKeys.orchestratorFallback('mecanica'): 'codex|gpt-6-luna|low',
        AppSettingKeys.orchestratorFallback('altoRisco'): 'none',
        AppSettingKeys.orchestratorProvider('documentacao'): 'codex',
      });
      expect(
        p.fallback(StepKind.mecanica),
        const StepRule('gpt-6-luna', 'low', provider: 'codex'),
      );
      expect(p.fallback(StepKind.altoRisco), isNull);
      // A rule on the Codex goes back to the table.
      expect(p.fallback(StepKind.documentacao), const StepRule('haiku', 'low'));
      // A line the person moved to the Codex: the rule is the reserve.
      expect(
        p.fallback(StepKind.implementacao, from: 'codex'),
        const StepRule('sonnet', 'medium'),
      );
    });

    test(
      'R1, R2: switching the provider of a rule keeps the other side as '
      'the reserve; Restaurar padrão goes back to the Claude table',
      () async {
        final db = memoryDatabase();
        final c = ProviderContainer(
          overrides: [databaseOverride(db)],
          retry: (_, _) => null,
        );
        addTearDown(c.dispose);
        final settings = c.read(appSettingsProvider.notifier);
        await settings.load();
        for (final MapEntry(:key, :value) in codexCatalog().entries) {
          await settings.set(key, value);
        }
        final ctl = c.read(orchestratorPrefsProvider.notifier);
        await ctl.setModel(StepKind.mecanica, 'sonnet');
        await ctl.setProvider(StepKind.mecanica, 'codex');
        var p = c.read(orchestratorPrefsProvider);
        expect(p.rule(StepKind.mecanica).provider, 'codex');
        expect(p.fallback(StepKind.mecanica), const StepRule('sonnet', 'low'));
        await ctl.setModel(StepKind.mecanica, 'gpt-6-luna');
        await ctl.setProvider(StepKind.mecanica, 'claude');
        p = c.read(orchestratorPrefsProvider);
        expect(p.rule(StepKind.mecanica), const StepRule('sonnet', 'low'));
        expect(p.fallback(StepKind.mecanica)?.model, 'gpt-6-luna');
        await ctl.setFallback(StepKind.mecanica, null);
        await ctl.setDivertOnQuota(true);
        await ctl.setDivertAbove(true);
        await ctl.setDivertPercent(80);
        await ctl.setSecondOpinion(true);
        await ctl.setCodexLadder(CodexLadder.models);
        await ctl.setCodexLadderModels(['gpt-6-luna', 'gpt-6.2-sol']);
        await ctl.setClassifier(
          const StepRule('gpt-6-luna', 'low', provider: 'codex'),
        );
        p = OrchestratorPrefs(await c.read(appSettingsRepoProvider).getAll());
        expect(p.fallback(StepKind.mecanica), isNull);
        expect(p.divertOnQuota, isTrue);
        expect(p.divertAbovePercent, 80);
        expect(p.secondOpinion, isTrue);
        expect(p.codexLadderModels, ['gpt-6-luna', 'gpt-6.2-sol']);
        expect(
          p.classifier,
          const StepRule('gpt-6-luna', 'low', provider: 'codex'),
        );
        await ctl.reset();
        expect(c.read(orchestratorPrefsProvider).isDefault, isTrue);
      },
    );

    test(
      'the line Revisão keeps its provider; the old form is Claude',
      () async {
        const codex = StepRule('gpt-6.2-sol', 'medium', provider: 'codex');
        final key = AppSettingKeys.orchestratorReviewOf(1);
        final p = prefs();
        expect(
          reviewRuleOf({key: 'sonnet|medium'}, 1, p),
          const StepRule('sonnet', 'medium'),
        );
        expect(reviewRuleOf({key: 'gpt-6.2-sol|medium|codex'}, 1, p), codex);
      },
    );
  });
}
