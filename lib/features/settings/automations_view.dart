import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/managed_hooks.dart';
import '../../core/codex/codex_hooks.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../sessions/widgets/codex_hooks_chip.dart' show hookWhenColor;
import '../sessions/widgets/session_style.dart' show Dot;

/// "Claude Code" / "Codex" of a hook's activity.
String hookProviderName(String provider) =>
    provider == 'codex' ? 'Codex' : 'Claude Code';

/// Label of a cell (R8): before the tool, after the turn, unavailable.
String hookWhenLabel(
  ManagedHook h,
  HookWhen? when, {
  required String provider,
}) {
  if (when == null) return 'Desligado';
  return switch (when) {
    HookWhen.beforeTool => switch (h) {
      ManagedHook.format =>
        provider == 'codex' ? 'Depois do apply_patch' : 'Depois da edição',
      ManagedHook.end => provider == 'codex' ? 'sessionEnd' : 'SessionEnd',
      _ => HookWhen.beforeTool.label,
    },
    // The block's substitute is the approval request (P2).
    HookWhen.afterTurn =>
      h == ManagedHook.block ? 'Na aprovação' : HookWhen.afterTurn.label,
    HookWhen.unavailable => HookWhen.unavailable.label,
  };
}

/// Configurações → Automações: the hooks the app adds to every session
/// ([ManagedHook]), each one on / off for both providers, with a column
/// per provider (SPEC-103 R8) and what it did last (R6).
class AutomationsCard extends ConsumerWidget {
  const AutomationsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final activity = ref.watch(hookActivityProvider);
    final python = ref.watch(pythonAvailableProvider).value;
    final latest = latestCodexHookStatus(ref.watch(codexHookStatusProvider));
    const head = TextStyle(
      fontSize: 10.5,
      letterSpacing: 0.8,
      color: AppColors.textMuted,
      fontWeight: FontWeight.w600,
    );
    return AgentCard(
      title: 'Automações · hooks do app nas sessões',
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Os mesmos hooks do app nos dois provedores. Ligar ou desligar '
            'vale para as próximas sessões iniciadas ou retomadas.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        if (python == false)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'python3 não encontrado: os hooks ficam desligados nos dois '
              'provedores até ele ser instalado; o Vigia de segredos confere '
              'ao fim do turno e antes do push.',
              key: ValueKey('automations-no-python'),
              style: TextStyle(fontSize: 12, color: AppColors.amber),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text('HOOK', style: head)),
              Expanded(flex: 3, child: Text('CLAUDE CODE', style: head)),
              Expanded(flex: 3, child: Text('CODEX', style: head)),
              Expanded(flex: 4, child: Text('ATIVIDADE', style: head)),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        for (final h in ManagedHook.values)
          _HookRow(
            hook: h,
            on: settings[h.settingKey] != '0',
            claude: claudeHookWhen(
              h,
              on: settings[h.settingKey] != '0',
              python: python,
            ),
            codex: codexHookWhen(
              h,
              on: settings[h.settingKey] != '0',
              python: python,
              latest: latest,
            ),
            latest: latest,
            last: activity[h],
            onChanged: (on) => ref
                .read(appSettingsProvider.notifier)
                .set(h.settingKey, on ? '1' : '0'),
          ),
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('automations-how'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: const Text(
            'Como entram · Claude Code: settings.json temporário (--settings). '
            'Codex: hooks de sessão (-c, origem sessionFlags), conferidos por '
            'hooks/list a cada sessão. Nada é escrito no ~/.claude nem no '
            '~/.codex, e o app nunca usa --trust. Seus hooks e os do projeto '
            'continuam rodando. A lista bloquear-comandos: e o comando '
            'formatar: ficam no config.yml do projeto.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Quando o Codex não aceita os hooks do app: Ao fim do turno = o '
          'substituto roda depois (vigia nos commits, formatar nos arquivos '
          'do turno; o bloqueio vai para o pedido de aprovação). Indisponível '
          '= sem python3, ou bloqueio no YOLO sem hooks (avisado antes de '
          'começar).',
          key: ValueKey('automations-fallback'),
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _HookRow extends StatelessWidget {
  const _HookRow({
    required this.hook,
    required this.on,
    required this.claude,
    required this.codex,
    required this.latest,
    required this.last,
    required this.onChanged,
  });

  final ManagedHook hook;
  final bool on;
  final HookWhen? claude;
  final HookWhen? codex;
  final CodexHookStatus? latest;
  final HookActivity? last;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final h = hook;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                SizedBox(
                  height: 28,
                  child: FittedBox(
                    child: Switch(
                      key: ValueKey('automation-${h.name}'),
                      value: on,
                      onChanged: onChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: h.description,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          switch (h) {
                            ManagedHook.block =>
                              'Antes de cada comando de shell',
                            ManagedHook.secrets =>
                              'Antes de git commit, push e gh pr create',
                            ManagedHook.format => 'Depois de cada edição (Edit, Write, apply_patch)',
                            ManagedHook.end => 'Ao encerrar o processo',
                          },
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(flex: 3, child: _cell('claude', claude)),
          Expanded(flex: 3, child: _cell('codex', codex)),
          Expanded(
            flex: 4,
            child: last == null
                ? const SizedBox.shrink()
                : Text(
                    'Último: ${hookProviderName(last!.provider)} · '
                    '${last!.text} · ${_clock(last!.at)}',
                    key: ValueKey('automation-last-${h.name}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: AppFonts.mono,
                      color: last!.error
                          ? AppColors.amber
                          : AppColors.textMuted,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String provider, HookWhen? when) {
    final color = when == null ? AppColors.textMuted : hookWhenColor(when);
    return Tooltip(
      message: hookWhenReason(hook, when, provider: provider, latest: latest),
      child: Row(
        key: ValueKey('automation-${hook.name}-$provider'),
        children: [
          Dot(color, size: 6),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              hookWhenLabel(hook, when, provider: provider),
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
