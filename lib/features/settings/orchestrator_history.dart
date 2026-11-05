import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../board/orchestrator/orchestrator_rules.dart';
import '../sessions/widgets/session_style.dart';
import 'settings_choices.dart';

/// Periods of the Histórico, in days (R17).
const orchestratorHistoryPeriods = [7, 30, 90];

/// The Histórico suggests a stronger rule from this many steps (R18)…
const historyMinSteps = 5;

/// …when at least this share of them escalated.
const historyEscalatedShare = 0.2;

/// What the steps of one [StepKind] did in a period (SPEC-035 R17).
@immutable
class KindHistory {
  const KindHistory({
    required this.kind,
    required this.models,
    required this.steps,
    required this.firstPass,
    required this.escalated,
    required this.costUsd,
    this.lastEscalation,
  });

  final StepKind kind;

  /// Models used by the attempts, weakest first (`haiku`, `sonnet`…).
  final List<String> models;

  /// Steps that ran, counted by (spec, step).
  final int steps;

  /// Steps whose first attempt in the period passed.
  final int firstPass;

  /// Steps with some escalated attempt.
  final int escalated;

  /// Sum of the cost of the attempts (US$, estimate of the CLI).
  final double costUsd;

  /// Most recent escalated attempt: "Ignorar" lasts until a newer one.
  final DateTime? lastEscalation;

  /// R18: 5 or more steps, and 20% or more of them escalated.
  bool get needsStrongerRule =>
      steps >= historyMinSteps && escalated >= steps * historyEscalatedShare;
}

/// The Histórico of the attempts [runs] (`step_runs` of the period, any
/// order), one entry per kind in the order of [StepKind]; attempts without
/// a kind (Manual) are left out. A step is (spec, step): it "passed at
/// first" when its oldest attempt passed and "escalated" when any attempt
/// escalated.
List<KindHistory> orchestratorHistory(Iterable<StepRun> runs) {
  final byKind = <StepKind, Map<(int, String), List<StepRun>>>{};
  for (final r in runs) {
    final name = r.kind;
    if (name == null) continue;
    final kind = StepKind.parse(name);
    (byKind[kind] ??= {}).putIfAbsent((r.specId, r.step), () => []).add(r);
  }
  int order(StepRun a, StepRun b) {
    final at = a.createdAt.compareTo(b.createdAt);
    return at != 0 ? at : a.id.compareTo(b.id);
  }

  int rung(String model) {
    final i = orchestratorModels.indexWhere((m) => m.$1 == model);
    return i < 0 ? orchestratorModels.length : i;
  }

  return [
    for (final kind in StepKind.values)
      if (byKind[kind] case final steps?)
        () {
          var firstPass = 0;
          var escalated = 0;
          var cost = 0.0;
          DateTime? last;
          final models = <String>{};
          for (final attempts in steps.values) {
            attempts.sort(order);
            if (attempts.first.result == StepRunResult.passed) firstPass++;
            if (attempts.any((a) => a.result == StepRunResult.escalated)) {
              escalated++;
            }
            for (final a in attempts) {
              models.add(a.model);
              cost += a.costUsd ?? 0;
              if (a.result == StepRunResult.escalated &&
                  (last == null || a.createdAt.isAfter(last))) {
                last = a.createdAt;
              }
            }
          }
          return KindHistory(
            kind: kind,
            models: models.toList()
              ..sort((a, b) {
                final r = rung(a).compareTo(rung(b));
                return r != 0 ? r : a.compareTo(b);
              }),
            steps: steps.length,
            firstPass: firstPass,
            escalated: escalated,
            costUsd: cost,
            lastEscalation: last,
          );
        }(),
  ];
}

/// Whether the suggestion of [h] shows (R18): the kind needs a stronger
/// rule and "Ignorar" ([ignoredAt], the last escalation seen when it was
/// tapped) came before the newest escalation of the period.
bool showHistorySuggestion(KindHistory h, DateTime? ignoredAt) {
  if (!h.needsStrongerRule) return false;
  final last = h.lastEscalation;
  return ignoredAt == null || (last != null && last.isAfter(ignoredAt));
}

/// The suggestion "Ignorar" of [kind] was tapped when its newest escalation
/// was [ignoredAt] (null = never).
DateTime? historyIgnoredAt(Map<String, String> settings, StepKind kind) =>
    DateTime.tryParse(
      settings[AppSettingKeys.orchestratorHistoryIgnored(kind.name)] ?? '',
    );

/// Attempts of the last [days] days, oldest first.
final stepRunsOfPeriodProvider = StreamProvider.autoDispose
    .family<List<StepRun>, int>(
      (ref, days) => ref
          .watch(stepRunsRepoProvider)
          .watchSince(DateTime.now().subtract(Duration(days: days))),
    );

String _usd(double v) => 'US\$ ${v.toStringAsFixed(2)}';

const _sub = TextStyle(fontSize: 11, color: AppColors.textSecondary);

