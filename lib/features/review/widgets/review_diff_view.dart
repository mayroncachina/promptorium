import 'package:flutter/material.dart';

import '../../../core/git/diff_parser.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';
import '../review_logic.dart';

const _mono = TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: 12,
  height: 1.7,
  color: AppColors.text,
);

/// Line opened for a new comment: (hunk index, line index).
typedef CommentTarget = (int, int);

/// Diff card of one file (mockup Review): header, hunks with
/// "Rejeitar hunk" / "Aceitar hunk", numbered lines; clicking a line number
/// opens the comment box under it.
class ReviewFileDiff extends StatelessWidget {
  const ReviewFileDiff({
    super.key,
    required this.file,
    required this.comments,
    required this.accepted,
    required this.commentTarget,
    required this.onOpenComment,
    required this.onCancelComment,
    required this.onSubmitComment,
    required this.onRemoveComment,
    required this.onRejectHunk,
    required this.onToggleAccept,
    this.busy = false,
  });

  final DiffFile file;

  /// Pending comments of this file.
  final List<ReviewComment> comments;
  final Set<String> accepted;
  final CommentTarget? commentTarget;
  final void Function(CommentTarget) onOpenComment;
  final VoidCallback onCancelComment;
  final void Function(CommentTarget, String) onSubmitComment;
  final void Function(ReviewComment) onRemoveComment;
  final void Function(DiffHunk) onRejectHunk;
  final void Function(DiffHunk) onToggleAccept;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget Function()>[];
    rows.add(() => _FileHeader(file: file));
    if (file.isBinary) {
      rows.add(() => const _Note('Arquivo binário — sem diff de texto.'));
    } else if (file.hunks.isEmpty) {
      rows.add(
        () => _Note(
          file.status == DiffFileStatus.renamed
              ? 'Renomeado sem alteração de conteúdo.'
              : 'Sem alterações de conteúdo (modo/permissões).',
        ),
      );
    }
    for (var hi = 0; hi < file.hunks.length; hi++) {
      final h = file.hunks[hi];
      final key = hunkKey(file, h);
      rows.add(
        () => _HunkHeader(
          key: ValueKey('review-hunk-$hi'),
          hunk: h,
          accepted: accepted.contains(key),
          busy: busy,
          onReject: () => onRejectHunk(h),
          onAccept: () => onToggleAccept(h),
          index: hi,
        ),
      );
      for (var li = 0; li < h.lines.length; li++) {
        final line = h.lines[li];
        final target = (hi, li);
        rows.add(
          () => _LineRow(
            line: line,
            accepted: accepted.contains(key),
            onNumberTap: () => onOpenComment(target),
          ),
        );
        for (final c in comments) {
          if (c.anchor == '$key#$li') {
            rows.add(
              () => _PendingComment(
                comment: c,
                onRemove: () => onRemoveComment(c),
              ),
            );
          }
        }
        if (commentTarget == target) {
          rows.add(
            () => _CommentBox(
              key: ValueKey('review-comment-box-$hi-$li'),
              onCancel: onCancelComment,
              onSubmit: (t) => onSubmitComment(target, t),
            ),
          );
        }
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ListView.builder(
          key: ValueKey('review-diff-${file.path}'),
          padding: EdgeInsets.zero,
          itemCount: rows.length,
          itemBuilder: (_, i) => rows[i](),
        ),
      ),
    );
  }
}

class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.file});

  final DiffFile file;

  @override
  Widget build(BuildContext context) {
    final (add, del) = fileStats(file);
    final renamed = file.status == DiffFileStatus.renamed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            fileStatusLetter(file.status),
            style: _mono.copyWith(color: statusColor(file.status)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              renamed ? '${file.oldPath} → ${file.newPath}' : file.path,
              key: const ValueKey('review-file-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono,
            ),
          ),
          Text('+$add', style: _mono.copyWith(color: AppColors.teal)),
          const SizedBox(width: 8),
          Text('−$del', style: _mono.copyWith(color: AppColors.red)),
        ],
      ),
    );
  }
}

/// Color of the A/M/D/R letter.
Color statusColor(DiffFileStatus s) => switch (s) {
  DiffFileStatus.added => AppColors.teal,
  DiffFileStatus.modified => AppColors.amber,
  DiffFileStatus.deleted => AppColors.red,
  DiffFileStatus.renamed => AppColors.blue,
};

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    ),
  );
}

