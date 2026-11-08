import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/process/shell_runner.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/board/test_count.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/review/conflict_resolution.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/review/restack.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../board/spec_runner_test.dart' as steps_test show resultLine;
import '../sessions/session_test_utils.dart';
import 'review_service_test.dart' show FakeCommands;

const _spec = '''---
id: SPEC-001
status: aprovada
---

# Extração

## Requisitos

- R1 · Tabelas

## Critérios de aceite

- [ ] As tabelas saem [R1] verificar: true
- [ ] Confere à mão [R1] verificar: manual (olhar a tela)
''';

/// `git` that may fail (a merge with conflicts exits 1).
Future<ProcessResult> _git(String dir, List<String> args) =>
    Process.run('git', ['-C', dir, ...args]);

String _replaceLine(String path, String from, String to) {
  final f = File(path);
  f.writeAsStringSync(f.readAsStringSync().replaceFirst('$from\n', '$to\n'));
  return path;
}

/// A spec in Review whose branch conflicts with `main` in `a.txt`.
class Env {
  Env(
    this.c,
    this.cli,
    this.notifier,
    this.ws,
    this.specId,
    this.sessionId,
    this.wt,
    this.repo,
  );

  final ProviderContainer c;
  final FakeCli cli;
  final FakeNotifier notifier;
  final Workspace ws;
  final int specId;
  final String sessionId;
  final String wt;
  final String repo;

  ReviewService get review => c.read(reviewServiceProvider);
  ConflictResolver get resolver => c.read(conflictResolverProvider);
  ConflictResolution? get resolution => resolver.get(sessionId);
  String get lastMessage =>
      cli.last.writtenJson.last['message']['content'] as String;

  Future<void> agentAnswers(String text) async {
    cli.last.emit(steps_test.resultLine(text));
    await settle();
  }

  Future<ConflictResolution> settled() async {
    await until(() async {
      final r = resolution;
      return r != null && !r.state.active;
    });
    return resolution!;
  }

  /// The agent merges `main` and keeps [result] in line 5.
  Future<String> agentMerges(String result) async {
    await _git(wt, ['merge', 'main']);
    final f = File('$wt/a.txt');
    final lines = f.readAsStringSync().split('\n');
    final start = lines.indexWhere((l) => l.startsWith('<<<<<<<'));
    final end = lines.indexWhere((l) => l.startsWith('>>>>>>>'));
    lines.replaceRange(start, end + 1, [result]);
    f.writeAsStringSync(lines.join('\n'));
    await gitIn(wt, ['add', 'a.txt']);
    await gitIn(wt, ['commit', '-q', '--no-edit']);
    return (await gitIn(wt, ['rev-parse', 'HEAD'])).trim();
  }
}

