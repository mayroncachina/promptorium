import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_args.dart';
import '../../../data/providers.dart';

/// Kind of a step, given by the classification of the Orquestrador
/// (SPEC-035 R2). Stored by `name` (`spec_steps.kind`, `step_runs.kind`).
enum StepKind {
  mecanica('Mecânica', 'Renomear, mover, ajustar valores, sem lógica nova'),
  implementacao('Implementação', 'Tela, serviço ou regra nova, com testes'),
  altoRisco('Alto risco', 'Migração, concorrência, segurança, arquitetura'),
  documentacao('Documentação', 'Só texto: ajuda, README, changelog'),
  revisao('Revisão', 'Revisão automática do diff (auto_reviewer)');

  const StepKind(this.label, this.hint);

  final String label;
  final String hint;

  /// The kind stored as [name]; an unknown or missing one is
  /// [implementacao] (Design, R3).
  static StepKind parse(String? name) =>
      values.where((k) => k.name == name).firstOrNull ?? implementacao;
}

/// Models of the rules and of the ladder, weakest first (Claude Code only,
/// D5): alias and label.
const orchestratorModels = [
  ('haiku', 'Haiku'),
  ('sonnet', 'Sonnet'),
  ('opus', 'Opus'),
];

/// Models that can classify the steps (R3, R6).
const classifierModels = [('haiku', 'Haiku'), ('sonnet', 'Sonnet')];

/// `--effort` levels of a rule.
const orchestratorEfforts = ClaudeOptions.effortLevels;

/// `sonnet` → `Sonnet` (unknown aliases as they are).
String orchestratorModelLabel(String id) =>
    orchestratorModels.where((m) => m.$1 == id).firstOrNull?.$2 ?? id;

/// Model and effort of a [StepKind].
@immutable
class StepRule {
  const StepRule(this.model, this.effort);

  /// Model alias (`haiku`, `sonnet`, `opus`).
  final String model;

  /// `--effort` level (`low`, `medium`…).
  final String effort;

  /// `Sonnet · medium`.
  String get label => '${orchestratorModelLabel(model)} · $effort';

  @override
  bool operator ==(Object other) =>
      other is StepRule && other.model == model && other.effort == effort;

  @override
  int get hashCode => Object.hash(model, effort);

  @override
  String toString() => 'StepRule($model, $effort)';
}

/// Preferences of the Orquestrador, stored in `app_settings`
/// (`orchestrator.*` keys) and valid for every project (R7). Read when a
/// plan is made: the plan copied to `spec_steps` does not follow later
/// changes.
@immutable
class OrchestratorPrefs {
  const OrchestratorPrefs(this._settings);

  final Map<String, String> _settings;

  /// The table of R2 (Revisão = Sonnet · medium, D5).
  static const defaultRules = {
    StepKind.mecanica: StepRule('haiku', 'low'),
    StepKind.implementacao: StepRule('sonnet', 'medium'),
    StepKind.altoRisco: StepRule('opus', 'high'),
    StepKind.documentacao: StepRule('haiku', 'low'),
    StepKind.revisao: StepRule('sonnet', 'medium'),
  };
  static const defaultAutoByDefault = false;
  static const defaultEscalations = 2;
  static const defaultAskBeforeOpus = false;
  static const defaultClassifierModel = 'haiku';

  /// Choices of "Escaladas por etapa".
  static const escalationChoices = [2, 1, 0];

  StepRule rule(StepKind k) {
    final d = defaultRules[k]!;
    final model = _settings[AppSettingKeys.orchestratorModel(k.name)];
    final effort = _settings[AppSettingKeys.orchestratorEffort(k.name)];
    return StepRule(
      model == null || model.isEmpty ? d.model : model,
      effort == null || !orchestratorEfforts.contains(effort)
          ? d.effort
          : effort,
    );
  }

  /// "Abrir Executar em Automático" (R1, R19).
  bool get autoByDefault =>
      _flag(AppSettingKeys.orchestratorAutoByDefault, defaultAutoByDefault);

  /// "Escaladas por etapa": 0, 1 or 2 (R9).
  int get maxEscalations {
    final v = int.tryParse(
      _settings[AppSettingKeys.orchestratorEscalations] ?? '',
    );
    return v != null && escalationChoices.contains(v) ? v : defaultEscalations;
  }

  /// "Perguntar antes de escalar para Opus" (R12).
  bool get askBeforeOpus =>
      _flag(AppSettingKeys.orchestratorAskBeforeOpus, defaultAskBeforeOpus);

  /// Model alias of the classification (R3).
  String get classifierModel {
    final v = _settings[AppSettingKeys.orchestratorClassifierModel];
    return classifierModels.any((m) => m.$1 == v) ? v! : defaultClassifierModel;
  }

  bool _flag(String key, bool fallback) => switch (_settings[key]) {
    '1' => true,
    '0' => false,
    _ => fallback,
  };

  /// Whether any value differs from the defaults ("alterado" dot).
  bool get isDefault {
    const d = OrchestratorPrefs({});
    return StepKind.values.every((k) => rule(k) == d.rule(k)) &&
        autoByDefault == d.autoByDefault &&
        maxEscalations == d.maxEscalations &&
        askBeforeOpus == d.askBeforeOpus &&
        classifierModel == d.classifierModel;
  }

  /// Every key of the Orquestrador in `app_settings`.
  static List<String> get keys => [
    for (final k in StepKind.values) ...[
      AppSettingKeys.orchestratorModel(k.name),
      AppSettingKeys.orchestratorEffort(k.name),
    ],
    AppSettingKeys.orchestratorAutoByDefault,
    AppSettingKeys.orchestratorEscalations,
    AppSettingKeys.orchestratorAskBeforeOpus,
    AppSettingKeys.orchestratorClassifierModel,
  ];
}

/// The current [OrchestratorPrefs] and their changes (Configurações →
/// Orquestrador). Writes go to `app_settings` ([AppSettingsController]).
class OrchestratorPrefsController extends Notifier<OrchestratorPrefs> {
  @override
  OrchestratorPrefs build() =>
      OrchestratorPrefs(ref.watch(appSettingsProvider));

  AppSettingsController get _settings => ref.read(appSettingsProvider.notifier);

  Future<void> setRule(StepKind k, StepRule rule) async {
    await _settings.set(AppSettingKeys.orchestratorModel(k.name), rule.model);
    await _settings.set(AppSettingKeys.orchestratorEffort(k.name), rule.effort);
  }

  Future<void> setModel(StepKind k, String model) =>
      setRule(k, StepRule(model, state.rule(k).effort));

  Future<void> setEffort(StepKind k, String effort) =>
      setRule(k, StepRule(state.rule(k).model, effort));

  Future<void> setAutoByDefault(bool on) =>
      _settings.set(AppSettingKeys.orchestratorAutoByDefault, on ? '1' : '0');

  Future<void> setMaxEscalations(int n) =>
      _settings.set(AppSettingKeys.orchestratorEscalations, '$n');

  Future<void> setAskBeforeOpus(bool on) =>
      _settings.set(AppSettingKeys.orchestratorAskBeforeOpus, on ? '1' : '0');

  Future<void> setClassifierModel(String model) =>
      _settings.set(AppSettingKeys.orchestratorClassifierModel, model);

  /// "Restaurar padrão": every key of the Orquestrador goes away.
  Future<void> reset() async {
    for (final key in OrchestratorPrefs.keys) {
      await _settings.remove(key);
    }
  }
}

final orchestratorPrefsProvider =
    NotifierProvider<OrchestratorPrefsController, OrchestratorPrefs>(
      OrchestratorPrefsController.new,
    );
