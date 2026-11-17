import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../ui/theme/tokens.dart';
import '../compare_run.dart';
import '../compare_weight.dart';
import 'compare_bar.dart' show compareSideColor;

/// Rebuilds every second while [active] (the live time of a side).
class CompareTicker extends StatefulWidget {
  const CompareTicker({super.key, required this.active, required this.builder});

  final bool active;
  final WidgetBuilder builder;

  @override
  State<CompareTicker> createState() => _CompareTickerState();
}

class _CompareTickerState extends State<CompareTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CompareTicker old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!widget.active) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Live time of a running side (`1:04`).
String compareElapsed(CompareSide s, {DateTime? now}) => s.startedAt == null
    ? '0:00'
    : compareClock((now ?? DateTime.now()).difference(s.startedAt!));

/// The tooltip of the weight (R8).
String compareWeightHint(bool measured) => measured
    ? 'estimado pela variação da janela durante a comparação'
    : 'estimado pela última leitura da janela (a regra da Atividades)';

/// Footer of a column (R7): time, tokens, calls and the weight in the
/// 5-hour window and in the week. Never US$.
class CompareMetricsView extends StatelessWidget {
  const CompareMetricsView({
    super.key,
    required this.run,
    required this.side,
    this.calls = 0,
  });

  final CompareRun run;
  final CompareSide side;

  /// Calls so far, while it runs.
  final int calls;

  @override
  Widget build(BuildContext context) {
    final s = side;
    if (s.state.live) {
      return CompareTicker(
        active: true,
        builder: (_) {
          final t = compareElapsed(s);
          final text =
              'rodando há $t · ${calls == 1 ? '1 chamada' : '$calls chamadas'} '
              'até agora · o peso aparece quando os dois terminarem';
          return Padding(
            key: ValueKey('compare-metrics-${s.letter}'),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    final m = s.metrics;
    final other = run.sides.firstWhere((o) => o.letter != s.letter);
    final ratio = compareRatio(run.a, run.b);
    // "B pesou 4,8× o A · levou 2,9× o tempo", on the heavier side.
    bool mine(String? t) => t?.startsWith('${s.letter} ') ?? false;
    final lines = [
      if (mine(ratio.weight)) ratio.weight!,
      if (mine(ratio.time))
        mine(ratio.weight)
            ? ratio.time!.replaceFirst('${s.letter} ', '')
            : ratio.time!,
    ];
    final max = [
      s.weight?.five ?? 0,
      other.weight?.five ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final maxWeek = [
      s.weight?.week ?? 0,
      other.weight?.week ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final pending = s.weight == null
        ? (run.anyLive ? 'medindo…' : 'sem leitura')
        : null;
    final spoken = [
      if (m != null) ...[
        'tempo ${compareDurationSpoken(m.durationMs)}',
        'tokens ${compareTokens(m.tokensIn)} de entrada e '
            '${compareTokens(m.tokensOut)} de saída',
        'chamadas: ${compareCalls(m.tools)}',
      ],
      if (s.weight case final w?) ...[
        'peso na janela de 5 horas, ${compareWeightSpoken(w.five)}',
        'peso na semana, ${compareWeightSpoken(w.week)}',
      ] else
        'peso $pending',
      ...lines,
    ].join('; ');
    return Semantics(
      key: ValueKey('compare-metrics-${s.letter}'),
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Cell(
                    'Tempo',
                    m == null ? '—' : compareDuration(m.durationMs),
                  ),
                  _Cell('Tokens', m == null ? '—' : compareTokensLine(m)),
                  _Cell(
                    'Chamadas',
                    m == null ? '—' : compareCalls(m.tools),
                    mono: false,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Bar(
                label: 'Janela de 5 h',
                letter: s.letter,
                value: s.weight?.five,
                max: max,
                pending: pending,
                hint: compareWeightHint(run.measured),
              ),
              const SizedBox(height: 4),
              _Bar(
                label: 'Semana',
                letter: s.letter,
                value: s.weight?.week,
                max: maxWeek,
                pending: pending,
                hint: compareWeightHint(run.measured),
              ),
              if (lines.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  lines.join('   ·   '),
                  key: ValueKey('compare-ratio-${s.letter}'),
                  style: const TextStyle(fontSize: 11, color: AppColors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.label, this.value, {this.mono = true});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontFamily: mono ? AppFonts.mono : null,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.letter,
    required this.value,
    required this.max,
    required this.pending,
    required this.hint,
  });

  final String label;
  final String letter;
  final double? value;
  final double max;
  final String? pending;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final fill = v == null || max <= 0 ? .02 : (v / max).clamp(.02, 1.0);
    return Tooltip(
      message: hint,
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fill,
                minHeight: 5,
                backgroundColor: AppColors.border,
                color: v == null
                    ? AppColors.textMuted
                    : compareSideColor(letter),
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              v == null ? pending ?? '' : compareWeightLabel(v),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: AppFonts.mono,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
