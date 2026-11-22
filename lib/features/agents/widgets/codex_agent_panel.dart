import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/agent_provider.dart';
import '../../../core/providers/provider_availability.dart';
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../../settings/settings_sections.dart';
import '../agent_file.dart';
import '../codex_agent.dart';

/// Color of each state (R7): teal = applied, amber = adapted, muted =
/// ignored.
Color codexFieldColor(CodexFieldState s) => switch (s) {
  CodexFieldState.applied => AppColors.teal,
  CodexFieldState.adapted => AppColors.amber,
  CodexFieldState.ignored => AppColors.textMuted,
};

/// Small pill with the state of a field or of the whole agent.
class CodexStatePill extends StatelessWidget {
  const CodexStatePill(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: 0.6)),
      borderRadius: BorderRadius.circular(5),
      color: color.withValues(alpha: 0.08),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: color),
    ),
  );
}

/// The rows of a translation (field · value → target · state).
class CodexAgentFieldTable extends StatelessWidget {
  const CodexAgentFieldTable(this.plan, {super.key});

  final CodexAgentPlan plan;

  static const _mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12,
    color: AppColors.text,
  );
  static const _target = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );

  Widget _wide(CodexAgentField f) => Row(
    children: [
      SizedBox(width: 104, child: Text(f.key, style: _mono)),
      Expanded(
        flex: 4,
        child: Text(
          f.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _mono,
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          '→',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ),
      Expanded(
        flex: 5,
        child: Text(
          f.target,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _target,
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        flex: 3,
        child: CodexStatePill(f.state.label, codexFieldColor(f.state)),
      ),
    ],
  );

  /// Narrow column (the editor beside the list): field and state on one
  /// line, "value → target" below.
  Widget _narrow(CodexAgentField f) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(f.key, style: _mono)),
          const SizedBox(width: 8),
          Flexible(
            child: CodexStatePill(f.state.label, codexFieldColor(f.state)),
          ),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        '${f.value} → ${f.target}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _target,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in plan.fields)
          Container(
            key: ValueKey('codex-agent-field-${f.key}'),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: c.maxWidth < 460 ? _narrow(f) : _wide(f),
          ),
        for (final w in plan.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              w,
              style: const TextStyle(fontSize: 11, color: AppColors.amber),
            ),
          ),
      ],
    ),
  );
}

/// "No Codex" in the agent editor (R7, mock 1): the translation of the
/// agent being edited, field by field, in Editar. It follows the edits and
/// writes nothing to the `.md`.
class CodexAgentPanel extends ConsumerWidget {
  const CodexAgentPanel({super.key, required this.file, required this.name});

  /// The file as it would be saved now.
  final AgentFile file;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final sandbox =
        ref
            .watch(providerAvailabilityProvider('codex'))
            .value
            ?.sandboxWarning ==
        null;
    final plan = codexAgentPlanFrom(
      settings,
      file,
      name: name.isEmpty ? 'agente' : name,
      access: AgentAccess.edit,
      sandboxAvailable: sandbox,
    );
    return Container(
      key: const ValueKey('codex-agent-panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'NO CODEX  ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                TextSpan(
                  text: 'tradução em cada execução · nada é gravado',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (plan.fields.isEmpty)
            const Text(
              'Sem campos para traduzir: o Codex roda como sem agente.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else
            CodexAgentFieldTable(plan),
          const SizedBox(height: 10),
          const Text(
            'O modelo vem de Configurações → Provedores → Modelos '
            'equivalentes. As ferramentas só restringem: o agente nunca sobe '
            'o sandbox acima do modo da execução. Na tabela, o modo é Editar.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SmallButton(
              key: const ValueKey('codex-agent-adjust'),
              label: 'Ajustar modelos equivalentes',
              onTap: () {
                ref
                    .read(selectedSettingsSectionProvider.notifier)
                    .select(SettingsSection.providers);
                ref.read(navigationProvider.notifier).go(AppSection.settings);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The agent in Nova sessão and Executar spec with the Codex (R8, mock 3):
/// name, "adaptado", "2 campos ignorados" and the detail line; the hint
/// opens the field table (R7).
class CodexAgentSummary extends StatelessWidget {
  const CodexAgentSummary(this.plan, {super.key});

  final CodexAgentPlan plan;

  @override
  Widget build(BuildContext context) {
    final n = plan.ignored.length;
    return Tooltip(
      key: const ValueKey('codex-agent-summary'),
      richMessage: WidgetSpan(
        child: SizedBox(width: 520, child: CodexAgentFieldTable(plan)),
      ),
      decoration: BoxDecoration(
        color: AppColors.panelSolid,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  plan.agent,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                CodexStatePill(
                  plan.stateLabel,
                  plan.stateLabel == 'aplicado'
                      ? AppColors.teal
                      : AppColors.amber,
                ),
                if (n > 0)
                  Text(
                    '$n ${n == 1 ? 'campo ignorado' : 'campos ignorados'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              plan.detail,
              key: const ValueKey('codex-agent-detail'),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            for (final w in plan.warnings)
              Text(
                w,
                style: const TextStyle(fontSize: 11, color: AppColors.amber),
              ),
          ],
        ),
      ),
    );
  }
}
