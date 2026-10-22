import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/diff_parser.dart';
import '../review_service.dart';
import 'review_diff_view.dart';
import '../comment_anchor.dart';
import 'persisted_comment.dart';

/// File the Review's file list asked to show (the page with every file
/// scrolls to it).
class ReviewScrollTarget extends Notifier<String?> {
  @override
  String? build() => null;

  void go(String? path) => state = path;
}

final reviewScrollTargetProvider =
    NotifierProvider<ReviewScrollTarget, String?>(ReviewScrollTarget.new);

/// Every changed file in one page ("Todos os arquivos"), one card per file;
/// a tap in the file list scrolls here ([reviewScrollTargetProvider]).
class ReviewAllFiles extends ConsumerStatefulWidget {
  const ReviewAllFiles({
    super.key,
    required this.files,
    required this.draft,
    this.persisted = const [],
    this.selected = const {},
    this.onSelectComment,
    this.sideBySide = false,
    this.readOnly = false,
    this.target,
    this.targetPath,
    this.busy = false,
    this.onOpenComment,
    this.onCancelComment,
    this.onSubmitComment,
    this.onRemoveComment,
    this.onRejectHunk,
    this.onToggleAccept,
  });

  final List<AnchoredComment> persisted;
  final Set<int> selected;
  final void Function(int, bool)? onSelectComment;
  final List<DiffFile> files;
  final ReviewDraft draft;
  final bool sideBySide;

  /// Commits of a step: no comments, reject or accept.
  final bool readOnly;
  final CommentTarget? target;
  final String? targetPath;
  final bool busy;
  final void Function(DiffFile, CommentTarget)? onOpenComment;
  final VoidCallback? onCancelComment;
  final void Function(DiffFile, CommentTarget, String)? onSubmitComment;
  final void Function(ReviewComment)? onRemoveComment;
  final void Function(DiffFile, DiffHunk)? onRejectHunk;
  final void Function(DiffFile, DiffHunk)? onToggleAccept;

  @override
  ConsumerState<ReviewAllFiles> createState() => _ReviewAllFilesState();
}

class _ReviewAllFilesState extends ConsumerState<ReviewAllFiles> {
  final _keys = <int, GlobalKey>{};
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyOf(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  void _scrollTo(String? path) {
    if (path == null) return;
    final i = widget.files.indexWhere((f) => f.path == path);
    if (i < 0) return;
    final ctx = _keyOf(i).currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 200),
      alignment: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(reviewScrollTargetProvider, (_, path) => _scrollTo(path));
    final w = widget;
    if (w.files.isEmpty && w.persisted.isEmpty) {
      return const Center(child: Text('Nenhuma alteração.'));
    }
    return SingleChildScrollView(
      key: const ValueKey('review-all-files'),
      controller: _scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (w.persisted.any(
            (c) =>
                c.row.path == null || !w.files.any((f) => f.path == c.row.path),
          ))
            const Text('Geral'),
          for (final c in w.persisted.where(
            (c) =>
                c.row.path == null || !w.files.any((f) => f.path == c.row.path),
          ))
            PersistedComment(
              comment: c,
              selected: w.selected.contains(c.row.id),
              onSelected: w.onSelectComment == null
                  ? null
                  : (v) => w.onSelectComment!(c.row.id, v),
            ),
          for (final (i, f) in w.files.indexed)
            Padding(
              key: _keyOf(i),
              padding: const EdgeInsets.only(bottom: 14),
              child: ReviewFileDiff(
                embedded: true,
                persisted: w.persisted
                    .where((c) => c.row.path == f.path)
                    .toList(),
                selected: w.selected,
                onSelectComment: w.onSelectComment,
                readOnly: w.readOnly,
                sideBySide: w.sideBySide,
                file: f,
                comments: [
                  for (final c in w.draft.comments)
                    if (c.path == f.path) c,
                ],
                accepted: w.draft.accepted,
                commentTarget: w.targetPath == f.path ? w.target : null,
                busy: w.busy,
                onOpenComment: (t) {
                  if (!w.readOnly) w.onOpenComment?.call(f, t);
                },
                onCancelComment: () => w.onCancelComment?.call(),
                onSubmitComment: (t, text) =>
                    w.onSubmitComment?.call(f, t, text),
                onRemoveComment: (c) => w.onRemoveComment?.call(c),
                onRejectHunk: (h) => w.onRejectHunk?.call(f, h),
                onToggleAccept: (h) => w.onToggleAccept?.call(f, h),
              ),
            ),
        ],
      ),
    );
  }
}
