import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/debt_links_repo.dart';

import '../helpers/test_db.dart';

/// SPEC-112 R3, R4: the links and the reservation of the IDs.
void main() {
  late AppDatabase db;
  late DebtLinksRepo repo;

  setUp(() async {
    db = memoryDatabase();
    repo = DebtLinksRepo(db);
    await db.customStatement(
      "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
    );
    await db.customStatement(
      "INSERT INTO specs (id, workspace_id, code, title, path) VALUES "
      "(1, 1, 'SPEC-031', 'a', 'specs/a.md'), "
      "(2, 1, 'SPEC-032', 'b', 'specs/b.md')",
    );
  });
  tearDown(() => db.close());

  Future<String> reserve({int min = 1, String repoRoot = '/r'}) async =>
      (await repo.reserve(
        repoRoot: repoRoot,
        kind: 'debito',
        prefix: 'DT',
        minNumber: min,
      )).code;

  test('two worktrees reading the same file get different IDs', () async {
    // Both read DT-08 as the highest in their files.
    final results = await Future.wait([reserve(min: 9), reserve(min: 9)]);
    expect(results.toSet(), {'DT-09', 'DT-10'});
  });

  test('a struck or deleted ID never comes back', () async {
    expect(await reserve(min: 9), 'DT-09');
    // The row DT-09 was removed by hand: the file goes back to DT-08 as the
    // highest, but the reservation stays.
    expect(await reserve(min: 9), 'DT-10');
    expect(await reserve(min: 3), 'DT-11');
    // The file got a higher one from outside (a merge).
    expect(await reserve(min: 21), 'DT-21');
  });

  test('IDs are per repository and per kind', () async {
    expect(await reserve(min: 9), 'DT-09');
    expect(await reserve(min: 1, repoRoot: '/outro'), 'DT-01');
    final dp = await repo.reserve(
      repoRoot: '/r',
      kind: 'decisao',
      prefix: 'DP',
      minNumber: 1,
    );
    expect(dp.code, 'DP-01');
  });

  test('the unique index refuses the same code twice', () async {
    await repo.ensure('/r', 'debito', 'DT-05');
    expect(await repo.ensure('/r', 'debito', 'DT-05'), isPositive);
    expect(await repo.forRepo('/r'), hasLength(1));
    expect(
      () => db
          .into(db.debtLinks)
          .insert(
            DebtLinksCompanion.insert(
              repoRoot: '/r',
              kind: 'debito',
              code: const Value('DT-05'),
            ),
          ),
      throwsA(anything),
    );
  });

  test('suggestions have no code and keep the proposed cells', () async {
    final id = await repo.addSuggestion(
      repoRoot: '/r',
      kind: 'debito',
      source: DebtSuggestionSource.mcp,
      body: {'titulo': 'Pagamento simulado', 'onde': 'PagarView.vue'},
      link: const DebtLinksCompanion(originSessionId: Value('s1')),
    );
    final l = (await repo.byId(id))!;
    expect(l.code, isNull);
    expect(l.suggestionState, DebtSuggestionState.pending);
    expect(DebtLinksRepo.suggestionOf(l)['titulo'], 'Pagamento simulado');
    expect(l.originSessionId, 's1');
    // Two suggestions without code do not clash on the unique index.
    await repo.addSuggestion(
      repoRoot: '/r',
      kind: 'debito',
      source: DebtSuggestionSource.interview,
      body: const {},
    );
    expect(await repo.forRepo('/r'), hasLength(2));
  });

  test('discarding a spec releases its payments and piggybacks', () async {
    final a = await repo.ensure('/r', 'debito', 'DT-03');
    final b = await repo.ensure('/r', 'debito', 'DT-05');
    await repo.update(a, const DebtLinksCompanion(paymentSpecId: Value(1)));
    await repo.update(
      b,
      const DebtLinksCompanion(
        piggybackSpecId: Value(1),
        piggybackState: Value(DebtPiggybackState.toConfirm),
      ),
    );
    expect((await repo.payingBy(1)).map((l) => l.code), ['DT-03']);
    expect((await repo.piggybackOf(1)).map((l) => l.code), ['DT-05']);
    await repo.releaseSpec(1);
    expect(await repo.payingBy(1), isEmpty);
    expect(await repo.piggybackOf(1), isEmpty);
  });

  test('deleting the spec leaves the link without it (set null)', () async {
    final a = await repo.ensure('/r', 'debito', 'DT-03');
    await repo.update(
      a,
      const DebtLinksCompanion(originSpecId: Value(2), paymentSpecId: Value(2)),
    );
    await db.customStatement('DELETE FROM specs WHERE id = 2');
    final l = (await repo.byId(a))!;
    expect((l.originSpecId, l.paymentSpecId, l.code), (null, null, 'DT-03'));
  });
}
