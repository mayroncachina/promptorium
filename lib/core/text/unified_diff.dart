import 'line_diff.dart';

/// Unified diff hunks (`@@ -a,b +c,d @@`) as the Codex sends them in a
/// `fileChange` (SPEC-095): parse, apply and apply in reverse.

/// One hunk: where it starts in the old and new text and its lines, each
/// with its op (` ` same, `-` del, `+` add).
class Hunk {
  const Hunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<DiffLine> lines;

  Iterable<String> get oldLines sync* {
    for (final l in lines) {
      if (l.op != DiffOp.add) yield l.text;
    }
  }

  Iterable<String> get newLines sync* {
    for (final l in lines) {
      if (l.op != DiffOp.del) yield l.text;
    }
  }

  /// The same hunk read backwards (new → old).
  Hunk get reversed => Hunk(
    oldStart: newStart,
    oldCount: newCount,
    newStart: oldStart,
    newCount: oldCount,
    lines: [
      for (final l in lines)
        (
          op: switch (l.op) {
            DiffOp.add => DiffOp.del,
            DiffOp.del => DiffOp.add,
            DiffOp.same => DiffOp.same,
          },
          text: l.text,
        ),
    ],
  );
}

final _header = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

/// The hunks of [diff] (file headers `---` / `+++` are skipped). Lines
/// before the first hunk header are ignored.
List<Hunk> parseHunks(String diff) {
  final out = <Hunk>[];
  int? os, oc, ns, nc;
  var lines = <DiffLine>[];
  void flush() {
    if (os != null) {
      out.add(
        Hunk(
          oldStart: os,
          oldCount: oc!,
          newStart: ns!,
          newCount: nc!,
          lines: lines,
        ),
      );
    }
  }

  final all = diff.split('\n');
  if (all.isNotEmpty && all.last.isEmpty) all.removeLast();
  for (final l in all) {
    final m = _header.firstMatch(l);
    if (m != null) {
      flush();
      os = int.parse(m.group(1)!);
      oc = m.group(2) == null ? 1 : int.parse(m.group(2)!);
      ns = int.parse(m.group(3)!);
      nc = m.group(4) == null ? 1 : int.parse(m.group(4)!);
      lines = [];
      continue;
    }
    if (os == null) continue;
    if (l.startsWith('\\')) continue; // "\ No newline at end of file"
    if (l.startsWith('+')) {
      lines.add((op: DiffOp.add, text: l.substring(1)));
    } else if (l.startsWith('-')) {
      lines.add((op: DiffOp.del, text: l.substring(1)));
    } else {
      lines.add((op: DiffOp.same, text: l.isEmpty ? '' : l.substring(1)));
    }
  }
  flush();
  return out;
}

/// Rows of [diff] with the line numbers of the hunks (a removed line has
/// its old number, the others the new one).
List<DiffRow> unifiedDiffRows(String diff) {
  final rows = <DiffRow>[];
  for (final h in parseHunks(diff)) {
    var o = h.oldStart == 0 ? 1 : h.oldStart;
    var n = h.newStart == 0 ? 1 : h.newStart;
    for (final l in h.lines) {
      switch (l.op) {
        case DiffOp.same:
          rows.add((op: DiffOp.same, text: l.text, line: n));
          o++;
          n++;
        case DiffOp.del:
          rows.add((op: DiffOp.del, text: l.text, line: o++));
        case DiffOp.add:
          rows.add((op: DiffOp.add, text: l.text, line: n++));
      }
    }
  }
  return rows;
}

/// [text] with [diff] applied; null when a hunk does not match (the file
/// changed in another way). [text] null = an empty file.
String? applyUnifiedDiff(String? text, String diff) =>
    applyHunks(text, parseHunks(diff)).text;

/// [text] (the file after the change) with [diff] undone: the text before
/// it (SPEC-095 P4). Null when the diff does not apply in reverse.
String? reverseUnifiedDiff(String text, String diff) =>
    applyHunks(text, [for (final h in parseHunks(diff)) h.reversed]).text;

/// Outcome of [applyHunks]: the text, or the hunk that did not match and the
/// first line of the text (1-based) that was already different (SPEC-110
/// R2; null = the hunk starts past the end of the text).
class HunksApplied {
  const HunksApplied.ok(String this.text) : failed = null, line = null;

  const HunksApplied.failed(this.failed, this.line) : text = null;

  final String? text;
  final Hunk? failed;
  final int? line;
}

/// [text] with [hunks] applied in order. [text] null = an empty file.
HunksApplied applyHunks(String? text, List<Hunk> hunks) {
  if (hunks.isEmpty) return const HunksApplied.failed(null, null);
  final src = text ?? '';
  final trailing = src.isEmpty || src.endsWith('\n');
  final lines = src.isEmpty
      ? <String>[]
      : (trailing ? src.substring(0, src.length - 1) : src).split('\n');
  final out = <String>[];
  var pos = 0; // next line of [lines] not copied yet
  for (final h in hunks) {
    final old = h.oldLines.toList();
    final at = _find(
      lines,
      old,
      h.oldCount == 0 ? h.oldStart : h.oldStart - 1,
      pos,
    );
    if (at == null) {
      return HunksApplied.failed(h, _firstDifferent(lines, old, h.oldStart));
    }
    out.addAll(lines.sublist(pos, at));
    out.addAll(h.newLines);
    pos = at + old.length;
  }
  out.addAll(lines.sublist(pos));
  if (out.isEmpty) return const HunksApplied.ok('');
  return HunksApplied.ok('${out.join('\n')}${trailing ? '\n' : ''}');
}

/// 1-based line where [lines] stops matching [block] placed at [start].
int? _firstDifferent(List<String> lines, List<String> block, int start) {
  final from = start < 1 ? 0 : start - 1;
  for (var k = 0; k < block.length; k++) {
    final i = from + k;
    if (i >= lines.length) return null;
    if (lines[i] != block[k]) return i + 1;
  }
  return start < 1 ? 1 : start;
}

/// Where [block] starts in [lines] at or after [from]: [hint] first, then
/// the nearest match.
int? _find(List<String> lines, List<String> block, int hint, int from) {
  bool at(int i) {
    if (i < from || i + block.length > lines.length) return false;
    for (var k = 0; k < block.length; k++) {
      if (lines[i + k] != block[k]) return false;
    }
    return true;
  }

  final start = hint.clamp(from, lines.length);
  if (at(start)) return start;
  for (var d = 1; d <= lines.length; d++) {
    if (at(start + d)) return start + d;
    if (at(start - d)) return start - d;
  }
  return null;
}
