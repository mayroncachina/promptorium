import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../auto_reviewer.dart';

final _specProvider = StreamProvider.family<Spec?, int>(
  (ref, id) => ref.watch(specsRepoProvider).watchById(id),
);

final reviewCommentsProvider =
    StreamProvider.family<List<ReviewCommentRow>, int>(
      (ref, specId) =>
          ref.watch(reviewCommentsRepoProvider).watchBySpec(specId),
    );

/// Top of the Review of a spec: the automatic reviewer's state and its
/// comments by round (F5).
class SpecReviewPanel extends ConsumerWidget {
  const SpecReviewPanel({super.key, required this.specId});

  final int specId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(_specProvider(specId)).value;
    final comments =
        ref.watch(reviewCommentsProvider(specId)).value ??
        const <ReviewCommentRow>[];
    if (spec == null) return const SizedBox.shrink();
    final auto = spec.reviewPhase == ReviewPhase.auto;
    if (!auto && comments.isEmpty) return const SizedBox.shrink();
    final rounds = <int, List<ReviewCommentRow>>{};
    for (final c in comments) {
      rounds.putIfAbsent(c.round, () => []).add(c);
    }
    return Container(
      key: const ValueKey('spec-review-panel'),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        children: [
          if (auto)
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.lilac,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reviewerLabel(spec, running: true) ?? '',
                    key: const ValueKey('review-auto-label'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.lilac,
                    ),
                  ),
                ),
                SmallButton(
                  key: const ValueKey('review-skip-reviewer'),
                  label: 'Pular revisor',
                  onTap: () => ref.read(autoReviewerProvider).skip(specId),
                ),
              ],
            ),
          for (final MapEntry(key: round, value: list)
              in rounds.entries.toList().reversed) ...[
            const SizedBox(height: 8),
            Text(
              'Revisor automático · rodada $round'
              '${switch (list.first.verdict) {
                'aprovar' => ' · aprovou',
                'corrigir' => ' · pediu correções',
                _ => '',
              }}',
              key: ValueKey('review-round-$round'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 8),
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (c.path != null)
                        TextSpan(
                          text:
                              '${c.path}${c.line != null && c.line! > 0 ? ':${c.line}' : ''} ',
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      if (c.severity != null)
                        TextSpan(
                          text: '[${c.severity}] ',
                          style: TextStyle(
                            color: c.severity == 'alta'
                                ? AppColors.red
                                : AppColors.amber,
                          ),
                        ),
                      TextSpan(text: c.body),
                      if (c.requirement != null)
                        TextSpan(
                          text: ' · ${c.requirement}',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
