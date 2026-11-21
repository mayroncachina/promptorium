import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/run_prefs.dart';
import '../../core/codex/codex_cli.dart';
import '../../core/codex/codex_probe.dart'
    show CodexModelInfo, codexSandboxFixCommand;
import '../../core/providers/agent_registry.dart';
import '../../core/providers/provider_availability.dart';
import '../../core/providers/provider_preferences.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/only_provider_tag.dart';
import '../agents/widgets/agent_style.dart';
import '../sessions/widgets/session_style.dart';
import 'settings_choices.dart';

/// Flow each run kind belongs to (R3), for the "Só Claude Code por
/// enquanto" tag of the Codex tab.
AppFlow flowOfKind(RunKind k) => switch (k) {
  RunKind.session => AppFlow.sessions,
  RunKind.conversation => AppFlow.prompt,
  RunKind.planner => AppFlow.structured,
};

/// Configurações → Consumo → Codex (SPEC-094 R8, R9): model and effort per
/// run kind from the cached `model/list`, with the version and time of the
/// reading. Never waits for the Codex to answer.
class CodexConsumptionTab extends ConsumerWidget {
  const CodexConsumptionTab({super.key});

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final cache = codexModelsCache(s);
    final flows = ref.watch(providerFlowsProvider);
    final checking = ref.watch(providerAvailabilityProvider('codex')).isLoading;
    return AgentCard(
      title: 'Modelo e esforço do Codex',
      children: [
        Row(
          children: [
            Icon(
              cache == null ? Icons.info_outline : Icons.check,
              size: 14,
              color: cache == null ? AppColors.textMuted : AppColors.teal,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                cache == null
                    ? 'Lista de modelos ainda não lida. Atualize com o Codex '
                          'instalado.'
                    : 'Lista lida do Codex ${cache.version ?? '?'} às '
                          '${_hhmm(cache.readAt)} · ${cache.models.length} '
                          'modelos',
                key: const ValueKey('codex-models-read'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SmallButton(
              key: const ValueKey('codex-models-refresh'),
              label: checking ? 'Lendo…' : 'Atualizar lista',
              onTap: checking
                  ? null
                  : () {
                      ref.invalidate(codexCliInfoProvider);
                      ref.invalidate(providerAvailabilityProvider('codex'));
                    },
            ),
          ],
        ),
        for (final k in RunKind.values) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AppColors.border),
          ),
          _row(
            k,
            s,
            cache,
            locked: !flows.allows('codex', flowOfKind(k)),
            onModel: (v) => notifier.set('codex.model.${k.name}', v),
            onEffort: (v) => notifier.set('codex.effort.${k.name}', v),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Modelos e esforços vêm do model/list do Codex instalado. Aliases do '
          'Claude (opus, sonnet) não valem aqui.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _row(
    RunKind k,
    Map<String, String> s,
    CodexModelsCache? cache, {
    required bool locked,
    required ValueChanged<String> onModel,
    required ValueChanged<String> onEffort,
  }) {
    final saved = s['codex.model.${k.name}'] ?? 'inherit';
    final effort = s['codex.effort.${k.name}'] ?? 'default';
    final missing = providerModelMissing(s, 'codex', saved);
    final current = missing ? 'inherit' : saved;
    final efforts =
        cache?.byId(current)?.efforts ??
        <String>{
          for (final m in cache?.models ?? const <CodexModelInfo>[])
            ...m.efforts,
        }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              k.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(width: 8),
            if (locked)
              OnlyProviderTag(
                key: ValueKey('codex-kind-locked-${k.name}'),
                provider: 'Claude Code',
                suffix: 'por enquanto',
                reason:
                    '${flowOfKind(k).label} ainda não roda com o Codex; o '
                    'modelo escolhido vale quando o fluxo for liberado.',
              ),
          ],
        ),
        Text(
          k.hint,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        if (missing)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$saved salvo antes: indisponível nesta versão. Usando o padrão '
              'do Codex.',
              key: ValueKey('codex-model-missing-${k.name}'),
              style: const TextStyle(fontSize: 11, color: AppColors.amber),
            ),
          ),
        const SizedBox(height: 8),
        const FieldLabel('Modelo'),
        choices(
          keyPrefix: 'codex-model-${k.name}',
          values: [
            ('inherit', 'Padrão do Codex'),
            for (final m in cache?.models ?? const <CodexModelInfo>[])
              (m.id, m.id),
          ],
          selected: current,
          onTap: onModel,
        ),
        const SizedBox(height: 8),
        const FieldLabel('Esforço'),
        choices(
          keyPrefix: 'codex-effort-${k.name}',
          values: [
            ('default', 'Padrão do Codex'),
            for (final e in efforts) (e, e),
            if (effort != 'default' && !efforts.contains(effort))
              (effort, effort),
          ],
          selected: effort,
          onTap: onEffort,
        ),
      ],
    );
  }
}

