import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../helpers/test_db.dart';

/// "Marcar como finalizada" / "Reabrir" (SPEC-019 R8–R10).
void main() {
  late Directory root;
  late AppDatabase db;
  late Workspace ws;
  late SpecsRepo repo;
  late SpecService service;
  late List<String> reported;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('spec-mark-done-');
    db = memoryDatabase();
    ws = await db
        .into(db.workspaces)
        .insertReturning(
          WorkspacesCompanion.insert(path: root.path, name: 'ws'),
        );
    repo = SpecsRepo(db);
    reported = [];
    service = SpecService(repo, onIssues: (_, i) => reported.addAll(i));
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  File file(String code) => File('${root.path}/specs/$code-a.md');

  Future<Spec> imported(String code, {String status = 'aprovada'}) async {
    final f = file(code);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(
      '---\nid: $code\nstatus: $status\n# comentário mantido\n---\n'
      '# Título\n\n## Requisitos\n- R1 · funcionar\n',
    );
    await service.sync(ws);
    return (await repo.getByCode(ws.id, code))!;
  }

  test('finishing writes the file and the row; the sync keeps it without '
      'issues (R8, R10)', () async {
    final spec = await imported('SPEC-001');
    expect(spec.stage, SpecStage.backlog);

    final done = await service.markDone(ws, spec);
    expect(done.stage, SpecStage.done);
    expect(done.status, SpecStatus.done);
    final text = file('SPEC-001').readAsStringSync();
    expect(text, contains('status: concluida\n'));
    expect(text, contains('estagio-anterior: backlog\n'));
    expect(text, contains('status-anterior: aprovada\n'));
    expect(text, contains('# comentário mantido\n'));

    await service.sync(ws);
    await service.sync(ws);
    final after = (await repo.getById(spec.id))!;
    expect(after.stage, SpecStage.done);
    expect(after.status, SpecStatus.done);
    expect(service.issues[ws.id], isEmpty);
    expect(reported, isEmpty);
    // Finishing twice is refused.
    expect(service.markDone(ws, after), throwsA(isA<SpecException>()));
  });

  test('reopening restores the saved stage and status, removes the saved '
      'keys, and the sync keeps it (R9, R10)', () async {
    final spec = await imported('SPEC-002', status: 'em-revisao');
    final done = await service.markDone(ws, spec);
    expect(
      file('SPEC-002').readAsStringSync(),
      contains('status-anterior: em-revisao'),
    );

    final reopened = await service.reopen(ws, done);
    expect(reopened.stage, SpecStage.backlog);
    expect(reopened.status, SpecStatus.review);
    final text = file('SPEC-002').readAsStringSync();
    expect(text, contains('status: em-revisao\n'));
    expect(text, isNot(contains('estagio-anterior')));
    expect(text, isNot(contains('status-anterior')));
    expect(text, contains('# comentário mantido\n'));

    await service.sync(ws);
    final after = (await repo.getById(spec.id))!;
    expect(after.stage, SpecStage.backlog);
    expect(after.status, SpecStatus.review);
    expect(service.issues[ws.id], isEmpty);
    expect(reported, isEmpty);
  });

  test('a spec concluded without a saved stage reopens to backlog / '
      'aprovada (R9)', () async {
    final spec = await imported('SPEC-003', status: 'concluida');
    expect(spec.stage, SpecStage.done);
    final reopened = await service.reopen(ws, spec);
    expect(reopened.stage, SpecStage.backlog);
    expect(reopened.status, SpecStatus.approved);
    expect(file('SPEC-003').readAsStringSync(), contains('status: aprovada'));
  });

  test(
    'finishing is refused while the spec runs; nothing changes (R8)',
    () async {
      final spec = await imported('SPEC-004');
      await repo.update(
        spec.id,
        const SpecsCompanion(stage: Value(SpecStage.running)),
      );
      final before = file('SPEC-004').readAsStringSync();
      await expectLater(
        service.markDone(ws, (await repo.getById(spec.id))!),
        throwsA(isA<SpecException>()),
      );
      expect(file('SPEC-004').readAsStringSync(), before);
      expect((await repo.getById(spec.id))!.stage, SpecStage.running);
    },
  );

  test('withMeta sets and removes extra keys keeping the other lines', () {
    final doc = SpecDocument.parse(
      '---\nid: SPEC-009\nstatus: aprovada\nfase: mvp\n---\n# T\n',
    );
    final marked = doc.withMeta(
      status: SpecStatus.done,
      fields: {'estagio-anterior': 'backlog', 'status-anterior': 'aprovada'},
    );
    final parsed = SpecDocument.parse(marked);
    expect(parsed.previousStage, SpecStage.backlog);
    expect(parsed.previousStatus, SpecStatus.approved);
    expect(parsed.phase, 'mvp');
    final cleared = parsed.withMeta(
      fields: const {'estagio-anterior': null, 'status-anterior': null},
    );
    expect(
      cleared,
      '---\nid: SPEC-009\nstatus: concluida\nfase: mvp\n---\n# T\n',
    );
    // A finished value is not a stage / status to restore.
    final bad = SpecDocument.parse(
      '---\nestagio-anterior: done\nstatus-anterior: arquivada\n---\n',
    );
    expect(bad.previousStage, isNull);
    expect(bad.previousStatus, isNull);
  });
}
