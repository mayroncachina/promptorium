import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../debts/origin_debts.dart';
import '../../debts/widgets/review_comment_debt.dart';
import '../../sessions/widgets/session_style.dart';
import '../comment_anchor.dart';

/// Shows the body of treated comments below it (diff since a round, where
/// the request is compared with its fix); elsewhere they collapse.
class ResolvedCommentBodies extends InheritedWidget {
  const ResolvedCommentBodies({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ResolvedCommentBodies>() !=
      null;

  @override
  bool updateShouldNotify(ResolvedCommentBodies oldWidget) => false;
}

/// Shared by inline, file-wide and outdated comments. Bodies are plain text.
class PersistedComment extends ConsumerWidget {
  const PersistedComment({
    super.key,
    required this.comment,
    this.selected = false,
    this.onSelected,
  });
  final AnchoredComment comment;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = comment.row;
    // SPEC-112 R8: the debt the comment became, and "Virar débito".
    final scope = ReviewDebtScope.maybeOf(context);
    final debt = scope == null
        ? null
        : ref.watch(
            reviewCommentDebtCodesProvider.select((m) => m.value?[c.id]),
          );
    final who = switch (c.author) {
      'pr' => 'PR · ${c.body.startsWith('@') ? c.body.split(':').first : ''}',
      'humano' => 'Você',
      _ => 'Revisor',
    };
    return Opacity(
      opacity: c.resolved && debt == null ? .55 : 1,
      child: Card(
        key: ValueKey('review-comment-${c.id}'),
        margin: const EdgeInsets.fromLTRB(20, 4, 12, 4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!c.resolved && c.author != 'humano' && onSelected != null)
                    Checkbox(
                      value: selected,
                      onChanged: (v) => onSelected!(v!),
                    ),
                  Expanded(
                    child: Text(
                      '$who · rodada ${c.round}'
                      '${c.severity == null ? '' : ' · ${c.severity}'}'
                      '${c.requirement == null ? '' : ' · ${c.requirement}'}',
                    ),
                  ),
                  if (debt != null)
                    CommentDebtSeal(
                      debt,
                      key: ValueKey('review-comment-debt-seal-${c.id}'),
                    )
                  else ...[
                    if (scope != null && isOpenReviewComment(c))
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: SmallButton(
                          key: ValueKey('review-comment-debt-${c.id}'),
                          label: 'Virar débito',
                          height: 26,
                          color: AppColors.amber,
                          border: AppColors.amber.withValues(alpha: .6),
                          background: Colors.transparent,
                          onTap: () =>
                              turnReviewCommentIntoDebt(context, ref, scope, c),
                        ),
                      ),
                    TextButton(
                      onPressed: () => ref
                          .read(reviewCommentsRepoProvider)
                          .setResolved(c.id, !c.resolved),
                      child: Text(c.resolved ? 'Reabrir' : 'Tratado'),
                    ),
                  ],
                ],
              ),
              if (debt != null)
                Text(
                  c.body,
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: AppColors.textSecondary,
                  ),
                )
              else if (!c.resolved || ResolvedCommentBodies.of(context))
                Text(c.body),
              if (debt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Virou débito · não conta mais como aberto',
                          style: TextStyle(fontSize: 12, color: AppColors.teal),
                        ),
                      ),
                      if (scope != null && !scope.merged)
                        SmallButton(
                          key: ValueKey('review-comment-debt-undo-${c.id}'),
                          label: 'Desfazer',
                          height: 26,
                          onTap: () => undoReviewCommentDebt(
                            context,
                            ref,
                            scope,
                            c,
                            debt,
                          ),
                        ),
                    ],
                  ),
                ),
              if (comment.outdatedReason != null)
                Text(
                  'Fora do diff atual · ${c.path ?? 'Geral'}:${c.line ?? 0} · ${comment.outdatedReason}'
                  '${c.commitSha == null ? '' : ' · ${c.commitSha}'}',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
