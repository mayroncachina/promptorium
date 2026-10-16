import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/specs_screen.dart'
    show refineSpecPrompt;

import '../../helpers/test_db.dart';

const sample = '''---
id: SPEC-002
status: em-revisao
# comentário mantido
autor: você
---

# Sessões com stream-json

## Requisitos
- R1 · Cada sessão roda em um worktree
- [ ] R2: Eventos persistidos no SQLite
1. **R3** - Retomar com --resume
- sem id aqui
''';

void main() {
  group('SpecDocument', () {
    test('parses id, status, title and requirements', () {
      final d = SpecDocument.parse(sample);
      expect(d.hasFrontmatter, isTrue);
      expect(d.id, 'SPEC-002');
      expect(d.rawStatus, 'em-revisao');
      expect(d.status, SpecStatus.review);
      expect(d.frontmatter['autor'], 'você');
      expect(d.title, 'Sessões com stream-json');
      expect(d.body, startsWith('\n# Sessões'));
      expect(d.requirements.map((r) => r.id), ['R1', 'R2', 'R3']);
      expect(d.requirements.first.text, 'Cada sessão roda em um worktree');
      expect(d.requirements[1].text, 'Eventos persistidos no SQLite');
    });

    test('status values round-trip (ideia/rascunho/em-revisao/aprovada)', () {
      for (final s in SpecStatus.values) {
        expect(specStatusFromValue(specStatusValue(s)), s);
      }
      expect(specStatusFromValue('Em revisão'), SpecStatus.review);
      expect(specStatusFromValue('APROVADA'), SpecStatus.approved);
      expect(specStatusFromValue('xyz'), isNull);
    });

    test('withMeta changes only id/status lines, keeps the rest byte for '
        'byte', () {
      final d = SpecDocument.parse(sample);
      final out = d.withMeta(status: SpecStatus.approved);
      expect(
        out,
        sample.replaceFirst('status: em-revisao', 'status: aprovada'),
      );
      final again = SpecDocument.parse(out);
      expect(again.status, SpecStatus.approved);
      expect(again.id, 'SPEC-002');
      expect(again.body, d.body);
      // No change requested = same text.
      expect(d.withMeta(), sample);
    });

    test('withMeta adds missing keys and creates the frontmatter', () {
      const noStatus = '---\nid: SPEC-009\n---\n\n# X\n';
      expect(
        SpecDocument.parse(noStatus).withMeta(status: SpecStatus.idea),
        '---\nid: SPEC-009\nstatus: ideia\n---\n\n# X\n',
      );
      const plain = '# Só corpo\n\ntexto\n';
      final out = SpecDocument.parse(plain)
          .withMeta(id: 'SPEC-010', status: SpecStatus.draft);
      expect(
        out,
        '---\nid: SPEC-010\nstatus: rascunho\n---\n\n# Só corpo\n\ntexto\n',
      );
      expect(SpecDocument.parse(out).title, 'Só corpo');
    });

    test('depende-de: list or text; withMeta writes it', () {
      expect(
        SpecDocument.parse('---\ndepende-de: SPEC-001, SPEC-002\n---\n')
            .dependsOn,
        ['SPEC-001', 'SPEC-002'],
      );
      final d = SpecDocument.parse(sample);
      expect(d.hasDependsOn, isFalse);
      final t = d.withMeta(dependsOn: ['SPEC-001', 'SPEC-004']);
      expect(t, contains('autor: você\ndepende-de: [SPEC-001, SPEC-004]\n---'));
      expect(SpecDocument.parse(t).dependsOn, ['SPEC-001', 'SPEC-004']);
      expect(
        SpecDocument.parse(t.replaceFirst('[SPEC-001, SPEC-004]', '[]'))
            .hasDependsOn,
        isTrue,
      );
    });

    test('invalid or unterminated frontmatter is treated as body', () {
      final d = SpecDocument.parse('---\nid: [\n# T\n');
      expect(d.hasFrontmatter, isFalse);
      expect(d.title, 'T');
      final bad = SpecDocument.parse('---\nid: [aberto\n---\n# T\n');
      expect(bad.hasFrontmatter, isTrue);
      expect(bad.frontmatter, isEmpty);
      expect(bad.status, isNull);
    });

    test('new spec template parses back', () {
      final d = SpecDocument.parse(
        newSpecMarkdown(code: 'SPEC-004', title: 'Kanban'),
      );
      expect(d.id, 'SPEC-004');
      expect(d.status, SpecStatus.draft);
      expect(d.title, 'Kanban');
    });
  });

  group('SpecService (temporary workspace)', () {
    late Directory tmp;
    late AppDatabase db;
    late Workspace ws;
    late SpecService service;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-specs-');
      db = memoryDatabase();
      ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: tmp.path, name: 'ws'),
          );
      service = SpecService(SpecsRepo(db));
    });

    tearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    test('sync registers files, create numbers after them, approve writes '
        'the frontmatter', () async {
      Directory('${tmp.path}/specs').createSync();
      File('${tmp.path}/specs/SPEC-002-sessoes.md').writeAsStringSync(sample);
      File('${tmp.path}/specs/SPEC-005-sem-frontmatter.md')
          .writeAsStringSync('# Review e merge\n');
      File('${tmp.path}/specs/notas.md').writeAsStringSync('# ignorada\n');

      await service.sync(ws);
      var rows = await db.select(db.specs).get();
      expect(rows.map((r) => (r.code, r.title, r.status, r.path)), [
        (
          'SPEC-002',
          'Sessões com stream-json',
          SpecStatus.review,
          'specs/SPEC-002-sessoes.md',
        ),
        (
          'SPEC-005',
          'Review e merge',
          SpecStatus.draft,
          'specs/SPEC-005-sem-frontmatter.md',
        ),
      ]);

      final created = await service.create(ws, title: 'Kanban de tarefas');
      expect(created.code, 'SPEC-006');
      expect(created.path, 'specs/SPEC-006-kanban-de-tarefas.md');
      final text = (await service.read(ws, created))!;
      expect(SpecDocument.parse(text).status, SpecStatus.draft);

      final spec2 = rows.first;
      final r = await service.approve(ws, spec2, sample);
      expect(r.spec.status, SpecStatus.approved);
      expect(
        File('${tmp.path}/${spec2.path}').readAsStringSync(),
        sample.replaceFirst('status: em-revisao', 'status: aprovada'),
      );

      // Edited outside the app: sync picks the new title / status.
      File('${tmp.path}/${spec2.path}').writeAsStringSync(
        sample
            .replaceFirst('status: em-revisao', 'status: ideia')
            .replaceFirst('# Sessões com stream-json', '# Sessões v2'),
      );
      await service.sync(ws);
      final s2 = await SpecsRepo(db).getByCode(ws.id, 'SPEC-002');
      expect(s2!.title, 'Sessões v2');
      expect(s2.status, SpecStatus.idea);
      rows = await db.select(db.specs).get();
      expect(rows, hasLength(3));
    });

    test('sync mirrors requirements, fase and depende-de; a file without '
        'depende-de keeps the stored list until the next save', () async {
      Directory('${tmp.path}/specs').createSync();
      final f = File('${tmp.path}/specs/SPEC-002-sessoes.md')
        ..writeAsStringSync(sample);
      await service.sync(ws);
      final repo = SpecsRepo(db);
      var s2 = (await repo.getByCode(ws.id, 'SPEC-002'))!;
      expect(s2.requirements.map((r) => r.id), ['R1', 'R2', 'R3']);
      expect(s2.requirements.first.text, 'Cada sessão roda em um worktree');
      expect(s2.phase, isNull);
      expect(s2.dependsOn, isEmpty);

      // Dependencies known only to the database (schema v8 migration).
      await repo.update(
        s2.id,
        const SpecsCompanion(dependsOn: Value(['SPEC-001'])),
      );
      await service.sync(ws);
      s2 = (await repo.getByCode(ws.id, 'SPEC-002'))!;
      expect(s2.dependsOn, ['SPEC-001']);

      // The next save writes them to the frontmatter.
      await service.save(ws, s2, sample);
      final saved = SpecDocument.parse(f.readAsStringSync());
      expect(saved.dependsOn, ['SPEC-001']);
      expect(f.readAsStringSync(), contains('depende-de: [SPEC-001]\n'));

      // The file is the source once it has the key.
      f.writeAsStringSync(
        sample.replaceFirst(
          'autor: você',
          'autor: você\nfase: mvp\ndepende-de: [SPEC-003, spec-004, x]',
        ),
      );
      await service.sync(ws);
      s2 = (await repo.getByCode(ws.id, 'SPEC-002'))!;
      expect(s2.dependsOn, ['SPEC-003', 'SPEC-004']);
      expect(s2.phase, 'mvp');
    });

    test('save writes the file and refreshes the row', () async {
      final s = await service.create(ws, title: 'Editor');
      final edited = (await service.read(
        ws,
        s,
      ))!.replaceFirst('# Editor', '# Editor de specs');
      final saved = await service.save(ws, s, edited);
      expect(saved.title, 'Editor de specs');
      expect(File('${tmp.path}/${s.path}').readAsStringSync(), edited);
      expect(
        Directory('${tmp.path}/specs').listSync().map((f) => f.path),
        isNot(contains(endsWith('.promptorium-tmp'))),
      );
    });
  });

  test('refine prompt mentions the spec file', () {
    final p = refineSpecPrompt(
      const Spec(
        id: 1,
        workspaceId: 1,
        code: 'SPEC-002',
        title: 't',
        status: SpecStatus.draft,
        path: 'specs/SPEC-002-sessoes.md',
        stage: SpecStage.backlog,
        requirements: [],
        dependsOn: [],
        autoAdvance: true,
      ),
    );
    expect(p, contains('@specs/SPEC-002-sessoes.md'));
  });

  test('spec paths are confined to <workspace>/specs (no traversal)', () {
    expect(SpecService.isSafeSpecPath('specs/SPEC-001-x.md'), isTrue);
    for (final bad in [
      '../etc/passwd.md',
      'specs/../../x.md',
      'specs/sub/SPEC-001.md',
      '/abs/specs/x.md',
      'specs/x.txt',
      'specs\\..\\x.md',
    ]) {
      expect(SpecService.isSafeSpecPath(bad), isFalse, reason: bad);
    }
  });
}
