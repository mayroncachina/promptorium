import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/review_comments_repo.dart';

import '../../helpers/test_db.dart';

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
}
