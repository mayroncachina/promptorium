import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../helpers/test_db.dart';

String document(String code, {String status = 'rascunho'}) =>
    '---\nid: $code\nstatus: $status\n---\n# $code\n\n## Requisitos\n- R1 · x\n';

/// Where new and approved specs go (SPEC-068 R7, R8).
void main() {
  late Directory root;
  late AppDatabase db;
  late Workspace ws;
  late SpecsRepo repo;
  late SpecService service;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('spec-tray-');
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

  void write(String code, {String status = 'rascunho'}) {
    final f = File('${root.path}/specs/$code.md');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(document(code, status: status));
  }

  test('the first reading of a project keeps its approved specs on the '
      'Quadro; specs that arrive later wait in the Bandeja', () async {
    write('SPEC-001', status: 'aprovada');
    write('SPEC-002');
    await service.sync(ws);
    final first = (await repo.getByCode(ws.id, 'SPEC-001'))!;
    expect(first.inTray, isFalse);
    expect(isOnBoard(first), isTrue);

    write('SPEC-003', status: 'aprovada');
    await service.sync(ws);
    final late = (await repo.getByCode(ws.id, 'SPEC-003'))!;
    expect(late.inTray, isTrue);
    expect(isOnBoard(late), isFalse);
    expect(isInTray(late), isTrue);
  });

  test('a new spec enters the Bandeja; approving keeps it there until it '
      'is taken (R8)', () async {
    final spec = await service.create(ws, title: 'Carrinho');
    expect(spec.inTray, isTrue);
    final text = (await service.read(ws, spec))!;
    final approved = (await service.approve(ws, spec, text)).spec;
    expect(approved.status, SpecStatus.approved);
    expect(approved.inTray, isTrue);
    expect(isOnBoard(approved), isFalse);
    await repo.setInTray([spec.id], false);
    expect(isOnBoard((await repo.getById(spec.id))!), isTrue);
  });

  test('a draft from before the Bandeja also waits there once approved, '
      'and the specs already on the Quadro stay', () async {
    write('SPEC-001');
    write('SPEC-002', status: 'aprovada');
    await service.sync(ws);
    final draft = (await repo.getByCode(ws.id, 'SPEC-001'))!;
    expect(draft.inTray, isFalse, reason: 'as the migration leaves it');
    final text = (await service.read(ws, draft))!;
    final approved = (await service.approve(ws, draft, text)).spec;
    expect(approved.inTray, isTrue);
    expect(isOnBoard((await repo.getByCode(ws.id, 'SPEC-002'))!), isTrue);
  });

  test('reopening a concluded spec goes back to the Quadro', () async {
    write('SPEC-001', status: 'aprovada');
    await service.sync(ws);
    var spec = (await repo.getByCode(ws.id, 'SPEC-001'))!;
    spec = await service.markDone(ws, spec);
    spec = await service.reopen(ws, spec);
    expect(spec.status, SpecStatus.approved);
    expect(spec.inTray, isFalse);
    expect(isOnBoard(spec), isTrue);
  });

  test('leaving the Backlog leaves the Bandeja', () async {
    final spec = await service.create(ws, title: 'Pix');
    await repo.setStage(spec.id, SpecStage.running);
    expect((await repo.getById(spec.id))!.inTray, isFalse);
    await repo.update(spec.id, const SpecsCompanion(inTray: Value(true)));
    await repo.setStage(spec.id, SpecStage.backlog);
    expect((await repo.getById(spec.id))!.inTray, isTrue);
  });
}
