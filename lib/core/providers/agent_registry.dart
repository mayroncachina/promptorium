import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/widgets/app_icon.dart';
import '../claude/claude_cli.dart';
import 'agent_provider.dart';
import 'claude_code_provider.dart';

export 'agent_provider.dart';
export 'claude_code_provider.dart';

/// Every provider shown in the Prompt menu, in order. Only Claude Code is
/// active; Codex and Gemini CLI are listed as "em breve" (DT-08).
final agentProvidersProvider = Provider<List<AgentProvider>>(
  (ref) => [
    ClaudeCodeProvider(
      executable: ref.watch(claudeExecutableProvider),
      starter: ref.watch(claudeProcessStarterProvider),
    ),
    ComingSoonProvider(id: 'codex', displayName: 'Codex', icon: AppIcons.code),
    ComingSoonProvider(
      id: 'gemini',
      displayName: 'Gemini CLI',
      icon: AppIcons.sparkle,
    ),
  ],
);

/// Provider by id (falls back to the first enabled one).
final agentProviderByIdProvider = Provider.family<AgentProvider, String>((
  ref,
  id,
) {
  final all = ref.watch(agentProvidersProvider);
  for (final p in all) {
    if (p.id == id) return p;
  }
  return all.firstWhere((p) => p.enabled);
});
