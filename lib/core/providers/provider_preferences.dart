import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../claude/run_prefs.dart';

String providerPreferenceKey(int? workspaceId) => workspaceId == null
    ? 'agent.provider.default'
    : 'agent.provider.workspace.$workspaceId';

final defaultAgentProvider = Provider.family<String, int?>((ref, workspaceId) {
  final settings = ref.watch(appSettingsProvider);
  return settings[providerPreferenceKey(workspaceId)] ??
      settings[providerPreferenceKey(null)] ??
      'claude';
});

final activeAgentProvider = Provider<String>(
  (ref) =>
      ref.watch(defaultAgentProvider(ref.watch(activeWorkspaceProvider)?.id)),
);

String providerModel(Ref ref, String provider, RunKind kind) =>
    provider == 'claude'
    ? ref.read(runPrefsProvider).model(kind)
    : ref.read(appSettingsProvider)['$provider.model.${kind.name}'] ??
          'inherit';

String providerEffort(Ref ref, String provider, RunKind kind) =>
    provider == 'claude'
    ? ref.read(runPrefsProvider).effort(kind)
    : ref.read(appSettingsProvider)['$provider.effort.${kind.name}'] ??
          'default';
