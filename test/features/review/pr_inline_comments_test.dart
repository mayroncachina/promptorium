import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/review_comments_repo.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/review/widgets/pr_panel.dart';

import '../../helpers/test_db.dart';
import 'review_logic_test.dart' show session;

void main() {
  test('external ids reconcile legacy rows deterministically and retain resolved state', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    await db.customStatement(
      "INSERT INTO workspaces(path,name) VALUES('/r','r')",
    );
    await db.customStatement(
      "INSERT INTO specs(workspace_id,code,title,path) VALUES(1,'SPEC-001','a','specs/a.md')",
    );
    final repo = ReviewCommentsRepo(db);
    await repo.insertAll([
      for (var i = 0; i < 2; i++)
        ReviewCommentsCompanion.insert(
          specId: 1,
          round: 1,
          author: 'pr',
          body: '@ana: ajuste',
        ),
    ]);
    ReviewCommentsCompanion external(String id) =>
        ReviewCommentsCompanion.insert(
          specId: 1,
          round: 2,
          author: 'pr',
          body: '@ana: ajuste',
          externalId: Value(id),
          path: const Value('a.dart'),
          line: const Value(12),
        );
    await repo.insertExternal(external('github:1'));
    await repo.insertExternal(external('github:2'));
    final rows = await repo.bySpec(1);
    expect(rows, hasLength(2));
    expect(rows.map((c) => c.externalId), ['github:1', 'github:2']);
    await repo.setResolved(rows.first.id, true);
    await repo.insertExternal(external('github:1'));
    final refreshed = await ReviewCommentsRepo(db).bySpec(1);
    expect(refreshed, hasLength(2));
    expect(refreshed.first.resolved, isTrue);
    expect(refreshed.first.resolvedAt, isNotNull);
    await repo.setResolved(rows.first.id, false);
    expect((await repo.bySpec(1)).first.resolvedAt, isNull);
    final index = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE name='review_comments_external'",
        )
        .getSingle();
    expect(
      index.read<String>('sql'),
      contains('WHERE external_id IS NOT NULL'),
    );
  });

  test(
    'a PR comment row keeps its host id; a legacy row with the same '
    'author and text is linked on the first read, without duplicating',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      await db.customStatement(
        "INSERT INTO workspaces(path,name) VALUES('/r','r')",
      );
      await db.customStatement(
        "INSERT INTO specs(workspace_id,code,title,path) VALUES(1,'SPEC-001','a','specs/a.md')",
      );
      final repo = ReviewCommentsRepo(db);
      await repo.insertAll([
        ReviewCommentsCompanion.insert(
          specId: 1,
          round: 1,
          author: 'pr',
          body: '@ana: ajuste',
        ),
      ]);
      final comment = PrComment(
        author: 'ana',
        body: 'ajuste',
        at: DateTime(2026),
        externalId: 'github:9',
        path: 'a.dart',
        line: 4,
      );
      final row = prCommentRow(1, 2, comment);
      expect(row.externalId.value, 'github:9');
      expect(row.body.value, '@ana: ajuste');
      await repo.insertExternal(row);
      await repo.insertExternal(prCommentRow(1, 3, comment));
      final rows = await repo.bySpec(1);
      expect(rows, hasLength(1));
      expect(rows.single.externalId, 'github:9');
    },
  );

  testWidgets('with gh failing, the PR panel shows the error', (tester) async {
    final db = memoryDatabase();
    final s = session().copyWith(
      prUrl: const Value('https://github.com/o/r/pull/7'),
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          databaseOverride(db),
          reviewServiceProvider.overrideWith(_FailingReview.new),
        ],
        child: MaterialApp(
          home: Scaffold(body: PrPanel(session: s)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('gh: offline'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _FailingReview extends ReviewService {
  _FailingReview(super.ref);
  @override
  Future<PrStatus?> refreshPrComments(String sessionId) async =>
      throw const ReviewException('gh: offline');
}
