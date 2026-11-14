import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../auto_reviewer.dart';
import '../pr_import.dart';
import '../review_service.dart';
import 'review_dialogs.dart' show ReviewDialogFrame;
import '../comment_anchor.dart' show isOpenReviewComment;

/// Review comments of a PR brought into the app without a spec, by session
/// (SPEC-050 P1).
final sessionReviewCommentsProvider =
    StreamProvider.family<List<ReviewCommentRow>, String>(
      (ref, sessionId) =>
          ref.watch(reviewCommentsRepoProvider).watchBySession(sessionId),
    );

/// Commits the author published and local ones not published yet, of a PR
/// brought into the app (SPEC-050 R7).
final importedAheadProvider =
    FutureProvider.family<({int author, int local}), String>(
      (ref, sessionId) =>
          ref.read(reviewServiceProvider).remoteAhead(sessionId),
    );

/// "O autor publicou 2 commits" / its detail (SPEC-050 R7, P4).
String authorCommitsTitle(int n) =>
    'O autor publicou $n ${n == 1 ? 'commit' : 'commits'} na branch do PR';

String authorCommitsDetail(int local) => local == 0
    ? 'Atualizar traz os commits do autor. Nada publicado é reescrito.'
    : 'Você tem $local ${local == 1 ? 'commit' : 'commits'} do agente ainda '
          'não ${local == 1 ? 'publicado' : 'publicados'}. Atualizar busca a '
          'branch e refaz ${local == 1 ? 'esse commit' : 'esses commits'} por '
          'cima. Nada publicado é reescrito.';

