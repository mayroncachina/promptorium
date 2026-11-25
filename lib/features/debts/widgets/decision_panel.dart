import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../debt_board.dart';

/// The detail of a decision on the "Decisões" tab (R12, R13).
class DecisionPanel extends ConsumerWidget {
  const DecisionPanel({
    super.key,
    required this.row,
    required this.board,
    required this.workspaceId,
  });

  final DecisionRowView row;
  final DebtBoard board;
  final int workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = row.item;
    return SingleChildScrollView(
      key: ValueKey('decision-panel-${d.code}'),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                d.code,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 13,
                  color: AppColors.amber,
                ),
              ),
              Text(
                '· desde ${d.since} · origem',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              DebtTag(row.origin),
              if (row.inSpec != null)
                DebtTag('na ${specLabel(row.inSpec!)}', color: AppColors.lilac),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            d.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          if (d.question != '**${d.title}**' && d.question != d.title) ...[
            const SizedBox(height: 6),
            Text(
              d.question.replaceAll('**', ''),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          DebtBox(label: 'RECOMENDAÇÃO', text: d.recommendation),
          if (d.decided) ...[
            const SizedBox(height: 12),
            DebtBox(
              label: 'DECISÃO',
              text: d.decision.replaceAll('**', ''),
              key: const ValueKey('decision-decided-text'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A labelled box (RECOMENDAÇÃO, DECISÃO).
class DebtBox extends StatelessWidget {
  const DebtBox({super.key, required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            letterSpacing: .8,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text.isEmpty ? '—' : text,
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
      ],
    ),
  );
}

/// A small outlined tag (origin, state).
class DebtTag extends StatelessWidget {
  const DebtTag(this.text, {super.key, this.color, this.filled = false});

  final String text;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: filled ? c.withValues(alpha: .12) : null,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color == null
              ? AppColors.borderHover
              : c.withValues(alpha: .6),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: c),
      ),
    );
  }
}
