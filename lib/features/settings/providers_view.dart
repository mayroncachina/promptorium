import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/acp_provider.dart';
import '../../core/update/update_check.dart';
import '../../data/providers.dart';
import '../../ui/shell/about_dialog.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../sessions/widgets/session_style.dart';

/// Configurações → Provedores (F18): the ACP agents offered in the Prompt
/// screen besides Claude Code, one per line (`nome = comando`).
class AcpProvidersCard extends ConsumerStatefulWidget {
  const AcpProvidersCard({super.key});

  @override
  ConsumerState<AcpProvidersCard> createState() => _AcpProvidersCardState();
}

class _AcpProvidersCardState extends ConsumerState<AcpProvidersCard> {
  late final _text = TextEditingController(
    text:
        ref.read(appSettingsProvider.notifier).get(AppSettingKeys.acpAgents) ??
        defaultAcpAgents,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agents = parseAcpAgents(_text.text);
    return AgentCard(
      title: 'Provedores · agentes ACP no Prompt',
      children: [
        const Text(
          'Agentes que falam o Agent Client Protocol (JSON-RPC pelo stdio) '
          'aparecem no seletor de provedor do Prompt. Um por linha: '
          'nome = comando.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('acp-agents'),
          controller: _text,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(fontSize: 12, fontFamily: AppFonts.mono),
          decoration: const InputDecoration(isDense: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                '${agents.length} agente(s): '
                '${agents.map((a) => a.name).join(', ')}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            SmallButton(
              key: const ValueKey('acp-agents-save'),
              label: 'Salvar',
              onTap: () => ref
                  .read(appSettingsProvider.notifier)
                  .set(AppSettingKeys.acpAgents, _text.text.trim()),
            ),
          ],
        ),
      ],
    );
  }
}

/// Configurações → Atualizações (F18).
class UpdatesCard extends ConsumerStatefulWidget {
  const UpdatesCard({super.key});

  @override
  ConsumerState<UpdatesCard> createState() => _UpdatesCardState();
}

class _UpdatesCardState extends ConsumerState<UpdatesCard> {
  bool _busy = false;
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateCheckerProvider);
    final settings = ref.watch(appSettingsProvider);
    final on = settings[UpdateChecker.enabledKey] != '0';
    final version = ref.watch(appVersionProvider).value;
    return AgentCard(
      title: version == null
          ? 'Atualizações'
          : 'Atualizações · versão $version',
      children: [
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            key: const ValueKey('update-check-toggle'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: on,
            title: const Text(
              'Avisar quando houver versão nova (GitHub Releases, uma vez '
              'por dia)',
              style: TextStyle(fontSize: 12),
            ),
            onChanged: (v) => ref
                .read(appSettingsProvider.notifier)
                .set(UpdateChecker.enabledKey, v ? '1' : '0'),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                update != null
                    ? 'Versão ${update.version} disponível.'
                    : _checked
                    ? 'Você está na versão mais recente.'
                    : '',
                key: const ValueKey('update-status'),
                style: TextStyle(
                  fontSize: 12,
                  color: update != null ? AppColors.amber : AppColors.textMuted,
                ),
              ),
            ),
            if (update != null)
              SmallButton(
                label: 'Abrir página',
                onTap: () => Process.run('xdg-open', [update.url]),
              ),
            const SizedBox(width: 6),
            SmallButton(
              key: const ValueKey('open-about'),
              label: 'Sobre',
              onTap: () => showAboutPromptorium(context),
            ),
            const SizedBox(width: 6),
            SmallButton(
              key: const ValueKey('update-check-now'),
              label: _busy ? 'Verificando…' : 'Verificar agora',
              onTap: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await ref
                          .read(updateCheckerProvider.notifier)
                          .check(force: true);
                      if (mounted) {
                        setState(() {
                          _busy = false;
                          _checked = true;
                        });
                      }
                    },
            ),
          ],
        ),
      ],
    );
  }
}