class _HunkHeader extends StatelessWidget {
  const _HunkHeader({
    super.key,
    required this.hunk,
    required this.accepted,
    required this.busy,
    required this.onReject,
    required this.onAccept,
    required this.index,
  });

  final DiffHunk hunk;
  final bool accepted;
  final bool busy;
  final VoidCallback onReject;
  final VoidCallback onAccept;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hunk.header,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono.copyWith(color: AppColors.blue, height: 1.3),
            ),
          ),
          const SizedBox(width: 8),
          _HunkButton(
            key: ValueKey('review-reject-$index'),
            label: 'Rejeitar hunk',
            onTap: busy ? null : onReject,
          ),
          const SizedBox(width: 6),
          _HunkButton(
            key: ValueKey('review-accept-$index'),
            label: accepted ? '✓ Revisado' : 'Aceitar hunk',
            accent: true,
            onTap: onAccept,
          ),
        ],
      ),
    );
  }
}

class _HunkButton extends StatelessWidget {
  const _HunkButton({
    super.key,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(4);
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: accent ? ReviewColors.acceptBg : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: accent ? ReviewColors.acceptBorder : AppColors.border,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                color: accent ? AppColors.teal : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.accepted,
    required this.onNumberTap,
  });

  final DiffLine line;
  final bool accepted;
  final VoidCallback onNumberTap;

  @override
  Widget build(BuildContext context) {
    final (bg, sign, signColor) = switch (line.kind) {
      DiffLineKind.add => (SessionColors.addBg, '+', AppColors.teal),
      DiffLineKind.del => (SessionColors.delBg, '-', AppColors.red),
      DiffLineKind.context => (Colors.transparent, '', AppColors.textSecondary),
    };
    final no = line.kind == DiffLineKind.del ? line.oldNo : line.newNo;
    final keyNo = line.kind == DiffLineKind.del ? 'o$no' : '$no';
    return Container(
      color: accepted && line.kind != DiffLineKind.context
          ? bg.withValues(alpha: 0.55)
          : bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: ValueKey('review-line-$keyNo'),
              onTap: onNumberTap,
              child: Tooltip(
                message: 'Comentar esta linha',
                waitDuration: const Duration(milliseconds: 600),
                child: Container(
                  width: 48,
                  padding: const EdgeInsets.only(right: 8),
                  alignment: Alignment.centerRight,
                  child: Text(
                    no == null ? '' : '$no',
                    style: _mono.copyWith(color: ReviewColors.lineNumber),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 16,
            child: Text(sign, style: _mono.copyWith(color: signColor)),
          ),
          Expanded(
            child: Text(
              line.text.isEmpty ? ' ' : line.text,
              softWrap: false,
              overflow: TextOverflow.clip,
              maxLines: 1,
              style: _mono,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingComment extends StatelessWidget {
  const _PendingComment({required this.comment, required this.onRemove});

  final ReviewComment comment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(64, 4, 12, 6),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: SessionColors.approvalBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Comentário pendente · ${comment.location}',
                style: const TextStyle(fontSize: 11, color: AppColors.amber),
              ),
              const SizedBox(height: 4),
              Text(
                comment.text,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: onRemove,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: AppIcon(
              AppIcons.close,
              size: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CommentBox extends StatefulWidget {
  const _CommentBox({
    super.key,
    required this.onCancel,
    required this.onSubmit,
  });

  final VoidCallback onCancel;
  final void Function(String) onSubmit;

  @override
  State<_CommentBox> createState() => _CommentBoxState();
}

class _CommentBoxState extends State<_CommentBox> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (_text.text.trim().isEmpty) return;
    widget.onSubmit(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(64, 6, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SessionColors.selectedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Seu comentário · será enviado ao agente',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('review-comment-field'),
            controller: _text,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.all(8),
              hintText: 'O que o agente deve ajustar aqui?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _BoxButton(
                key: const ValueKey('review-comment-cancel'),
                label: 'Cancelar',
                onTap: widget.onCancel,
              ),
              const SizedBox(width: 6),
              _BoxButton(
                key: const ValueKey('review-comment-submit'),
                label: 'Comentar',
                primary: true,
                onTap: _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoxButton extends StatelessWidget {
  const _BoxButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    return Material(
      color: primary ? AppColors.amber : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: primary
            ? BorderSide.none
            : const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
              color: primary ? AppColors.onAmber : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
