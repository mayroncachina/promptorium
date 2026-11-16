import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/project/stack_commands.dart';
import 'package:promptorium/features/project/stack_detect.dart';

void main() {
  test('the plan keeps the commands; an old plan reads them empty '
      '(SPEC-072 R11)', () {
    const cmds = StackCommands(
      install: 'test ! -f go.mod || go mod download',
      run: 'go run ./cmd/api',
      test: 'go test ./...',
      pinned: {'test'},
    );
    final plan = ProjectPlanData(stack: StackPlan(commands: cmds));
    final back = ProjectPlanData.decode(plan.encode());
    expect(back.stack.commands, cmds);
    expect(back.stack.commands.pinned, {'test'});

    final old = ProjectPlanData.decode(
      '{"stack":{"decisions":[],"claudeMd":"# x"}}',
    );
    expect(old.stack.commands.isEmpty, isTrue);
    expect(old.stack.commands.run, '');
  });

  test('the merge fills only the empty keys, adds {arquivo} to formatar and '
      'lists + and = lines (R13)', () {
    const config = ProjectConfig(
      baseBranch: 'main',
      testCommand: 'flutter test',
      lintCommand: 'flutter analyze',
    );
    const cmds = StackCommands(
      install: 'test ! -f pubspec.yaml || flutter pub get',
      run: 'flutter run -d linux',
      test: 'flutter test --coverage',
      format: 'dart format',
    );
    final m = mergeStackCommands(config, cmds);
    expect(m.config.testCommand, 'flutter test');
    expect(m.config.lintCommand, 'flutter analyze');
    expect(m.config.runCommand, 'flutter run -d linux');
    expect(m.config.formatCommand, 'dart format {arquivo}');
    expect(m.config.worktree.prepare, cmds.install);
    expect(m.config.dev, isNull);
    expect(m.config.baseBranch, 'main');
    expect(
      [for (final l in m.lines) '${l.mark} ${l.key}: ${l.value}'],
      [
        '= branch-base: main',
        '+ worktree.preparar: test ! -f pubspec.yaml || flutter pub get',
        '+ executar: flutter run -d linux',
        '= testes: flutter test',
        '= lint: flutter analyze',
        '+ formatar: dart format {arquivo}',
      ],
    );
    expect(m.lines.last.note, contains('{arquivo}'));
    expect((m.added, m.kept, m.changed), (3, 3, true));

    // dev becomes the short form of dev:.
    final dev = mergeStackCommands(
      const ProjectConfig(),
      const StackCommands(dev: 'air'),
    );
    expect(dev.config.dev?.command, 'air');
    expect(mergeStackCommands(config, const StackCommands()).changed, isFalse);
    expect(withFileArg('gofmt -w {arquivo}'), 'gofmt -w {arquivo}');
  });

  test('a template brings its commands pinned; a detection fills them '
      '(R11, R14)', () {
    const c = ProjectConfig(
      testCommand: 'pytest',
      worktree: WorktreeConfig(prepare: 'pip install -r requirements.txt'),
    );
    final t = commandsOfConfig(c);
    expect(t.test, 'pytest');
    expect(t.install, 'pip install -r requirements.txt');
    expect(t.pinned, {'install', 'test'});
    expect(configCommand(c, 'lint'), isNull);

    const d = StackDetection(
      name: 'Flutter',
      tests: 'flutter test',
      lint: 'flutter analyze',
      format: 'dart format {arquivo}',
      prepare: 'flutter pub get',
      evidence: ['pubspec.yaml'],
    );
    final filled = const StackCommands(test: 'flutter test -r expanded')
        .fillEmpty(commandsOfDetection(d));
    expect(filled.test, 'flutter test -r expanded');
    expect(filled.lint, 'flutter analyze');
    expect(filled.install, 'flutter pub get');
  });
}
