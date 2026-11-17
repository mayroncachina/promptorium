import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/secret_waivers_repo.dart';

import '../helpers/test_db.dart';

/// SPEC-085 R11, R12.
void main() {
  late AppDatabase db;
  late SecretWaiversRepo repo;

  setUp(() async {
    db = memoryDatabase();
    repo = SecretWaiversRepo(db);
    await db.customStatement(
      "INSERT INTO workspaces (id, path, name) VALUES (1, '/a', 'a'), "
      "(2, '/b', 'b')",
    );
  });
  tearDown(() => db.close());

  Future<int> add({
    int ws = 1,
    String scope = SecretWaiverScope.value,
    String reason = 'chave de teste revogada',
  }) => repo.add(
    workspaceId: ws,
    rule: 'stripe',
    path: 'src/a.ts',
    fingerprint: 'f1',
    scope: scope,
    reason: reason,
    origin: 'sessao:s1',
  );

  test('a reason under 10 characters is refused', () async {
    expect(() => add(reason: ' curta  '), throwsArgumentError);
    expect(await db.select(db.secretWaivers).get(), isEmpty);
  });

  test('refs by workspace; a file waiver keeps no fingerprint', () async {
    await add();
    await add(scope: SecretWaiverScope.file);
    await add(ws: 2);
    final refs = await repo.refs(1);
    expect(refs, hasLength(2));
    expect(refs.where((r) => r.byValue).single.fingerprint, 'f1');
    expect(refs.where((r) => !r.byValue).single.fingerprint, '');
    expect(refs.first.matches('outra', 'x', 'f1'), isTrue);
  });

  test('90 days without a match removes it; touch keeps it (R12)', () async {
    final old = await add();
    final kept = await add(scope: SecretWaiverScope.file);
    final long = DateTime.now().subtract(const Duration(days: 91));
    await (db.update(db.secretWaivers)).write(
      SecretWaiversCompanion(lastUsedAt: Value(long)),
    );
    await repo.touch([kept]);
    final ids = [for (final w in await repo.active(1)) w.id];
    expect(ids, [kept]);
    expect(ids, isNot(contains(old)));
  });

  test('remove', () async {
    final id = await add();
    await repo.remove(id);
    expect(await repo.refs(1), isEmpty);
  });
}
