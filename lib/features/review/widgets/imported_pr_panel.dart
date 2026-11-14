import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../auto_reviewer.dart';
import '../pr_import.dart';
import '../comment_anchor.dart' show isOpenReviewComment;

/// Review comments of a PR brought into the app without a spec, by session
/// (SPEC-050 P1).
final sessionReviewCommentsProvider =
    StreamProvider.family<List<ReviewCommentRow>, String>(
      (ref, sessionId) =>
          ref.watch(reviewCommentsRepoProvider).watchBySession(sessionId),
    );

/// The panel of a PR brought into the app (SPEC-050 R6): who opened it,
/// the open comments and the automatic reviewer, off by default with
/// "Rodar revisor".
class ImportedPrPanel extends ConsumerStatefulWidget {
  const ImportedPrPanel({
    super.key,
    required this.sessionId,
    this.merged = false,
  });

  final String sessionId;
  final bool merged;

  @override
  ConsumerState<ImportedPrPanel> createState() => _ImportedPrPanelState();
}

class _ImportedPrPanelState extends ConsumerState<ImportedPrPanel> {
  bool _reviewing = false;

  Future<void> _runReviewer(ImportedPr pr) async {
    setState(() => _reviewing = true);
    try {
      await ref
          .read(autoReviewerProvider)
          .reviewSession(widget.sessionId, title: pr.title);
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pr = ref.watch(
      appSettingsProvider.select((m) => importedPrOf(m, widget.sessionId)),
    );
    if (pr == null) return const SizedBox.shrink();
    final rows =
        ref.watch(sessionReviewCommentsProvider(widget.sessionId)).value ??
        const <ReviewCommentRow>[];
    final open = rows.where(isOpenReviewComment).length;
    final verdict = rows
        .where((r) => r.author == 'revisor' && r.verdict != null)
        .lastOrNull;
    final failed = rows
        .where(
          (r) =>
              r.author == 'revisor' &&
              r.body.startsWith(AutoReviewer.failurePrefix),
        )
        .lastOrNull;
    final reviewer = _reviewing
        ? 'Revisor automático revisando…'
        : failed != null && (verdict == null || failed.id > verdict.id)
        ? failed.body
        : verdict != null
        ? 'Revisor (rodada ${verdict.round}): ${verdict.body}'
        : 'Revisor automático desligado';
    const muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Container(
      key: const ValueKey('imported-pr-panel'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'PR #${pr.number} · @${pr.author} · ${pr.headRef} → ${pr.baseRef}',
            key: const ValueKey('imported-pr-title'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.text,
            ),
          ),
          Text(
            open == 0
                ? 'sem comentários abertos'
                : '$open ${open == 1 ? 'comentário aberto' : 'comentários abertos'}',
            key: const ValueKey('imported-pr-open'),
            style: muted,
          ),
          Text(
            reviewer,
            key: const ValueKey('imported-pr-reviewer'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
          if (!widget.merged)
            SmallButton(
              key: const ValueKey('imported-pr-run-reviewer'),
              label: 'Rodar revisor',
              onTap: _reviewing ? null : () => unawaited(_runReviewer(pr)),
            ),
        ],
      ),
    );
  }
}
