import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../board/orchestrator/orchestrator_rules.dart';
import '../sessions/widgets/session_style.dart';

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

/// `US$ 6,20` (decimal comma, as in the mockup).
String historyUsd(double v) =>
    'US\$ ${v.toStringAsFixed(2).replaceFirst('.', ',')}';

/// Text of the suggestion of R18: the next model and the next effort of
/// [rule], when there is one (no "crie um tipo próprio", D3).
String historySuggestionText(KindHistory h, int days, StepRule rule) {
  final m = orchestratorModels.indexWhere((x) => x.$1 == rule.model);
  final e = orchestratorEfforts.indexOf(rule.effort);
  final nextModel = m >= 0 && m + 1 < orchestratorModels.length
      ? orchestratorModels[m + 1].$2
      : null;
  final nextEffort = e >= 0 && e + 1 < orchestratorEfforts.length
      ? orchestratorEfforts[e + 1]
      : null;
  final raise = [
    if (nextModel != null) 'o modelo para $nextModel',
    if (nextEffort != null) 'o esforço para $nextEffort',
  ];
  return '${h.escalated} de ${h.steps} etapas escalaram nos últimos $days '
      'dias. '
      '${raise.isEmpty ? 'A regra já está no topo (${rule.label}).' : 'Suba ${raise.join(' ou ')}.'}';
}

const _sub = TextStyle(fontSize: 11, color: AppColors.textSecondary);
const _mono = TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: 12,
  color: AppColors.text,
);

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

  @override
  Widget build(BuildContext context) {
    final runs = ref.watch(stepRunsOfPeriodProvider(_days));
    final settings = ref.watch(appSettingsProvider);
    final prefs = ref.watch(orchestratorPrefsProvider);
    final history = orchestratorHistory(runs.value ?? const []);
    const header = TextStyle(fontSize: 11, color: AppColors.textMuted);
    Widget row(List<Widget> cells, {Key? key}) => Row(
      key: key,
      children: [
        Expanded(flex: 3, child: cells[0]),
        Expanded(flex: 3, child: cells[1]),
        Expanded(flex: 4, child: cells[2]),
        Expanded(
          flex: 2,
          child: Align(alignment: Alignment.centerRight, child: cells[3]),
        ),
        Expanded(
          flex: 2,
          child: Align(alignment: Alignment.centerRight, child: cells[4]),
        ),
      ],
    );
    Text ellipsis(String text, TextStyle style) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return Container(
      key: const ValueKey('orchestrator-history'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Histórico do Orquestrador',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'US\$ é estimativa do CLI; no plano Max não é cobrança.',
                      key: ValueKey('orchestrator-history-usd-note'),
                      style: _sub,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _PeriodSwitch(
                days: _days,
                onChanged: (d) => setState(() => _days = d),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final h in history)
            if (showHistorySuggestion(h, historyIgnoredAt(settings, h.kind)))
              _Suggestion(
                history: h,
                text: historySuggestionText(h, _days, prefs.rule(h.kind)),
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
                  : 'Nenhuma etapa rodou em Automático nos últimos $_days '
                        'dias.',
              key: const ValueKey('orchestrator-history-empty'),
              style: _sub,
            )
          else ...[
            row([
              const Text('Tipo de etapa', style: header),
              const Text('Modelo', style: header),
              const Text('Passou de primeira', style: header),
              const Text('Escalou', style: header),
              const Text('Estimativa', style: header),
            ]),
            for (final h in history) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: AppColors.border),
              ),
              row(key: ValueKey('orchestrator-history-${h.kind.name}'), [
                ellipsis(
                  h.kind.label,
                  const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                ellipsis(
                  h.models.map(orchestratorModelLabel).join(' → '),
                  const TextStyle(fontSize: 13, color: AppColors.text),
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          key: ValueKey(
                            'orchestrator-history-bar-${h.kind.name}',
                          ),
                          value: h.steps == 0 ? 0 : h.firstPass / h.steps,
                          minHeight: 6,
                          backgroundColor: AppColors.border,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: ellipsis('${h.firstPass} de ${h.steps}', _mono),
                    ),
                  ],
                ),
                ellipsis(
                  '${h.escalated}',
                  _mono.copyWith(
                    color: h.needsStrongerRule
                        ? AppColors.amber
                        : AppColors.text,
                  ),
                ),
                ellipsis(historyUsd(h.costUsd), _mono),
              ]),
            ],
          ],
          const SizedBox(height: 12),
          const Text(
            'Uma etapa conta uma vez por tipo: "passou de primeira" é a que '
            'passou na primeira tentativa do período. Quando uma sessão roda '
            'várias etapas, o custo dela é dividido entre elas.',
            style: _sub,
          ),
        ],
      ),
    );
  }
}

/// "7 dias" | "30 dias" | "90 dias".
class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: AppColors.background,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in orchestratorHistoryPeriods)
          Semantics(
            button: true,
            selected: d == days,
            child: Material(
              color: d == days ? SessionColors.selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                key: ValueKey('orchestrator-history-days-$d'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => onChanged(d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    '$d dias',
                    style: TextStyle(
                      fontSize: 12,
                      color: d == days
                          ? AppColors.text
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// R18: a kind escalates too much; "Ignorar" and "Ver regra".
class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.history,
    required this.text,
    required this.onShow,
    required this.onIgnore,
  });

  final KindHistory history;
  final String text;
  final VoidCallback onShow;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final h = history;
    return Container(
      key: ValueKey('orchestrator-history-suggestion-${h.kind.name}'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.amberTint,
        border: Border.all(color: SessionColors.approvalBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sugestão para a regra ${h.kind.label}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SmallButton(
            key: ValueKey('orchestrator-history-ignore-${h.kind.name}'),
            label: 'Ignorar',
            onTap: onIgnore,
          ),
          const SizedBox(width: 8),
          AmberButton(
            key: ValueKey('orchestrator-history-show-${h.kind.name}'),
            label: 'Ver regra',
            onTap: onShow,
          ),
        ],
      ),
    );
  }
}
