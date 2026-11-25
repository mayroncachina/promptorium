import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_args.dart';
import '../../../core/claude/run_prefs.dart' show defaultEffort;
import '../../../core/providers/capabilities.dart';
import '../../../core/providers/provider_preferences.dart';
import '../../../data/providers.dart';
import '../spec_run_provider.dart' show codexModelEfforts, codexRunModel;

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

/// Models of the Claude rules and of their ladder, weakest first: alias and
/// label. The models of the Codex come from its `model/list` (SPEC-109 R1).
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

/// Short name of a provider in the plan: `Claude`, `Codex`.
String planProviderLabel(String provider) =>
    isClaudeCode(provider) ? 'Claude' : capabilitiesFor(provider).displayName;

/// The other provider of the Orquestrador (Claude Code ↔ Codex).
String otherPlanProvider(String provider) =>
    isClaudeCode(provider) ? 'codex' : 'claude';

/// Provider, model and effort of a [StepKind].
@immutable
class StepRule {
  const StepRule(this.model, this.effort, {this.provider = 'claude'});

  /// Model alias (`haiku`, `sonnet`, `opus`) or a model id of the Codex
  /// catalog.
  final String model;

  /// `--effort` level (`low`, `medium`…), or one of the efforts the Codex
  /// catalog gives for [model].
  final String effort;

  /// `claude` or `codex` (SPEC-109 R1).
  final String provider;

  bool get isClaude => isClaudeCode(provider);

  /// `Sonnet · medium`.
  String get label {
    final m = model == 'inherit' && !isClaude
        ? 'modelo padrão'
        : orchestratorModelLabel(model);
    final e = effort == defaultEffort && !isClaude ? 'esforço padrão' : effort;
    return '$m · $e';
  }

  /// `Codex · gpt-6-luna · low`.
  String get fullLabel => '${planProviderLabel(provider)} · $label';

  /// [label], with the provider when it is not [other]'s.
  String labelBeside(StepRule other) =>
      other.provider == provider ? label : fullLabel;

  /// `codex|gpt-6-luna|low` (a stored reserve).
  String encode() => '$provider|$model|$effort';

  static StepRule? decode(String? raw) {
    final p = raw?.split('|');
    if (p == null || p.length != 3 || p[0].isEmpty || p[1].isEmpty) return null;
    return StepRule(p[1], p[2], provider: p[0]);
  }

  @override
  bool operator ==(Object other) =>
      other is StepRule &&
      other.model == model &&
      other.effort == effort &&
      other.provider == provider;

  @override
  int get hashCode => Object.hash(model, effort, provider);

  @override
  String toString() => isClaude
      ? 'StepRule($model, $effort)'
      : 'StepRule($provider, $model, $effort)';
}

/// How a step climbs on the Codex (SPEC-109 R3, P2).
enum CodexLadder {
  /// The same model, with the effort going up.
  effort,

  /// A list of models the person orders.
  models,
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

  static const defaultDivertOnQuota = false;
  static const defaultDivertAbove = false;
  static const defaultDivertPercent = 90;
  static const defaultSecondOpinion = false;

  /// Choices of the N% of the preventive diversion (SPEC-109 R6).
  static const divertPercentChoices = [70, 80, 90, 95];

  /// Stored value of "sem reserva" (SPEC-109 R2).
  static const noFallback = 'none';

  /// Choices of "Escaladas por etapa".
  static const escalationChoices = [2, 1, 0];

  StepRule rule(StepKind k) {
    final d = defaultRules[k]!;
    final model = _settings[AppSettingKeys.orchestratorModel(k.name)];
    final effort = _settings[AppSettingKeys.orchestratorEffort(k.name)];
    final provider = _settings[AppSettingKeys.orchestratorProvider(k.name)];
    // SPEC-109 R1: model and effort of the Codex catalog.
    if (provider == ProviderCapabilities.codex.providerId) {
      return codexRule(model: model, effort: effort);
    }
    return StepRule(
      model == null || model.isEmpty ? d.model : model,
      effort == null || !orchestratorEfforts.contains(effort)
          ? d.effort
          : effort,
    );
  }

  /// The catalog of the Codex (`model/list`, SPEC-094): model ids.
  List<String> get codexModels => [
    for (final m in codexModelsCache(_settings)?.models ?? const []) m.id,
  ];

  /// The efforts [model] takes (SPEC-109 R1: never a fixed list), `default`
  /// first.
  List<String> codexEfforts(String model) =>
      codexModelEfforts(_settings, model);

