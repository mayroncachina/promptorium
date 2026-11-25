import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../debt_detector.dart';

/// "Simplificar agora → débito" and "Decidir depois → DP" under a question
/// of the interview (SPEC-112 R6).
class QuestionDebtActions extends StatelessWidget {
  const QuestionDebtActions({
    super.key,
    required this.onDebt,
    required this.onDecision,
    this.keyPrefix = 'question',
    this.height = 28,
  });

  final VoidCallback? onDebt;
  final VoidCallback? onDecision;
  final String keyPrefix;
  final double height;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      SmallButton(
        key: ValueKey('$keyPrefix-to-debt'),
        label: 'Simplificar agora → débito',
        height: height,
        color: AppColors.amber,
        border: AppColors.amber.withValues(alpha: .55),
        background: AppColors.amber.withValues(alpha: .08),
        onTap: onDebt,
      ),
      SmallButton(
        key: ValueKey('$keyPrefix-to-decision'),
        label: 'Decidir depois → DP',
        height: height,
        onTap: onDecision,
      ),
    ],
  );
}

/// "Parece um débito: “…” · nada foi gravado ainda" (R7): the answer asks
/// for a debt or a decision; [note] says what happens to the suggestion.
class DetectedDebtHint extends StatelessWidget {
  const DetectedDebtHint({
    super.key,
    required this.intent,
    required this.answer,
    this.note = 'nada foi gravado ainda',
  });

  final DebtIntent intent;
  final String answer;
  final String note;

  @override
  Widget build(BuildContext context) {
    final text = answer.replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = text.length > 80 ? '${text.substring(0, 79)}…' : text;
    return Container(
      key: const ValueKey('detected-debt-hint'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.lilac.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.lilac.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.lilac.withValues(alpha: .6)),
            ),
            child: const Text(
              'sugestão',
              style: TextStyle(fontSize: 11, color: AppColors.lilac),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: intent == DebtIntent.debt
                        ? 'Parece um débito: '
                        : 'Parece uma decisão para depois: ',
                  ),
                  TextSpan(
                    text: '“$short”',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: ' · $note',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// "→ débito pendente" under a question of the draft (P2).
class PendingDebtTag extends StatelessWidget {
  const PendingDebtTag(this.text, {super.key, this.onRemove});

  final String text;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 11.5,
            color: AppColors.teal,
          ),
        ),
      ),
      if (onRemove != null)
        IconButton(
          tooltip: 'Desfazer',
          visualDensity: VisualDensity.compact,
          iconSize: 14,
          onPressed: onRemove,
          icon: const Icon(Icons.close, color: AppColors.textMuted),
        ),
    ],
  );
}
