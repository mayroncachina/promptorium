import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/git/repo_setup.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/project/project_service.dart';
import 'package:promptorium/features/project/project_templates.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/specs/spec_service.dart';

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
        code: 'S3',
        title: 'Receitas',
        phase: RoadmapPhase.mvp,
        requirements: [(id: 'R1', text: 'CRUD'), (id: 'R2', text: 'Fotos')],
        dependsOn: ['S2'],
      ),
      RoadmapSpec(
        code: 'S1',
        title: 'Esqueleto do projeto',
        phase: RoadmapPhase.foundation,
        requirements: [(id: 'R1', text: 'Criar o projeto')],
      ),
      RoadmapSpec(
        code: 'S2',
        title: 'CI',
        phase: RoadmapPhase.foundation,
        requirements: [(id: 'R1', text: 'Pipeline')],
        dependsOn: ['S1'],
      ),
    ],
  ),
);

/// Fails the [failAt]-th creation (1-based) while [failAt] is set.
class _FlakySpecService extends SpecService {
  _FlakySpecService(super.repo);

  int? failAt;
  var calls = 0;

  @override
  Future<Spec> create(
    Workspace ws, {
    required String title,
    String? body,
    String Function(String code)? render,
    String? agentSession,
    bool inTray = true,
  }) {
    if (++calls == failAt) throw const SpecException('disco cheio');
    return super.create(
      ws,
      title: title,
      body: body,
      render: render,
      agentSession: agentSession,
      inTray: inTray,
    );
  }
}

