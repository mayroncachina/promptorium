import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/process/shell_runner.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/board/test_count.dart';
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
    TestCount? baseline,
  }) => StepGate(git: git, shell: runShell).run(
    specCode: 'SPEC-003',
    steps: steps,
    startSha: noStart ? null : (from ?? start),
    config: config,
    baseline: baseline,
  );

  /// `testes:` that prints [output] (a file, so quotes need no escaping).
  ProjectConfig printing(String output, {String? lint, bool count = true}) {
    final f = File('${tmp.path}/saida-${output.hashCode}.txt')
      ..writeAsStringSync(output);
    return ProjectConfig(
      testCommand: 'cat ${f.path}',
      lintCommand: lint,
      verification: VerificationConfig(countTests: count),
    );
  }

  GateCheck check(GateReport r, String name) =>
      r.checks.firstWhere((c) => c.name == name);

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
    expect(r.checks.map((c) => c.name), [
      'commit',
      'arvore',
      'testes',
      'contagem',
    ]);
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
    expect(r.checks.map((c) => c.name), [
      'commit',
      'arvore',
      'testes',
      'contagem',
      'lint',
    ]);
    expect(r.checks[2].output, contains('3 testes ok'));
    final back = GateReport.decode(r.encode())!;
    expect(back.ok, isTrue);
    expect(back.checks.map((c) => c.command), [
      null,
      null,
      'echo 3 testes ok',
      null,
      'true',
    ]);
  });

  group('test count (SPEC-023)', () {
    // A long run: the summary is past the 20 lines the report keeps.
    final flutterRun = [
      for (var i = 1; i <= 40; i++)
        '00:${i.toString().padLeft(2, '0')} +$i: t$i',
      '00:45 +9: All tests passed!',
    ].join('\n');

    test('R1: the count of the testes check is parsed from the whole output '
        'and survives encode / decode', () async {
      await commit('b.txt', 'SPEC-003 R2: feito');
      final r = await gate(printing(flutterRun));
      expect(r.ok, isTrue, reason: r.summary);
      final t = check(r, 'testes');
      expect(t.output, startsWith('…'));
      expect(t.count, const TestCount(passed: 9));
      final back = GateReport.decode(r.encode())!;
      expect(back.testCount, const TestCount(passed: 9));
      expect(check(back, 'contagem').label, 'contagem de testes');
    });

    test('R2: fewer passing than the baseline fails "contagem de testes" '
        'with before and after; the next commands still run', () async {
      await commit('b.txt', 'SPEC-003 R2: feito');
      final r = await gate(
        printing(flutterRun, lint: 'echo lint ok'),
        baseline: const TestCount(passed: 10),
      );
      expect(r.ok, isFalse);
      expect(r.summary, 'contagem de testes');
      expect(r.onlyTestCount, isTrue);
      expect(
        r.failures.single.output,
        'antes: 10 passaram, 0 pulados · depois: 9 passaram, 0 pulados',
      );
      expect(r.checks.last.name, 'lint');
      expect(r.checks.last.ok, isTrue);
      expect(gateRetryMessage(r, ['R2']), contains('antes: 10 passaram'));
    });

    test('R2: one more skipped than the baseline fails; same or more passing '
        'passes', () async {
      await commit('b.txt', 'SPEC-003 R2: feito');
      const pytest = '==== 12 passed, 1 skipped in 0.30s ====';
      final skipped = await gate(
        printing(pytest),
        baseline: const TestCount(passed: 12),
      );
      expect(skipped.onlyTestCount, isTrue);
      expect(
        skipped.failures.single.output,
        contains('depois: 12 passaram, 1 pulados'),
      );
      final more = await gate(
        printing('test result: ok. 13 passed; 0 failed; 0 ignored;'),
        baseline: const TestCount(passed: 12),
      );
      expect(more.ok, isTrue, reason: more.summary);
    });

    test('R3: another failure with the count → not only the count', () async {
      await commit('b.txt', 'SPEC-003 R2: feito');
      final r = await gate(
        printing(flutterRun, lint: 'echo erro; exit 1'),
        baseline: const TestCount(passed: 10),
      );
      expect(r.failures.map((c) => c.name), ['contagem', 'lint']);
      expect(r.onlyTestCount, isFalse);
      expect(r.onlyDirtyTree, isFalse);
    });

    test('R4: no baseline, or no summary → passes, "contagem não conferida" '
        'with the reason', () async {
      await commit('b.txt', 'SPEC-003 R2: feito');
      final first = await gate(printing(flutterRun));
      expect(first.ok, isTrue);
      expect(
        check(first, 'contagem').output,
        startsWith('contagem não conferida: a spec não tem gate aprovado'),
      );
      expect(check(first, 'contagem').output, contains('9 passaram'));
      final none = await gate(
        printing('tudo certo'),
        baseline: const TestCount(passed: 10),
      );
      expect(none.ok, isTrue);
      expect(none.testCount, isNull);
      expect(
        check(none, 'contagem').output,
        contains('não tem um resumo reconhecido'),
      );
    });

    test('R5: contar-testes: nao → no count item at all', () async {
      await commit('b.txt', 'SPEC-003 R2: feito');
      final r = await gate(
        printing(flutterRun, count: false),
        baseline: const TestCount(passed: 100),
      );
      expect(r.ok, isTrue);
      expect(r.checks.map((c) => c.name), ['commit', 'arvore', 'testes']);
    });
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

  test(
    'this repository runs analyze and the suite in the gate (SPEC-017 R1)',
    () {
      expect(
        ProjectConfig.loadSync(Directory.current.path).testCommand,
        'flutter analyze && flutter test',
      );
    },
  );
}
