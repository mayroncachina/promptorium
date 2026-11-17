import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../board/board_rules.dart' show specStageLabel;
import '../../board/board_screen.dart'
    show boardFocusSpecProvider, boardSelectedSpecProvider, specStageColor;
import '../../sessions/widgets/session_style.dart';
import '../cost_format.dart';
import '../spec_cost.dart';

/// Period and "Todos os workspaces" of the ranking (kept while the app is
/// open).
class CostRankingFilter extends Notifier<({CostPeriod period, bool all})> {
  @override
  ({CostPeriod period, bool all}) build() =>
      (period: CostPeriod.week, all: false);

  void setPeriod(CostPeriod p) => state = (period: p, all: state.all);

  void setAll(bool all) => state = (period: state.period, all: all);
}

final costRankingFilterProvider =
    NotifierProvider<CostRankingFilter, ({CostPeriod period, bool all})>(
      CostRankingFilter.new,
    );

/// Opens [spec] in the Quadro with its panel (R10): the workspace becomes
/// the active one if it is another.
Future<void> openSpecCostInBoard(WidgetRef ref, Spec spec) async {
  if (ref.read(activeWorkspaceProvider)?.id != spec.workspaceId) {
    await ref.read(workspaceActionsProvider).select(spec.workspaceId);
  }
  ref.read(boardSelectedSpecProvider.notifier).select(spec.id);
  ref.read(boardFocusSpecProvider.notifier).select(spec.id);
  ref.read(navigationProvider.notifier).go(AppSection.tasks);
}

const _head = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: AppColors.textSecondary,
);
const _mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 12);

