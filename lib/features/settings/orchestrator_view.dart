import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../board/orchestrator/orchestrator_rules.dart';
import 'settings_choices.dart';

/// Configurações → Orquestrador (SPEC-035 R6): the rule of each kind of
/// step and the options of Automático.
class OrchestratorView extends StatelessWidget {
  const OrchestratorView({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OrchestratorRulesCard(),
      SizedBox(height: 16),
      OrchestratorOptionsCard(),
      // Histórico por tipo de etapa (SPEC-035 T7, R17 e R18) entra aqui,
      // depois das opções.
    ],
  );
}

/// "Amber box" text of the section: what the current values do.
String orchestratorEffect(OrchestratorPrefs p) {
  final rules = [
    for (final k in StepKind.values) '${k.label} em ${p.rule(k).label}',
  ].join(' · ');
  final open = p.autoByDefault ? 'Automático' : 'Manual';
  final ladder = switch (p.maxEscalations) {
    0 => 'uma etapa reprovada não escala',
    1 => 'uma etapa reprovada sobe até 1 degrau',
    final n => 'uma etapa reprovada sobe até $n degraus',
  };
  return 'Executar abre em $open. $rules. Depois dos reenvios, $ladder'
      '${p.askBeforeOpus ? ', e pergunta antes do Opus' : ''}. '
      'A classificação usa ${orchestratorModelLabel(p.classifierModel)}.';
}

const _sub = TextStyle(fontSize: 11, color: AppColors.textSecondary);

/// The table of R2: model and effort of each [StepKind], editable.
class OrchestratorRulesCard extends ConsumerWidget {
  const OrchestratorRulesCard({super.key});

  static const _kindWidth = 190.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(orchestratorPrefsProvider);
    final ctl = ref.read(orchestratorPrefsProvider.notifier);
    const header = TextStyle(fontSize: 11, color: AppColors.textMuted);
    return AgentCard(
      title: 'Regras por tipo de etapa',
      children: [
        const Row(
          children: [
            SizedBox(
              width: _kindWidth,
              child: Text('Tipo', style: header),
            ),
            Expanded(flex: 3, child: Text('Modelo', style: header)),
            SizedBox(width: 12),
            Expanded(flex: 5, child: Text('Esforço', style: header)),
          ],
        ),
        for (final k in StepKind.values) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Row(
            key: ValueKey('orchestrator-rule-${k.name}'),
            children: [
              SizedBox(
                width: _kindWidth,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        k.hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _sub,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: choices(
                  keyPrefix: 'orchestrator-model-${k.name}',
                  values: [
                    for (final m in orchestratorModels) m,
                    if (!orchestratorModels.any(
                      (m) => m.$1 == prefs.rule(k).model,
                    ))
                      (prefs.rule(k).model, prefs.rule(k).model),
                  ],
                  selected: prefs.rule(k).model,
                  onTap: (v) => ctl.setModel(k, v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: choices(
                  keyPrefix: 'orchestrator-effort-${k.name}',
                  values: [for (final e in orchestratorEfforts) (e, e)],
                  selected: prefs.rule(k).effort,
                  onTap: (v) => ctl.setEffort(k, v),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Em Automático, o Orquestrador classifica cada etapa aberta num '
          'destes tipos e propõe o modelo e o esforço dele; no Executar, '
          'você pode trocar qualquer linha antes de começar. A regra Revisão '
          'vale para a revisão automática do diff. Só o Claude Code entra no '
          'Automático.',
          style: _sub,
        ),
      ],
    );
  }
}

/// Options of Automático: how Executar opens, the ladder and the
/// classification.
class OrchestratorOptionsCard extends ConsumerWidget {
  const OrchestratorOptionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(orchestratorPrefsProvider);
    final ctl = ref.read(orchestratorPrefsProvider.notifier);
    return AgentCard(
      title: 'Opções',
      children: [
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            key: const ValueKey('orchestrator-auto-by-default'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: prefs.autoByDefault,
            onChanged: ctl.setAutoByDefault,
            title: const Text(
              'Abrir Executar em Automático',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: const Text(
              'Desligado, Executar abre em Manual, com o modelo e o esforço '
              'da spec inteira. Ligado, o piloto automático e "Executar tudo" '
              'também usam o Automático.',
              style: _sub,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const FieldLabel('Escaladas por etapa'),
        choices(
          keyPrefix: 'orchestrator-escalations',
          values: [
            for (final n in OrchestratorPrefs.escalationChoices)
              ('$n', n == 0 ? '0 · não escala' : '$n'),
          ],
          selected: '${prefs.maxEscalations}',
          onTap: (v) => ctl.setMaxEscalations(int.parse(v)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Quando a verificação reprova e os reenvios automáticos acabam, a '
          'etapa recomeça num modelo acima: Haiku → Sonnet → Opus. Com 0, '
          'ela para em "aguardando você", como hoje.',
          style: _sub,
        ),
        const SizedBox(height: 4),
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            key: const ValueKey('orchestrator-ask-opus'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: prefs.askBeforeOpus,
            onChanged: ctl.setAskBeforeOpus,
            title: const Text(
              'Perguntar antes de escalar para Opus',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: const Text(
              'A etapa para em "aguardando você" antes do degrau Opus, com a '
              'ação "Escalar para Opus".',
              style: _sub,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const FieldLabel('Classificar as etapas com'),
        choices(
          keyPrefix: 'orchestrator-classifier',
          values: classifierModels,
          selected: prefs.classifierModel,
          onTap: ctl.setClassifierModel,
        ),
        const SizedBox(height: 6),
        const Text(
          'Uma execução somente leitura ao abrir o Automático, guardada até o '
          'texto da etapa mudar.',
          style: _sub,
        ),
      ],
    );
  }
}
