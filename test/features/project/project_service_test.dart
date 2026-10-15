import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/repo_setup.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/project/project_service.dart';
import 'package:promptorium/features/specs/spec_file.dart';

import '../../core/git/git_test_utils.dart';
import '../../core/git/repo_setup_test.dart' show gitRun;
import '../../helpers/test_db.dart';

const plan = ProjectPlanData(
  vision: VisionPlan(summary: 'Receitas', mvp: ['Cadastro']),
  stack: StackPlan(
    decisions: [StackDecision(area: 'Banco', choice: 'SQLite')],
    claudeMd: '# Receitas\n\nUse SQLite.',
  ),
  roadmap: Roadmap(
    specs: [
      RoadmapSpec(
        title: 'Receitas',
        phase: RoadmapPhase.mvp,
        requirements: [(id: 'R1', text: 'CRUD')],
        tasks: [
          RoadmapTask(code: 'T3', title: 'CRUD de receitas', requirement: 'R1'),
        ],
      ),
      RoadmapSpec(
        title: 'Esqueleto do projeto',
        phase: RoadmapPhase.foundation,
        tasks: [
          RoadmapTask(code: 'T1', title: 'Criar o projeto'),
          RoadmapTask(code: 'T2', title: 'CI', dependsOn: ['T1']),
        ],
      ),
    ],
  ),
);

void main() {
  late Directory tmp;
  late ProviderContainer c;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-project-');
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        processRunnerProvider.overrideWithValue(gitRun),
        repoSetupProvider.overrideWithValue(RepoSetup(run: gitRun)),
      ],
    );
    await c.read(appSettingsProvider.notifier).load();
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  ProjectService service() => c.read(projectServiceProvider);

  test('createProject: folder + git repo with one commit, active workspace '
      'and an empty plan', () async {
    final ws = await service().createProject(
      parent: tmp.path,
      name: 'receitas',
      remoteUrl: 'git@example.com:familia/receitas.git',
    );
    final path = '${tmp.path}/receitas';
    expect(
      Directory(ws.path).resolveSymbolicLinksSync(),
      Directory(path).resolveSymbolicLinksSync(),
    );
    expect(await gitIn(path, ['rev-list', '--count', 'HEAD']), '1\n');
    expect(
      await gitIn(path, ['remote', 'get-url', 'origin']),
      'git@example.com:familia/receitas.git\n',
    );
    expect(
      c
          .read(appSettingsProvider.notifier)
          .getInt(AppSettingKeys.activeWorkspace),
      ws.id,
    );
    final row = await c.read(projectPlansRepoProvider).get(ws.id);
    expect(row?.step, 'vision');

    // An existing empty folder is reused.
    Directory('${tmp.path}/vazia').createSync();
    await service().createProject(parent: tmp.path, name: 'vazia');
    expect(Directory('${tmp.path}/vazia/.git').existsSync(), isTrue);
  });

  test('createProject rejects bad names and non-empty folders', () async {
    Future<void> bad(String parent, String name, String message) => expectLater(
      service().createProject(parent: parent, name: name),
      throwsA(
        isA<ProjectException>().having(
          (e) => e.message,
          'message',
          contains(message),
        ),
      ),
    );
    await bad(tmp.path, '', 'Informe o nome');
    await bad(tmp.path, 'a/b', 'Use só letras');
    await bad(tmp.path, '.oculta', 'Use só letras');
    await bad('relativo', 'x', 'Escolha onde');
    await bad('${tmp.path}/nao-existe', 'x', 'não existe');
    File('${tmp.path}/cheia/a.txt').createSync(recursive: true);
    await bad(tmp.path, 'cheia', 'não está vazia');
    File('${tmp.path}/arquivo').createSync();
    await bad(tmp.path, 'arquivo', 'Já existe um arquivo');
  });

  test('materialize: CLAUDE.md, approved specs, tasks with translated '
      'dependencies and one commit with exactly those files', () async {
    final ws = await service().createProject(
      parent: tmp.path,
      name: 'receitas',
    );
    File('${ws.path}/rascunho.txt').writeAsStringSync('não commitar');
    await c
        .read(projectPlansRepoProvider)
        .update(ws.id, ProjectPlansCompanion(data: Value(plan.encode())));

    final out = await service().materialize(ws);
    expect(out.commitError, isNull);
    expect(out.files, [
      'CLAUDE.md',
      'specs/SPEC-001-esqueleto-do-projeto.md',
      'specs/SPEC-002-receitas.md',
    ]);
    expect(
      File('${ws.path}/CLAUDE.md').readAsStringSync(),
      '# Receitas\n\nUse SQLite.\n',
    );
    final doc = SpecDocument.parse(
      File('${ws.path}/specs/SPEC-002-receitas.md').readAsStringSync(),
    );
    expect(doc.id, 'SPEC-002');
    expect(doc.requirements.single.id, 'R1');

    // Foundation first: T1 → TASK-001, T2 → TASK-002, T3 → TASK-003; the
    // MVP task waits for the whole foundation.
    final byCode = {for (final t in out.tasks) t.code: t};
    expect(byCode.keys, ['TASK-001', 'TASK-002', 'TASK-003']);
    expect(byCode['TASK-002']!.dependsOn, ['TASK-001']);
    expect(byCode['TASK-003']!.dependsOn, ['TASK-001', 'TASK-002']);
    expect(byCode['TASK-003']!.requirement, 'R1');
    expect(byCode['TASK-003']!.specId, out.specs[1].id);
    expect(out.firstTask?.code, 'TASK-001');

    expect(
      await gitIn(ws.path, ['log', '-1', '--format=%s']),
      '$planCommitMessage\n',
    );
    final committed = await gitIn(ws.path, [
      'show',
      '--name-only',
      '--format=',
      'HEAD',
    ]);
    expect(committed.trim().split('\n'), out.files);
    expect(
      await gitIn(ws.path, ['status', '--porcelain']),
      '?? rascunho.txt\n',
    );

    final row = (await c.read(projectPlansRepoProvider).get(ws.id))!;
    expect(row.materializedAt, isNotNull);
    expect(row.step, ProjectStep.create.name);
    await expectLater(
      service().materialize(ws),
      throwsA(isA<ProjectException>()),
    );
  });

  test('materialize without CLAUDE.md and without commit', () async {
    final ws = await service().createProject(parent: tmp.path, name: 'x');
    await c
        .read(projectPlansRepoProvider)
        .update(ws.id, ProjectPlansCompanion(data: Value(plan.encode())));
    final out = await service().materialize(
      ws,
      writeClaudeMd: false,
      commit: false,
    );
    expect(out.files, hasLength(2));
    expect(File('${ws.path}/CLAUDE.md').existsSync(), isFalse);
    expect(await gitIn(ws.path, ['rev-list', '--count', 'HEAD']), '1\n');
  });
}