/// Projeto → Métricas: "Specs que mais custaram" (SPEC-081 R10, R12, R14):
/// the 10 specs with the most weight in the period. A table navigable by
/// the keyboard (↑/↓, Enter opens).
class SpecCostRanking extends ConsumerWidget {
  const SpecCostRanking({super.key, required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(costRankingFilterProvider);
    final list = ref.watch(
      specCostRankingProvider((
        workspaceId: workspace.id,
        all: filter.all,
        period: filter.period,
      )),
    );
    final dollars = ref.watch(costInDollarsProvider);
    final rows = list ?? const <SpecCostRank>[];
    final top = rows.isEmpty ? 0.0 : rankWeight(rows.first.cost);
    final weekSum = rows.fold<double?>(
      null,
      (a, r) => r.cost.total.week == null ? a : (a ?? 0) + r.cost.total.week!,
    );
    final costSum = rows.fold(0.0, (a, r) => a + r.cost.total.costUsd);
    final summary = rows.isEmpty
        ? ''
        : dollars
        ? ' · ${rows.length} specs somam ${formatUsd(costSum)} (estimativa do '
              'CLI)'
        : weekSum == null
        ? ' · % depois da primeira leitura de cota'
        : ' · ${rows.length} specs somam ${formatQuota(weekSum)} de uma semana';

    return Container(
      key: const ValueKey('spec-cost-ranking'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            spacing: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'Specs que mais custaram',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    (dollars
                            ? 'custo de todas as sessões de cada spec'
                            : 'peso de todas as sessões de cada spec na cota '
                                  'do plano') +
                        summary,
                    key: const ValueKey('spec-cost-ranking-summary'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  SegmentedButton<CostPeriod>(
                    key: const ValueKey('spec-cost-period'),
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                      selectedForegroundColor: AppColors.amber,
                      selectedBackgroundColor: AppColors.amberTint,
                    ),
                    segments: [
                      for (final p in CostPeriod.values)
                        ButtonSegment(
                          value: p,
                          label: Text(
                            p.label,
                            key: ValueKey('spec-cost-period-${p.name}'),
                          ),
                        ),
                    ],
                    selected: {filter.period},
                    onSelectionChanged: (s) => ref
                        .read(costRankingFilterProvider.notifier)
                        .setPeriod(s.first),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: const ValueKey('spec-cost-all-workspaces'),
                        value: filter.all,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) => ref
                            .read(costRankingFilterProvider.notifier)
                            .setAll(v ?? false),
                      ),
                      const Text(
                        'Todos os workspaces',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (list == null)
            const Text('Calculando…', style: TextStyle(fontSize: 12))
          else if (rows.isEmpty)
            const Text(
              'Nenhum turno de spec no período.',
              key: ValueKey('spec-cost-ranking-empty'),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else
            Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    NextFocusIntent(),
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    PreviousFocusIntent(),
              },
              child: FocusTraversalGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RankRow.header(dollars: dollars, all: filter.all),
                    for (final (i, r) in rows.indexed)
                      _RankRow(
                        key: ValueKey('spec-cost-rank-${r.spec.code}'),
                        index: i + 1,
                        rank: r,
                        top: top,
                        dollars: dollars,
                        all: filter.all,
                        onOpen: () => openSpecCostInBoard(ref, r.spec),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    super.key,
    required this.index,
    required this.rank,
    required this.top,
    required this.dollars,
    required this.all,
    required this.onOpen,
  }) : isHeader = false;

  const _RankRow.header({required this.dollars, required this.all})
    : index = 0,
      rank = null,
      top = 0,
      onOpen = null,
      isHeader = true;

  final int index;
  final SpecCostRank? rank;
  final double top;
  final bool dollars;
  final bool all;
  final VoidCallback? onOpen;
  final bool isHeader;

  static Widget _num(String t, double w, TextStyle style) => SizedBox(
    width: w,
    child: Text(t, textAlign: TextAlign.right, maxLines: 1, style: style),
  );

  @override
  Widget build(BuildContext context) {
    if (isHeader) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          spacing: 10,
          children: [
            _num('#', 22, _head),
            const Expanded(flex: 4, child: Text('Spec', style: _head)),
            const SizedBox(width: 110, child: Text('Coluna', style: _head)),
            const Expanded(flex: 3, child: Text('Peso', style: _head)),
            if (dollars)
              _num('Custo', 80, _head)
            else ...[
              _num('Semana', 64, _head),
              _num('5 h', 72, _head),
            ],
            _num('Tokens', 60, _head),
            const SizedBox(width: 110, child: Text('Mais pesou', style: _head)),
          ],
        ),
      );
    }
    final r = rank!;
    final c = r.cost.total;
    final weight = rankWeight(r.cost);
    final bar = top <= 0 ? 0.0 : (weight / top).clamp(0.0, 1.0);
    final best = r.top;
    final bestText = best == null
        ? '—'
        : '${usageSourceLabel(best.$1).toLowerCase()} '
              '${(best.$2 * 100).round()}%';
    final spoken = [
      '$index',
      r.spec.code,
      r.spec.title,
      if (all) r.workspace.name,
      specStageLabel(r.spec.stage),
      if (dollars)
        formatUsd(c.costUsd)
      else ...[
        '${spokenQuota(c.week)} da semana',
        spokenFiveHour(c.fiveHour),
      ],
      spokenTokens(c.tokens),
      'mais pesou: $bestText',
    ].join(', ');
    return Semantics(
      button: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(6),
            focusColor: AppColors.amberTint,
            hoverColor: AppColors.surfaceRaised,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                spacing: 10,
                children: [
                  _num(
                    '$index',
                    22,
                    _mono.copyWith(color: AppColors.textMuted),
                  ),
                  Expanded(
                    flex: 4,
                    child: Row(
                      spacing: 8,
                      children: [
                        Text(
                          r.spec.code,
                          style: _mono.copyWith(color: AppColors.textSecondary),
                        ),
                        Flexible(
                          child: Text(
                            r.spec.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (all)
                          Text(
                            r.workspace.name,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Row(
                      spacing: 6,
                      children: [
                        Dot(specStageColor(r.spec.stage), size: 7),
                        Flexible(
                          child: Text(
                            specStageLabel(r.spec.stage),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(height: 6, color: AppColors.border),
                          FractionallySizedBox(
                            widthFactor: bar,
                            child: Container(
                              height: 6,
                              color: index == 1
                                  ? AppColors.amber
                                  : AppColors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (dollars)
                    _num(formatUsd(c.costUsd), 80, _mono)
                  else ...[
                    _num(formatQuota(c.week), 64, _mono),
                    _num(formatFiveHour(c.fiveHour, short: true), 72, _mono),
                  ],
                  _num(formatTokens(c.tokens), 60, _mono),
                  SizedBox(
                    width: 110,
                    child: Text(
                      bestText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
