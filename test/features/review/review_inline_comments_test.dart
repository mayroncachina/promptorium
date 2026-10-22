import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/comment_anchor.dart';
import 'package:promptorium/features/review/widgets/review_diff_view.dart';
import 'package:promptorium/features/review/widgets/spec_review_panel.dart';

import '../../helpers/test_db.dart';

void main() {
  testWidgets(
    'reviewer card follows its new line; resolved/reopened state comes from the database',
    (tester) async {
      final db = memoryDatabase();
      await db.customStatement(
        "INSERT INTO workspaces(path,name) VALUES('/r','r')",
      );
      await db.customStatement(
        "INSERT INTO specs(workspace_id,code,title,path) VALUES(1,'SPEC-001','a','specs/a.md')",
      );
      await db
          .into(db.reviewComments)
          .insert(
            ReviewCommentsCompanion.insert(
              specId: 1,
              round: 2,
              author: 'revisor',
              body: 'corrigir erro',
              path: const Value('a.dart'),
              line: const Value(12),
              severity: const Value('alta'),
              requirement: const Value('R1'),
            ),
          );
      final file = DiffParser.parse('''diff --git a/a.dart b/a.dart
--- a/a.dart
+++ b/a.dart
@@ -12 +12 @@
-old
+new
''').single;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseOverride(db)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final rows =
                      ref.watch(reviewCommentsProvider(1)).value ??
                      <ReviewCommentRow>[];
                  return ReviewFileDiff(
                    file: file,
                    comments: const [],
                    accepted: const {},
                    persisted: [
                      for (final row in rows) anchorOf(row, file, {}),
                    ],
                    commentTarget: null,
                    onOpenComment: (_) {},
                    onCancelComment: () {},
                    onSubmitComment: (_, _) {},
                    onRemoveComment: (_) {},
                    onRejectHunk: (_) {},
                    onToggleAccept: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('corrigir erro'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('corrigir erro')).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('review-line-12'))).dy,
        ),
      );
      await tester.tap(find.text('Tratado'));
      await tester.pumpAndSettle();
      expect(find.text('corrigir erro'), findsNothing);
      expect((await db.select(db.reviewComments).getSingle()).resolved, isTrue);
      await tester.tap(find.text('Reabrir'));
      await tester.pumpAndSettle();
      expect(find.text('corrigir erro'), findsOneWidget);
      expect(
        (await db.select(db.reviewComments).getSingle()).resolvedAt,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
