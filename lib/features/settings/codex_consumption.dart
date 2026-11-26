import 'dart:io';

import 'package:flutter/material.dart';

import '../../ui/providers/provider_logos.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/run_prefs.dart';
import '../../core/codex/codex_cli.dart';
import '../../core/codex/codex_probe.dart'
    show CodexModelInfo, codexSandboxFixCommand;
import '../../core/providers/agent_registry.dart';
import '../../core/providers/provider_availability.dart';
import '../../core/providers/provider_preferences.dart';
import '../../core/system/worktree_launcher.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/only_provider_tag.dart';
import '../agents/widgets/agent_style.dart';
import '../sessions/widgets/session_style.dart';

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
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _Select(
                key: ValueKey('codex-model-${k.name}'),
                label: 'Modelo',
                value: current,
                items: [
                  ('inherit', 'Padrão do Codex'),
                  for (final m in cache?.models ?? const <CodexModelInfo>[])
                    (m.id, m.id),
                ],
                onChanged: onModel,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _Select(
                key: ValueKey('codex-effort-${k.name}'),
                label: 'Esforço',
                value: effort,
                items: [
                  ('default', 'Padrão do Codex'),
                  for (final e in efforts) (e, e),
                  if (effort != 'default' && !efforts.contains(effort))
                    (effort, effort),
                ],
                onChanged: onEffort,
              ),
            ),
          ],
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
      Align(alignment: Alignment.centerLeft, child: ProviderChip('codex')),
      const SizedBox(height: 6),
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
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (hasProviderIdentity(provider)) ...[
        ProviderLogo(provider),
        const SizedBox(width: 6),
      ],
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
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
        Align(alignment: Alignment.centerLeft, child: ProviderChip('codex')),
        const SizedBox(height: 6),
        Text(
          a.isLoading
              ? 'Verificando o Codex…'
              : v == null
              ? 'Não foi possível verificar o Codex.'
              : 'Codex ${v.version ?? ''} · ${v.label}'.replaceAll('  ', ' '),
          key: const ValueKey('codex-status'),
          style: const TextStyle(fontSize: 12, color: AppColors.text),
        ),
        if (v?.status == ProviderStatus.loginRequired) ...[
          // SPEC-096 R2: the login is the person's; the app never logs in
          // nor reads ~/.codex/auth.json.
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Rode '),
                TextSpan(
                  text: 'codex login',
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    color: AppColors.amber,
                  ),
                ),
                TextSpan(
                  text:
                      ' no terminal. O Promptorium não faz login nem lê suas '
                      'credenciais.',
                ),
              ],
            ),
            key: ValueKey('codex-login-hint'),
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ] else if (v != null && !v.available)
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
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 6,
          children: [
            if (v?.status == ProviderStatus.loginRequired)
              SmallButton(
                key: const ValueKey('codex-open-terminal'),
                label: 'Abrir terminal',
                onTap: () => _openTerminal(context, ref),
              ),
            SmallButton(
              key: const ValueKey('codex-recheck'),
              label: 'Verificar de novo',
              onTap: () {
                ref.invalidate(codexCliInfoProvider);
                ref.invalidate(providerAvailabilityProvider('codex'));
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _CodexFlows(),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: AppColors.border),
        ),
        const _CodexKillSwitch(),
      ],
    );
  }

  /// A plain shell in the home folder: the person types `codex login`.
  static Future<void> _openTerminal(BuildContext context, WidgetRef ref) async {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final used = await ref.read(worktreeLauncherProvider).terminal(home);
    if (used == null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum terminal encontrado. Rode codex login num terminal.',
          ),
        ),
      );
    }
  }
}

/// Where the Codex runs (mock 4): released flows in teal, the others with
/// the spec that releases them.
class _CodexFlows extends ConsumerWidget {
  const _CodexFlows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flows = ref.watch(providerFlowsProvider);
    Widget chip(String label, {required bool on, Key? key}) => Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: on ? AppColors.teal.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: on ? AppColors.teal : AppColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: on ? AppColors.teal : AppColors.textSecondary,
        ),
      ),
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final f in [
          AppFlow.prompt,
          AppFlow.sessions,
          AppFlow.runSpec,
          AppFlow.compare,
        ])
          chip(
            f.label,
            on: flows.allows('codex', f),
            key: ValueKey('codex-flow-${f.name}'),
          ),
        for (final MapEntry(key: f, value: spec) in codexFlowSpecs.entries)
          chip(
            '${f.label} · $spec',
            on: false,
            key: ValueKey('codex-flow-${f.name}'),
          ),
      ],
    );
  }
}

/// "Desligar o Codex" (SPEC-096 P1): hides the Codex in every flow without
/// a new version, because the App Server is experimental.
class _CodexKillSwitch extends ConsumerWidget {
  const _CodexKillSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final off = ref.watch(
      appSettingsProvider.select((s) => s[codexKillSwitchKey] == '1'),
    );
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Desligar o Codex',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              Text(
                'Interruptor de emergência: esconde o Codex em todos os fluxos '
                'sem precisar de outra versão.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Switch(
          key: const ValueKey('codex-kill-switch'),
          value: off,
          onChanged: (v) => ref
              .read(appSettingsProvider.notifier)
              .set(codexKillSwitchKey, v ? '1' : '0'),
        ),
      ],
    );
  }
}

/// Labeled dropdown of the Codex tab (the catalog has many models).
class _Select extends StatelessWidget {
  const _Select({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<(String, String)> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel(label),
      DropdownButtonFormField<String>(
        key: ValueKey('$value-${items.length}'),
        initialValue: items.any((i) => i.$1 == value) ? value : items.first.$1,
        isDense: true,
        isExpanded: true,
        dropdownColor: AppColors.panelSolid,
        style: const TextStyle(
          fontSize: 13,
          fontFamily: AppFonts.mono,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
        items: [
          for (final (v, l) in items)
            DropdownMenuItem(
              key: ValueKey(
                '${key is ValueKey ? (key as ValueKey).value : ''}-$v',
              ),
              value: v,
              child: Text(l, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    ],
  );
}
