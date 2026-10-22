import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
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
    final who = switch (c.author) {
      'pr' => 'PR · ${c.body.startsWith('@') ? c.body.split(':').first : ''}',
      'humano' => 'Você',
      _ => 'Revisor',
    };
    return Opacity(
      opacity: c.resolved ? .55 : 1,
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
                  TextButton(
                    onPressed: () => ref
                        .read(reviewCommentsRepoProvider)
                        .setResolved(c.id, !c.resolved),
                    child: Text(c.resolved ? 'Reabrir' : 'Tratado'),
                  ),
                ],
              ),
              if (!c.resolved || ResolvedCommentBodies.of(context))
                Text(c.body),
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
