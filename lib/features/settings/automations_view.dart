import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/managed_hooks.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';

/// Configurações → Automações: the hooks the app adds to every session
/// ([ManagedHook]), each one on / off, with what it did last.
class AutomationsCard extends ConsumerWidget {
  const AutomationsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final activity = ref.watch(hookActivityProvider);
    final python = ref.watch(pythonAvailableProvider).value;
    return AgentCard(
      title: 'Automações · hooks do app nas sessões',
      children: [
        if (python == false)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'python3 não encontrado: os hooks ficam desligados até ele '
              'ser instalado.',
              key: ValueKey('automations-no-python'),
              style: TextStyle(fontSize: 12, color: AppColors.amber),
            ),
          ),
        for (final h in ManagedHook.values) ...[
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              key: ValueKey('automation-${h.name}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: settings[h.settingKey] != '0',
              onChanged: (on) => ref
                  .read(appSettingsProvider.notifier)
                  .set(h.settingKey, on ? '1' : '0'),
              title: Text(
                '${h.label} · ${h.event}',
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                h.description,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          if (activity[h] case final a?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Último: ${a.text}',
                key: ValueKey('automation-last-${h.name}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: AppFonts.mono,
                  color: a.error ? AppColors.amber : AppColors.textMuted,
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        const Text(
          'Ficam num settings.json temporário de cada sessão (--settings), '
          'somados aos seus hooks; nada é escrito no ~/.claude. Valem a '
          'partir da próxima sessão iniciada ou retomada. A lista '
          'bloquear-comandos: e o comando formatar: ficam no config.yml do '
          'projeto.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
