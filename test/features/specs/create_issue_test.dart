import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/git/gh_issues.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/issues/issue_create.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../core/git/fake_issues.dart';
import '../../helpers/test_db.dart';

/// "Criar issue" (SPEC-074 R11): `issue: N` only after the issue exists.
void main() {
  const text =
      '---\nid: SPEC-027\nstatus: rascunho\n---\n# Exportar pedidos em CSV\n\n'
      '## Objetivo\n\nA loja precisa mandar os pedidos do mês para a '
      'contabilidade.\n<!-- dica -->\n\n## Requisitos\n\n'
      '- R1 · Botão “Exportar CSV” na lista de pedidos\n'
      '- R2 · Filtro por período antes de exportar\n';

  test('the text: the Objetivo, the requirements as a checklist and the '
      'path of the spec (P6)', () {
    expect(
      issueBodyFromSpec(text, path: 'docs/specs/SPEC-027-exportar.md'),
      'A loja precisa mandar os pedidos do mês para a contabilidade.\n\n'
      '- [ ] R1 · Botão “Exportar CSV” na lista de pedidos\n'
      '- [ ] R2 · Filtro por período antes de exportar\n\n'
      'Spec: `docs/specs/SPEC-027-exportar.md` (Promptorium)',
    );
  });

  group('createIssueForSpec', () {
    late Directory root;
    late AppDatabase db;
    late Workspace ws;
    late SpecsRepo repo;
    late SpecService service;
    late FakeIssuesGh gh;
    late Spec spec;
    late File file;
    setUp(() async {
      root = Directory.systemTemp.createTempSync('create-issue-');
      file = File('${root.path}/specs/SPEC-027-exportar.md')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
      db = memoryDatabase();
      ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: root.path, name: 'ws'),
          );
      repo = SpecsRepo(db);
      service = SpecService(repo);
      await service.sync(ws);
      spec = (await repo.getByCode(ws.id, 'SPEC-027'))!;
      gh = FakeIssuesGh()..nextNumber = 251;
    });
    tearDown(() async {
      await db.close();
      root.deleteSync(recursive: true);
    });

    Future<int> create() => createIssueForSpec(
      client: GhIssues(GhCli(gh.call, cwd: root.path), repo: gh.repo),
      service: service,
      repo: repo,
      ws: ws,
      spec: spec,
      title: 'Exportar pedidos em CSV',
      body: 'corpo',
      labels: ['enhancement'],
      milestone: 'v1.2',
      assignee: '@me',
    );

    test('the issue is created, then issue: N goes into the file and the '
        'badge', () async {
      expect(await create(), 251);
      expect(gh.issues[251]!['title'], 'Exportar pedidos em CSV');
      expect(SpecDocument.parse(file.readAsStringSync()).issue, 251);
      final row = (await repo.getById(spec.id))!;
      expect(row.issueNumber, 251);
      expect(row.issueState, IssueState.open);
    });

    test('a failure of gh changes nothing in the spec', () async {
      gh.createFails = true;
      await expectLater(create(), throwsA(isA<GhException>()));
      expect(file.readAsStringSync(), text);
      expect((await repo.getById(spec.id))!.issueNumber, isNull);
    });
  });
}
