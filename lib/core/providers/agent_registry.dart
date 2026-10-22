import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../claude/claude_cli.dart';
import '../codex/codex_cli.dart';
import '../codex/codex_provider.dart';
import '../claude/claude_process.dart' show ProcessStarter;
import '../../ui/widgets/app_icon.dart';
import 'acp_provider.dart';
import 'agent_provider.dart';
import 'claude_code_provider.dart';

export 'acp_provider.dart';
export 'agent_provider.dart';
export 'claude_code_provider.dart';

/// Starter of the ACP agents (tests inject a fake process).
final acpStarterProvider = Provider<ProcessStarter?>((ref) => null);

/// Codex integration switch. Off for now: Codex is listed as "em breve" and
/// never started; saved Codex sessions fail with an explicit message. Tests of
/// the adapter override it to true.
final codexEnabledProvider = Provider<bool>((ref) => false);

/// Every provider shown in the Prompt menu, in order: Claude Code, the ACP
/// agents of Configurações → Provedores (F18; default Gemini CLI) and Codex.
final agentProvidersProvider = Provider<List<AgentProvider>>((ref) {
  final acp =
      ref.watch(
        appSettingsProvider.select((s) => s[AppSettingKeys.acpAgents]),
      ) ??
      defaultAcpAgents;
  return [
    ClaudeCodeProvider(
      executable: ref.watch(claudeExecutableProvider),
      starter: ref.watch(claudeProcessStarterProvider),
    ),
    for (final a in parseAcpAgents(acp))
      AcpProvider(
        id: a.id,
        displayName: a.name,
        command: a.command,
        starter: ref.watch(acpStarterProvider),
      ),
    if (ref.watch(codexEnabledProvider))
      CodexProvider(
        executable: ref.watch(codexExecutableProvider),
        starter: ref.watch(codexProcessStarterProvider),
      )
    else
      ComingSoonProvider(
        id: 'codex',
        displayName: 'Codex',
        icon: AppIcons.code,
      ),
  ];
});

/// Provider by id; unknown ids fail rather than switching providers.
final agentProviderByIdProvider = Provider.family<AgentProvider, String>((
  ref,
  id,
) {
  final all = ref.watch(agentProvidersProvider);
  for (final p in all) {
    if (p.id == id) return p;
  }
  throw AgentUnavailable(
    'Provedor desconhecido: $id. Selecione um provedor disponível.',
  );
});
