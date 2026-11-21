import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/text/line_diff.dart';
import 'package:promptorium/core/text/unified_diff.dart';

/// SPEC-095: the hunks of a Codex `fileChange` (P4: the "antes" is the diff
/// applied in reverse).
void main() {
  const diff = '@@ -1 +1 @@\n-base\n+linha dois\n';

  test('applies the real update of edicao-turno', () {
    expect(applyUnifiedDiff('base\n', diff), 'linha dois\n');
  });

  test('reverses it: the text before the change', () {
    expect(reverseUnifiedDiff('linha dois\n', diff), 'base\n');
  });

  test('a hunk that does not match gives null', () {
    expect(applyUnifiedDiff('outra coisa\n', diff), isNull);
    expect(reverseUnifiedDiff('outra coisa\n', diff), isNull);
  });

  test('a new file applies over nothing', () {
    expect(applyUnifiedDiff(null, '@@ -0,0 +1,2 @@\n+a\n+b\n'), 'a\nb\n');
  });

  test('hunks in the middle, with context and a shifted position', () {
    const text = 'x\n1\n2\n3\n4\n5\n';
    const d = '@@ -2,3 +2,3 @@ cls\n 2\n-3\n+três\n 4\n';
    // The hunk says line 2; the block is at line 3 (one line above).
    expect(applyUnifiedDiff(text, d), 'x\n1\n2\ntrês\n4\n5\n');
    expect(reverseUnifiedDiff('x\n1\n2\ntrês\n4\n5\n', d), text);
  });

  test('rows carry the hunk line numbers', () {
    final rows = unifiedDiffRows('@@ -12,2 +12,3 @@\n a\n-b\n+c\n+d\n');
    expect(rows.map((r) => (r.op, r.line)), [
      (DiffOp.same, 12),
      (DiffOp.del, 13),
      (DiffOp.add, 13),
      (DiffOp.add, 14),
    ]);
  });
}
