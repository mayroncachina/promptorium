import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';

import '../../helpers/test_db.dart';

String document(String code, {String status = 'rascunho'}) =>
    '---\nid: $code\nstatus: $status\n---\n# Importada\n\n## Requisitos\n- R1 · funcionar\n';

void main() {
  late Directory root;
  late AppDatabase db;
  late Workspace ws;
  late SpecsRepo repo;
  late SpecService service;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('spec-discovery-');
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

  File write(String name, String text, {String folder = 'specs'}) {
    final f = File('${root.path}/$folder/$name');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
    return f;
  }

  test(
    'imports Done, preserves identity after rename, and can explicitly reopen',
    () async {
      final file = write(
        'SPEC-001-a.md',
        document('SPEC-001', status: 'concluida'),
      );
      await Future.wait([service.sync(ws), service.sync(ws)]);
      var spec = (await repo.getByCode(ws.id, 'SPEC-001'))!;
      expect(spec.stage, SpecStage.done);
      expect(spec.status, SpecStatus.done);
      final id = spec.id;
      file.renameSync('${root.path}/specs/SPEC-001-renamed.md');
      await service.sync(ws);
      spec = (await repo.getByCode(ws.id, 'SPEC-001'))!;
      expect(spec.id, id);
      expect(spec.path, endsWith('renamed.md'));
      expect(await db.select(db.sessions).get(), isEmpty);
      expect(await db.select(db.specSteps).get(), isEmpty);
      await service.reopen(ws, spec);
      spec = (await repo.getById(id))!;
      expect(spec.stage, SpecStage.backlog);
      expect(spec.status, SpecStatus.approved);
      expect(
        File('${root.path}/${spec.path}').readAsStringSync(),
        contains('status: aprovada'),
      );
    },
  );

  test('duplicates, divergent ID, unknown status and malformed YAML never overwrite valid rows', () async {
    write('SPEC-001-a.md', document('SPEC-001'));
    await service.sync(ws);
    write('SPEC-001-b.md', document('SPEC-001', status: 'done'));
    write('SPEC-002-wrong.md', document('SPEC-003'));
    write('SPEC-004-bad.md', '---\nid: [\n---\n# Invalid');
    write('SPEC-005-status.md', document('SPEC-005', status: 'banana'));
    write('README.md', '# Docs');
    await service.sync(ws);
    expect(await db.select(db.specs).get(), hasLength(1));
    expect((await repo.getByCode(ws.id, 'SPEC-001'))!.status, SpecStatus.draft);
    expect(service.issues[ws.id], hasLength(4));
  });

  test(
    'does not silently regress Done or close running/review/worktree specs',
    () async {
      for (final stage in [
        SpecStage.running,
        SpecStage.review,
        SpecStage.backlog,
      ]) {
        final code = 'SPEC-00${stage.index + 1}';
        final spec = await repo.insert(
          workspaceId: ws.id,
          code: code,
          title: code,
          path: 'specs/$code.md',
        );
        await repo.update(
          spec.id,
          SpecsCompanion(
            stage: Value(stage),
            worktreePath: Value(
              stage == SpecStage.backlog ? '/tmp/pending' : null,
            ),
          ),
        );
        write('$code.md', document(code, status: 'done'));
      }
      write('SPEC-009.md', document('SPEC-009', status: 'done'));
      await service.sync(ws);
      for (final s in await db.select(db.specs).get()) {
        if (s.code != 'SPEC-009') expect(s.stage, isNot(SpecStage.done));
      }
      write('SPEC-009.md', document('SPEC-009'));
      await service.sync(ws);
      expect(
        (await repo.getByCode(ws.id, 'SPEC-009'))!.status,
        SpecStatus.done,
      );
      expect(service.issues[ws.id], hasLength(4));
    },
  );

  test(
    'missing files retain history and moving to configured folder keeps ID',
    () async {
      final f = write('SPEC-001.md', document('SPEC-001'));
      await service.sync(ws);
      final id = (await repo.getByCode(ws.id, 'SPEC-001'))!.id;
      await ProjectConfig.save(
        root.path,
        const ProjectConfig(specsDir: 'docs/specs'),
      );
      Directory('${root.path}/docs/specs').createSync(recursive: true);
      f.renameSync('${root.path}/docs/specs/SPEC-001.md');
      await service.sync(ws);
      expect((await repo.getById(id))!.path, 'docs/specs/SPEC-001.md');
      File('${root.path}/docs/specs/SPEC-001.md').deleteSync();
      await service.sync(ws);
      expect(await repo.getById(id), isNotNull);
      expect(service.issues[ws.id]!.single, contains('ausente'));
    },
  );

  test(
    'watcher initially discovers files and handles late folders/config changes',
    () async {
      write('SPEC-001.md', document('SPEC-001', status: 'done'));
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          activeWorkspaceProvider.overrideWithValue(ws),
        ],
      );
      final sub = c.listen(workspaceWatcherProvider, (_, _) {});
      Future<void> until(Future<bool> Function() predicate) async {
        for (var i = 0; i < 100; i++) {
          if (await predicate()) return;
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        fail('Watcher did not synchronize');
      }

      try {
        await until(
          () async => await repo.getByCode(ws.id, 'SPEC-001') != null,
        );
        await ProjectConfig.save(
          root.path,
          const ProjectConfig(specsDir: 'docs/specs'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        write(
          'SPEC-002.md',
          document('SPEC-002', status: 'done'),
          folder: 'docs/specs',
        );
        await until(
          () async => await repo.getByCode(ws.id, 'SPEC-002') != null,
        );
        expect(
          (await repo.getByCode(ws.id, 'SPEC-002'))!.stage,
          SpecStage.done,
        );
      } finally {
        sub.close();
        c.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    },
  );
}
