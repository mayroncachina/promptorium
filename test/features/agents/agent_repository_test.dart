import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/agents/agent_file.dart';
import 'package:promptorium/features/agents/agent_repository.dart';
import 'package:promptorium/features/sessions/agent_names.dart';

void main() {
  late Directory tmp;
  late String home, ws;
  late AgentRepository repo;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-agents-');
    home = '${tmp.path}/home';
    ws = '${tmp.path}/ws';
    Directory(home).createSync();
    Directory(ws).createSync();
    repo = AgentRepository(home: home, workspacePath: ws);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('lists global and project agents; project overrides global', () async {
    write(
      '$home/.claude/agents/reviewer.md',
      '---\nname: reviewer\ndescription: global\nmodel: opus\n---\n',
    );
    write(
      '$home/.claude/agents/planner.md',
      '---\nname: planner\ndescription: g\n---\n',
    );
    write('$home/.claude/agents/broken.md', 'sem frontmatter');
    write(
      '$ws/.claude/agents/rev.md',
      '---\nname: reviewer\ndescription: projeto\npermissionMode: plan\nmaxTurns: 7\n---\n',
    );
    write('$ws/.claude/agents/notes.txt', 'x');

    final list = await repo.list();
    expect(list.map((e) => (e.name, e.scope.name)), [
      ('planner', 'global'),
      ('reviewer', 'global'),
      ('reviewer', 'project'),
    ]);
    expect(list[1].overriddenByProject, isTrue);
    expect(list[2].overridesGlobal, isTrue);
    expect(list[0].overriddenByProject, isFalse);

    final found = (await repo.find('reviewer'))!;
    expect(found.isProject, isTrue);
    expect(found.file.description, 'projeto');

    final refs = await listAgents(workspacePath: ws, home: home);
    expect(refs.map((r) => (r.name, r.project)), [
      ('planner', false),
      ('reviewer', true),
    ]);
    expect(refs[1].permissionMode, 'plan');
    expect(refs[1].maxTurns, 7);
  });

  test('save / rename / move / delete', () async {
    final f = AgentFile.create(name: 'tester', description: 'Testa');
    final p1 = await repo.save(f, AgentScope.project);
    expect(p1, '$ws/.claude/agents/tester.md');
    expect(File(p1).readAsStringSync(), f.serialize());

    // Same name elsewhere is an error; same file is fine.
    await expectLater(
      repo.save(f, AgentScope.project),
      throwsA(isA<AgentException>()),
    );
    expect(await repo.save(f, AgentScope.project, previousPath: p1), p1);

    // Rename: new file, old one removed.
    final p2 = await repo.save(
      f.withValue('name', 'unit-tester'),
      AgentScope.project,
      previousPath: p1,
    );
    expect(p2, '$ws/.claude/agents/unit-tester.md');
    expect(File(p1).existsSync(), isFalse);

    // Move to global.
    final p3 = await repo.save(
      AgentFile.parse(File(p2).readAsStringSync()),
      AgentScope.global,
      previousPath: p2,
    );
    expect(p3, '$home/.claude/agents/unit-tester.md');
    expect(File(p2).existsSync(), isFalse);
    expect((await repo.list()).single.scope, AgentScope.global);

    await repo.delete(p3);
    expect(await repo.list(), isEmpty);
  });

  test('a file whose name differs from <name>.md keeps its path', () async {
    write(
      '$ws/.claude/agents/Revisor.md',
      '---\nname: reviewer\ndescription: a\n---\n',
    );
    final e = (await repo.list()).single;
    final p = await repo.save(
      e.file.withValue('description', 'b'),
      AgentScope.project,
      previousPath: e.path,
    );
    expect(p, e.path);
    expect(File(p).readAsStringSync(), contains('description: b'));
  });

  test('validation', () async {
    await expectLater(
      repo.save(
        AgentFile.create(name: 'Com Espaço', description: 'x'),
        AgentScope.global,
      ),
      throwsA(isA<AgentException>()),
    );
    await expectLater(
      repo.save(
        AgentFile.create(name: 'ok', description: ' '),
        AgentScope.global,
      ),
      throwsA(isA<AgentException>()),
    );
    await expectLater(
      AgentRepository(home: home).save(
        AgentFile.create(name: 'ok', description: 'x'),
        AgentScope.project,
      ),
      throwsA(isA<AgentException>()),
    );
  });

  test('names cannot escape the agents dir nor overwrite another agent',
      () async {
    for (final bad in ['', ' ', '../evil', 'a/b', '..', '/abs', 'x/../y',
        'a\\b', '-flag', 'ok\n']) {
      await expectLater(
        repo.save(
          AgentFile.create(name: bad, description: 'x'),
          AgentScope.global,
        ),
        throwsA(isA<AgentException>()),
        reason: 'nome "$bad"',
      );
    }
    expect(Directory('$home/.claude/agents').existsSync(), isFalse);

    // Renaming onto an existing agent is refused and keeps both files.
    final a = await repo.save(
      AgentFile.create(name: 'alpha', description: 'A'),
      AgentScope.project,
    );
    final b = await repo.save(
      AgentFile.create(name: 'beta', description: 'B'),
      AgentScope.project,
    );
    final before = File(b).readAsStringSync();
    await expectLater(
      repo.save(
        AgentFile.parse(File(a).readAsStringSync()).withValue('name', 'beta'),
        AgentScope.project,
        previousPath: a,
      ),
      throwsA(isA<AgentException>()),
    );
    expect(File(a).existsSync(), isTrue);
    expect(File(b).readAsStringSync(), before);
  });

  test('MCP server names come from ~/.claude.json and .mcp.json', () async {
    write('$home/.claude.json', '''
{"mcpServers": {"youtrack": {"type": "http", "url": "x", "headers": {"Authorization": "secret"}}},
 "projects": {"$ws": {"mcpServers": {"local-db": {"command": "x"}}},
              "/outro": {"mcpServers": {"nao": {}}}}}
''');
    write('$ws/.mcp.json', '{"mcpServers": {"context7": {"command": "npx"}}}');
    expect(await readMcpServerNames(home: home, workspacePath: ws), [
      'context7',
      'local-db',
      'youtrack',
    ]);
    write('$ws/.mcp.json', '{inválido');
    expect(await readMcpServerNames(home: home), ['youtrack']);
  });
}