  /// A rule on the Codex: [model] when the catalog has it, else the Codex
  /// default of "Executar spec"; [effort] when the model takes it, else its
  /// default.
  StepRule codexRule({String? model, String? effort}) {
    final m = codexRunModel(_settings, requested: model);
    return StepRule(
      m,
      effort != null && codexEfforts(m).contains(effort)
          ? effort
          : defaultEffort,
      provider: ProviderCapabilities.codex.providerId,
    );
  }

  /// "Se a cota acabar" (SPEC-109 R2): the rule of [k] on the provider
  /// [from] is not on ([from] null = the rule of [k]); null = the kind has
  /// no reserve and never leaves. P6: by default the Codex model of
  /// "Executar spec" with the effort of the rule, or, for a rule on the
  /// Codex, the line of the SPEC-035 table.
  StepRule? fallback(StepKind k, {String? from}) {
    final own = rule(k);
    final origin = from ?? own.provider;
    final stored = _settings[AppSettingKeys.orchestratorFallback(k.name)];
    if (stored == noFallback) return null;
    final target = otherPlanProvider(origin);
    final saved = StepRule.decode(stored);
    if (saved != null && saved.provider == target) {
      return saved.isClaude
          ? saved
          : codexRule(model: saved.model, effort: saved.effort);
    }
    // A step on the other provider than its rule's (picked by the person):
    // the rule itself is its reserve.
    if (own.provider == target) return own;
    return isClaudeCode(target)
        ? defaultRules[k]!
        : codexRule(effort: own.effort);
  }

  /// "Desviar para o outro provedor quando a cota acabar" (R5).
  bool get divertOnQuota =>
      _flag(AppSettingKeys.orchestratorDivertOnQuota, defaultDivertOnQuota);

  /// "Desviar antes de começar uma etapa…" (R6); null = off.
  int? get divertAbovePercent =>
      _flag(AppSettingKeys.orchestratorDivertAbove, defaultDivertAbove)
      ? divertPercent
      : null;

  /// The N% of [divertAbovePercent], even when it is off.
  int get divertPercent {
    final v = int.tryParse(
      _settings[AppSettingKeys.orchestratorDivertAbovePercent] ?? '',
    );
    return v != null && divertPercentChoices.contains(v)
        ? v
        : defaultDivertPercent;
  }

  /// "No topo da escada, tentar o outro provedor" (R4).
  bool get secondOpinion =>
      _flag(AppSettingKeys.orchestratorSecondOpinion, defaultSecondOpinion);

  /// The ladder of the Codex (R3, P2).
  CodexLadder get codexLadder =>
      _settings[AppSettingKeys.orchestratorCodexLadder] ==
          CodexLadder.models.name
      ? CodexLadder.models
      : CodexLadder.effort;

  /// The models of [CodexLadder.models], weakest first; the ones gone from
  /// the catalog are skipped.
  List<String> get codexLadderModels {
    final catalog = codexModels;
    return [
      for (final m
          in (_settings[AppSettingKeys.orchestratorCodexLadderModels] ?? '')
              .split(','))
        if (m.trim().isNotEmpty &&
            (catalog.isEmpty || catalog.contains(m.trim())))
          m.trim(),
    ];
  }

  /// Any rule runs on the Codex.
  bool get usesCodex => StepKind.values.any((k) => !rule(k).isClaude);

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

  /// Who classifies (SPEC-109 R11): [classifierModel] on the Claude Code,
  /// or `codex|<model>` of the catalog, with the effort `low` when it takes
  /// it.
  StepRule get classifier {
    final v = _settings[AppSettingKeys.orchestratorClassifierModel];
    if (v != null && v.startsWith('codex|') && v.length > 6) {
      return codexRule(model: v.substring(6), effort: 'low');
    }
    return StepRule(classifierModel, 'low');
  }

