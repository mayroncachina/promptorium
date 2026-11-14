import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/vibe/vibe_numbers.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';

/// The VIBE as a spec (SPEC-069 R3, R12).
void main() {
  late Directory root;
  late AppDatabase db;
  late Workspace ws;
  late SpecsRepo repo;
  late SpecService service;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('spec-vibe-');
    db = memoryDatabase();
    ws = await db
        .into(db.workspaces)
        .insertReturning(
          WorkspacesCompanion.insert(path: root.path, name: 'ws'),
        );
    repo = SpecsRepo(db);
    service = SpecService(repo);
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  void write(String rel, String text) {
    final f = File('${root.path}/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  test('newVibeMarkdown: frontmatter with kind vibe, the request as R1 and '
      'one criterion', () {
    final text = newVibeMarkdown(
      code: 'VIBE-007',
      title: 'Botão Comprar verde',
      request: 'Deixa o botão Comprar verde\ne um pouco maior.',
    );
    final doc = SpecDocument.parse(text);
    expect(doc.id, 'VIBE-007');
    expect(doc.kind, SpecKind.vibe);
    expect(doc.status, SpecStatus.approved);
    expect(doc.requirements.single.id, 'R1');
    expect(
      doc.requirements.single.text,
      'Deixa o botão Comprar verde e um pouco maior.',
    );
    expect(parseCriteria(text).single.text, contains('conferido no Review'));
  });

  test('sync reads docs/vibe/ as VIBEs, outside the Bandeja, and the series '
      'never meet', () async {
    write(
      'specs/SPEC-001-login.md',
      '---\nid: SPEC-001\nstatus: aprovada\n---\n# Login\n\n## Requisitos\n- R1 · x\n',
    );
    write(
      'docs/vibe/VIBE-004-fonte.md',
      newVibeMarkdown(code: 'VIBE-004', title: 'Fonte', request: 'Testar'),
    );
    await service.sync(ws);
    final vibe = (await repo.getByCode(ws.id, 'VIBE-004'))!;
    expect(vibe.kind, SpecKind.vibe);
    expect(vibe.path, 'docs/vibe/VIBE-004-fonte.md');
    expect(vibe.inTray, isFalse);
    expect(isOnBoard(vibe), isTrue);
    final spec = (await repo.getByCode(ws.id, 'SPEC-001'))!;
    expect(spec.kind, SpecKind.spec);
    expect(service.issues[ws.id], isEmpty);

    // A later VIBE never waits in the Bandeja either.
    write(
      'docs/vibe/VIBE-005-x.md',
      newVibeMarkdown(code: 'VIBE-005', title: 'X', request: 'y'),
    );
    await service.sync(ws);
    expect((await repo.getByCode(ws.id, 'VIBE-005'))!.inTray, isFalse);

    expect(await nextSpecCode(repo, ws), 'SPEC-002');
    expect(await nextSpecCode(repo, ws, kind: SpecKind.vibe), 'VIBE-006');
  });

  test('a SPEC id in docs/vibe/ is refused', () async {
    write(
      'docs/vibe/VIBE-001-x.md',
      '---\nid: SPEC-001\nstatus: aprovada\nkind: vibe\n---\n# X\n',
    );
    await service.sync(ws);
    expect(await repo.getByCode(ws.id, 'SPEC-001'), isNull);
    expect(service.issues[ws.id]!.single, contains('ID divergente'));
  });

  test('vibe.pasta and vibe.teto of the config', () {
    final c = ProjectConfig.parse(
      'vibe:\n  pasta: tarefas\n  teto:\n    arquivos: 5\n    linhas: 100\n',
    );
    expect(c.vibeDir, 'tarefas');
    expect(c.vibe.maxFiles, 5);
    expect(c.vibe.maxLines, 100);
    expect(ProjectConfig.parse(c.toYaml()), c);
    const d = ProjectConfig();
    expect(d.vibeDir, 'docs/vibe');
    expect(d.vibe.maxFiles, 15);
    expect(d.vibe.maxLines, 400);
  });

  test('R12: a reserved number is never given back, even when its row is '
      'gone', () async {
    final v = await repo.insert(
      workspaceId: ws.id,
      code: 'VIBE-009',
      title: 'x',
      path: 'docs/vibe/VIBE-009-x.md',
      kind: SpecKind.vibe,
      inTray: true,
    );
    expect(v.inTray, isFalse, reason: 'a VIBE never goes to the Bandeja');
    await repo.reserve(ws.id, 'VIBE-009');
    await repo.delete(v.id);
    expect(await nextSpecCode(repo, ws, kind: SpecKind.vibe), 'VIBE-010');
    expect(await nextSpecCode(repo, ws), 'SPEC-001');
  });

  test('the file of a VIBE is read from its worktree before the merge, and '
      'is not "arquivo ausente"', () async {
    final wt = Directory.systemTemp.createTempSync('spec-vibe-wt-');
    addTearDown(() => wt.deleteSync(recursive: true));
    final v = await repo.insert(
      workspaceId: ws.id,
      code: 'VIBE-001',
      title: 'x',
      path: 'docs/vibe/VIBE-001-x.md',
      kind: SpecKind.vibe,
    );
    await repo.update(v.id, SpecsCompanion(worktreePath: Value(wt.path)));
    File('${wt.path}/docs/vibe/VIBE-001-x.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        newVibeMarkdown(code: 'VIBE-001', title: 'x', request: 'y'),
      );
    final spec = (await repo.getById(v.id))!;
    expect(await service.read(ws, spec), contains('VIBE-001'));
    write('specs/SPEC-001.md', '---\nid: SPEC-001\n---\n# A\n');
    await service.sync(ws);
    expect(service.issues[ws.id], isEmpty);
  });

  group('renumberIfTaken (R12)', () {
    late Directory tmp;
    late String main;
    late String wt;
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('vibe-renumber-');
      main = await createRepo(tmp);
      wt = '${tmp.path}/wt';
      await gitIn(main, ['worktree', 'add', '-q', '-b', 'vibe/001-x', wt]);
      // Another machine merged its own VIBE-001 into main.
      File('$main/docs/vibe/VIBE-001-outra.md')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          newVibeMarkdown(code: 'VIBE-001', title: 'Outra', request: 'a'),
        );
      await gitIn(main, ['add', '.']);
      await gitIn(main, ['commit', '-q', '-m', 'outra']);
      File('$wt/docs/vibe/VIBE-001-x.md')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          newVibeMarkdown(code: 'VIBE-001', title: 'X', request: 'b'),
        );
      await gitIn(wt, ['add', '.']);
      await gitIn(wt, ['commit', '-q', '-m', 'VIBE-001: pedido']);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('moves the file and its references to the next free number', () async {
      final w = await db
          .into(db.workspaces)
          .insertReturning(WorkspacesCompanion.insert(path: main, name: 'r'));
      final v = await repo.insert(
        workspaceId: w.id,
        code: 'VIBE-001',
        title: 'X',
        path: 'docs/vibe/VIBE-001-x.md',
        kind: SpecKind.vibe,
      );
      await repo.update(v.id, SpecsCompanion(worktreePath: Value(wt)));
      final moved = await renumberIfTaken(
        repo: repo,
        ws: w,
        spec: (await repo.getById(v.id))!,
        main: GitService(main),
        worktree: GitService(wt),
        base: 'main',
      );
      expect(moved, 'VIBE-002');
      final row = (await repo.getById(v.id))!;
      expect(row.code, 'VIBE-002');
      expect(row.path, 'docs/vibe/VIBE-002-x.md');
      expect(File('$wt/docs/vibe/VIBE-001-x.md').existsSync(), isFalse);
      final text = File('$wt/docs/vibe/VIBE-002-x.md').readAsStringSync();
      expect(SpecDocument.parse(text).id, 'VIBE-002');
      expect(await gitIn(wt, ['status', '--porcelain']), isEmpty);
      expect(
        await gitIn(wt, ['log', '-1', '--format=%s']),
        contains('VIBE-002: renumerada'),
      );
      expect(await nextSpecCode(repo, w, kind: SpecKind.vibe), 'VIBE-003');
    });

    test('a free number stays', () async {
      final w = await db
          .into(db.workspaces)
          .insertReturning(WorkspacesCompanion.insert(path: main, name: 'r'));
      final v = await repo.insert(
        workspaceId: w.id,
        code: 'VIBE-005',
        title: 'X',
        path: 'docs/vibe/VIBE-005-x.md',
        kind: SpecKind.vibe,
      );
      await repo.update(v.id, SpecsCompanion(worktreePath: Value(wt)));
      expect(
        await renumberIfTaken(
          repo: repo,
          ws: w,
          spec: (await repo.getById(v.id))!,
          main: GitService(main),
          worktree: GitService(wt),
          base: 'main',
        ),
        isNull,
      );
    });
  });
}
