import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/run_prefs.dart' show defaultEffort;
import '../../core/providers/provider_availability.dart';
import '../../ui/providers/provider_logos.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../board/orchestrator/escalation.dart' show ladderFor;
import '../board/orchestrator/orchestrator_rules.dart';
import '../board/widgets/quota_widgets.dart' show planProviderBlockedProvider;
import '../sessions/widgets/session_style.dart' show SmallButton;
import 'orchestrator_history.dart';
import 'settings_choices.dart';

/// Configurações → Orquestrador (SPEC-035 R6, R17): the rule of each kind
/// of step, the options of Automático and the Histórico. "Ver regra" of the
/// Histórico scrolls to the line of the rule and marks it.
class OrchestratorView extends StatefulWidget {
  const OrchestratorView({super.key});

  @override
  State<OrchestratorView> createState() => _OrchestratorViewState();
}

class _OrchestratorViewState extends State<OrchestratorView> {
  final _rows = {for (final k in StepKind.values) k: GlobalKey()};
  StepKind? _shown;

  void _showRule(StepKind k) {
    setState(() => _shown = k);
    final context = _rows[k]!.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.2,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OrchestratorRulesCard(rowKeys: _rows, highlight: _shown),
      const SizedBox(height: 16),
      const OrchestratorQuotaCards(),
      const SizedBox(height: 16),
      const OrchestratorOptionsCard(),
      const SizedBox(height: 16),
      OrchestratorHistoryCard(onShowRule: _showRule),
    ],
  );
}

/// "Amber box" text of the section: what the current values do.
String orchestratorEffect(OrchestratorPrefs p) {
  final rules = [
    for (final k in StepKind.values)
      '${k.label} em '
          '${p.rule(k).isClaude ? p.rule(k).label : p.rule(k).fullLabel}',
  ].join(' · ');
  final open = p.autoByDefault ? 'Automático' : 'Manual';
  final ladder = switch (p.maxEscalations) {
    0 => 'uma etapa reprovada não escala',
    1 => 'uma etapa reprovada sobe até 1 degrau',
    final n => 'uma etapa reprovada sobe até $n degraus',
  };
  return 'Executar abre em $open. $rules. Depois dos reenvios, $ladder'
      '${p.askBeforeOpus ? ', e pergunta antes do degrau mais alto' : ''}. '
      '${p.divertOnQuota ? 'Sem cota, a etapa segue no outro provedor. ' : ''}'
      'A classificação usa '
      '${p.classifier.isClaude ? orchestratorModelLabel(p.classifierModel) : 'Codex · ${p.classifier.model}'}.';
}

const _sub = TextStyle(fontSize: 11, color: AppColors.textSecondary);

/// The table of R2: provider, model and effort of each [StepKind], editable,
/// and its reserve on the other provider, "Se a cota acabar" (SPEC-109 R1,
/// R2).
class OrchestratorRulesCard extends ConsumerWidget {
  const OrchestratorRulesCard({
    super.key,
    this.rowKeys = const {},
    this.highlight,
  });

  /// Keys of the line of each kind ("Ver regra" scrolls to it).
  final Map<StepKind, GlobalKey> rowKeys;

  /// The line "Ver regra" pointed to, marked in amber.
  final StepKind? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AgentCard(
    title: 'Regras por tipo de etapa',
    children: [
      for (final k in StepKind.values) ...[
        if (k != StepKind.values.first)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: AppColors.border),
          ),
        Container(
          key: rowKeys[k],
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: highlight == k ? AppColors.amber : Colors.transparent,
            ),
          ),
          child: _RuleRow(k, key: ValueKey('orchestrator-rule-${k.name}')),
        ),
      ],
      const SizedBox(height: 12),
      const Text(
        'Em Automático, o Orquestrador classifica cada etapa aberta num '
        'destes tipos e propõe o provedor, o modelo e o esforço dele; no '
        'Executar, você pode trocar qualquer linha antes de começar. A regra '
        'Revisão vale para a revisão automática do diff. A reserva só é '
        'usada com o desvio por cota ligado. Os modelos e esforços do Codex '
        'vêm do catálogo dele (model/list).',
        style: _sub,
      ),
    ],
  );
}

/// One kind: the rule, and the reserve behind "Se a cota acabar".
class _RuleRow extends ConsumerStatefulWidget {
  const _RuleRow(this.kind, {super.key});

  final StepKind kind;

  @override
  ConsumerState<_RuleRow> createState() => _RuleRowState();
}

