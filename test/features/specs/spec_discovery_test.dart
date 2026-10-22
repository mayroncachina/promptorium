import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/spec_verifier.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';

import '../../helpers/test_db.dart';

String document(String code, {String status = 'rascunho'}) =>
    '---\nid: $code\nstatus: $status\n---\n# Importada\n\n## Requisitos\n- R1 · funcionar\n';

/// Fails the next [update] once, like a crash between file and database.
class _FailingRepo extends SpecsRepo {
  _FailingRepo(super.db);
  bool fail = true;

  @override
  Future<int> update(int id, SpecsCompanion changes) {
    if (fail) {
      fail = false;
      throw StateError('banco indisponível');
    }
    return super.update(id, changes);
  }
}

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
      // Resources are kept: the worktree stays attached.
      expect(
        (await repo.getByCode(ws.id, 'SPEC-001'))!.worktreePath,
        '/tmp/pending',
      );
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
        for (var i = 0; i < 500; i++) {
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

  test(
    'accepted aliases import as Done and archived files stay filtered',
    () async {
      write('SPEC-001.md', document('SPEC-001', status: 'feita'));
      write('SPEC-002.md', document('SPEC-002', status: 'concluída'));
      write('SPEC-003.md', document('SPEC-003', status: 'arquivada'));
      await service.sync(ws);
      for (final code in ['SPEC-001', 'SPEC-002']) {
        final spec = (await repo.getByCode(ws.id, code))!;
        expect(spec.status, SpecStatus.done);
        expect(spec.stage, SpecStage.done);
        expect(isOnBoard(spec), isTrue);
      }
      final archived = (await repo.getByCode(ws.id, 'SPEC-003'))!;
      expect(archived.status, SpecStatus.archived);
      expect(isOnBoard(archived), isFalse);
      expect(isOnBoard(archived, showArchived: true), isTrue);
      expect(await db.select(db.sessions).get(), isEmpty);
      expect(service.issues[ws.id], isEmpty);
    },
  );

  test('temporary files and reports without ID are ignored', () async {
    write('SPEC-001-a.md', document('SPEC-001'));
    final done = document('SPEC-001', status: 'concluida');
    for (final name in [
      '.SPEC-001-a.md',
      '.#SPEC-001-a.md',
      '~SPEC-001-a.md',
      'SPEC-001-a.md.promptorium-tmp',
      'SPEC-001-a.md.tmp',
      'SPEC-001-a.md~',
      'SPEC-001-a.md.swp',
    ]) {
      write(name, done);
    }
    write('IMPLEMENTACAO-014-015.md', '# Relatório\n\nSPEC-001 concluída.\n');
    write('RELATORIO.md', '---\nstatus: concluida\n---\n# Relatório\n');
    await service.sync(ws);
    final rows = await db.select(db.specs).get();
    expect(rows.single.code, 'SPEC-001');
    expect(rows.single.status, SpecStatus.draft);
    expect(rows.single.stage, SpecStage.backlog);
    expect(service.issues[ws.id], isEmpty);
  });

  test('renaming keeps sessions, steps and dependencies attached', () async {
    final file = write(
      'SPEC-002-a.md',
      '---\nid: SPEC-002\nstatus: aprovada\ndepende-de: [SPEC-001]\n---\n'
          '# Importada\n\n## Requisitos\n- R1 · funcionar\n',
    );
    await service.sync(ws);
    final spec = (await repo.getByCode(ws.id, 'SPEC-002'))!;
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 'sess-1',
            workspaceId: ws.id,
            worktreePath: '/tmp/wt',
            branch: 'pr/SPEC-002',
            model: 'sonnet',
            specId: Value(spec.id),
            status: const Value(SessionStatus.completed),
          ),
        );
    await db
        .into(db.specSteps)
        .insert(
          SpecStepsCompanion.insert(
            specId: spec.id,
            step: 'R1',
            status: const Value(StepStatus.done),
            sessionId: const Value('sess-1'),
          ),
        );
    file.renameSync('${root.path}/specs/SPEC-002-renomeada.md');
    await service.sync(ws);
    await service.sync(ws);
    final rows = await db.select(db.specs).get();
    expect(rows.single.id, spec.id);
    expect(rows.single.path, 'specs/SPEC-002-renomeada.md');
    expect(rows.single.dependsOn, ['SPEC-001']);
    expect((await db.select(db.sessions).get()).single.specId, spec.id);
    final step = (await db.select(db.specSteps).get()).single;
    expect(step.specId, spec.id);
    expect(step.status, StepStatus.done);
  });

  test(
    'a failure between writing the file and the database recovers on sync',
    () async {
      write('SPEC-001.md', document('SPEC-001'));
      await service.sync(ws);
      final spec = (await repo.getByCode(ws.id, 'SPEC-001'))!;
      final failing = SpecService(_FailingRepo(db));
      await expectLater(
        failing.save(ws, spec, document('SPEC-001', status: 'concluida')),
        throwsA(isA<StateError>()),
      );
      expect(
        File('${root.path}/specs/SPEC-001.md').readAsStringSync(),
        contains('status: concluida'),
      );
      expect((await repo.getById(spec.id))!.stage, SpecStage.backlog);
      await service.sync(ws);
      final recovered = (await repo.getById(spec.id))!;
      expect(recovered.status, SpecStatus.done);
      expect(recovered.stage, SpecStage.done);
    },
  );

  test('watcher synchronizes files without starting an AI analysis', () async {
    var calls = 0;
    write('SPEC-001.md', document('SPEC-001', status: 'concluida'));
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        activeWorkspaceProvider.overrideWithValue(ws),
        verificationAgentProvider.overrideWithValue((
          ws,
          prompt,
          provider,
          token,
        ) async {
          calls++;
          return null;
        }),
      ],
    );
    final sub = c.listen(workspaceWatcherProvider, (_, _) {});
    Future<void> until(Future<bool> Function() predicate) async {
      for (var i = 0; i < 500; i++) {
        if (await predicate()) return;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      fail('Watcher did not synchronize');
    }

    try {
      await until(() async => await repo.getByCode(ws.id, 'SPEC-001') != null);
      write('SPEC-002.md', document('SPEC-002'));
      await until(() async => await repo.getByCode(ws.id, 'SPEC-002') != null);
      write('SPEC-002.md', document('SPEC-002', status: 'aprovada'));
      await until(
        () async =>
            (await repo.getByCode(ws.id, 'SPEC-002'))!.status ==
            SpecStatus.approved,
      );
      expect(calls, 0);
      expect(
        Directory('${root.path}/.promptorium/verifications').existsSync(),
        isFalse,
      );
    } finally {
      sub.close();
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
}
