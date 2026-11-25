import '../../core/git/diff_parser.dart';
import 'auto_reviewer.dart' show ReviewerComment;

/// Severities the Review knows (SPEC-102 R8).
const reviewerSeverities = {'alta', 'media', 'baixa'};

/// Normalizes the reviewer's comments before they are saved (SPEC-102 R8),
/// the same for every provider:
///
/// - the path becomes relative to the worktree root, without `./`, `a/`,
///   `b/` or the absolute path;
/// - a file outside the diff becomes a general comment, with the path in
///   the text;
/// - a line outside the hunks of the file becomes a comment on the file
///   (line 0);
/// - a severity other than `alta`, `media` and `baixa` becomes `media`;
/// - a requirement the spec does not have is dropped (null);
/// - duplicates of the round (same file, line and text) enter once.
///
/// [diff] is the whole diff of the branch (not the cut one the prompt
/// carries); [requirements] the ids of the spec (`R1`…), null when there is
/// no spec (a PR without spec has no requirement to point to).
List<ReviewerComment> normalizeReviewerComments(
  List<ReviewerComment> comments, {
  required String diff,
  required String worktree,
  Set<String>? requirements,
}) {
  final files = {
    for (final f in DiffParser.parse(diff))
      if (f.path.isNotEmpty) f.path: f,
  };
  final seen = <(String?, int?, String)>{};
  final out = <ReviewerComment>[];
  for (final c in comments) {
    var path = c.path == null ? null : relativeReviewPath(c.path!, worktree);
    if (path != null && !files.containsKey(path)) {
      path =
          _withoutSidePrefix(path, files.keys) ??
          _bySuffix(c.path!, files.keys) ??
          path;
    }
    var line = c.line;
    var text = c.text;
    if (path != null && path.isEmpty) path = null;
    if (path != null) {
      final file = files[path];
      if (file == null) {
        // Outside the diff: a general comment that still says where (an
        // absolute path of somewhere else stays as written).
        final raw = c.path!.trim();
        final shown = raw.startsWith('/') && !raw.startsWith(worktree)
            ? raw
            : path;
        text = '$shown${line == null || line <= 0 ? '' : ':$line'} — $text';
        path = null;
        line = null;
      } else if (line != null && line != 0 && !_inHunks(file, line)) {
        line = 0;
      }
    } else {
      line = null;
    }
    final sev = c.severity?.trim().toLowerCase();
    final req = c.requirement?.trim().toUpperCase();
    final key = (path, line == null || line == 0 ? 0 : line, text.trim());
    if (!seen.add(key)) continue;
    out.add(
      ReviewerComment(
        text: text,
        path: path,
        line: path == null ? null : line,
        severity: reviewerSeverities.contains(sev) ? sev : 'media',
        requirement:
            req != null && requirements != null && requirements.contains(req)
            ? req
            : null,
      ),
    );
  }
  return out;
}

/// [path] relative to [worktree]: no absolute prefix, no `./`.
String relativeReviewPath(String path, String worktree) {
  var p = path.trim().replaceAll('\\', '/');
  final root = worktree.endsWith('/') ? worktree : '$worktree/';
  if (p.startsWith(root)) p = p.substring(root.length);
  while (p.startsWith('./')) {
    p = p.substring(2);
  }
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  return p;
}

/// `a/lib/x.dart` / `b/lib/x.dart` (the diff's sides) → `lib/x.dart`, only
/// when that is a file of the diff (a real folder `a/` stays).
String? _withoutSidePrefix(String path, Iterable<String> files) {
  for (final prefix in const ['a/', 'b/']) {
    if (!path.startsWith(prefix)) continue;
    final rest = path.substring(prefix.length);
    if (files.contains(rest)) return rest;
  }
  return null;
}

/// An absolute path of another checkout of the repository that ends with
/// a file of the diff (`/home/x/repo/lib/a.dart` → `lib/a.dart`).
String? _bySuffix(String path, Iterable<String> files) {
  final p = path.trim().replaceAll('\\', '/');
  if (!p.startsWith('/')) return null;
  String? best;
  for (final f in files) {
    if (p.endsWith('/$f') && (best == null || f.length > best.length)) {
      best = f;
    }
  }
  return best;
}

bool _inHunks(DiffFile file, int line) =>
    file.hunks.any((h) => h.lines.any((l) => l.newNo == line));
