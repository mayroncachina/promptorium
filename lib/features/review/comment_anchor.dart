import '../../core/git/diff_parser.dart';
import '../../data/db/app_database.dart';

/// Git work is done once by ReviewService; rendering only consults this map.
typedef AnchorShifts = Map<int, ({int? line, String? reason})>;

class AnchoredComment {
  const AnchoredComment(this.row, {this.line, this.outdatedReason});
  final ReviewCommentRow row;
  final int? line;
  final String? outdatedReason;
}

/// Maps an old line across zero-context hunks. An insertion at line N is
/// after N; a replacement/deletion invalidates the lines it touches.
int? shiftedLine(int line, List<DiffHunk> hunks) {
  var delta = 0;
  for (final h in hunks) {
    if (h.oldLen == 0) {
      if (line > h.oldStart) delta += h.newLen;
    } else if (line >= h.oldStart && line < h.oldStart + h.oldLen) {
      return null;
    } else if (line >= h.oldStart + h.oldLen) {
      delta += h.newLen - h.oldLen;
    }
  }
  return line + delta;
}

AnchoredComment anchorOf(
  ReviewCommentRow comment,
  DiffFile? file,
  AnchorShifts shifts,
) {
  final shift = shifts[comment.id];
  final line = shift == null ? comment.line : shift.line;
  String? reason = shift?.reason;
  if (comment.path == null) return AnchoredComment(comment);
  if (file == null || file.newPath == null) {
    reason ??= 'arquivo ausente do diff atual';
  } else if (reason == null && (line == null || line == 0)) {
    return AnchoredComment(comment, line: 0);
  } else if (reason == null &&
      file.hunks.any((h) => h.lines.any((l) => l.newNo == line))) {
    return AnchoredComment(comment, line: line);
  }
  return AnchoredComment(
    comment,
    outdatedReason: reason ?? 'linha fora do trecho alterado',
  );
}
