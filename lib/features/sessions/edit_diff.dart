import '../../core/text/line_diff.dart';
import 'timeline.dart';

export '../../core/text/line_diff.dart' show DiffOp, DiffRow;

/// What an `Edit` / `MultiEdit` / `Write` changes (SPEC-026 R1–R3).
class EditDiff {
  const EditDiff({
    required this.rows,
    this.section,
    this.unknownBefore = false,
  });

  final List<DiffRow> rows;

  /// Title of the nearest `## ` heading above the change (without `## `).
  final String? section;

  /// A `Write` whose previous content is not known: every line is shown as
  /// added, with the note "Conteúdo anterior desconhecido" (R3).
  final bool unknownBefore;

  int get added => rows.where((r) => r.op == DiffOp.add).length;
  int get removed => rows.where((r) => r.op == DiffOp.del).length;
}

/// File edit tools whose input carries the change.
bool isEditTool(String name) =>
    name == 'Edit' || name == 'MultiEdit' || name == 'Write';

/// `file_path` of an edit input (null when missing).
String? editFilePath(Map<String, dynamic> input) {
  final p = input['file_path'];
  return p is String && p.isNotEmpty ? p : null;
}

String _chomp(String s) => s.endsWith('\n') ? s.substring(0, s.length - 1) : s;

String? _str(Object? v) => v is String ? v : null;

List<Map<String, dynamic>> _edits(Map<String, dynamic> input) {
  final e = input['edits'];
  return [
    if (e is List)
      for (final x in e)
        if (x is Map) x.cast<String, dynamic>(),
  ];
}

/// Title of the `## ` heading at or above [index] (0-based) in [lines].
String? _headingAbove(List<String> lines, int index) {
  for (var i = index.clamp(0, lines.length - 1); i >= 0; i--) {
    final l = lines[i];
    if (l.startsWith('## ')) return l.substring(3).trim();
  }
  return null;
}

/// Section of the first changed row: a heading added or removed there, or
/// the nearest heading above it.
String? _sectionOf(List<DiffRow> rows, String? seed) {
  var current = seed;
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    if (r.op != DiffOp.same) {
      // Blank lines added before a new heading belong to it.
      var j = i;
      while (j < rows.length &&
          rows[j].op != DiffOp.same &&
          rows[j].text.trim().isEmpty) {
        j++;
      }
      final first = j < rows.length && rows[j].op != DiffOp.same ? rows[j] : r;
      return first.text.startsWith('## ')
          ? first.text.substring(3).trim()
          : current;
    }
    if (r.text.startsWith('## ')) current = r.text.substring(3).trim();
  }
  return current;
}

/// Diff of one `old → new` replacement inside [before] (full lines, with
/// [context] unchanged lines around and positions in the file).
List<DiffRow>? _replaceRows(
  String before,
  String old,
  String neu,
  int context,
) {
  if (old.isEmpty) return null;
  final idx = before.indexOf(old);
  if (idx < 0) return null;
  final lineStart = idx == 0 ? 0 : before.lastIndexOf('\n', idx - 1) + 1;
  final end = idx + old.length;
  var lineEnd = before.indexOf('\n', end);
  if (lineEnd < 0) lineEnd = before.length;
  final oldFull = before.substring(lineStart, lineEnd);
  final newFull =
      before.substring(lineStart, idx) + neu + before.substring(end, lineEnd);
  final all = before.split('\n');
  final s = '\n'.allMatches(before.substring(0, lineStart)).length;
  final k = oldFull.split('\n').length;
  final rows = <DiffRow>[];
  for (var i = (s - context).clamp(0, s); i < s; i++) {
    rows.add((op: DiffOp.same, text: all[i], line: i + 1));
  }
  var oldNo = s + 1, newNo = s + 1;
  for (final d in lineDiff(oldFull, newFull)) {
    switch (d.op) {
      case DiffOp.same:
        rows.add((op: DiffOp.same, text: d.text, line: newNo));
        oldNo++;
        newNo++;
      case DiffOp.del:
        rows.add((op: DiffOp.del, text: d.text, line: oldNo++));
      case DiffOp.add:
        rows.add((op: DiffOp.add, text: d.text, line: newNo++));
    }
  }
  final after = s + k;
  final stop = (after + context).clamp(0, all.length);
  for (var i = after; i < stop; i++) {
    // A trailing newline leaves an empty last element: not a line.
    if (i == all.length - 1 && all[i].isEmpty) break;
    rows.add((op: DiffOp.same, text: all[i], line: newNo++));
  }
  return rows;
}

List<DiffRow> _plain(String a, String b) => [
  for (final d in lineDiff(_chomp(a), _chomp(b)))
    (op: d.op, text: d.text, line: null),
];

