import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/process/shell_runner.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/project/project_config.dart';

import '../../core/git/git_test_utils.dart';

void main() {
  late Directory tmp;
  late String repo;
  late GitService git;
  late String start;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-gate-');
    repo = await createRepo(tmp);
    git = GitService(repo);
    start = (await git.headSha())!;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<GateReport> gate(
    ProjectConfig config, {
    List<String> steps = const ['R2'],
    String? from,
    bool noStart = false,
  }) => StepGate(git: git, shell: runShell).run(
    specCode: 'SPEC-003',
    steps: steps,
    startSha: noStart ? null : (from ?? start),
    config: config,
  );

  Future<void> commit(String file, String message) async {
    File('$repo/$file').writeAsStringSync('x\n');
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', message]);
  }

  test('no commit since the start → commit fails', () async {
    final r = await gate(const ProjectConfig(testCommand: 'true'));
    expect(r.ok, isFalse);
    expect(r.failures.single.name, 'commit');
    expect(r.failures.single.output, contains('Nenhum commit'));
    expect(r.checks.map((c) => c.name), ['commit', 'arvore', 'testes']);
  });

  test('commit with another prefix / step does not count', () async {
    await commit('b.txt', 'SPEC-003 R1: outra etapa');
    await commit('c.txt', 'ajustes R2');
    final r = await gate(const ProjectConfig(testCommand: 'true'));
    expect(r.failures.single.name, 'commit');
    expect(r.failures.single.output, contains('SPEC-003 R2'));
    expect(r.failures.single.output, contains('ajustes R2'));
  });

  test('right commit, clean tree, tests pass → ok; several steps in one '
      'commit', () async {
    await commit('b.txt', 'SPEC-003 R2, R3: extrair índices');
    final r = await gate(
      const ProjectConfig(testCommand: 'echo 3 testes ok', lintCommand: 'true'),
      steps: ['R2', 'R3'],
    );
    expect(r.ok, isTrue, reason: r.summary);
    expect(r.checks.map((c) => c.name), ['commit', 'arvore', 'testes', 'lint']);
    expect(r.checks[2].output, contains('3 testes ok'));
    final back = GateReport.decode(r.encode())!;
    expect(back.ok, isTrue);
    expect(back.checks.map((c) => c.command), [
      null,
      null,
      'echo 3 testes ok',
      'true',
    ]);
  });

  test('dirty tree → only that fails (Commitar o que sobrou)', () async {
    await commit('b.txt', 'SPEC-003 R2: feito');
    File('$repo/sobrou.txt').writeAsStringSync('x');
    final r = await gate(const ProjectConfig(testCommand: 'true'));
    expect(r.summary, 'árvore limpa');
    expect(r.onlyDirtyTree, isTrue);
    expect(r.failures.single.output, contains('sobrou.txt'));
    expect(await git.commitAll('SPEC-003 R2: arquivos restantes'), isTrue);
    expect((await gate(const ProjectConfig(testCommand: 'true'))).ok, isTrue);
    expect(await git.commitAll('nada'), isFalse);
  });

  test('failing test stops the commands; its output is kept; retry message '
      'names the steps', () async {
    await commit('b.txt', 'SPEC-003 R2: feito');
    final r = await gate(
      const ProjectConfig(
        testCommand: 'echo "FALHOU: teste_x"; exit 3',
        lintCommand: 'echo nunca',
      ),
    );
    expect(r.summary, 'testes');
    expect(r.checks.last.name, 'testes');
    expect(r.checks.last.output, contains('FALHOU: teste_x'));
    final msg = gateRetryMessage(r, ['R2']);
    expect(msg, contains('falhou: testes'));
    expect(msg, contains('FALHOU: teste_x'));
    expect(msg, endsWith('ETAPA CONCLUÍDA: R2'));
  });

  test('timeout kills the command and its children', () async {
    await commit('b.txt', 'SPEC-003 R2: feito');
    final watch = Stopwatch()..start();
    final r = await gate(
      const ProjectConfig(
        testCommand: 'sleep 30 & sleep 30; echo fim',
        verification: VerificationConfig(timeoutSeconds: 1),
      ),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    expect(r.ok, isFalse);
    expect(r.checks.last.output, contains('encerrado após 1 s'));
  });

  test('switches: no commit / clean tree required; unknown start', () async {
    File('$repo/sujo.txt').writeAsStringSync('x');
    final r = await gate(
      const ProjectConfig(
        verification: VerificationConfig(
          requireCommit: false,
          requireCleanTree: false,
        ),
      ),
    );
    expect(r.ok, isTrue);
    expect(r.checks, isEmpty);
    final unknown = await gate(
      const ProjectConfig(
        verification: VerificationConfig(requireCleanTree: false),
      ),
      noStart: true,
    );
    expect(unknown.ok, isTrue);
  });

  test('config: gate on only with a command or verificacao', () {
    expect(const ProjectConfig().gateEnabled, isFalse);
    expect(const ProjectConfig(testCommand: 'x').gateEnabled, isTrue);
    expect(const ProjectConfig(lintCommand: 'x').gateEnabled, isTrue);
    expect(
      ProjectConfig.parse('verificacao:\n  tentativas: 2\n').gateEnabled,
      isTrue,
    );
  });
}