class _RuleRowState extends ConsumerState<_RuleRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    final prefs = ref.watch(orchestratorPrefsProvider);
    final ctl = ref.read(orchestratorPrefsProvider.notifier);
    final rule = prefs.rule(k);
    final reserve = prefs.fallback(k);
    final other = otherPlanProvider(rule.provider);
    // R1: only a rule on the Codex asks whether it can run.
    final blocked = rule.isClaude
        ? null
        : ref.watch(planProviderBlockedProvider(rule.provider));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 190,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, top: 4),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MiniSelect<String>(
                    id: 'orchestrator-provider-${k.name}',
                    label: 'Provedor de ${k.label}',
                    value: rule.provider,
                    items: const [('claude', 'Claude'), ('codex', 'Codex')],
                    leading: (p) => ProviderLogo(p, size: 14),
                    onChanged: (p) => ctl.setProvider(k, p),
                  ),
                  _MiniSelect<String>(
                    id: 'orchestrator-model-${k.name}',
                    label: 'Modelo de ${k.label}',
                    value: rule.model,
                    items: _modelItems(prefs, rule),
                    onChanged: (m) => ctl.setModel(k, m),
                  ),
                  _MiniSelect<String>(
                    id: 'orchestrator-effort-${k.name}',
                    label: 'Esforço de ${k.label}',
                    value: rule.effort,
                    items: _effortItems(prefs, rule),
                    onChanged: (e) => ctl.setEffort(k, e),
                  ),
                  InkWell(
                    key: ValueKey('orchestrator-fallback-toggle-${k.name}'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _open = !_open),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Se a cota acabar', style: _sub),
                          Icon(
                            _open ? Icons.expand_less : Icons.expand_more,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          if (!_open) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                reserve?.fullLabel ?? 'sem reserva',
                                key: ValueKey(
                                  'orchestrator-fallback-label-${k.name}',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _sub.copyWith(color: AppColors.text),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (blocked != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Codex indisponível: $blocked',
                    key: ValueKey('orchestrator-blocked-${k.name}'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.amber,
                    ),
                  ),
                ),
              if (_open)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _MiniSelect<bool>(
                        id: 'orchestrator-fallback-on-${k.name}',
                        label: 'Reserva de ${k.label}',
                        value: reserve != null,
                        items: [
                          (true, planProviderLabel(other)),
                          (false, 'sem reserva'),
                        ],
                        leading: (on) =>
                            on ? ProviderLogo(other, size: 14) : null,
                        onChanged: (on) => ctl.setFallback(
                          k,
                          !on
                              ? null
                              : other == 'claude'
                              ? OrchestratorPrefs.defaultRules[k]
                              : prefs.codexRule(effort: rule.effort),
                        ),
                      ),
                      if (reserve != null) ...[
                        _MiniSelect<String>(
                          id: 'orchestrator-fallback-model-${k.name}',
                          label: 'Modelo da reserva de ${k.label}',
                          value: reserve.model,
                          items: _modelItems(prefs, reserve),
                          onChanged: (m) => ctl.setFallback(
                            k,
                            reserve.isClaude
                                ? StepRule(m, reserve.effort)
                                : prefs.codexRule(
                                    model: m,
                                    effort: reserve.effort,
                                  ),
                          ),
                        ),
                        _MiniSelect<String>(
                          id: 'orchestrator-fallback-effort-${k.name}',
                          label: 'Esforço da reserva de ${k.label}',
                          value: reserve.effort,
                          items: _effortItems(prefs, reserve),
                          onChanged: (e) => ctl.setFallback(
                            k,
                            StepRule(
                              reserve.model,
                              e,
                              provider: reserve.provider,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Models of the provider of [rule]: the Claude aliases, or the catalog of
/// the Codex; the current one is always there.
List<(String, String)> _modelItems(OrchestratorPrefs prefs, StepRule rule) {
  String label(String m) => m == 'inherit' ? 'modelo padrão' : m;
  return rule.isClaude
      ? [
          ...orchestratorModels,
          if (!orchestratorModels.any((m) => m.$1 == rule.model))
            (rule.model, rule.model),
        ]
      : [
          for (final m in {...prefs.codexModels, rule.model}) (m, label(m)),
        ];
}

/// Efforts [rule]'s model takes.
List<(String, String)> _effortItems(OrchestratorPrefs prefs, StepRule rule) =>
    rule.isClaude
    ? [
        for (final e in {...orchestratorEfforts, rule.effort}) (e, e),
      ]
    : [
        for (final e in {...prefs.codexEfforts(rule.model), rule.effort})
          (e, e == defaultEffort ? 'esforço padrão' : e),
      ];

/// A small selector with a visible value.
class _MiniSelect<T> extends StatelessWidget {
  const _MiniSelect({
    required this.id,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.leading,
  });

  final String id;
  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final Widget? Function(T)? leading;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: ValueKey(id),
          value: value,
          isDense: true,
          dropdownColor: AppColors.panelSolid,
          iconSize: 16,
          style: const TextStyle(fontSize: 12, color: AppColors.text),
          items: [
            for (final (v, text) in items)
              DropdownMenuItem(
                value: v,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading?.call(v) case final w?) ...[
                      w,
                      const SizedBox(width: 6),
                    ],
                    Text(text),
                  ],
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null && v != value) onChanged(v);
          },
        ),
      ),
    ),
  );
}

