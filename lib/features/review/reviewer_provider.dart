import 'package:flutter/foundation.dart';

import '../../core/providers/capabilities.dart';
import '../../core/providers/provider_preferences.dart';
import '../project/project_config.dart';

/// Who reviews a spec or a PR (SPEC-102 R2, R3).
@immutable
class ReviewerChoice {
  const ReviewerChoice({
    required this.provider,
    required this.executedBy,
    this.fromConfig = false,
    this.fromPlan = false,
  });

  /// The provider of the round (`claude`, `codex`…).
  final String provider;

  /// The provider that executed the spec (or ran the PR's session).
  final String executedBy;

  /// An explicit `provedor:` of the config decided it (R3: "do config do
  /// projeto").
  final bool fromConfig;

  /// The rule Revisão of the Orquestrador's plan decided it (Automático,
  /// SPEC-035 R8): the Claude Code until the SPEC-109.
  final bool fromPlan;

  /// The reviewer is not the provider that executed: "segunda opinião"
  /// (R9).
  bool get secondOpinion => provider != executedBy;

  @override
  bool operator ==(Object other) =>
      other is ReviewerChoice &&
      other.provider == provider &&
      other.executedBy == executedBy &&
      other.fromConfig == fromConfig &&
      other.fromPlan == fromPlan;

  @override
  int get hashCode => Object.hash(provider, executedBy, fromConfig, fromPlan);
}

/// The other provider of a second opinion (Claude Code ↔ Codex).
String otherReviewerProvider(String executedBy) =>
    executedBy == ProviderCapabilities.codex.providerId
    ? ProviderCapabilities.claude.providerId
    : ProviderCapabilities.codex.providerId;

/// Resolves `revisor: provedor:` (R2) for a spec executed by [executedBy]
/// (for a PR without spec, the provider of its session). [auto] = the spec
/// runs in Automático: the plan's rule (Claude Code) holds unless the
/// config sets `provedor:` explicitly (R3).
ReviewerChoice resolveReviewerChoice(
  ReviewerConfig config, {
  required String executedBy,
  bool auto = false,
}) {
  final exec = executedBy.isEmpty
      ? ProviderCapabilities.claude.providerId
      : executedBy;
  if (auto && !config.explicitProvider) {
    return ReviewerChoice(
      provider: ProviderCapabilities.claude.providerId,
      executedBy: exec,
      fromPlan: true,
    );
  }
  final provider = switch (config.provider) {
    ReviewerProvider.other => otherReviewerProvider(exec),
    ReviewerProvider.claude => ProviderCapabilities.claude.providerId,
    ReviewerProvider.codex => ProviderCapabilities.codex.providerId,
    _ => exec,
  };
  return ReviewerChoice(
    provider: provider,
    executedBy: exec,
    fromConfig: config.explicitProvider,
  );
}

/// The provider that executed a spec, from its sessions (SPEC-102 R2):
/// the last step session's; none or only Claude sessions → `claude`.
/// The SPEC-101 records it per run; until then the sessions tell.
String executionProviderOf(Iterable<String> sessionProviders) =>
    sessionProviders.lastOrNull ?? ProviderCapabilities.claude.providerId;

/// `app_settings` key of the local Codex model of the reviewer (R4).
const codexReviewerModelKey = 'codex.model.reviewer';

/// Claude Code model names that never go to another provider (R4).
bool isClaudeModelAlias(String model) {
  final m = model.trim().toLowerCase();
  return const {
        'haiku',
        'sonnet',
        'opus',
        'max',
        'opusplan',
        'default',
      }.contains(m) ||
      m.startsWith('claude');
}

/// The Codex model of the reviewer (R4): `modelo-codex:` of the config >
/// `codex.model.reviewer` > null (the model of the kind, read from the
/// `model/list`). A Claude alias, or a model gone from the cached catalog,
/// is skipped.
String? reviewerCodexModel(
  ReviewerConfig config,
  Map<String, String> settings,
) {
  for (final m in [config.codexModel, settings[codexReviewerModelKey]]) {
    if (m == null || m.trim().isEmpty || m == 'inherit') continue;
    if (isClaudeModelAlias(m)) continue;
    if (providerModelMissing(
      settings,
      ProviderCapabilities.codex.providerId,
      m,
    )) {
      continue;
    }
    return m.trim();
  }
  return null;
}

/// The model the reviewer will use on [provider], as the dialogs show it
/// (R4): Claude → `modelo:` (or the plan's rule); Codex → [reviewerCodexModel]
/// or the Codex model of the planner kind.
String reviewerModelLabel(
  ReviewerChoice choice,
  ReviewerConfig config,
  Map<String, String> settings, {
  String? planModel,
}) {
  if (isClaudeCode(choice.provider)) return planModel ?? config.model;
  return reviewerCodexModel(config, settings) ??
      settings['${choice.provider}.model.planner'] ??
      'padrão';
}

/// "segunda opinião" (R9).
const secondOpinionLabel = 'segunda opinião';

/// Who reviewed a round (R9): "Codex gpt-6.1-terra · segunda opinião".
/// Null for rounds of before (no provider saved): they read as before.
/// [executedBy] = the provider that executed the spec / ran the PR.
String? reviewerAuthorLabel(
  String? provider,
  String? model, {
  String? executedBy,
}) {
  if (provider == null || provider.isEmpty) return null;
  final name = capabilitiesFor(provider).displayName;
  final m = model == null || model.isEmpty ? '' : ' $model';
  final second = executedBy != null && executedBy != provider
      ? ' · $secondOpinionLabel'
      : '';
  return '$name$m$second';
}

/// Text of the warning of R7, once per spec.
const ownReviewerAgentNotice =
    'O revisor do projeto (.claude/agents/spec-reviewer.md) é só do Claude '
    'Code; esta rodada usou o revisor embutido do Promptorium.';

/// "Revisar com o Claude Code desta vez" (R2).
String reviewOnceLabel(String failedProvider) =>
    'Revisar com o '
    '${capabilitiesFor(otherReviewerProvider(failedProvider)).displayName} '
    'desta vez';
