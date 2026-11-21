import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/usage_tracker.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../board/board_screen.dart' show openSession;
import '../../sessions/widgets/session_style.dart';
import '../cost_format.dart';
import '../spec_cost.dart';
import '../usage_ledger.dart' show entryHasCost;

/// Colour of each origin (the bar and the dot of its line; the label always
/// goes with it, R13).
Color usageSourceColor(UsageSource s) => switch (s) {
  UsageSource.etapa => AppColors.amber,
  UsageSource.revisor => AppColors.lilac,
  UsageSource.ci => AppColors.blue,
  UsageSource.vibe => AppColors.teal,
  UsageSource.refino => CanvasColors.review,
  UsageSource.orquestrador => CanvasColors.agent,
  UsageSource.verificacao => AppColors.yellow,
  UsageSource.outros => AppColors.textMuted,
  UsageSource.livre => AppColors.textDisabled,
};

/// `sonnet` of `claude-sonnet-4-5-20250929`.
String shortModel(String? model) {
  if (model == null || model.isEmpty) return '—';
  for (final m in ['opus', 'sonnet', 'haiku', 'fable']) {
    if (model.contains(m)) return m;
  }
  return model;
}

String _hhmm(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
}

/// "hoje 11:42", "ontem 18:05", "12/11 09:30".
String turnTime(DateTime at, DateTime now) {
  final l = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(l.year, l.month, l.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'hoje ${_hhmm(l)}';
  if (diff == 1) return 'ontem ${_hhmm(l)}';
  return '${l.day.toString().padLeft(2, '0')}/'
      '${l.month.toString().padLeft(2, '0')} ${_hhmm(l)}';
}

/// "Etapa R2", "Revisor · rodada 2", "Corrigir CI · R2", "VIBE".
String turnOrigin(UsageEntry e) {
  final label = switch (e.source) {
    UsageSource.etapa => 'Etapa',
    _ => usageSourceLabel(e.source),
  };
  if (e.step == null) return label;
  return e.source == UsageSource.etapa
      ? '$label ${e.step}'
      : '$label · ${e.step}';
}

const _mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 11);
const _muted = TextStyle(fontSize: 11, color: AppColors.textMuted);
const _head = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: AppColors.textSecondary,
);

/// The section Cota of the panel of a spec (SPEC-081 R7–R9, R12, R14):
/// totals, the weight of now, this window, by origin, by step and the
/// turns. Nothing while the spec has no entry.
class SpecCostSection extends ConsumerWidget {
  const SpecCostSection({
    super.key,
    required this.specId,
    this.sessions = const [],
  });

  final int specId;

  /// Sessions of the spec (the weight of the live ones, R7).
  final List<Session> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cost = ref.watch(specCostProvider(specId));
    if (cost.isEmpty) return const SizedBox.shrink();
    final dollars = ref.watch(costInDollarsProvider);
    final total = cost.total;
    // The weights are of the sessions open in the window (alive).
    final weights = dollars
        ? const <String, double>{}
        : ref.watch(liveQuotaWeightsProvider);
    double? now;
    for (final s in sessions) {
      final running =
          s.status == SessionStatus.running ||
          s.status == SessionStatus.waitingApproval;
      if (running && weights[s.id] != null) now = (now ?? 0) + weights[s.id]!;
    }
    final rate = ref.watch(rateLimitProvider);
    final weighed = total.week != null || total.fiveHour != null;

    // SPEC-097 R9: the Codex turns have tokens, never a measured US\$ 0.
    final only = total.onlyUnpriced;
    final mixed = total.hasUnpriced
        ? formatMixedCost(total.costUsd, total.unpricedTokens, priced: !only)
        : null;
    final spoken = only
        ? 'Cota da spec: $costUnavailable, ${spokenTokens(total.tokens)} do '
              'Codex'
        : dollars
        ? 'Cota da spec: ${formatUsd(total.costUsd)}, estimativa do CLI, '
              '${spokenTokens(total.tokens)}${mixed == null ? '' : ', $mixed'}'
        : 'Cota da spec: ${spokenQuota(total.week)} da semana, '
              '${spokenFiveHour(total.fiveHour)}, ${spokenTokens(total.tokens)}'
              '${mixed == null ? '' : ', $mixed'}';
    final tokensLabel = total.hasUnpriced && !only
        ? 'tokens · Codex ${formatTokenWords(total.unpricedTokens)} · '
              'Claude ${formatTokenWords(total.pricedTokens)}'
        : total.cacheRead > 0
        ? 'tokens · + ${formatTokens(total.cacheRead)} do cache'
        : 'tokens';