/// "Atualizar…" asks first when local commits will be replayed on top of
/// the author's (SPEC-050 P4). True = go on.
Future<bool> confirmImportedUpdate(BuildContext context, int local) async {
  if (local == 0) return true;
  final ok = await showAppDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (context) => ReviewDialogFrame(
      key: const ValueKey('imported-update-dialog'),
      title: 'Atualizar a branch do PR',
      content: [
        Text(
          'Atualizar busca os commits do autor e refaz '
          '$local ${local == 1 ? 'commit local' : 'commits locais'} por '
          'cima com rebase. Nada publicado é reescrito. Se houver '
          'conflito, ele segue o fluxo de conflito do Review.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
      actions: [
        SmallButton(
          label: 'Cancelar',
          onTap: () => Navigator.of(context).pop(false),
        ),
        AmberButton(
          key: const ValueKey('imported-update-confirm'),
          label: 'Refazer $local por cima',
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return ok == true;
}

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
  String? _busy;

  ReviewService get _service => ref.read(reviewServiceProvider);

  void _toast(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showAppToast(SnackBar(content: Text(text), persist: false));

  Future<void> _job(String label, Future<void> Function() job) async {
    setState(() => _busy = label);
    try {
      await job();
    } on Object catch (e) {
      if (mounted) _toast('$label: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
      ref.invalidate(importedAheadProvider(widget.sessionId));
      ref.invalidate(reviewDetailProvider(widget.sessionId));
      ref.invalidate(mergeReadinessProvider(widget.sessionId));
    }
  }

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

  Future<void> _copyPatch() => _job('Copiar patch', () async {
    final patch = await _service.copyPatch(widget.sessionId);
    await Clipboard.setData(ClipboardData(text: patch));
    if (mounted) _toast('Patch copiado · mande para quem abriu o PR');
  });

  /// "Atualizar…" (R7, P4): asks first when local commits will be replayed.
  Future<void> _update(int local) async {
    if (!await confirmImportedUpdate(context, local) || !mounted) return;
    await _job('Atualizar', () async {
      final r = await _service.updateFromRemote(widget.sessionId);
      ref.invalidate(rebaseStatusProvider(widget.sessionId));
      if (mounted) {
        _toast(
          r.inProgress
              ? 'Conflito ao refazer os commits locais · resolva no Review'
              : 'Branch do PR atualizada',
        );
      }
    });
  }

  /// "Soltar o PR" (R9): confirms, and with commits not published offers
  /// "Copiar patch" first.
  Future<void> _release(int local) async {
    final ok = await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (context) => ReviewDialogFrame(
        key: const ValueKey('imported-release-dialog'),
        title: 'Soltar o PR',
        content: [
          Text(
            [
              'Remove o worktree e a branch local. A sessão fica no '
                  'histórico. A branch remota e o PR continuam como estão.',
              if (local > 0)
                '$local ${local == 1 ? 'commit não publicado será perdido' : 'commits não publicados serão perdidos'}: '
                    'copie o patch antes, se quiser mandá-los para quem abriu '
                    'o PR.',
            ].join('\n\n'),
            key: const ValueKey('imported-release-text'),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        actions: [
          SmallButton(
            label: 'Cancelar',
            onTap: () => Navigator.of(context).pop(false),
          ),
          if (local > 0)
            SmallButton(
              key: const ValueKey('imported-release-patch'),
              label: 'Copiar patch',
              onTap: () => unawaited(_copyPatch()),
            ),
          AmberButton(
            key: const ValueKey('imported-release-confirm'),
            label: 'Soltar o PR',
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _job('Soltar o PR', () async {
      await _service.releaseImported(widget.sessionId, force: true);
      if (mounted) _toast('PR solto · a sessão fica no histórico');
    });
  }

  Future<void> _setReply(ImportedPr pr, Workspace? ws, bool value) async {
    final settings = ref.read(appSettingsProvider.notifier);
    await settings.set(
      ImportedPr.key(widget.sessionId),
      pr.copyWith(replyInPr: value).encode(),
    );
    if (ws != null) await settings.set(replyInPrKey(ws.id), value ? '1' : '0');
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
    final ahead = widget.merged
        ? null
        : ref.watch(importedAheadProvider(widget.sessionId)).value;
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
    final local = ahead?.local ?? 0;
    final busy = _busy != null;
    return Container(
      key: const ValueKey('imported-pr-panel'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((ahead?.author ?? 0) > 0)
            Container(
              key: const ValueKey('imported-author-commits'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amberTint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SessionColors.approvalBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync, size: 18, color: AppColors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authorCommitsTitle(ahead!.author),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(authorCommitsDetail(local), style: muted),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AmberButton(
                    key: const ValueKey('imported-update'),
                    label: 'Atualizar…',
                    onTap: busy ? null : () => unawaited(_update(local)),
                  ),
                ],
              ),
            ),
          Wrap(
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
              if (pr.canPush)
                Container(
                  key: const ValueKey('imported-pr-push'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.teal),
                  ),
                  child: const Text(
                    'Push para a branch do PR',
                    style: TextStyle(fontSize: 11, color: AppColors.teal),
                  ),
                )
              else
                const Text(
                  'Sem permissão de escrita na branch do PR · os commits '
                  'ficam locais',
                  key: ValueKey('imported-pr-no-push'),
                  style: TextStyle(fontSize: 12, color: AppColors.amber),
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
            ],
          ),
          if (!widget.merged) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IntrinsicWidth(
                  child: SmallButton(
                    key: const ValueKey('imported-pr-run-reviewer'),
                    label: 'Rodar revisor',
                    onTap: _reviewing || busy
                        ? null
                        : () => unawaited(_runReviewer(pr)),
                  ),
                ),
                if (!pr.canPush || local > 0)
                  IntrinsicWidth(
                    child: SmallButton(
                      key: const ValueKey('imported-pr-patch'),
                      label: 'Copiar patch',
                      onTap: busy || local == 0
                          ? null
                          : () => unawaited(_copyPatch()),
                    ),
                  ),
                IntrinsicWidth(
                  child: SmallButton(
                    key: const ValueKey('imported-pr-release'),
                    label: 'Soltar o PR',
                    onTap: busy ? null : () => unawaited(_release(local)),
                  ),
                ),
                if (pr.canPush)
                  InkWell(
                    key: const ValueKey('imported-pr-reply'),
                    onTap: () => unawaited(
                      _setReply(
                        pr,
                        ref.read(activeWorkspaceProvider),
                        !pr.replyInPr,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          pr.replyInPr
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 16,
                          color: pr.replyInPr
                              ? AppColors.amber
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Responder no PR depois do push, com o SHA que '
                          'corrigiu',
                          style: TextStyle(fontSize: 12, color: AppColors.text),
                        ),
                      ],
                    ),
                  ),
                if (_busy != null)
                  Text(
                    '$_busy…',
                    style: muted.copyWith(color: AppColors.amber),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
