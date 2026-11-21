import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../claude/run_prefs.dart';
import '../codex/codex_probe.dart' show CodexModelInfo;
import 'capabilities.dart';

String providerPreferenceKey(int? workspaceId) => workspaceId == null
    ? 'agent.provider.default'
    : 'agent.provider.workspace.$workspaceId';

final defaultAgentProvider = Provider.family<String, int?>((ref, workspaceId) {
  final settings = ref.watch(appSettingsProvider);
  // A saved Codex default stays Codex even while its flows are off: each
  // flow says why it does not run (R12), nothing switches by itself.
  return settings[providerPreferenceKey(workspaceId)] ??
      settings[providerPreferenceKey(null)] ??
      'claude';
});

final activeAgentProvider = Provider<String>(
  (ref) =>
      ref.watch(defaultAgentProvider(ref.watch(activeWorkspaceProvider)?.id)),
);

/// `app_settings` key of the cached Codex `model/list` (P2).
const codexModelsCacheKey = 'codex.models.cache';

/// The Codex model catalog read from `model/list`, with the CLI version and
/// the time of reading (SPEC-094 R8). Opening Configurações never waits for
/// the Codex to answer.
class CodexModelsCache {
  const CodexModelsCache({
    required this.version,
    required this.readAt,
    required this.models,
  });

  final String? version;
  final DateTime readAt;
  final List<CodexModelInfo> models;

  bool has(String model) => models.any((m) => m.id == model);

  CodexModelInfo? byId(String model) =>
      models.where((m) => m.id == model).firstOrNull;

  String encode() => jsonEncode({
    'version': version,
    'readAt': readAt.toIso8601String(),
    'models': [for (final m in models) m.toJson()],
  });

  static CodexModelsCache? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return CodexModelsCache(
        version: j['version'] as String?,
        readAt: DateTime.parse(j['readAt'] as String),
        models: [
          for (final m in j['models'] as List? ?? const [])
            CodexModelInfo.fromJson(m as Map<String, dynamic>),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

CodexModelsCache? codexModelsCache(Map<String, String> settings) =>
    CodexModelsCache.decode(settings[codexModelsCacheKey]);

/// Model saved for [provider] and [kind], as stored (may be gone).
String savedProviderModel(
  RunPrefs prefs,
  Map<String, String> settings,
  String provider,
  RunKind kind,
) => isClaudeCode(provider)
    ? prefs.model(kind)
    : settings['$provider.model.${kind.name}'] ?? 'inherit';

/// A saved Codex model missing from the cached `model/list` (R9).
bool providerModelMissing(
  Map<String, String> settings,
  String provider,
  String model,
) {
  if (model == 'inherit' || model.isEmpty) return false;
  if (provider != ProviderCapabilities.codex.providerId) return false;
  final cache = codexModelsCache(settings);
  return cache != null && !cache.has(model);
}

/// Model a run of [provider] uses: the saved one, or the provider default
/// (`inherit`) when the saved model left the catalog (R9). Claude aliases
/// never go to Codex and vice versa (R8): each reads its own keys.
String providerModelFrom(
  RunPrefs prefs,
  Map<String, String> settings,
  String provider,
  RunKind kind,
) {
  final saved = savedProviderModel(prefs, settings, provider, kind);
  return providerModelMissing(settings, provider, saved) ? 'inherit' : saved;
}

String providerEffortFrom(
  RunPrefs prefs,
  Map<String, String> settings,
  String provider,
  RunKind kind,
) => isClaudeCode(provider)
    ? prefs.effort(kind)
    : settings['$provider.effort.${kind.name}'] ?? 'default';

String providerModel(Ref ref, String provider, RunKind kind) =>
    providerModelFrom(
      ref.read(runPrefsProvider),
      ref.read(appSettingsProvider),
      provider,
      kind,
    );

String providerEffort(Ref ref, String provider, RunKind kind) =>
    providerEffortFrom(
      ref.read(runPrefsProvider),
      ref.read(appSettingsProvider),
      provider,
      kind,
    );
