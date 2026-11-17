import 'package:flutter/material.dart';

import '../../../../ui/theme/tokens.dart';
import '../../../sessions/timeline.dart';
import '../../../sessions/widgets/timeline_view.dart';
import '../compare_run.dart';
import '../compare_weight.dart';
import 'compare_bar.dart';

/// The folded comparison in the conversation (R11): the side chosen, the
/// metrics of both and "Ver a resposta" of the other, read only.
class CompareCard extends StatefulWidget {
  const CompareCard({super.key, required this.item, this.root});

  final CompareItem item;
  final String? root;

  @override
  State<CompareCard> createState() => _CompareCardState();
}

class _CompareCardState extends State<CompareCard> {
  bool _open = false;
  List<TimelineItem>? _otherItems;

  @override
  Widget build(BuildContext context) {
    final run = CompareRun.fromJson(widget.item.data, conversationId: 0);
    final chosen = run?.chosenSide;
    final other = run?.otherSide;
    if (run == null || chosen == null || other == null) {
      return Text(
        widget.item.text,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }
    const head = TextStyle(fontSize: 11, color: AppColors.textSecondary);
    const cell = TextStyle(
      fontSize: 12,
      fontFamily: AppFonts.mono,
      color: AppColors.text,
    );
    TableRow row(CompareSide s) {
      final m = s.metrics;
      final w = s.weight;
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                CompareLetter(s.letter, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: compareModelLabel(s.model),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                        if (s.letter != run.chosen)
                          const TextSpan(
                            text: '  (não escolhida)',
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Text(m == null ? '—' : compareDuration(m.durationMs), style: cell),
          Text(m == null ? '—' : compareTokensLine(m), style: cell),
          Text(w == null ? '—' : compareWeightLabel(w.five), style: cell),
          Text(w == null ? '—' : compareWeightLabel(w.week), style: cell),
        ],
      );
    }

    final otherItems = _otherItems ??= [
      for (final i in other.timeline().items)
        if (i is! NoticeItem) i,
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Semantics(
          container: true,
          label: widget.item.text,
          child: Container(
            key: const ValueKey('compare-card'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.view_column_outlined,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Comparação',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '· escolhida ${chosen.letter} · ${chosen.label}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: compareSideColor(chosen.letter),
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      key: const ValueKey('compare-card-toggle'),
                      onPressed: () => setState(() => _open = !_open),
                      icon: Icon(
                        _open ? Icons.expand_less : Icons.chevron_right,
                        size: 16,
                      ),
                      label: Text(
                        _open
                            ? 'Recolher'
                            : 'Ver a resposta do ${other.letter}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(2),
                    3: FlexColumnWidth(1.2),
                    4: FlexColumnWidth(1),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    const TableRow(
                      children: [
                        SizedBox(),
                        Text('Tempo', style: head),
                        Text('Tokens', style: head),
                        Text('Janela de 5 h', style: head),
                        Text('Semana', style: head),
                      ],
                    ),
                    for (final s in run.sides) row(s),
                  ],
                ),
                if (_open) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const ValueKey('compare-card-answer'),
                    constraints: const BoxConstraints(maxHeight: 420),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: otherItems.isEmpty
                        ? const Text(
                            'Sem resposta guardada.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final i in otherItems)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: TimelineItemView(
                                      item: i,
                                      root: widget.root,
                                      assistantName:
                                          'Claude · ${other.label} · não '
                                          'escolhida',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