/// Diff of an edit tool call. [before] is the file text before the edit,
/// when known (R3): it gives the section and the line numbers.
EditDiff? editDiffOf(
  String name,
  Map<String, dynamic> input, {
  String? before,
  int context = 3,
}) {
  switch (name) {
    case 'Edit':
      final old = _str(input['old_string']) ?? '';
      final neu = _str(input['new_string']) ?? '';
      final rows = before == null
          ? null
          : _replaceRows(before, old, neu, context);
      if (rows == null) return EditDiff(rows: _plain(old, neu));
      final first = rows.isEmpty || rows.first.line == null
          ? 0
          : rows.first.line! - 1;
      return EditDiff(
        rows: rows,
        section: _sectionOf(
          rows,
          _headingAbove(before!.split('\n'), first - 1),
        ),
      );
    case 'MultiEdit':
      final rows = <DiffRow>[];
      String? section;
      var text = before;
      for (final e in _edits(input)) {
        final old = _str(e['old_string']) ?? '';
        final neu = _str(e['new_string']) ?? '';
        final r = text == null ? null : _replaceRows(text, old, neu, context);
        if (r == null) {
          rows.addAll(_plain(old, neu));
          text = null;
          continue;
        }
        if (section == null) {
          final first = r.isEmpty || r.first.line == null
              ? 0
              : r.first.line! - 1;
          section = _sectionOf(r, _headingAbove(text!.split('\n'), first - 1));
        }
        rows.addAll(r);
        text = _replace(text!, old, neu, e['replace_all'] == true);
      }
      return EditDiff(rows: rows, section: section);
    case 'Write':
      final content = _chomp(_str(input['content']) ?? '');
      if (before == null) {
        final lines = content.split('\n');
        return EditDiff(
          rows: [
            for (var i = 0; i < lines.length; i++)
              (op: DiffOp.add, text: lines[i], line: i + 1),
          ],
          unknownBefore: true,
        );
      }
      final rows = <DiffRow>[];
      var oldNo = 1, newNo = 1;
      for (final d in lineDiff(_chomp(before), content)) {
        switch (d.op) {
          case DiffOp.same:
            rows.add((op: DiffOp.same, text: d.text, line: newNo));
            oldNo++;
            newNo++;
          case DiffOp.del:
            rows.add((op: DiffOp.del, text: d.text, line: oldNo++));
          case DiffOp.add:
            rows.add((op: DiffOp.add, text: d.text, line: newNo++));
        }
      }
      return EditDiff(rows: rows, section: _sectionOf(rows, null));
  }
  return null;
}

String? _replace(String text, String old, String neu, bool all) {
  if (old.isEmpty || !text.contains(old)) return null;
  return all ? text.replaceAll(old, neu) : text.replaceFirst(old, neu);
}

/// File text after the edit, or null when it cannot be known.
String? applyEditTo(String name, Map<String, dynamic> input, String? before) {
  switch (name) {
    case 'Write':
      return _str(input['content']);
    case 'Edit':
      if (before == null) return null;
      return _replace(
        before,
        _str(input['old_string']) ?? '',
        _str(input['new_string']) ?? '',
        input['replace_all'] == true,
      );
    case 'MultiEdit':
      String? text = before;
      for (final e in _edits(input)) {
        if (text == null) return null;
        text = _replace(
          text,
          _str(e['old_string']) ?? '',
          _str(e['new_string']) ?? '',
          e['replace_all'] == true,
        );
      }
      return text;
  }
  return null;
}

/// Edit applied to the file: finished without error and not denied (R4).
bool editApplied(ToolItem t) => t.done && !t.isError && !t.denied;

/// Every edit tool of [items] (subagents included), in order.
Iterable<ToolItem> editToolsOf(List<TimelineItem> items) sync* {
  for (final i in items) {
    if (i is! ToolItem) continue;
    if (isEditTool(i.name)) yield i;
    yield* editToolsOf(i.children);
  }
}

/// Absolute path of [path] under [root] (paths given relative to it).
String absolutePath(String path, String? root) {
  if (path.startsWith('/') || root == null || root.isEmpty) return path;
  return '$root/$path';
}

/// Diffs of every edit of a conversation, keyed by `tool_use_id`. Each file
/// text is followed from [known] (absolute path → text) through the applied
/// edits in order, so later edits get positions and sections; a `Write`
/// makes its file known (R3).
Map<String, EditDiff> editDiffsOf(
  List<TimelineItem> items, {
  Map<String, String> known = const {},
  String? root,
}) {
  final texts = Map.of(known);
  final out = <String, EditDiff>{};
  for (final t in editToolsOf(items)) {
    final path = editFilePath(t.input);
    final key = path == null ? null : absolutePath(path, root);
    final before = key == null ? null : texts[key];
    final d = editDiffOf(t.name, t.input, before: before);
    if (d != null) out[t.id] = d;
    if (key != null && editApplied(t)) {
      final after = applyEditTo(t.name, t.input, before);
      if (after == null) {
        texts.remove(key);
      } else {
        texts[key] = after;
      }
    }
  }
  return out;
}

/// Text of the file at [path] after the applied edits of [items], starting
/// from [base]; null when an edit could not be followed.
String? textAfterEdits(
  List<TimelineItem> items,
  String path, {
  required String? base,
  String? root,
}) {
  var text = base;
  for (final t in editToolsOf(items)) {
    final p = editFilePath(t.input);
    if (p == null || absolutePath(p, root) != path || !editApplied(t)) {
      continue;
    }
    text = applyEditTo(t.name, t.input, text);
  }
  return text;
}

/// What an edit card shows (SPEC-026 R2, R11): its diff, the target text
/// ("SPEC-024 · Requisitos") and whether it edits a file other than the
/// spec being refined.
class EditInfo {
  const EditInfo({this.diff, this.target, this.outside = false});

  final EditDiff? diff;

  /// Replaces the path in the header; null = the path.
  final String? target;

  /// "fora da spec": shown with the full path, in amber (R11).
  final bool outside;
}