void main() {
  group('pure', () {
    test('parseHowResolved reads one line per file; null without the '
        'section', () {
      final how = parseHowResolved(
        'Pronto, juntei os dois lados.\n\n## Como resolvi\n'
        '- `lib/a.dart`: mantive a família da main e o filtro da spec\n'
        'b.txt: fiquei com a versão da spec\n\n## Testes\n- ok',
      )!;
      expect(how.files, {
        'lib/a.dart': 'mantive a família da main e o filtro da spec',
        'b.txt': 'fiquei com a versão da spec',
      });
      expect(how.explain('lib/a.dart'), contains('família'));
      expect(how.explain('docs/b.txt'), 'fiquei com a versão da spec');
      expect(how.section, isNot(contains('Testes')));
      expect(parseHowResolved('Resolvi tudo e rodei os testes.'), isNull);
      expect(parseHowResolved(null), isNull);
    });

    test('parseResolutionDiff takes both sides and the result of each '
        'stretch', () {
      const diff = '''
diff --git a/a.txt b/a.txt
index 1111111..2222222 100644
--- a/a.txt
+++ b/a.txt
@@ -3,9 +3,7 @@ linha 2
 linha 3
 linha 4
-<<<<<<< 1234567 (spec)
-linha 5 spec
-=======
-linha 5 main
->>>>>>> 89abcde (main)
+linha 5 main e spec
+comentário
 linha 6
@@ -20,5 +18,3 @@
-<<<<<<< 1234567 (spec)
-x
-=======
-y
->>>>>>> 89abcde (main)
+y
''';
      final hunks = parseResolutionDiff(diff, firstIsBase: false);
      expect(hunks, hasLength(2));
      expect(hunks.first.path, 'a.txt');
      expect(hunks.first.spec, ['linha 5 spec']);
      expect(hunks.first.base, ['linha 5 main']);
      expect(hunks.first.result, ['linha 5 main e spec', 'comentário']);
      expect(hunks.first.line, 5);
      expect(hunks.last.spec, ['x']);
      expect(hunks.last.base, ['y']);
      expect(hunks.last.result, ['y']);
      // Base first (merge-tree of base and spec).
      final swapped = parseResolutionDiff(diff, firstIsBase: true);
      expect(swapped.first.base, ['linha 5 spec']);
    });

    test('the resolution round-trips through the app settings', () {
      final r = ConflictResolution(
        state: ResolutionState.reprovada,
        workspaceId: 3,
        files: const ['a.txt'],
        origin: ResolutionOrigin.automatic,
        beforeSha: 'abc',
        report: GateReport(
          at: DateTime(2026),
          checks: const [GateCheck(name: 'testes', ok: false)],
        ),
        autoFixUsed: true,
        approvedCount: const TestCount(passed: 4),
      );
      final back = ConflictResolution.decode(r.encode())!;
      expect(back.state, ResolutionState.reprovada);
      expect(back.files, ['a.txt']);
      expect(back.automatic, isTrue);
      expect(back.autoFixUsed, isTrue);
      expect(back.approvedCount, const TestCount(passed: 4));
      expect(back.text, 'Resolução reprovada no gate · testes');
      expect(ConflictResolution.decode('lixo'), isNull);
    });

    test('every conflict message asks for ## Como resolvi (R8)', () {
      expect(conflictMessage('main'), contains('## Como resolvi'));
      expect(
        restackMessage(branch: 'pr/x', base: 'main', files: const ['a']),
        contains('`caminho: o que foi mantido de cada lado`'),
      );
    });

    test('verificar: of every criterion except the manual ones', () {
      expect(resolutionVerifyCommands(_spec), ['true']);
    });
  });

  group('StepGate.runResolution (R1)', () {
    late Directory tmp;
    late String repo;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-resolucao-');
      repo = await createRepo(tmp);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    StepGate gate() => StepGate(git: GitService(repo), shell: runShell);

    test('order of the items; a forgotten marker fails it and stops', () async {
      const config = ProjectConfig(testCommand: 'echo "3 passed in 0.1s"');
      expect(StepGate.resolutionPlan(config, verifyCount: 1), [
        'arvore',
        'marcadores',
        'base',
        'testes',
        'verificar',
        'contagem',
      ]);
      final base = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
      File('$repo/a.txt')
          .writeAsStringSync('<<<<<<< HEAD\na\n=======\nb\n>>>>>>> x\n');
      await gitIn(repo, ['commit', '-qam', 'esqueci']);
      final seen = <String>[];
      final r = await gate().runResolution(
        files: const ['a.txt'],
        baseSha: base,
        config: config,
        onProgress: (name, _) => seen.add(name),
      );
      expect(r.ok, isFalse);
      expect(r.failures.single.name, 'marcadores');
      expect(r.failures.single.output, contains('a.txt: 3 marcador(es)'));
      expect(r.checks.map((c) => c.name), ['arvore', 'marcadores']);
      expect(seen, ['arvore', 'marcadores']);
    });

    test('a branch without the tip of the base fails it', () async {
      await gitIn(repo, ['checkout', '-qb', 'outra']);
      await gitIn(repo, ['checkout', '-q', 'main']);
      File('$repo/b.txt').writeAsStringSync('b\n');
      await gitIn(repo, ['add', '.']);
      await gitIn(repo, ['commit', '-qm', 'main andou']);
      final tip = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
      await gitIn(repo, ['checkout', '-q', 'outra']);
      final r = await gate().runResolution(
        files: const ['a.txt'],
        baseSha: tip,
        config: const ProjectConfig(),
      );
      expect(r.failures.single.name, 'base');
      expect(r.failures.single.output, contains(tip));
    });

    test('the test count is compared with the baseline, after the other '
        'commands', () async {
      final base = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
      final r = await gate().runResolution(
        files: const ['a.txt'],
        baseSha: base,
        config: const ProjectConfig(testCommand: 'echo "3 passed in 0.1s"'),
        extraCommands: const ['true'],
        baseline: const TestCount(passed: 5),
      );
      expect(r.checks.map((c) => c.name), [
        'arvore',
        'marcadores',
        'base',
        'testes',
        'verificar',
        'contagem',
      ]);
      expect(r.failures.single.name, 'contagem');
      expect(r.testCount, const TestCount(passed: 3));
    });
  });

  group('resolution in a real repository', () {
    late Directory tmp;
    late String repo;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-resolucao-spec-');
      repo = await createRepo(tmp);
      Directory('$repo/specs').createSync();
      File('$repo/specs/SPEC-001-extracao.md').writeAsStringSync(_spec);
      await gitIn(repo, ['add', '.']);
      await gitIn(repo, ['commit', '-q', '-m', 'spec']);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    Future<Env> setUpEnv({String config = ''}) async {
      final cli = FakeCli();
      final notifier = FakeNotifier();
      final c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: notifier,
          worktreesBase: '${tmp.path}/wt',
        ),
        commandRunnerProvider.overrideWithValue(FakeCommands().call),
      ]);
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      await c.read(specServiceProvider).sync(ws);
      final spec = (await c
          .read(specsRepoProvider)
          .getByCode(ws.id, 'SPEC-001'))!;
      await c.read(specRunnerProvider).runNext(spec.id);
      await settle();
      final wt = (await c.read(specsRepoProvider).getById(spec.id))!
          .worktreePath!;
      _replaceLine('$wt/a.txt', 'linha 5', 'linha 5 spec');
      await gitIn(wt, ['commit', '-qam', 'SPEC-001 R1: tabelas']);
      cli.last.emit(steps_test.resultLine('ETAPA CONCLUÍDA: R1'));
      await until(
        () async =>
            (await c.read(specsRepoProvider).getById(spec.id))!.stage ==
            SpecStage.review,
      );
      // The base moves in the same line, and the project gets its gate.
      _replaceLine('$repo/a.txt', 'linha 5', 'linha 5 main');
      Directory('$repo/.promptorium').createSync();
      File('$repo/.promptorium/config.yml')
          .writeAsStringSync('testes: echo "3 passed in 0.1s"\n$config');
      await gitIn(repo, ['add', '.']);
      await gitIn(repo, ['commit', '-qm', 'main: linha 5']);
      final session = (await c.read(sessionsRepoProvider).bySpec(spec.id))
          .single;
      return Env(c, cli, notifier, ws, spec.id, session.id, wt, repo);
    }

    test(
      'resolveConflict saves the tip, the agent merges, the gate runs '
      'by itself and approves; the decisions show the remerge-diff with '
      'the explanation; the history has origin, files, gate and SHA',
      () async {
        final e = await setUpEnv();
        final before = (await gitIn(e.wt, ['rev-parse', 'HEAD'])).trim();
        final files = await e.review.resolveConflict(e.sessionId);
        await settle();
        expect(files, ['a.txt']);
        expect(e.lastMessage, contains('git merge main'));
        expect(e.lastMessage, contains('## Como resolvi'));
        expect(e.resolution!.state, ResolutionState.resolvendo);
        expect(e.resolution!.beforeSha, before);
        expect(
          (await gitIn(e.repo, [
            'rev-parse',
            beforeResolutionRef('SPEC-001'),
          ])).trim(),
          before,
        );

        final merged = await e.agentMerges('linha 5 main e spec');
        await e.agentAnswers(
          'Juntei.\n\n## Como resolvi\na.txt: mantive o texto da main e o da spec',
        );
        final r = await e.settled();
        expect(
          r.state,
          ResolutionState.aprovada,
          reason: '${r.report?.encode()}',
        );
        expect(r.checkedSha, merged);
        expect(r.report!.checks.map((c) => c.name), [
          'arvore',
          'marcadores',
          'base',
          'testes',
          'verificar',
          'contagem',
        ]);
        expect(r.text, 'Conflito resolvido · gate aprovado');

        final d = await e.resolver.decisions(e.sessionId);
        expect(d.hunks, hasLength(1));
        expect(d.hunks.single.path, 'a.txt');
        expect(d.hunks.single.base, ['linha 5 main']);
        expect(d.hunks.single.spec, ['linha 5 spec']);
        expect(d.hunks.single.result, ['linha 5 main e spec']);
        expect(d.explain('a.txt'), 'mantive o texto da main e o da spec');

        final history =
            (await e.c.read(reviewCommentsRepoProvider).bySpec(e.specId))
                .where((x) => x.author == resolutionAuthor)
                .toList();
        expect(history.map((x) => x.verdict), ['inicio', 'aprovada']);
        expect(history.first.body, contains('você'));
        expect(history.first.body, contains('a.txt'));
        expect(history.first.commitSha, before);
        expect(history.last.commitSha, merged);
        expect(history.every((x) => x.resolved && x.round == 0), isTrue);

        // R5: approved on the current tip, so nothing blocks it.
        final inputs = await e.review.readinessInputs(e.sessionId);
        expect(inputs.hasResolution, isTrue);
        expect(inputs.resolutionProblem, isNull);

        // R7: the base moves after the gate → outdated.
        _replaceLine('${e.repo}/a.txt', 'linha 9', 'linha 9 main');
        await gitIn(e.repo, ['commit', '-qam', 'main andou']);
        final stale = await e.review.readinessInputs(e.sessionId);
        expect(stale.resolutionProblem, startsWith('desatualizada'));
        expect(e.resolution!.state, ResolutionState.desatualizada);
      },
    );

    test(
      'without ## Como resolvi the whole answer stands for each file',
      () async {
        final e = await setUpEnv();
        await e.review.resolveConflict(e.sessionId);
        await settle();
        await e.agentMerges('linha 5 main');
        await e.agentAnswers('Fiquei com a versão da main.');
        expect((await e.settled()).state, ResolutionState.aprovada);
        final d = await e.resolver.decisions(e.sessionId);
        expect(d.how, isNull);
        expect(d.explain('a.txt'), 'Fiquei com a versão da main.');
      },
    );

    test('the three origins start a resolution: the PR/merge message, the '
        'restack and "Passar para o agente"', () async {
      final e = await setUpEnv();
      // Restack (SPEC-032 R7): the mark has the files.
      await e.c
          .read(appSettingsProvider.notifier)
          .set(restackMarkKey(e.sessionId), 'conflito\na.txt');
      await e.review.resolveConflict(e.sessionId);
      await settle();
      expect(e.lastMessage, contains('refazer a base'));
      expect(e.lastMessage, contains('## Como resolvi'));
      expect(e.resolution!.files, ['a.txt']);
      expect(e.resolution!.restackMark, 'conflito\na.txt');
      expect(
        e.c.read(appSettingsProvider)[restackMarkKey(e.sessionId)],
        isNull,
      );
      // The agent stops without doing anything: the gate still runs.
      await e.agentAnswers('Não consegui.');
      final r = await e.settled();
      expect(r.state, ResolutionState.reprovada);
      expect(r.firstFailure!.name, 'base');

      // Undo puts the restack mark back.
      await e.resolver.undo(e.sessionId);
      expect(e.resolution, isNull);
      expect(
        e.c.read(appSettingsProvider)[restackMarkKey(e.sessionId)],
        'conflito\na.txt',
      );

      // "Passar para o agente" during a manual rebase.
      await e.c
          .read(appSettingsProvider.notifier)
          .remove(restackMarkKey(e.sessionId));
      final status = await e.review.startRebase(e.sessionId);
      expect(status.inProgress, isTrue);
      final tip = (await gitIn(e.repo, [
        'rev-parse',
        'refs/heads/${(await e.c.read(sessionsRepoProvider).getById(e.sessionId))!.branch}',
      ])).trim();
      await e.review.handRebaseToAgent(e.sessionId);
      await settle();
      expect(e.lastMessage, contains('## Como resolvi'));
      expect(e.resolution!.state, ResolutionState.resolvendo);
      expect(e.resolution!.beforeSha, tip);
      // The rebase still stopped: the gate says so.
      await e.agentAnswers('Parei no meio.');
      final stopped = await e.settled();
      expect(stopped.state, ResolutionState.reprovada);
      expect(stopped.firstFailure!.output, contains('rebase em andamento'));
    });

    test('fewer tests than the last approved gate of the spec fail the '
        'count', () async {
      final e = await setUpEnv();
      await e.c.read(specStepsRepoProvider).setGate(
        e.specId,
        const ['R1'],
        report: GateReport(
          at: DateTime.now(),
          checks: const [
            GateCheck(name: 'testes', ok: true, count: TestCount(passed: 5)),
          ],
        ).encode(),
      );
      await e.review.resolveConflict(e.sessionId);
      await settle();
      await e.agentMerges('linha 5 main e spec');
      await e.agentAnswers('## Como resolvi\na.txt: os dois');
      final r = await e.settled();
      expect(r.state, ResolutionState.reprovada);
      expect(r.firstFailure!.name, 'contagem');
      expect(r.firstFailure!.output, contains('antes: 5 passaram'));
    });

    test('a forgotten marker fails it; "Corrigir e verificar" sends the '
        'report and the gate runs again; undo refuses a dirty worktree and '
        'then goes back to the SHA from before', () async {
      final e = await setUpEnv();
      final before = (await gitIn(e.wt, ['rev-parse', 'HEAD'])).trim();
      await e.review.resolveConflict(e.sessionId);
      await settle();
      // The agent commits the file with the markers.
      await _git(e.wt, ['merge', 'main']);
      await gitIn(e.wt, ['commit', '-qam', 'merge']);
      await e.agentAnswers('## Como resolvi\na.txt: pronto');
      var r = await e.settled();
      expect(r.state, ResolutionState.reprovada);
      expect(r.firstFailure!.name, 'marcadores');
      expect(r.text, 'Resolução reprovada no gate · sem marcadores');
      expect(r.automatic, isFalse);
      expect(
        e.notifier.shown.where((n) => n.$1 == 'Resolução automática'),
        isEmpty,
      );

      final sent = e.cli.last.writtenJson.length;
      await e.resolver.fix(e.sessionId);
      await settle();
      expect(e.cli.last.writtenJson.length, sent + 1);
      expect(e.lastMessage, contains('reprovou a resolução'));
      expect(e.lastMessage, contains('a.txt: 3 marcador(es)'));
      expect(e.lastMessage, contains('## Como resolvi'));
      expect(e.resolution!.state, ResolutionState.resolvendo);
      // The agent fixes it and the gate runs again by itself.
      File('${e.wt}/a.txt')
          .writeAsStringSync(File('${e.repo}/a.txt').readAsStringSync());
      await gitIn(e.wt, ['commit', '-qam', 'corrige']);
      await e.agentAnswers('## Como resolvi\na.txt: fiquei com a main');
      r = await e.settled();
      expect(r.state, ResolutionState.aprovada);
      expect(r.gates, 2);

      // Undo: refused with uncommitted changes (nothing touched)…
      final head = (await gitIn(e.wt, ['rev-parse', 'HEAD'])).trim();
      _replaceLine('${e.wt}/a.txt', 'linha 2', 'linha 2 suja');
      await expectLater(
        e.resolver.undo(e.sessionId),
        throwsA(
          isA<ReviewException>().having(
            (x) => x.message,
            'message',
            contains('não commitada'),
          ),
        ),
      );
      expect((await gitIn(e.wt, ['rev-parse', 'HEAD'])).trim(), head);
      expect(File('${e.wt}/a.txt').readAsStringSync(), contains('suja'));
      // …and done with a clean one.
      await gitIn(e.wt, ['checkout', '--', 'a.txt']);
      expect(await e.resolver.undo(e.sessionId), before);
      expect((await gitIn(e.wt, ['rev-parse', 'HEAD'])).trim(), before);
      expect(e.resolution, isNull);
      expect(
        await GitService(e.repo).resolveRef(beforeResolutionRef('SPEC-001')),
        isNull,
      );
      final verdicts =
          (await e.c.read(reviewCommentsRepoProvider).bySpec(e.specId))
              .where((x) => x.author == resolutionAuthor)
              .map((x) => x.verdict)
              .toList();
      expect(verdicts, [
        'inicio',
        'reprovada',
        'corrigir',
        'aprovada',
        'desfeita',
      ]);
    });

    test('resolver-conflitos: automatico starts on a predicted conflict, one '
        'at a time, fixes by itself only after the first failure and never '
        'merges', () async {
      final e = await setUpEnv(
        config: 'review:\n  resolver-conflitos: automatico\n',
      );
      expect(ProjectConfig.loadSync(e.repo).autoResolveConflicts, isTrue);
      // Another spec of the workspace is being resolved: wait.
      final settings = e.c.read(appSettingsProvider.notifier);
      await settings.set(
        resolutionKey('outra'),
        ConflictResolution(
          state: ResolutionState.conferindo,
          workspaceId: e.ws.id,
        ).encode(),
      );
      expect(await e.resolver.autoStart(e.sessionId), isFalse);
      expect(e.resolution, isNull);
      await settings.remove(resolutionKey('outra'));

      // The forecast of the queue finds the conflict and starts it.
      final prediction = await e.c.read(
        conflictForecastProvider(e.sessionId).future,
      );
      expect(prediction.files, ['a.txt']);
      await until(() async => e.resolution != null);
      expect(e.resolution!.automatic, isTrue);
      expect(e.lastMessage, contains('git merge main'));
      expect(e.notifier.shown.last, (
        'Resolução automática',
        'SPEC-001 tem conflito em a.txt. O agente começou a resolver. Nada '
            'é mergeado sem você.',
      ));
      // Already resolving: no second start.
      expect(await e.resolver.autoStart(e.sessionId), isFalse);

      // First failure: the app sends "Corrigir e verificar" once.
      final sent = e.cli.last.writtenJson.length;
      await _git(e.wt, ['merge', 'main']);
      await gitIn(e.wt, ['commit', '-qam', 'merge']);
      await e.agentAnswers('## Como resolvi\na.txt: pronto');
      await until(
        () async =>
            e.resolution!.autoFixUsed &&
            e.resolution!.state == ResolutionState.resolvendo,
      );
      expect(e.cli.last.writtenJson.length, sent + 1);
      expect(e.lastMessage, contains('reprovou a resolução'));
      expect(e.notifier.shown.last.$2, contains('vai corrigir uma vez'));

      // Second failure: nothing else is sent.
      await e.agentAnswers('## Como resolvi\na.txt: pronto de novo');
      final r = await e.settled();
      await settle();
      expect(r.state, ResolutionState.reprovada);
      expect(e.cli.last.writtenJson.length, sent + 1);
      expect(
        e.notifier.shown.last.$2,
        contains('próximas correções são com você'),
      );
      expect(await e.resolver.autoStart(e.sessionId), isFalse);

      // Never merged by itself.
      final s = (await e.c.read(sessionsRepoProvider).getById(e.sessionId))!;
      expect(s.status, isNot(SessionStatus.merged));
      expect(s.mergeCommit, isNull);
      expect(
        await gitIn(e.repo, ['branch', '--merged', 'main']),
        isNot(contains(s.branch)),
      );
    });

    test('manual mode (default) never starts by itself', () async {
      final e = await setUpEnv();
      expect(ProjectConfig.loadSync(e.repo).autoResolveConflicts, isFalse);
      expect(await e.resolver.autoStart(e.sessionId), isFalse);
      expect(e.resolution, isNull);
    });
  });
}