    return Semantics(
      key: const ValueKey('spec-cost-section'),
      container: true,
      explicitChildNodes: true,
      label: spoken,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                const Text(
                  'COTA',
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  dollars
                      ? 'todas as sessões da spec · chave de API'
                      : 'todas as sessões da spec',
                  style: _muted,
                ),
                if (cost.estimated)
                  Container(
                    key: const ValueKey('spec-cost-estimated'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.lilac),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'inclui histórico estimado',
                      style: TextStyle(fontSize: 10, color: AppColors.lilac),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Row(
              spacing: 6,
              children: dollars
                  ? [
                      _Tile(
                        key: const ValueKey('spec-cost-usd'),
                        value: only ? 'indisponível' : formatUsd(total.costUsd),
                        label: only
                            ? 'custo · o Codex não informa US\$'
                            : total.hasUnpriced
                            ? 'custo (CLI) · + '
                                  '${formatTokenWords(total.unpricedTokens)} '
                                  'tokens do Codex (sem US\$)'
                            : 'custo (CLI)',
                      ),
                      _Tile(
                        key: const ValueKey('spec-cost-tokens'),
                        value: formatTokens(total.tokens),
                        label: tokensLabel,
                      ),
                      _Tile(value: '${total.turns}', label: 'turnos'),
                    ]
                  : [
                      _Tile(
                        key: const ValueKey('spec-cost-week'),
                        value: only ? 'indisponível' : formatQuota(total.week),
                        label: only
                            ? 'da semana · o Codex não tem peso'
                            : total.hasUnpriced
                            ? 'da semana · só a parte do Claude'
                            : 'da semana',
                      ),
                      _Tile(
                        key: const ValueKey('spec-cost-five'),
                        value: only
                            ? 'indisponível'
                            : formatFiveHourValue(total.fiveHour),
                        label: 'janela de 5 h',
                      ),
                      _Tile(
                        key: const ValueKey('spec-cost-tokens'),
                        value: formatTokens(total.tokens),
                        label: tokensLabel,
                      ),
                    ],
            ),
          ),
          if (mixed != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                mixed,
                key: const ValueKey('spec-cost-mixed'),
                style: _mono.copyWith(color: AppColors.text),
              ),
            ),
          if (only)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'O Codex informa tokens, não US\$. O app nunca mostra 0 no '
                'lugar de "indisponível".',
                key: ValueKey('spec-cost-unpriced-note'),
                style: _muted,
              ),
            )
          else if (dollars)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'estimativa do CLI · sem plano, o US\$ é o que você paga',
                key: ValueKey('spec-cost-cli-estimate'),
                style: _muted,
              ),
            )
          else if (!weighed)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '% depois da primeira leitura de cota. Os turnos de agora '
                'recebem o peso quando a régua existir.',
                key: ValueKey('spec-cost-no-ruler'),
                style: _muted,
              ),
            ),
          if (!dollars && (now != null || cost.thisWindow != null))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _NowLine(
                now: now,
                window: cost.thisWindow,
                resetsAt: rate?.fiveHourResetsAt,
                windowUse: rate?.fiveHourUtilization,
              ),
            ),
          const SizedBox(height: 12),
          const Text('Por origem', style: _head),
          const SizedBox(height: 6),
          _StackedBar(cost: cost),
          const SizedBox(height: 6),
          _Table(
            key: const ValueKey('spec-cost-by-source'),
            first: 'Origem',
            dollars: dollars,
            extra: 'Parte',
            rows: [
              for (final MapEntry(:key, :value) in cost.bySource.entries)
                _Row(
                  key: ValueKey('spec-cost-source-${key.name}'),
                  leading: Dot(usageSourceColor(key), size: 7),
                  label: usageSourceLabel(key),
                  detail: usageUnitsLabel(key, value.units),
                  extra: '${(cost.share(value) * 100).round()}%',
                  slice: value,
                ),
            ],
          ),
          if (cost.bySteps.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Por etapa', style: _head),
            const SizedBox(height: 6),
            _Table(
              key: const ValueKey('spec-cost-by-step'),
              first: 'Etapa',
              dollars: dollars,
              extra: 'Turnos',
              rows: [
                for (final (step, slice) in cost.bySteps)
                  _Row(
                    key: ValueKey('spec-cost-step-$step'),
                    label: step,
                    labelColor: AppColors.amber,
                    extra: '${slice.turns}',
                    slice: slice,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              SmallButton(
                key: const ValueKey('spec-cost-turns'),
                label: 'Ver turnos (${cost.entries.length})',
                height: 28,
                onTap: () => showSpecTurnsDialog(context, specId),
              ),
              if (!dollars)
                const Text(
                  'o peso é a parte do custo estimado de cada turno na '
                  'subida da cota',
                  style: _muted,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

/// "● agora ≈ 9% · 5 h, rodando" and "nesta janela: ≈ 31% · renova às
/// 14:00" (R7, R9). The teal always comes with the text "rodando".
class _NowLine extends StatelessWidget {
  const _NowLine({
    required this.now,
    required this.window,
    required this.resetsAt,
    required this.windowUse,
  });

  final double? now;
  final double? window;
  final DateTime? resetsAt;
  final double? windowUse;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('spec-cost-now'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: SessionColors.runningToolBg,
      border: Border.all(color: SessionColors.runningToolBorder),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Wrap(
      spacing: 10,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (now != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              const Dot(AppColors.teal, size: 7),
              Text(
                'agora ${formatQuota(now)} · 5 h, rodando',
                key: const ValueKey('spec-cost-now-text'),
                style: _mono.copyWith(
                  color: AppColors.teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        if (window != null)
          Text(
            [
              'nesta janela: ${formatFiveHour(window)}',
              if (resetsAt != null) 'renova às ${_hhmm(resetsAt!)}',
              if (now == null && windowUse != null)
                'a janela está em ${(windowUse! * 100).round()}%',
            ].join(' · '),
            key: const ValueKey('spec-cost-window'),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    ),
  );
}

/// The stacked bar by origin, with the list beside it (R14).
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.cost});

  final SpecCost cost;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(
          spacing: 2,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final MapEntry(:key, :value) in cost.bySource.entries)
              if (cost.share(value) > 0)
                Expanded(
                  flex: (cost.share(value) * 1000).round().clamp(1, 1000),
                  child: ColoredBox(color: usageSourceColor(key)),
                ),
          ],
        ),
      ),
    ),
  );
}

class _Row {
  const _Row({
    required this.key,
    required this.label,
    required this.extra,
    required this.slice,
    this.leading,
    this.detail,
    this.labelColor,
  });

  final Key key;
  final Widget? leading;
  final String label;
  final String? detail;
  final Color? labelColor;
  final String extra;
  final CostSlice slice;
}

/// A small table: label, [extra], week, 5 h, tokens (or cost and tokens
/// with an API key).
class _Table extends StatelessWidget {
  const _Table({
    super.key,
    required this.first,
    required this.extra,
    required this.rows,
    required this.dollars,
  });

  final String first;
  final String extra;
  final bool dollars;
  final List<_Row> rows;

  static const _w = 48.0;

  /// Space before each column: "indisp." fills the whole cell, so without
  /// it the Codex lines read as one word ("100%indisp.indisp.").
  static const _gap = 8.0;

  Widget _cell(String text, {TextStyle style = _mono}) => Padding(
    padding: const EdgeInsets.only(left: _gap),
    child: SizedBox(
      width: _w,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          text,
          textAlign: TextAlign.right,
          maxLines: 1,
          softWrap: false,
          style: style,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    Widget line({
      Key? key,
      required Widget label,
      required List<String> cells,
      TextStyle style = _mono,
    }) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: label),
          for (final c in cells) _cell(c, style: style),
        ],
      ),
    );

    final head = dollars
        ? [extra, 'Custo', 'Tokens']
        : [extra, 'Semana', '5 h', 'Tokens'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line(
          label: Text(first, style: _head),
          cells: head,
          style: _head,
        ),
        const Divider(height: 1, color: AppColors.border),
        for (final r in rows) ...[
          Semantics(
            label: [
              r.label,
              if (r.detail != null) r.detail!,
              '${head.first}: ${r.extra}',
              if (r.slice.onlyUnpriced)
                costUnavailable
              else if (dollars)
                formatUsd(r.slice.costUsd)
              else ...[
                '${spokenQuota(r.slice.week)} da semana',
                spokenFiveHour(r.slice.fiveHour),
              ],
              spokenTokens(r.slice.tokens),
            ].join(', '),
            child: ExcludeSemantics(
              child: line(
                key: r.key,
                label: _RowLabel(row: r),
                // SPEC-097 R9: a line only of the Codex has no US\$ and no
                // weight.
                cells: dollars
                    ? [
                        r.extra,
                        r.slice.onlyUnpriced
                            ? costUnavailableShort
                            : formatUsd(r.slice.costUsd),
                        formatTokens(r.slice.tokens),
                      ]
                    : [
                        r.extra,
                        r.slice.onlyUnpriced
                            ? costUnavailableShort
                            : formatQuota(r.slice.week),
                        r.slice.onlyUnpriced
                            ? costUnavailableShort
                            : formatFiveHour(r.slice.fiveHour, short: true),
                        formatTokens(r.slice.tokens),
                      ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
      ],
    );
  }
}

/// The label of a line: the dot, the origin and its sessions or rounds
/// beside it; in a narrow panel (the Specs screen) the detail goes below,
/// so the origin is never cut.
class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.row});

  final _Row row;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final r = row;
      final label = Text(
        r.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: r.labelColor,
          fontFamily: r.labelColor == null ? null : AppFonts.mono,
        ),
      );
      final detail = r.detail == null
          ? null
          : Text(
              r.detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _muted,
            );
      final wide = box.maxWidth >= 150;
      return Row(
        spacing: 5,
        children: [
          ?r.leading,
          if (wide || detail == null) ...[
            Flexible(flex: 2, child: label),
            if (detail != null) Flexible(child: detail),
          ] else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, detail],
              ),
            ),
        ],
      );
    },
  );
}

