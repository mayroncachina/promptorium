import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/run_prefs.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../context/context_snapshot.dart' show autocompactLabel;
import 'settings_choices.dart';

/// Configurações → Consumo → Codex: the Codex compaction threshold
/// (SPEC-107 R6, P1). Its own preference (`codex.autocompact`), starting at
/// the agent's default; it never changes Claude's `--autocompact`.
class CodexAutocompactCard extends ConsumerWidget {
  const CodexAutocompactCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(runPrefsProvider);
    final settings = ref.read(appSettingsProvider.notifier);
    return AgentCard(
      title: 'Compactação automática do Codex',
      children: [
        choices(
          keyPrefix: 'settings-codex-autocompact',
          values: [
            for (final a in autocompactChoices)
              (a, a == 'auto' ? 'Padrão do agente' : a),
          ],
          selected: prefs.codexAutocompact,
          onTap: (v) => settings.set(AppSettingKeys.codexAutocompact, v),
        ),
        const SizedBox(height: 12),
        Text(
          'Enviado a cada execução do Codex como '
          'model_auto_compact_token_limit. "Padrão do agente" não envia '
          'nada e o Codex compacta no limite dele. Separado do Claude Code '
          '(hoje em ${autocompactLabel(prefs.autocompact)}): mudar um não '
          'mexe no outro. Vale para as próximas execuções.',
          key: const ValueKey('settings-codex-autocompact-hint'),
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
