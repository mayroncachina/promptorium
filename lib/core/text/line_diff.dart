/// Line diff (LCS) shared by the spec previews and the edit diffs.
library;

enum DiffOp { same, add, del }

typedef DiffLine = ({DiffOp op, String text});

/// One line of a rendered diff. [line] is the position in the file (the old
/// position for removed lines, the new one otherwise); null when unknown.
typedef DiffRow = ({DiffOp op, String text, int? line});

/// Line diff of [a] → [b] (LCS). Very large inputs fall back to removing
/// every line of [a] and adding every line of [b].
List<DiffLine> lineDiff(String a, String b) {
  final x = a.split('\n'), y = b.split('\n');
  if (x.length * y.length > 4000000) {
    return [
      for (final l in x) (op: DiffOp.del, text: l),
      for (final l in y) (op: DiffOp.add, text: l),
    ];
  }
  final n = x.length, m = y.length;
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = x[i] == y[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (x[i] == y[j]) {
      out.add((op: DiffOp.same, text: x[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add((op: DiffOp.del, text: x[i++]));
    } else {
      out.add((op: DiffOp.add, text: y[j++]));
    }
  }
  while (i < n) {
    out.add((op: DiffOp.del, text: x[i++]));
  }
  while (j < m) {
    out.add((op: DiffOp.add, text: y[j++]));
  }
  return out;
}

/// Word diff of [a] → [b]: [lineDiff] with one token per line. Words, spaces
/// and punctuation are tokens of their own, so a comma after a word does not
/// mark the word, and joining the [DiffLine.text]s gives the text back with
/// each run of spaces as one space.
List<DiffLine> wordDiff(String a, String b) {
  final token = RegExp(r'\s+|[\p{L}\p{N}_]+|.', unicode: true, dotAll: true);
  String tokens(String text) => token
      .allMatches(text.trim())
      .map((m) => m[0]!.trim().isEmpty ? ' ' : m[0]!)
      .join('\n');
  return lineDiff(tokens(a), tokens(b));
}