/// "O que o Codex faz neste app" (mock 1): the declared capabilities with
/// "Só Claude Code" where the Codex has none (R1, R11).
class CodexCapabilitiesCard extends StatelessWidget {
  const CodexCapabilitiesCard({
    super.key,
    this.caps = ProviderCapabilities.codex,
  });

  final ProviderCapabilities caps;

  @override
  Widget build(BuildContext context) => AgentCard(
    title: 'O que o Codex faz neste app',
    children: [
      const Text(
        'Capacidades comprovadas no 0.170 (SPEC-093). Não testado conta como '
        'não suportado.',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      for (final c in ProviderCapability.values)
        Padding(
          key: ValueKey('codex-cap-${c.name}'),
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  switch (caps[c].support) {
                    CapabilitySupport.supported => '✓',
                    CapabilitySupport.partial => '~',
                    CapabilitySupport.unsupported => '—',
                  },
                  style: TextStyle(
                    fontSize: 12,
                    color: switch (caps[c].support) {
                      CapabilitySupport.supported => AppColors.teal,
                      CapabilitySupport.partial => AppColors.amber,
                      CapabilitySupport.unsupported => AppColors.textMuted,
                    },
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  c.label,
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                ),
              ),
              if (caps[c].support == CapabilitySupport.unsupported &&
                  ProviderCapabilities.claude.supports(c))
                OnlyProviderTag(
                  provider: 'Claude Code',
                  reason: caps.reasonFor(c),
                )
              else if (caps[c].reason case final r?)
                Text(
                  caps[c].support == CapabilitySupport.partial
                      ? 'parcial · $r'
                      : r,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

/// Label of a provider tab ("Claude Code" / "Codex").
class ProviderTabLabel extends StatelessWidget {
  const ProviderTabLabel(this.provider, this.label, {super.key});

  final String provider;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: const TextStyle(fontSize: 12));
}

/// Configurações → Provedores: the Codex version, its warnings and the
/// sandbox of this machine (SPEC-094 R7a, R10), with "Verificar de novo".
/// The app never changes the system: it only shows the command.
class CodexStatusCard extends ConsumerWidget {
  const CodexStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(providerAvailabilityProvider('codex'));
    final v = a.value;
    return AgentCard(
      title: 'Provedores · Codex',
      children: [
        Text(
          a.isLoading
              ? 'Verificando o Codex…'
              : v == null
              ? 'Não foi possível verificar o Codex.'
              : 'Codex ${v.version ?? ''} · ${v.label}'.replaceAll('  ', ' '),
          key: const ValueKey('codex-status'),
          style: const TextStyle(fontSize: 12, color: AppColors.text),
        ),
        if (v != null && !v.available)
          Text(
            v.message,
            style: const TextStyle(fontSize: 11, color: AppColors.red),
          ),
        if (v?.warning != null)
          Text(
            v!.warning!,
            style: const TextStyle(fontSize: 11, color: AppColors.amber),
          ),
        if (v?.sandboxWarning != null) ...[
          const SizedBox(height: 6),
          const Text(
            'Sandbox do Codex indisponível',
            key: ValueKey('codex-no-sandbox'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.amber,
            ),
          ),
          const Text(
            'Perguntar, Planejar e Editar não rodam nesta máquina; o Codex só '
            'roda em worktree com acesso total, e o app commita no fim do '
            'turno. Para liberar (o app não altera o sistema):',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SelectableText(
            codexSandboxFixCommand,
            style: TextStyle(fontSize: 11, fontFamily: AppFonts.mono),
          ),
          const Text(
            'Ou um perfil AppArmor que libere o bwrap.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: SmallButton(
            key: const ValueKey('codex-recheck'),
            label: 'Verificar de novo',
            onTap: () {
              ref.invalidate(codexCliInfoProvider);
              ref.invalidate(providerAvailabilityProvider('codex'));
            },
          ),
        ),
      ],
    );
  }
}