void main() {
  late Directory tmp;
  late ProviderContainer c;
  late List<String> trashed;
  var trashFails = false;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-project-');
    trashed = [];
    trashFails = false;
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        processRunnerProvider.overrideWithValue(gitRun),
        repoSetupProvider.overrideWithValue(RepoSetup(run: gitRun)),
        gitServiceFactoryProvider.overrideWithValue(
          (root) =>
              GitService(root, run: gitRun, worktreesBase: '${tmp.path}/wt'),
        ),
        trashFolderProvider.overrideWithValue((path) async {
          if (trashFails) throw const ProjectException('sem lixeira');
          trashed.add(path);
          await Directory(path).rename('${tmp.path}/lixeira');
        }),
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

  test('createProject with a template commits config.yml and CLAUDE.md; '
      'plan: false starts no plan (UX v2, U7)', () async {
    final ws = await service().createProject(
      parent: tmp.path,
      name: 'app',
      template: templateById('flutter'),
      plan: false,
    );
    final path = '${tmp.path}/app';
    expect(ProjectConfig.loadSync(path).testCommand, 'flutter test');
    expect(
      ProjectConfig.loadSync(path).worktree.prepare,
      'test ! -f pubspec.yaml || flutter pub get',
    );
    expect(File('$path/CLAUDE.md').readAsStringSync(), contains('Flutter'));
    // Both files are in the initial commit.
    expect(
      await gitIn(path, ['ls-tree', '--name-only', '-r', 'HEAD']),
      contains('.promptorium/config.yml'),
    );
    expect(await c.read(projectPlansRepoProvider).get(ws.id), isNull);

    // With a plan: the template's choices are pinned for the planner.
    final ws2 = await service().createProject(
      parent: tmp.path,
      name: 'app2',
      template: templateById('flutter'),
    );
    final row = await c.read(projectPlansRepoProvider).get(ws2.id);
    final data = ProjectPlanData.decode(row!.data);
    expect(data.stack.decisions.map((d) => d.choice), ['Flutter', 'Riverpod']);
    expect(data.stack.decisions.every((d) => d.pinned), isTrue);

    // "Vazio" writes nothing extra.
    await service().createProject(
      parent: tmp.path,
      name: 'vazio2',
      template: templateById('empty'),
      plan: false,
    );
    expect(File('${tmp.path}/vazio2/CLAUDE.md').existsSync(), isFalse);
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

  test('createProject without a git identity creates nothing and says how '
      'to configure it; a folder left by a failed creation is accepted on '
      'retry, on branch main (SPEC-071 R21, R25)', () async {
    final home = Directory('${tmp.path}/home')..createSync();
    Future<ProcessResult> noIdentity(String exe, List<String> args) =>
        Process.run(
          exe,
          args,
          includeParentEnvironment: false,
          environment: {
            'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
            'HOME': home.path,
            'XDG_CONFIG_HOME': home.path,
            'GIT_CONFIG_NOSYSTEM': '1',
            'GIT_TERMINAL_PROMPT': '0',
            'GIT_CONFIG_COUNT': '1',
            'GIT_CONFIG_KEY_0': 'user.useConfigOnly',
            'GIT_CONFIG_VALUE_0': 'true',
          },
        );
    final local = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        processRunnerProvider.overrideWithValue(noIdentity),
        repoSetupProvider.overrideWithValue(RepoSetup(run: noIdentity)),
      ],
    );
    addTearDown(local.dispose);
    await local.read(appSettingsProvider.notifier).load();
    await expectLater(
      local
          .read(projectServiceProvider)
          .createProject(parent: tmp.path, name: 'sem-git'),
      throwsA(
        isA<ProjectException>().having(
          (e) => e.message,
          'message',
          allOf(contains('git config --global user.email'), contains('nome')),
        ),
      ),
    );
    expect(Directory('${tmp.path}/sem-git').existsSync(), isFalse);

    // What an older failure left: .git without commits and template files.
    final left = '${tmp.path}/sobra';
    await gitIn(tmp.path, ['init', '-q', left]);
    File('$left/CLAUDE.md').writeAsStringSync('# modelo\n');
    await ProjectConfig.save(left, templateById('flutter').config);
    final ws = await service().createProject(
      parent: tmp.path,
      name: 'sobra',
      template: templateById('flutter'),
    );
    expect(await gitIn(ws.path, ['rev-list', '--count', 'HEAD']), '1\n');
    expect(await gitIn(ws.path, ['branch', '--show-current']), 'main\n');

    // A folder with a real repository (commits) is still refused.
    await expectLater(
      service().createProject(parent: tmp.path, name: 'sobra'),
      throwsA(isA<ProjectException>()),
    );
  });

  test('materialize: CLAUDE.md, approved specs with translated '
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
      'specs/SPEC-002-ci.md',
      'specs/SPEC-003-receitas.md',
    ]);
    expect(
      File('${ws.path}/CLAUDE.md').readAsStringSync(),
      '# Receitas\n\nUse SQLite.\n',
    );
    SpecDocument read(String name) => SpecDocument.parse(
      File('${ws.path}/specs/$name.md').readAsStringSync(),
    );
    final base = read('SPEC-001-esqueleto-do-projeto');
    expect(base.id, 'SPEC-001');
    expect(base.status, SpecStatus.approved);
    expect(base.dependsOn, isEmpty);
    expect(read('SPEC-002-ci').dependsOn, ['SPEC-001']);
    final recipes = read('SPEC-003-receitas');
    expect(recipes.requirements.map((r) => r.id), ['R1', 'R2']);
    // The MVP spec depended on S2; the foundation rule keeps it there.
    expect(recipes.dependsOn, ['SPEC-002']);

    // Specs are cards of the Quadro: in the database with their steps and
    // dependencies, no tasks.
    final rows = await c.read(specsRepoProvider).watchByWorkspace(ws.id).first;
    expect(
      rows.map(
        (r) => '${r.code} ${r.dependsOn.join(',')} ${r.requirements.length}',
      ),
      ['SPEC-001  1', 'SPEC-002 SPEC-001 1', 'SPEC-003 SPEC-002 2'],
    );
    expect(
      await c.read(tasksRepoProvider).watchByWorkspace(ws.id).first,
      isEmpty,
    );
    expect(out.firstSpec?.code, 'SPEC-001');

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

  test('materialize puts every spec on the Quadro (not in the Bandeja), and '
      'a retry after a failure halfway does not duplicate them (SPEC-071 '
      'R22)', () async {
    late _FlakySpecService flaky;
    final local = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        processRunnerProvider.overrideWithValue(gitRun),
        repoSetupProvider.overrideWithValue(RepoSetup(run: gitRun)),
        gitServiceFactoryProvider.overrideWithValue(
          (root) => GitService(root, run: gitRun),
        ),
        specServiceProvider.overrideWith(
          (ref) => flaky = _FlakySpecService(ref.watch(specsRepoProvider)),
        ),
      ],
    );
    addTearDown(local.dispose);
    await local.read(appSettingsProvider.notifier).load();
    final svc = local.read(projectServiceProvider);
    final ws = await svc.createProject(parent: tmp.path, name: 'quadro');
    await local
        .read(projectPlansRepoProvider)
        .update(ws.id, ProjectPlansCompanion(data: Value(plan.encode())));

    local.read(specServiceProvider);
    flaky.failAt = 3;
    await expectLater(svc.materialize(ws), throwsA(isA<SpecException>()));
    final half = await local
        .read(specsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    expect(half, hasLength(2));

    flaky.failAt = null;
    final out = await svc.materialize(ws);
    final rows = await local
        .read(specsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    expect(rows.map((r) => r.code), ['SPEC-001', 'SPEC-002', 'SPEC-003']);
    expect(out.specs.map((s) => s.code), ['SPEC-001', 'SPEC-002', 'SPEC-003']);
    expect(rows.every(isOnBoard), isTrue);
    expect(rows.any((r) => r.inTray), isFalse);
    expect(rows.singleWhere((r) => r.code == 'SPEC-003').dependsOn, [
      'SPEC-002',
    ]);
    expect(
      Directory('${ws.path}/specs').listSync().map((f) => f.path).length,
      3,
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
    expect(out.files, hasLength(3));
    expect(File('${ws.path}/CLAUDE.md').existsSync(), isFalse);
    expect(await gitIn(ws.path, ['rev-list', '--count', 'HEAD']), '1\n');
  });

  test('deleteProject: worktrees removed, folder to the trash, everything '
      'the app kept about it gone', () async {
    final ws = await service().createProject(
      parent: tmp.path,
      name: 'receitas',
    );
    await c
        .read(projectPlansRepoProvider)
        .update(ws.id, ProjectPlansCompanion(data: Value(plan.encode())));
    await service().materialize(ws);
    final wt = await c
        .read(gitServiceFactoryProvider)(ws.path)
        .addWorktree('x');
    await c
        .read(sessionsRepoProvider)
        .insert(
          id: 's1',
          workspaceId: ws.id,
          worktreePath: wt.path,
          branch: wt.branch,
          model: 'haiku',
        );
    final summary = await service().deleteSummary(ws);
    expect(summary, (sessions: 1, tasks: 0, specs: 3, worktrees: 1));

    await service().deleteProject(ws);
    expect(trashed, [ws.path]);
    expect(Directory(ws.path).existsSync(), isFalse);
    expect(File('${tmp.path}/lixeira/CLAUDE.md').existsSync(), isTrue);
    expect(Directory(wt.path).existsSync(), isFalse);
    expect(await c.read(workspacesRepoProvider).getById(ws.id), isNull);
    expect(await c.read(projectPlansRepoProvider).get(ws.id), isNull);
    expect(await c.read(sessionsRepoProvider).getById('s1'), isNull);
    expect(
      await c.read(tasksRepoProvider).watchByWorkspace(ws.id).first,
      isEmpty,
    );
    expect(
      c
          .read(appSettingsProvider.notifier)
          .getInt(AppSettingKeys.activeWorkspace),
      isNull,
    );
  });

  test('deleteProject keeps everything when the trash fails, and refuses '
      'unsafe folders', () async {
    final ws = await service().createProject(parent: tmp.path, name: 'x');
    trashFails = true;
    await expectLater(
      service().deleteProject(ws),
      throwsA(isA<ProjectException>()),
    );
    expect(Directory(ws.path).existsSync(), isTrue);
    expect(await c.read(workspacesRepoProvider).getById(ws.id), isNotNull);

    expect(isUnsafeProjectPath('/', home: '/home/u'), isTrue);
    expect(isUnsafeProjectPath('/home', home: '/home/u'), isTrue);
    expect(isUnsafeProjectPath('/home/u', home: '/home/u'), isTrue);
    expect(isUnsafeProjectPath('/home/u/', home: '/home/u'), isTrue);
    expect(isUnsafeProjectPath('relativo/x', home: '/home/u'), isTrue);
    expect(isUnsafeProjectPath('/srv', home: '/home/u'), isTrue);
    expect(
      isUnsafeProjectPath('/home/u/workspace/app', home: '/home/u'),
      isFalse,
    );
    expect(isUnsafeProjectPath('/srv/app', home: '/home/u'), isFalse);
  });
}
