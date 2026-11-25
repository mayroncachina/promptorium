import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/debt_links_repo.dart';
import 'package:promptorium/features/debts/debt_files.dart';
import 'package:promptorium/features/debts/debt_service.dart';
import 'package:promptorium/features/debts/debt_table.dart';

import '../../helpers/test_db.dart';

/// SPEC-112 R2, R3, R7, R10, R18: the service on a real git repository.
void main() {
  late Directory dir;
  late String root;
  late AppDatabase db;
  late DebtService service;
  final fixture = File('test/fixtures/debts/debitos.md').readAsStringSync();

  Future<String> git(List<String> args, {String? at}) async {
    final r = await Process.run('git', ['-C', at ?? root, ...args]);
    if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
    return '${r.stdout}';
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('debt_service_');
    root = '${dir.path}/repo';
    Directory(root).createSync();
    await git(['init', '-q', '-b', 'main']);
    await git(['config', 'user.email', 't@t']);
    await git(['config', 'user.name', 't']);
    await git(['config', 'commit.gpgsign', 'false']);
    File('$root/README.md').writeAsStringSync('x\n');
    await git(['add', '.']);
    await git(['commit', '-q', '-m', 'init']);
    db = memoryDatabase();
    service = DebtService(
      links: DebtLinksRepo(db),
      now: () => DateTime(2026, 11, 24),
    );
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  const draft = DebtDraft(
    kind: DebtKind.debt,
    title: 'Lotes da equipe técnica',
    reason: 'ficam para depois',
    where: 'backend/lotes.py',
    toResolve: 'fazer os lotes',
  );

  test('an item by hand creates the file and is committed only with the '
      'file, after asking (R10, R18)', () async {
    File('$root/outro.txt').writeAsStringSync('sujo');
    final dirty = await service.isDirty(root, 'DEBITO_TECNICO.md');
    expect(dirty, isFalse);
    final w = await service.create(root, draft);
    expect(w.code, 'DT-01');
    final text = File('$root/DEBITO_TECNICO.md').readAsStringSync();
    expect(
      text,
      contains(
        '| DT-01 | 2026-11-24 | **Lotes da equipe técnica**: ficam para '
        'depois. | `backend/lotes.py` | fazer os lotes |',
      ),
    );
    // Nothing is committed until the person confirms.
    expect(await git(['log', '--oneline']), isNot(contains('docs:')));
    final r = await service.commitOwn(
      root,
      w.relPath,
      code: w.code,
      title: draft.title,
      wasDirty: dirty,
    );
    expect(r, DebtCommitResult.committed);
    expect(
      (await git(['log', '-1', '--format=%s'])).trim(),
      'docs: DT-01 lotes da equipe técnica',
    );
    expect(
      (await git(['show', '--name-only', '--format=', 'HEAD'])).trim(),
      'DEBITO_TECNICO.md',
    );
    // The other change stays out and nothing was pushed (no remote).
    expect(await git(['status', '--porcelain']), contains('outro.txt'));
  });

  test('a file already dirty is written but not committed (P5)', () async {
    File('$root/DEBITO_TECNICO.md').writeAsStringSync(fixture);
    await git(['add', '.']);
    await git(['commit', '-q', '-m', 'débitos']);
    File('$root/DEBITO_TECNICO.md').writeAsStringSync('$fixture\nnota\n');
    final dirty = await service.isDirty(root, 'DEBITO_TECNICO.md');
    expect(dirty, isTrue);
    final w = await service.create(root, draft);
    expect(w.code, 'DT-09');
    final r = await service.commitOwn(
      root,
      w.relPath,
      code: w.code,
      title: draft.title,
      wasDirty: dirty,
    );
    expect(r, DebtCommitResult.dirty);
    expect((await git(['log', '-1', '--format=%s'])).trim(), 'débitos');
  });

  test('an item born in a worktree goes to its file, and the next ID '
      'skips it (R3, R18)', () async {
    File('$root/DEBITO_TECNICO.md').writeAsStringSync(fixture);
    await git(['add', '.']);
    await git(['commit', '-q', '-m', 'débitos']);
    final wt = '${dir.path}/wt';
    await git(['worktree', 'add', '-q', '-b', 'spec/33', wt]);
    final a = await service.create(root, draft, writeRoot: wt);
    expect(a.code, 'DT-09');
    expect(File('$wt/DEBITO_TECNICO.md').readAsStringSync(), contains('DT-09'));
    expect(
      File('$root/DEBITO_TECNICO.md').readAsStringSync(),
      isNot(contains('DT-09')),
    );
    final b = await service.create(root, draft);
    expect(b.code, 'DT-10');
  });

  test('a suggestion writes nothing until accepted (R7)', () async {
    final id = await service.suggest(
      root,
      draft,
      source: DebtSuggestionSource.interview,
      link: const DebtLinksCompanion(originQuestion: Value('Q6')),
    );
    expect(File('$root/DEBITO_TECNICO.md').existsSync(), isFalse);
    final w = await service.accept(
      id,
      edited: draft.copyWith(title: 'Lotes (editado)'),
    );
    expect(w.code, 'DT-01');
    final l = (await service.links.byId(id))!;
    expect(
      (l.code, l.suggestionState, l.originQuestion),
      ('DT-01', DebtSuggestionState.accepted, 'Q6'),
    );
    expect(
      File('$root/DEBITO_TECNICO.md').readAsStringSync(),
      contains('**Lotes (editado)**'),
    );
    final other = await service.suggest(
      root,
      draft,
      source: DebtSuggestionSource.mcp,
    );
    await service.discard(other);
    expect(
      (await service.links.byId(other))!.suggestionState,
      DebtSuggestionState.discarded,
    );
    expect((await DebtSnapshot.load(root)).debts.debts.map((d) => d.code), [
      'DT-01',
    ]);
  });

  test('decisions get DP codes and an empty Decisão', () async {
    final w = await service.create(
      root,
      const DebtDraft(
        kind: DebtKind.decision,
        title: 'Quem cadastra as funções?',
        origin: 'spec 33, Q7',
        toResolve: 'Importar do painel.',
      ),
    );
    expect(w.code, 'DP-01');
    final s = await DebtSnapshot.load(root);
    final d = s.decisions.decisions.single;
    expect(d.title, 'Quem cadastra as funções?');
    expect(d.origin, 'spec 33, Q7');
    expect(d.recommendation, 'Importar do painel.');
    expect(d.decided, isFalse);
    expect(s.pendingDecisions, hasLength(1));
  });

  group('old files of docs/ (R2)', () {
    setUp(() async {
      Directory('$root/docs').createSync();
      File('$root/docs/debitos-tecnicos.md').writeAsStringSync(fixture);
      await git(['add', '.']);
      await git(['commit', '-q', '-m', 'antigos']);
    });

    test('"Usar estes arquivos" writes the path in the config', () async {
      await service.useLegacy(root);
      final s = await DebtSnapshot.load(root);
      expect(s.config.debtsPath, 'docs/debitos-tecnicos.md');
      expect(s.legacyDebts, isNull);
      expect(s.debts.debts, hasLength(8));
      expect(
        File('$root/.promptorium/config.yml').readAsStringSync(),
        contains('arquivo: docs/debitos-tecnicos.md'),
      );
    });

    test('"Mover para a raiz" does git mv and fixes the links', () async {
      await service.moveLegacy(root);
      expect(File('$root/docs/debitos-tecnicos.md').existsSync(), isFalse);
      final text = File('$root/DEBITO_TECNICO.md').readAsStringSync();
      expect(text, contains('[spec 28](docs/specs/28-armazenamento-s3.md)'));
      expect(text, contains('[spec 31](docs/specs/31-equipe-tecnica'));
      final status = await git(['status', '--porcelain']);
      expect(
        status,
        contains('R  docs/debitos-tecnicos.md -> DEBITO_TECNICO.md'),
      );
      final s = await DebtSnapshot.load(root);
      expect(s.debts.debts, hasLength(8));
      expect(s.legacyDebts, isNull);
    });
  });

  test('fixRelativeLinks', () {
    String fix(String t, String from, String to) =>
        DebtService.fixRelativeLinks(t, from: from, to: to);
    expect(fix('[a](specs/x.md)', 'docs/d.md', 'D.md'), '[a](docs/specs/x.md)');
    expect(fix('[a](../x.md)', 'docs/d.md', 'D.md'), '[a](x.md)');
    expect(fix('[a](docs/x.md)', 'D.md', 'docs/d.md'), '[a](x.md)');
    expect(fix('[a](x.md)', 'D.md', 'docs/d.md'), '[a](../x.md)');
    expect(fix('[a](https://x/y)', 'docs/d.md', 'D.md'), '[a](https://x/y)');
    expect(fix('[a](#t)', 'docs/d.md', 'D.md'), '[a](#t)');
  });

  test('commitMessage', () {
    expect(
      DebtService.commitMessage('DT-09', 'Lotes da equipe técnica'),
      'docs: DT-09 lotes da equipe técnica',
    );
  });

  test('DebtTable new file header has the table', () {
    expect(
      DebtTable.parse(
        DebtFiles.newFileText(DebtKind.debt),
        DebtKind.debt,
      ).hasTable,
      isTrue,
    );
  });
}
