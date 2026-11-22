import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/run_prefs.dart';
import '../../core/providers/provider_availability.dart';
import '../../core/providers/provider_preferences.dart';
import '../../core/providers/structured_run.dart';
import '../../data/providers.dart';
import '../../ui/providers/provider_logos.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/only_provider_tag.dart';
import '../agents/widgets/agent_style.dart';
import '../project/project_config.dart';
import '../project/widgets/project_config_view.dart'
    show reviewerProviderChoices;
import '../review/reviewer_provider.dart';
import 'settings_sections.dart';
import '../specs/prototype/prototype_service.dart'
    show prototypeClaudeOnlyReason;

/// Why the Orquestrador's classifier stays on the Claude Code (R8).
const classifierClaudeOnlyReason =
    'O classificador do Orquestrador usa os modelos do Claude Code até o '
    'Orquestrador multi-provedor (SPEC-109).';

/// The order of R9, as the card explains it.
const providerKindOrder =
    'Ordem: execução em andamento › escolha no diálogo › tipo › rodapé do '
    'workspace › padrão global. Nenhuma execução troca de provedor no meio.';

/// Configurações → Modelo e consumo → "Provedor por tipo" (SPEC-100 R9):
/// one row per kind of run. "Planner e assistentes" is editable; the
/// other rows show their state until the spec of each flow arrives.
class ProviderKindCard extends ConsumerWidget {
  const ProviderKindCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final flows = ref.watch(providerFlowsProvider);
    final ws = ref.watch(activeWorkspaceProvider)?.id;
    final footer = ref.watch(activeAgentProvider);
    // Read only when already probed: opening Configurações never starts
    // the Codex detection.
    final probe = providerAvailabilityProvider('codex');
    final codex = ref.exists(probe) ? ref.watch(probe).value : null;
    // R9: Codex is offered when available and compatible; a saved Codex
    // stays selected even if it went away (the run then says why).
    final codexOffered =
        codex != null &&
        codex.available &&
        flows.allows('codex', AppFlow.structured);
    return AgentCard(
      key: const ValueKey('provider-kind-card'),
      title: 'Provedor por tipo',
      trailing: const Text(
        'o rodapé vale para o que não tiver escolha aqui',
        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
      children: [
        for (final (i, kind) in ProviderKind.values.indexed) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: AppColors.border),
            ),
          _row(
            kind,
            s,
            footer: footer,
            ws: ws,
            flows: flows,
            codexOffered: codexOffered,
            onChoose: (v) => v == null
                ? notifier.remove(kind.settingKey)
                : notifier.set(kind.settingKey, v),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          providerKindOrder,
          key: ValueKey('provider-kind-order'),
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        const Text(
          'FICAM NO CLAUDE CODE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        const _ClaudeOnly(
          key: ValueKey('kind-only-prototype'),
          label: 'Protótipo de telas',
          reason: prototypeClaudeOnlyReason,
        ),
        const SizedBox(height: 6),
        const _ClaudeOnly(
          key: ValueKey('kind-only-classifier'),
          label: 'Classificador do Orquestrador',
          reason: classifierClaudeOnlyReason,
        ),
      ],
    );
  }

  Widget _row(
    ProviderKind kind,
    Map<String, String> s, {
    required String footer,
    required int? ws,
    required ProviderFlows flows,
    required bool codexOffered,
    required ValueChanged<String?> onChoose,
  }) {
    final editable = ProviderKind.editable.contains(kind);
    final saved = providerKindChoice(s, kind);
    final resolved = providerForKind(s, kind, workspaceId: ws, flows: flows);
    final Widget state;
    if (editable) {
      final choices = <(String?, String)>[
        (null, 'Seguir o rodapé'),
        ('claude', 'Claude Code'),
        if (codexOffered || saved == 'codex') ('codex', 'Codex'),
      ];
      state = Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final (id, label) in choices)
            IntrinsicWidth(
              child: ToggleBox(
                key: ValueKey('kind-${kind.name}-${id ?? 'follow'}'),
                on: saved == id,
                height: 28,
                onTap: () => onChoose(id),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: saved == id ? AppColors.amber : AppColors.text,
                  ),
                ),
              ),
            ),
        ],
      );
    } else if (kind == ProviderKind.reviewer) {
      // SPEC-102 R4: the project's choice, no second one saved here.
      state = const ReviewerKindState(key: ValueKey('kind-reviewer-state'));
    } else if (kind == ProviderKind.sessions) {
      state = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'segue o rodapé:',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 6),
          ProviderChip(footer, dense: true),
        ],
      );
    } else {
      state = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OnlyProviderTag(
            provider: 'Claude Code',
            reason: 'O Codex chega a esta linha numa próxima versão.',
          ),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'o Codex chega a esta linha numa próxima versão',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ],
      );
    }
    final model = editable
        ? '${providerModelFrom(RunPrefs(s), s, resolved, RunKind.planner)} · '
              '${providerEffortFrom(RunPrefs(s), s, resolved, RunKind.planner)}'
        : null;
    return Row(
      key: ValueKey('kind-row-${kind.name}'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kind.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                kind.hint,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: state),
        ),
        if (model != null)
          Text(
            '${providerDisplayName(resolved)} · $model',
            key: ValueKey('kind-${kind.name}-model'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}

/// The row Revisor automático (SPEC-102 R4): `revisor: provedor:` of the
/// active project, resolved, and the way to Configuração do projeto.
class ReviewerKindState extends ConsumerWidget {
  const ReviewerKindState({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    final s = ref.watch(appSettingsProvider);
    final config = ws == null
        ? null
        : ref.watch(projectConfigProvider(ws.path)).value;
    final reviewer = config?.reviewer ?? const ReviewerConfig();
    final label = reviewerProviderChoices
        .firstWhere(
          (c) => c.$1 == reviewer.provider,
          orElse: () => reviewerProviderChoices.first,
        )
        .$2;
    final codex = reviewerCodexModel(reviewer, s);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'do projeto: $label',
          key: const ValueKey('kind-reviewer-value'),
          style: const TextStyle(fontSize: 12, color: AppColors.text),
        ),
        Text(
          'Claude Code ${reviewer.model} · Codex ${codex ?? 'modelo do tipo'}',
          key: const ValueKey('kind-reviewer-models'),
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        TextButton(
          key: const ValueKey('kind-reviewer-open-project'),
          onPressed: () => ref
              .read(selectedSettingsSectionProvider.notifier)
              .select(SettingsSection.project),
          child: const Text(
            'Configuração do projeto',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ClaudeOnly extends StatelessWidget {
  const _ClaudeOnly({super.key, required this.label, required this.reason});

  final String label;
  final String reason;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 220,
        child: Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: AppColors.text),
        ),
      ),
      const SizedBox(width: 12),
      OnlyProviderTag(provider: 'Claude Code', reason: reason),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          reason,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ),
    ],
  );
}