/// Configurações → Orquestrador → Histórico (SPEC-035 R17, R18): per kind of
/// step, in 7, 30 or 90 days, the models used, how many steps passed at
/// first, how many escalated and the estimated cost. [onShowRule] is "Ver
/// regra" of a suggestion.
class OrchestratorHistoryCard extends ConsumerStatefulWidget {
  const OrchestratorHistoryCard({super.key, required this.onShowRule});

  final ValueChanged<StepKind> onShowRule;

  @override
  ConsumerState<OrchestratorHistoryCard> createState() =>
      _OrchestratorHistoryCardState();
}

class _OrchestratorHistoryCardState
    extends ConsumerState<OrchestratorHistoryCard> {
  int _days = 30;

  static const _kindWidth = 130.0;

  @override
  Widget build(BuildContext context) {
    final runs = ref.watch(stepRunsOfPeriodProvider(_days));
    final settings = ref.watch(appSettingsProvider);
    final prefs = ref.watch(orchestratorPrefsProvider);
    final history = orchestratorHistory(runs.value ?? const []);
    const header = TextStyle(fontSize: 11, color: AppColors.textMuted);
    Widget cell(String text, {TextStyle? style, int flex = 2}) => Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style ?? const TextStyle(fontSize: 13, color: AppColors.text),
      ),
    );
    return AgentCard(
      title: 'Histórico',
      children: [
        choices(
          keyPrefix: 'orchestrator-history-days',
          values: [
            for (final d in orchestratorHistoryPeriods) ('$d', '$d dias'),
          ],
          selected: '$_days',
          onTap: (v) => setState(() => _days = int.parse(v)),
        ),
        const SizedBox(height: 12),
        for (final h in history)
          if (showHistorySuggestion(h, historyIgnoredAt(settings, h.kind)))
            _Suggestion(
              history: h,
              days: _days,
              rule: prefs.rule(h.kind),
              onShow: () => widget.onShowRule(h.kind),
              onIgnore: () => ref
                  .read(appSettingsProvider.notifier)
                  .set(
                    AppSettingKeys.orchestratorHistoryIgnored(h.kind.name),
                    (h.lastEscalation ?? DateTime.now()).toIso8601String(),
                  ),
            ),
        if (history.isEmpty)
          Text(
            runs.isLoading
                ? 'Carregando…'
                : 'Nenhuma etapa rodou em Automático nos últimos $_days dias.',
            key: const ValueKey('orchestrator-history-empty'),
            style: _sub,
          )
        else ...[
          Row(
            children: [
              const SizedBox(
                width: _kindWidth,
                child: Text('Tipo', style: header),
              ),
              cell('Modelo', style: header, flex: 3),
              cell('Etapas', style: header),
              cell('De primeira', style: header),
              cell('Escalaram', style: header),
              cell('Custo est.', style: header),
            ],
          ),
          for (final h in history) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: AppColors.border),
            ),
            Row(
              key: ValueKey('orchestrator-history-${h.kind.name}'),
              children: [
                SizedBox(
                  width: _kindWidth,
                  child: Text(
                    h.kind.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                cell(h.models.map(orchestratorModelLabel).join(', '), flex: 3),
                cell('${h.steps}'),
                cell('${h.firstPass}'),
                cell(
                  '${h.escalated}',
                  style: TextStyle(
                    fontSize: 13,
                    color: h.needsStrongerRule
                        ? AppColors.amber
                        : AppColors.text,
                  ),
                ),
                cell(_usd(h.costUsd)),
              ],
            ),
          ],
        ],
        const SizedBox(height: 12),
        const Text(
          'Uma etapa conta uma vez por tipo: "de primeira" é a que passou na '
          'primeira tentativa do período. US\$ é estimativa do CLI, com o '
          'custo de uma sessão dividido entre as etapas dela; no plano Max, '
          'não é cobrança.',
          style: _sub,
        ),
      ],
    );
  }
}

/// R18: a kind escalates too much; "Ver regra" and "Ignorar".
class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.history,
    required this.days,
    required this.rule,
    required this.onShow,
    required this.onIgnore,
  });

  final KindHistory history;
  final int days;
  final StepRule rule;
  final VoidCallback onShow;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final h = history;
    final share = (h.escalated * 100 / h.steps).round();
    return Container(
      key: ValueKey('orchestrator-history-suggestion-${h.kind.name}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.amber),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${h.kind.label}: ${h.escalated} de ${h.steps} etapas escalaram '
              '($share%) nos últimos $days dias. Considere subir o modelo ou '
              'o esforço da regra, hoje ${rule.label}.',
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
          const SizedBox(width: 8),
          SmallButton(
            key: ValueKey('orchestrator-history-show-${h.kind.name}'),
            label: 'Ver regra',
            onTap: onShow,
          ),
          const SizedBox(width: 6),
          SmallButton(
            key: ValueKey('orchestrator-history-ignore-${h.kind.name}'),
            label: 'Ignorar',
            onTap: onIgnore,
          ),
        ],
      ),
    );
  }
}
