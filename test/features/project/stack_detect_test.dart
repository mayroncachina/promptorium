import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/project/project_memory.dart';
import 'package:promptorium/features/project/stack_detect.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('promptorium-stack-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('detects Flutter, Node (pnpm), Python (ruff) and unknown', () async {
    File('${tmp.path}/pubspec.yaml').writeAsStringSync(
      'name: x\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    var d = await detectStack(tmp.path);
    expect(d.name, 'Flutter');
    expect(d.tests, 'flutter test');
    expect(d.format, 'dart format {arquivo}');
    expect(d.evidence, ['pubspec.yaml']);
    File('${tmp.path}/pubspec.yaml').deleteSync();

    File('${tmp.path}/package.json').writeAsStringSync(
      '{"scripts":{"test":"vitest","lint":"eslint ."},'
      '"devDependencies":{"prettier":"3"}}',
    );
    File('${tmp.path}/pnpm-lock.yaml').writeAsStringSync('');
    d = await detectStack(tmp.path);
    expect(d.name, 'Node.js');
    expect(d.tests, 'pnpm test');
    expect(d.lint, 'pnpm run lint');
    expect(d.format, 'npx prettier --write {arquivo}');
    expect(d.prepare, 'pnpm install');
    File('${tmp.path}/package.json').deleteSync();
    File('${tmp.path}/pnpm-lock.yaml').deleteSync();

    File('${tmp.path}/pyproject.toml')
        .writeAsStringSync('[tool.poetry]\nname="x"\n[tool.ruff]\n');
    d = await detectStack(tmp.path);
    expect(d.name, 'Python');
    expect(d.lint, 'ruff check .');
    expect(d.prepare, 'poetry install');
    File('${tmp.path}/pyproject.toml').deleteSync();

    d = await detectStack(tmp.path);
    expect(d.isUnknown, isTrue);
    expect(d.summary, 'Desconhecida');
  });

  test('applyDetection fills only the empty fields; the workspace gets '
      'the config and a memory line', () async {
    const d = StackDetection(
      name: 'Flutter',
      tests: 'flutter test',
      lint: 'flutter analyze',
      format: 'dart format {arquivo}',
      prepare: 'flutter pub get',
    );
    final (c1, changed1) = applyDetection(
      const ProjectConfig(testCommand: 'make check'),
      d,
    );
    expect(changed1, isTrue);
    expect(c1.testCommand, 'make check'); // kept
    expect(c1.lintCommand, 'flutter analyze');
    expect(c1.worktree.prepare, 'flutter pub get');
    final (_, changed2) = applyDetection(c1, d);
    expect(changed2, isFalse);

    expect(await applyDetectionToWorkspace(tmp.path, d), isTrue);
    final saved = ProjectConfig.loadSync(tmp.path);
    expect(saved.testCommand, 'flutter test');
    expect(saved.formatCommand, 'dart format {arquivo}');
    final mem = ProjectMemory.loadSync(tmp.path);
    expect(mem.entries.single.origin, 'análise');
    expect(mem.entries.single.text, startsWith('Stack detectada: Flutter'));
    // Running again replaces the line instead of adding another.
    await applyDetectionToWorkspace(tmp.path, d);
    expect(ProjectMemory.loadSync(tmp.path).entries, hasLength(1));
  });
}
