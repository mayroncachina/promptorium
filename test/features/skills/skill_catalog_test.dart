import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/agents/agent_file.dart';
import 'package:promptorium/features/skills/skill_catalog.dart';
import 'package:promptorium/features/skills/skill_repository.dart';

import '../../core/git/repo_setup_test.dart' show gitRun;

void main() {
  late Directory tmp;
  late String remote;
  late SkillCatalog catalog;
  late SkillRepository mine;
  const repo = CatalogRepo('familia', 'skills');

  /// What a catalog maintainer does: commit [files] (path → text, null
  /// deletes) to the remote's main branch.
  Future<void> pushToRemote(Map<String, String?> files, String message) async {
    final work = '${tmp.path}/maintainer';
    if (!Directory(work).existsSync()) {
      await gitRun('git', ['clone', '-q', remote, work]);
      await gitRun('git', [
        '-C',
        work,
        'symbolic-ref',
        'HEAD',
        'refs/heads/main',
      ]);
    }
    files.forEach((path, text) {
      final f = File('$work/$path');
      if (text == null) {
        f.deleteSync();
      } else {
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(text);
      }
    });
    Future<void> git(List<String> args) async {
      final r = await gitRun('git', ['-C', work, ...args]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    await git(['add', '-A']);
    await git(['commit', '-q', '-m', message]);
    await git(['push', '-q', 'origin', 'HEAD:refs/heads/main']);
  }

  String skillMd(String name) =>
      '---\nname: $name\ndescription: Faz $name. Use quando precisar.\n---\n# $name\n';

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-skills-');
    remote = '${tmp.path}/remote.git';
    await Process.run('git', ['init', '-q', '--bare', '-b', 'main', remote]);
    catalog = SkillCatalog(
      baseDir: '${tmp.path}/catalogs',
      run: gitRun,
      urlFor: (_) => remote,
    );
    mine = SkillRepository(
      home: '${tmp.path}/home',
      workspacePath: '${tmp.path}/ws',
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<SkillEntry> createSkill(
    SkillRepository repo,
    String name, {
    AgentScope scope = AgentScope.project,
    String body = '# Passos\n',
  }) async {
    final dir = await repo.save(
      AgentFile.create(
        name: name,
        description: 'Faz $name. Use quando precisar.',
        body: body,
      ),
      scope,
    );
    File('$dir/apoio.md').writeAsStringSync('apoio de $name\n');
    return (await repo.load(dir, scope))!;
  }

  test(
    'repository: save, rename, copy between scopes, list and delete',
    () async {
      final e = await createSkill(mine, 'revisar-migration');
      expect(e.dir, '${tmp.path}/ws/.claude/skills/revisar-migration');
      expect(e.files, ['SKILL.md', 'apoio.md']);
      expect(e.origin, isNull);

      // Rename moves the folder (support files included).
      final renamed = await mine.save(
        e.file.withValue('name', 'migrations'),
        AgentScope.project,
        previousDir: e.dir,
      );
      expect(Directory(e.dir).existsSync(), isFalse);
      expect(File('$renamed/apoio.md').existsSync(), isTrue);

      final moved = (await mine.load(renamed, AgentScope.project))!;
      final global = await mine.copy(moved, AgentScope.global);
      expect(global, '${tmp.path}/home/.claude/skills/migrations');
      await expectLater(
        mine.copy(moved, AgentScope.global),
        throwsA(isA<SkillException>()),
      );
      expect((await mine.list()).map((s) => '${s.scope.name}:${s.name}'), [
        'project:migrations',
        'global:migrations',
      ]);

      await expectLater(
        mine.save(
          AgentFile.create(name: 'Nome Ruim', description: 'x'),
          AgentScope.project,
        ),
        throwsA(isA<SkillException>()),
      );
      await expectLater(
        mine.save(
          AgentFile.create(name: 'sem-descricao', description: ' '),
          AgentScope.project,
        ),
        throwsA(isA<SkillException>()),
      );
      await mine.delete(renamed);
      expect((await mine.list()).single.scope, AgentScope.global);
    },
  );

  test('hash ignores the origin file and dot files, follows content', () async {
    final e = await createSkill(mine, 'a');
    final h = e.hash;
    File('${e.dir}/$skillOriginFile').writeAsStringSync('{}');
    Directory('${e.dir}/.git').createSync();
    File('${e.dir}/.git/x').writeAsStringSync('y');
    expect(await skillHash(e.dir), h);
    File('${e.dir}/apoio.md').writeAsStringSync('mudou\n');
    expect(await skillHash(e.dir), isNot(h));
    expect(h, hasLength(16));
  });

  test('empty catalog, then skills upstream: listed, installed, updates and '
      'local changes told apart', () async {
    await catalog.sync(repo);
    var snap = await catalog.read(repo);
    expect(snap.cloned, isTrue);
    expect(snap.empty, isTrue);
    expect(snap.skills, isEmpty);
    expect(snap.syncedAt, isNotNull);

    await pushToRemote({
      'README.md': '# skills\n',
      'skills/commit-convencional/SKILL.md': skillMd('commit-convencional'),
      'skills/commit-convencional/apoio.md': 'v1\n',
      'skills/sem-skill-md/notas.md': 'ignorada\n',
    }, 'Primeira');
    await catalog.sync(repo);
    snap = await catalog.read(repo);
    expect(snap.empty, isFalse);
    final skill = snap.skills.single;
    expect(skill.name, 'commit-convencional');
    expect(skill.description, startsWith('Faz commit-convencional'));
    expect(skill.files, ['SKILL.md', 'apoio.md']);
    expect(skill.commit, snap.head);

    // Install globally: origin recorded, same hash as the catalog.
    final dir = await catalog.install(skill, repo, mine, AgentScope.global);
    expect(dir, '${tmp.path}/home/.claude/skills/commit-convencional');
    var installed = (await mine.load(dir, AgentScope.global))!;
    expect(installed.origin?.repo, 'familia/skills');
    expect(installed.origin?.path, 'skills/commit-convencional');
    expect(installed.origin?.hash, skill.hash);
    expect(installed.hasLocalChanges, isFalse);
    await expectLater(
      catalog.install(skill, repo, mine, AgentScope.global),
      throwsA(isA<SkillException>()),
    );

    // A new version upstream: an update, not a local change.
    await pushToRemote({
      'skills/commit-convencional/apoio.md': 'v2\n',
    }, 'Atualiza');
    await catalog.sync(repo);
    final newer = (await catalog.read(repo)).skills.single;
    installed = (await mine.load(dir, AgentScope.global))!;
    expect(newer.hash, isNot(installed.origin!.hash));
    expect(newer.commit, isNot(skill.commit));
    expect(installed.hasLocalChanges, isFalse);

    // Edited here: a local change.
    File('$dir/apoio.md').writeAsStringSync('meu\n');
    installed = (await mine.load(dir, AgentScope.global))!;
    expect(installed.hasLocalChanges, isTrue);

    // Updating replaces the folder with the catalog version.
    await catalog.install(
      newer,
      repo,
      mine,
      AgentScope.global,
      overwrite: true,
    );
    installed = (await mine.load(dir, AgentScope.global))!;
    expect(File('$dir/apoio.md').readAsStringSync(), 'v2\n');
    expect(installed.origin?.hash, newer.hash);
    expect(installed.hasLocalChanges, isFalse);
  });

  test(
    'both layouts: <name>/SKILL.md at the root and skills/<name>/',
    () async {
      await pushToRemote({
        'README.md': '# skills\n',
        'grill-me/SKILL.md': skillMd('grill-me'),
        'pick-ui-library/SKILL.md': skillMd('pick-ui-library'),
        'pick-ui-library/libs.md': 'lista\n',
        'skills/revisar/SKILL.md': skillMd('revisar'),
        // Same name in both places: skills/ wins.
        'revisar/SKILL.md': skillMd('outra'),
        'docs/notas.md': 'sem SKILL.md\n',
        '.github/SKILL.md': skillMd('oculta'),
      }, 'Skills');
      await catalog.sync(repo);
      final skills = (await catalog.read(repo)).skills;
      expect(skills.map((s) => '${s.name}@${s.path}'), [
        'grill-me@grill-me',
        'pick-ui-library@pick-ui-library',
        'revisar@skills/revisar',
      ]);
      expect(skills[1].files, ['SKILL.md', 'libs.md']);
      expect(skills.every((s) => s.commit.isNotEmpty), isTrue);

      final dir = await catalog.install(
        skills[0],
        repo,
        mine,
        AgentScope.project,
      );
      expect(dir, '${tmp.path}/ws/.claude/skills/grill-me');
      final e = (await mine.load(dir, AgentScope.project))!;
      expect(e.origin?.path, 'grill-me');
      expect(e.origin?.hash, skills[0].hash);
    },
  );

  test('sync resets leftovers in the clone (the clone is a cache)', () async {
    await pushToRemote({'skills/a/SKILL.md': skillMd('a')}, 'Primeira');
    await catalog.sync(repo);
    final clone = catalog.cloneDir(repo);
    File('$clone/skills/a/SKILL.md').writeAsStringSync('estragado');
    File('$clone/lixo.txt').writeAsStringSync('x');
    await catalog.sync(repo);
    expect(File('$clone/skills/a/SKILL.md').readAsStringSync(), skillMd('a'));
    expect(File('$clone/lixo.txt').existsSync(), isFalse);
    expect((await catalog.read(repo)).skills.single.name, 'a');
  });

  test('sync reports a repository that cannot be cloned', () async {
    final broken = SkillCatalog(
      baseDir: '${tmp.path}/catalogs2',
      run: gitRun,
      urlFor: (_) => '${tmp.path}/nao-existe.git',
    );
    await expectLater(
      broken.sync(repo),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.message,
          'message',
          startsWith('Não foi possível clonar familia/skills'),
        ),
      ),
    );
    expect((await broken.read(repo)).cloned, isFalse);
  });

  test('repository names: owner/name, URLs, rejects the rest', () {
    expect(
      CatalogRepo.parse('mayroncachina/promptorium-skills'),
      defaultCatalog,
    );
    expect(
      CatalogRepo.parse(
        'https://github.com/mayroncachina/promptorium-skills.git/',
      ),
      defaultCatalog,
    );
    expect(
      CatalogRepo.parse('git@github.com:mayroncachina/promptorium-skills.git'),
      defaultCatalog,
    );
    expect(CatalogRepo.parse('só-um-nome'), isNull);
    expect(CatalogRepo.parse('a/b/c'), isNull);
    expect(CatalogRepo.parse('a/..'), isNull);
    expect(CatalogRepo.parse('https://gitlab.com/a/b'), isNull);
  });
}
