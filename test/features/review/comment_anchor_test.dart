import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/review/comment_anchor.dart';

void main() {
  final changed = DiffParser.parse('''diff --git a/a.dart b/a.dart
--- a/a.dart
+++ b/a.dart
@@ -2,0 +3,2 @@
+x
+y
@@ -10,2 +12,1 @@
-a
-b
+c
''').single;
  ReviewCommentRow row(int line, {String? path = 'a.dart'}) => ReviewCommentRow(
    id: 1,
    specId: 1,
    round: 2,
    author: 'revisor',
    body: 'corrigir',
    line: line,
    path: path,
    resolved: false,
    createdAt: DateTime(2026),
  );
  test(
    'insertions shift following lines; replacements invalidate touched lines',
    () {
      expect(shiftedLine(2, changed.hunks), 2);
      expect(shiftedLine(3, changed.hunks), 5);
      expect(shiftedLine(10, changed.hunks), isNull);
      expect(shiftedLine(11, changed.hunks), isNull);
      expect(shiftedLine(12, changed.hunks), 13);
    },
  );
  test('anchors only to new lines in visible hunks', () {
    expect(anchorOf(row(12), changed, {}).line, 12);
    expect(
      anchorOf(row(8), changed, {}).outdatedReason,
      'linha fora do trecho alterado',
    );
    expect(anchorOf(row(0), changed, {}).line, 0);
    expect(anchorOf(row(12), null, {}).outdatedReason, isNotNull);
    expect(anchorOf(row(12, path: null), null, {}).outdatedReason, isNull);
  });
  test('a known invalid anchor never falls back to its old line', () {
    expect(
      anchorOf(row(12), changed, {
        1: (line: null, reason: 'linha alterada'),
      }).outdatedReason,
      'linha alterada',
    );
  });
}