  /// Claude model alias of the classification (R3).
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
        classifier == d.classifier &&
        !divertOnQuota &&
        divertAbovePercent == null &&
        !secondOpinion &&
        codexLadder == CodexLadder.effort &&
        StepKind.values.every(
          (k) => _settings[AppSettingKeys.orchestratorFallback(k.name)] == null,
        );
  }

  /// Every key of the Orquestrador in `app_settings`.
  static List<String> get keys => [
    for (final k in StepKind.values) ...[
      AppSettingKeys.orchestratorModel(k.name),
      AppSettingKeys.orchestratorEffort(k.name),
      AppSettingKeys.orchestratorProvider(k.name),
      AppSettingKeys.orchestratorFallback(k.name),
    ],
    AppSettingKeys.orchestratorAutoByDefault,
    AppSettingKeys.orchestratorEscalations,
    AppSettingKeys.orchestratorAskBeforeOpus,
    AppSettingKeys.orchestratorClassifierModel,
    AppSettingKeys.orchestratorDivertOnQuota,
    AppSettingKeys.orchestratorDivertAbove,
    AppSettingKeys.orchestratorDivertAbovePercent,
    AppSettingKeys.orchestratorSecondOpinion,
    AppSettingKeys.orchestratorCodexLadder,
    AppSettingKeys.orchestratorCodexLadderModels,
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
    final key = AppSettingKeys.orchestratorProvider(k.name);
    rule.isClaude
        ? await _settings.remove(key)
        : await _settings.set(key, rule.provider);
  }

  Future<void> setModel(StepKind k, String model) {
    final r = state.rule(k);
    return setRule(
      k,
      r.isClaude
          ? StepRule(model, r.effort)
          : state.codexRule(model: model, effort: r.effort),
    );
  }

  Future<void> setEffort(StepKind k, String effort) {
    final r = state.rule(k);
    return setRule(k, StepRule(r.model, effort, provider: r.provider));
  }

  /// The rule of [k] goes to [provider] (SPEC-109 R1): the reserve it had
  /// there, so switching back and forth loses nothing; the rule it leaves
  /// becomes the reserve.
  Future<void> setProvider(StepKind k, String provider) async {
    final old = state.rule(k);
    if (old.provider == provider) return;
    final next =
        state.fallback(k) ??
        (isClaudeCode(provider)
            ? OrchestratorPrefs.defaultRules[k]!
            : state.codexRule(effort: old.effort));
    final stored = state._settings[AppSettingKeys.orchestratorFallback(k.name)];
    if (stored != OrchestratorPrefs.noFallback) await setFallback(k, old);
    await setRule(k, next);
  }

  /// "Se a cota acabar" of [k] (R2); null = sem reserva.
  Future<void> setFallback(StepKind k, StepRule? rule) => _settings.set(
    AppSettingKeys.orchestratorFallback(k.name),
    rule?.encode() ?? OrchestratorPrefs.noFallback,
  );

  Future<void> setDivertOnQuota(bool on) =>
      _settings.set(AppSettingKeys.orchestratorDivertOnQuota, on ? '1' : '0');

  Future<void> setDivertAbove(bool on) =>
      _settings.set(AppSettingKeys.orchestratorDivertAbove, on ? '1' : '0');

  Future<void> setDivertPercent(int n) =>
      _settings.set(AppSettingKeys.orchestratorDivertAbovePercent, '$n');

  Future<void> setSecondOpinion(bool on) =>
      _settings.set(AppSettingKeys.orchestratorSecondOpinion, on ? '1' : '0');

  Future<void> setCodexLadder(CodexLadder v) =>
      _settings.set(AppSettingKeys.orchestratorCodexLadder, v.name);

  Future<void> setCodexLadderModels(List<String> models) => _settings.set(
    AppSettingKeys.orchestratorCodexLadderModels,
    models.join(','),
  );

  /// Who classifies (R11): a Claude alias, or a model of the Codex.
  Future<void> setClassifier(StepRule r) =>
      setClassifierModel(r.isClaude ? r.model : 'codex|${r.model}');

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

/// Stores [rule], the line "Revisão" of the plan of [specId] (null = the
/// spec runs in Manual, or the reviewer is off): the automatic reviewer
/// reads it with [reviewRuleOf].
Future<void> storeReviewRule(
  AppSettingsController settings,
  int specId,
  StepRule? rule,
) {
  final key = AppSettingKeys.orchestratorReviewOf(specId);
  return rule == null
      ? settings.remove(key)
      : settings.set(
          key,
          // The Claude Code keeps the old form (`sonnet|medium`).
          rule.isClaude
              ? '${rule.model}|${rule.effort}'
              : '${rule.model}|${rule.effort}|${rule.provider}',
        );
}

/// The rule of the automatic reviewer of a spec run in Automático (R8): the
/// line "Revisão" chosen in Executar, else the rule Revisão of [prefs].
StepRule reviewRuleOf(
  Map<String, String> settings,
  int specId,
  OrchestratorPrefs prefs,
) {
  final parts = settings[AppSettingKeys.orchestratorReviewOf(specId)]?.split(
    '|',
  );
  if (parts != null &&
      (parts.length == 2 || parts.length == 3) &&
      parts[0].isNotEmpty) {
    return StepRule(
      parts[0],
      parts[1],
      provider: parts.length == 3 ? parts[2] : 'claude',
    );
  }
  return prefs.rule(StepKind.revisao);
}