/// "Ver turnos": the entries of the spec, newest first (R8). A turn of a
/// session opens the session.
Future<void> showSpecTurnsDialog(BuildContext context, int specId) =>
    showAppDialog<void>(
      context: context,
      builder: (context) => _TurnsDialog(specId: specId),
    );

class _TurnsDialog extends ConsumerWidget {
  const _TurnsDialog({required this.specId});

  final int specId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cost = ref.watch(specCostProvider(specId));
    final dollars = ref.watch(costInDollarsProvider);
    final now = DateTime.now();
    Widget cell(String t, double w, {TextStyle style = _mono}) => SizedBox(
      width: w,
      child: Text(t, textAlign: TextAlign.right, maxLines: 1, style: style),
    );
    final heads = dollars
        ? ['Modelo', 'Tokens', 'Custo']
        : ['Modelo', 'Tokens', 'Semana', '5 h'];
    return AlertDialog(
      key: const ValueKey('spec-turns-dialog'),
      backgroundColor: AppColors.panelSolid,
      title: Text(
        'Turnos da spec (${cost.entries.length})',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 640,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 96, child: Text('Hora', style: _head)),
                const Expanded(child: Text('Origem', style: _head)),
                for (final h in heads)
                  cell(h, h == 'Modelo' ? 70 : 64, style: _head),
              ],
            ),
            const Divider(height: 8, color: AppColors.border),
            Expanded(
              child: ListView.builder(
                itemCount: cost.entries.length,
                itemBuilder: (context, i) {
                  final e = cost.entries[i];
                  final open = e.sessionId == null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          openSession(ref, e.sessionId!);
                        };
                  return InkWell(
                    key: ValueKey('spec-turn-${e.id}'),
                    onTap: open,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              turnTime(e.at, now),
                              style: _mono.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Row(
                              spacing: 6,
                              children: [
                                Dot(usageSourceColor(e.source), size: 7),
                                Flexible(
                                  child: Text(
                                    turnOrigin(e),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (e.estimated)
                                  const Text('estimado', style: _muted),
                                if (!entryHasCost(e))
                                  Text(
                                    e.provider == 'codex'
                                        ? 'Codex'
                                        : e.provider,
                                    style: _muted,
                                  ),
                              ],
                            ),
                          ),
                          cell(shortModel(e.model), 70),
                          cell(
                            formatTokens(
                              e.tokensIn + e.tokensCacheWrite + e.tokensOut,
                            ),
                            64,
                          ),
                          if (!entryHasCost(e)) ...[
                            cell(costUnavailableShort, 64, style: _muted),
                            if (!dollars)
                              cell(costUnavailableShort, 64, style: _muted),
                          ] else if (dollars)
                            cell(formatUsd(e.costUsd), 64)
                          else ...[
                            cell(formatQuota(e.weekPct), 64),
                            cell(
                              formatFiveHour(e.fiveHourPct, short: true),
                              64,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Clicar num turno de sessão abre a sessão. Os turnos do revisor '
              'e do Orquestrador não abrem nada: são claude -p.',
              style: _muted,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('spec-turns-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