/// "Escada do Codex" and "Quando a cota acabar" (SPEC-109 R3–R6).
class OrchestratorQuotaCards extends ConsumerWidget {
  const OrchestratorQuotaCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, box) {
      const ladder = _CodexLadderCard();
      const quota = _QuotaCard();
      if (box.maxWidth < 720) {
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [ladder, SizedBox(height: 16), quota],
        );
      }
      return const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: ladder),
          SizedBox(width: 16),
          Expanded(child: quota),
        ],
      );
    },
  );
}

class _CodexLadderCard extends ConsumerWidget {
  const _CodexLadderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(orchestratorPrefsProvider);
    final ctl = ref.read(orchestratorPrefsProvider.notifier);
    final example = prefs.codexRule();
    final rungs = ladderFor(example, prefs);
    final catalog = prefs.codexModels;
    final chosen = prefs.codexLadderModels;
    Widget option(CodexLadder v, String label) => Semantics(
      inMutuallyExclusiveGroup: true,
      checked: prefs.codexLadder == v,
      child: InkWell(
        key: ValueKey('orchestrator-ladder-${v.name}'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => ctl.setCodexLadder(v),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                prefs.codexLadder == v
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 16,
                color: prefs.codexLadder == v
                    ? AppColors.amber
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
    return AgentCard(
      title: 'Escada do Codex',
      children: [
        option(CodexLadder.effort, 'Mesmo modelo, esforço subindo'),
        if (prefs.codexLadder == CodexLadder.effort)
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 4),
            child: Text(
              rungs.isEmpty
                  ? 'O catálogo do Codex ainda não foi lido: sem ele, uma '
                        'etapa no Codex não escala.'
                  : '${rungs.map((r) => r.effort).join(' → ')} · do model/list '
                        'de ${example.model}',
              key: const ValueKey('orchestrator-ladder-efforts'),
              style: _sub,
            ),
          ),
        option(CodexLadder.models, 'Lista de modelos que eu ordeno'),
        if (prefs.codexLadder == CodexLadder.models)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (catalog.isEmpty)
                  const Text(
                    'O catálogo do Codex ainda não foi lido.',
                    style: _sub,
                  ),
                for (final (i, m) in chosen.indexed)
                  Row(
                    key: ValueKey('orchestrator-ladder-model-$m'),
                    children: [
                      Text('${i + 1}. ', style: _sub),
                      Expanded(
                        child: Text(m, style: const TextStyle(fontSize: 12)),
                      ),
                      IconButton(
                        key: ValueKey('orchestrator-ladder-up-$m'),
                        tooltip: 'Degrau abaixo',
                        iconSize: 14,
                        visualDensity: VisualDensity.compact,
                        onPressed: i == 0
                            ? null
                            : () => ctl.setCodexLadderModels(
                                [...chosen]
                                  ..removeAt(i)
                                  ..insert(i - 1, m),
                              ),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        key: ValueKey('orchestrator-ladder-down-$m'),
                        tooltip: 'Degrau acima',
                        iconSize: 14,
                        visualDensity: VisualDensity.compact,
                        onPressed: i + 1 == chosen.length
                            ? null
                            : () => ctl.setCodexLadderModels(
                                [...chosen]
                                  ..removeAt(i)
                                  ..insert(i + 1, m),
                              ),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        key: ValueKey('orchestrator-ladder-remove-$m'),
                        tooltip: 'Tirar da escada',
                        iconSize: 14,
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            ctl.setCodexLadderModels([...chosen]..removeAt(i)),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in catalog)
                      if (!chosen.contains(m))
                        SmallButton(
                          key: ValueKey('orchestrator-ladder-add-$m'),
                          label: '+ $m',
                          onTap: () => ctl.setCodexLadderModels([...chosen, m]),
                        ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Claude: Haiku → Sonnet → Opus, como hoje. Escaladas por etapa: '
          '${prefs.maxEscalations}.',
          style: _sub,
        ),
      ],
    );
  }
}

class _QuotaCard extends ConsumerWidget {
  const _QuotaCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(orchestratorPrefsProvider);
    final ctl = ref.read(orchestratorPrefsProvider.notifier);
    final diverts = prefs.divertOnQuota || prefs.divertAbovePercent != null;
    // Decision 15: without the sandbox the Codex only runs in YOLO. Only
    // asked when something would send a step there.
    final noSandbox =
        diverts &&
        ref
                .watch(providerAvailabilityProvider('codex'))
                .value
                ?.sandboxWarning !=
            null;
    Widget toggle(
      String id,
      String title,
      bool value,
      ValueChanged<bool> onChanged, {
      Widget? trailing,
    }) => Material(
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: SwitchListTile(
              key: ValueKey(id),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: value,
              onChanged: onChanged,
              title: Text(title, style: const TextStyle(fontSize: 13)),
            ),
          ),
          ?trailing,
        ],
      ),
    );
    return AgentCard(
      title: 'Quando a cota acabar',
      children: [
        toggle(
          'orchestrator-divert-quota',
          'Desviar para o outro provedor quando a cota acabar',
          prefs.divertOnQuota,
          ctl.setDivertOnQuota,
        ),
        toggle(
          'orchestrator-divert-above',
          'Desviar antes de começar uma etapa quando a janela passar de',
          prefs.divertAbovePercent != null,
          ctl.setDivertAbove,
          trailing: _MiniSelect<int>(
            id: 'orchestrator-divert-percent',
            label: 'Limite do desvio preventivo',
            value: prefs.divertPercent,
            items: [
              for (final n in OrchestratorPrefs.divertPercentChoices)
                (n, '$n%'),
            ],
            onChanged: ctl.setDivertPercent,
          ),
        ),
        toggle(
          'orchestrator-second-opinion',
          'No topo da escada, tentar o outro provedor',
          prefs.secondOpinion,
          ctl.setSecondOpinion,
        ),
        toggle(
          'orchestrator-ask-opus',
          'Perguntar antes do degrau mais alto',
          prefs.askBeforeOpus,
          ctl.setAskBeforeOpus,
        ),
        const SizedBox(height: 6),
        const Text(
          'Nunca troca dentro de uma sessão: a etapa volta ao início no outro '
          'provedor. O que a tentativa interrompida deixou no worktree da '
          'spec fica guardado numa ref do git.',
          style: _sub,
        ),
        if (noSandbox)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Sandbox do Codex indisponível nesta máquina: uma etapa '
              'desviada para o Codex roda em YOLO, só no worktree da spec, e '
              'o app commita no fim do turno.',
              key: ValueKey('orchestrator-divert-no-sandbox'),
              style: TextStyle(fontSize: 11, color: AppColors.amber),
            ),
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
          'etapa recomeça no degrau acima da escada do provedor dela. Com 0, '
          'ela para em "aguardando você", como hoje.',
          style: _sub,
        ),
        const SizedBox(height: 12),
        const FieldLabel('Classificar as etapas com'),
        Row(
          children: [
            Expanded(
              child: choices(
                keyPrefix: 'orchestrator-classifier',
                values: classifierModels,
                selected: prefs.classifier.isClaude
                    ? prefs.classifierModel
                    : '',
                onTap: ctl.setClassifierModel,
              ),
            ),
            // SPEC-109 R11: a model of the Codex too.
            if (prefs.codexModels.isNotEmpty || !prefs.classifier.isClaude)
              _MiniSelect<String>(
                id: 'orchestrator-classifier-codex',
                label: 'Classificar com um modelo do Codex',
                value: prefs.classifier.isClaude ? '' : prefs.classifier.model,
                items: [
                  ('', 'Codex…'),
                  for (final m in {
                    ...prefs.codexModels,
                    if (!prefs.classifier.isClaude) prefs.classifier.model,
                  })
                    (m, m),
                ],
                leading: (m) =>
                    m.isEmpty ? null : const ProviderLogo('codex', size: 14),
                onChanged: (m) => ctl.setClassifierModel(
                  m.isEmpty
                      ? OrchestratorPrefs.defaultClassifierModel
                      : 'codex|$m',
                ),
              ),
          ],
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
