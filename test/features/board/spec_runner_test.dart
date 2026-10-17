import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/project/project_memory.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

const specText = '''---
id: SPEC-001
status: aprovada
---

# Extração do schema

## Requisitos

- R1 · Extrair tabelas
- R2 · Extrair índices
- R3 · Extrair generators
- R4 · Ligar na CLI
''';

/// `result` line of the fixture with [text] as the final answer.
String resultLine(String text, {bool success = true, double cost = 0.01}) {
  final j = jsonDecode(
    fixtureLines().firstWhere((l) => l.contains('"result"')),
  ) as Map<String, dynamic>;
  j['result'] = text;
  j['total_cost_usd'] = cost;
  if (!success) {
    j['subtype'] = 'error_during_execution';
    j['is_error'] = true;
  }
  return jsonEncode(j);
}

void main() {
  group('pure', () {
    test('marker: last line wins; accents, case, "e" and lists', () {
      expect(parseStepMarker(null), isEmpty);
      expect(parseStepMarker('feito, sem marcador'), isEmpty);
      expect(parseStepMarker('ok\nETAPA CONCLUÍDA: R3'), {'R3'});
      expect(parseStepMarker('etapas concluidas: r1, R2 e R3.'), {
        'R1',
        'R2',
        'R3',
      });
      expect(
        parseStepMarker('ETAPA CONCLUÍDA: R1\n…depois…\nETAPA CONCLUÍDA: R2'),
        {'R2'},
      );
    });

    test('subagentPlan: each moment lands in the right session', () {
      const steps = [
        StepView(id: 'R1', text: 'a'),
        StepView(id: 'R2', text: 'b'),
        StepView(id: 'R3', text: 'c'),
      ];
      const subs = [
        SpecSubagent(agent: 'ini', when: SubagentWhen.specStart),
        SpecSubagent(agent: 'antes', when: SubagentWhen.beforeEach),
        SpecSubagent(agent: 'depois', when: SubagentWhen.afterEach),
        SpecSubagent(agent: 'em2', when: SubagentWhen.atStep, step: 'R2'),
        SpecSubagent(
          agent: 'rev',
          when: SubagentWhen.specEnd,
          instruction: 'foco em testes',
        ),
      ];
      List<String> agents(List<String> todo, [List<StepView> st = steps]) => [
        for (final l in subagentPlan(subs, steps: st, todo: todo))
          l.split(':').first,
      ];
      expect(agents(['R1']), ['ini', 'antes', 'depois']);
      expect(agents(['R2']), ['antes', 'depois', 'em2']);
      expect(agents(['R3']), ['antes', 'depois', 'rev']);
      // Small spec in one session: everything applies at once.
      expect(agents(['R1', 'R2', 'R3']), [
        'ini',
        'antes',
        'depois',
        'em2',
        'rev',
      ]);
      expect(
        subagentPlan(subs, steps: steps, todo: ['R3']).last,
        contains('Instrução: foco em testes'),
      );
      expect(subagentPlan(const [], steps: steps, todo: ['R1']), isEmpty);
    });

    test('prompt: spec embedded, done / now / later, commit and marker', () {
      final spec = Spec(
        id: 1,
        workspaceId: 1,
        code: 'SPEC-001',
        title: 'Extração do schema',
        status: SpecStatus.approved,
        path: 'specs/SPEC-001-x.md',
        stage: SpecStage.running,
        requirements: const [],
        dependsOn: const [],
        autoAdvance: true,
        reviewRounds: 0,
        gateResends: 0,
        rejectedHunks: 0,
      );
      const steps = [
        StepView(id: 'R1', text: 'Extrair tabelas', status: StepStatus.done),
        StepView(id: 'R2', text: 'Extrair índices'),
        StepView(id: 'R3', text: 'Extrair generators'),
      ];
      final p = specStepPrompt(
        spec: spec,
        specText: specText,
        steps: steps,
        todo: ['R2'],
      );
      expect(p, startsWith('Implemente a etapa R2 da spec SPEC-001'));
      expect(p, contains('- R2 · Extrair índices'));
      expect(p, contains('Já concluídas (commits nesta branch):\n- R1 ·'));
      expect(p, contains('(não implemente agora): R3.'));
      expect(p, contains('<spec>\n---\nid: SPEC-001'));
      expect(p, contains('"SPEC-001 R2: <resumo do que mudou>"'));
      expect(p, contains('linha exata: ETAPA CONCLUÍDA: R2'));
      expect(
        specSessionTitle(spec, steps, ['R2']),
        'SPEC-001 · R2 · Extrair índices',
      );
      expect(
        specSessionTitle(spec, steps, ['R1', 'R2', 'R3']),
        'SPEC-001 · R1–R3 · Extração do schema',
      );
    });
  });

  group('SpecRunner (temporary repo, fake CLI)', () {
    late Directory tmp;
    late String repo;
    late FakeCli cli;
    late ProviderContainer c;
    late Workspace ws;
    late Spec spec;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-runner-');
      repo = await createRepo(tmp);
      Directory('$repo/specs').createSync();
      File('$repo/specs/SPEC-001-extracao.md').writeAsStringSync(specText);
      cli = FakeCli();
      c = sessionContainer(
        sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
      );
      await c.read(appSettingsProvider.notifier).load();
      ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'repo');
      await c.read(specServiceProvider).sync(ws);
      spec = (await c.read(specsRepoProvider).getByCode(ws.id, 'SPEC-001'))!;
    });

    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    Future<Map<String, StepStatus>> states() async {
      final s = (await c.read(specsRepoProvider).getById(spec.id))!;
      final rows = await c.read(specStepsRepoProvider).bySpec(spec.id);
      return {for (final v in stepsOf(s, rows)) v.id: v.status};
    }

    Future<SpecStage> stage() async =>
        (await c.read(specsRepoProvider).getById(spec.id))!.stage;

    /// Waits (up to 15 s) for [cond]: the gate runs real git / bash.
    Future<void> until(Future<bool> Function() cond) async {
      final end = DateTime.now().add(const Duration(seconds: 15));
      while (!await cond()) {
        if (DateTime.now().isAfter(end)) fail('condição não atingida');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await settle();
    }

    Future<SpecStep> stepRow(String step) async =>
        (await c.read(specStepsRepoProvider).bySpec(spec.id))
            .firstWhere((r) => r.step == step);

    test('step by step in the spec worktree: marker → done → next session; '
        'no marker → waits for the user; last step → Review', () async {
      final runner = c.read(specRunnerProvider);
      final first = await runner.runNext(
        spec.id,
        mode: ClaudePermissionMode.acceptEdits,
      );
      await settle();

      // Own worktree / branch, stored on the spec.
      var row = (await c.read(specsRepoProvider).getById(spec.id))!;
      expect(row.branch, startsWith('pr/spec-001-extracao-do-schema-'));
      expect(cli.cwds.single, row.worktreePath);
      expect(Directory(row.worktreePath!).existsSync(), isTrue);
      final s1 = (await c.read(sessionsRepoProvider).getById(first))!;
      expect(s1.specId, spec.id);
      expect(s1.steps, 'R1'); // 4 steps > 3: one per session
      expect(s1.title, 'SPEC-001 · R1 · Extrair tabelas');
      final sent = cli.last.writtenJson.single['message']['content'] as String;
      expect(sent, contains('<spec>'));
      expect(await states(), {
        'R1': StepStatus.running,
        'R2': StepStatus.pending,
        'R3': StepStatus.pending,
        'R4': StepStatus.pending,
      });
      expect(await stage(), SpecStage.running);

      // Busy: a second run is refused.
      await expectLater(
        runner.runNext(spec.id),
        throwsA(isA<SpecRunException>()),
      );

      // R1 done → its process is closed and R2 starts in the same worktree.
      cli.last.emit(resultLine('Pronto.\nETAPA CONCLUÍDA: R1'));
      await until(() async => cli.processes.length == 2);
      expect((await states())['R1'], StepStatus.done);
      expect(cli.processes.first.signals, isNotEmpty);
      expect(cli.cwds.last, row.worktreePath);
      expect(
        cli.args.last,
        containsAllInOrder(['--permission-mode', 'acceptEdits']),
      );
      final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
      expect(sessions.map((s) => s.steps), ['R1', 'R2']);
      final second = sessions.last.id;

      // R2 without the marker: waits for the user, no new session.
      cli.last.emit(resultLine('Qual banco devo usar?'));
      await settle();
      expect((await states())['R2'], StepStatus.needsInput);
      expect(cli.processes, hasLength(2));
      expect(await stage(), SpecStage.running);

      // The user answers in the same session; now it finishes.
      await c.read(sessionManagerProvider.notifier).send(second, 'O Postgres.');
      await settle();
      expect((await states())['R2'], StepStatus.running);
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R2'));
      await until(() async => cli.processes.length == 3);

      // Turn off auto-advance: R3 done does not open R4.
      await c.read(specsRepoProvider).setAutoAdvance(spec.id, false);
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R3'));
      await settle();
      await settle();
      expect(cli.processes, hasLength(3));
      expect((await states())['R3'], StepStatus.done);

      await runner.runNext(spec.id);
      await settle();
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R4'));
      await settle();
      expect((await states()).values.toSet(), {StepStatus.done});
      expect(await stage(), SpecStage.review);
      row = (await c.read(specsRepoProvider).getById(spec.id))!;
      expect(
        (await c.read(sessionsRepoProvider).bySpec(spec.id))
            .map((s) => s.worktreePath),
        everyElement(row.worktreePath),
      );
    });

    test(
      'a spec started while its dependency is in Review keeps advancing',
      () async {
        final repoSpecs = c.read(specsRepoProvider);
        final dep = await repoSpecs.insert(
          workspaceId: ws.id,
          code: 'SPEC-000',
          title: 'Base',
          path: 'specs/SPEC-000.md',
          status: SpecStatus.approved,
          requirements: const [],
          dependsOn: const [],
        );
        await repoSpecs.setStage(dep.id, SpecStage.review);
        await repoSpecs.update(
          spec.id,
          const SpecsCompanion(dependsOn: Value(['SPEC-000'])),
        );
        final runner = c.read(specRunnerProvider);
        await expectLater(
          runner.runNext(spec.id),
          throwsA(isA<SpecRunException>()),
        );
        await runner.runNext(spec.id, reviewUnblocks: true);
        await settle();
        cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
        await until(() async => cli.processes.length == 2);
      },
    );

    test(
      'autopilot starts the spec and turns itself off after the last one',
      () async {
        final pilot = c.read(autopilotProvider.notifier);
        await pilot.start(ws.id);
        await settle();
        expect(c.read(autopilotProvider), {ws.id});
        for (final (i, r) in ['R1', 'R2', 'R3', 'R4'].indexed) {
          cli.last.emit(resultLine('ETAPA CONCLUÍDA: $r'));
          await until(() async => i == 3 || cli.processes.length == i + 2);
        }
        await until(() async => await stage() == SpecStage.review);
        await until(() async => c.read(autopilotProvider).isEmpty);
      },
    );

    test('small spec runs whole in one session; stop → pending; failure → '
        'waits; blocked spec is refused', () async {
      File(
        '$repo/specs/SPEC-001-extracao.md',
      ).writeAsStringSync(specText.replaceFirst('- R4 · Ligar na CLI\n', ''));
      final runner = c.read(specRunnerProvider);
      final id = await runner.runNext(spec.id);
      await settle();
      expect(
        (await c.read(sessionsRepoProvider).getById(id))!.steps,
        'R1,R2,R3',
      );
      expect(
        cli.last.writtenJson.single['message']['content'],
        contains('ETAPA CONCLUÍDA: R1, R2, R3'),
      );

      await c.read(sessionManagerProvider.notifier).stop(id);
      await settle();
      expect((await states()).values.toSet(), {StepStatus.pending});

      await runner.runNext(spec.id);
      await settle();
      cli.last.emit(resultLine('falhou', success: false));
      await settle();
      expect((await states()).values.toSet(), {StepStatus.needsInput});

      // Not untouched any more: one step per session from now on. A
      // marker naming another step does not count.
      await runner.runNext(spec.id);
      await settle();
      expect(
        (await c.read(sessionsRepoProvider).bySpec(spec.id)).last.steps,
        'R1',
      );
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1, R2'));
      await until(() async => (await states())['R2'] == StepStatus.running);
      expect((await states())['R1'], StepStatus.done);
      // R2 (left waiting by the failure) is picked by the next session.
      expect((await states())['R2'], StepStatus.running);
      expect(
        (await c.read(sessionsRepoProvider).bySpec(spec.id)).last.steps,
        'R2',
      );

      // Dependencies.
      await c
          .read(specServiceProvider)
          .create(
            ws,
            title: 'Depois',
            body: specText
                .replaceFirst('SPEC-001', 'SPEC-002')
                .replaceFirst(
                  'status: aprovada',
                  'status: aprovada\ndepende-de: [SPEC-001]',
                ),
          );
      final s2 = (await c
          .read(specsRepoProvider)
          .getByCode(ws.id, 'SPEC-002'))!;
      await expectLater(
        runner.runNext(s2.id),
        throwsA(
          isA<SpecRunException>().having(
            (e) => e.message,
            'message',
            contains('depende de SPEC-001'),
          ),
        ),
      );
    });

    test('gate: marker without commit → resent once to the same session; '
        'fixed → done and next step; failing again → waits for the user; '
        'Commitar o que sobrou', () async {
      Directory('$repo/.promptorium').createSync();
      File('$repo/.promptorium/config.yml').writeAsStringSync(
        'testes: test ! -f quebrado.txt\nverificacao:\n  tentativas: 1\n',
      );
      final runner = c.read(specRunnerProvider);
      await runner.runNext(spec.id);
      await settle();
      final wt = (await c.read(specsRepoProvider).getById(spec.id))!
          .worktreePath!;
      expect((await stepRow('R1')).startSha, isNotNull);

      // 1. Marker, no commit: verifying → resend with the failure.
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
      await until(() async => cli.last.writtenJson.length == 2);
      expect(cli.processes, hasLength(1));
      final retry = cli.last.writtenJson.last['message']['content'] as String;
      expect(retry, contains('A verificação do Promptorium falhou: commit'));
      expect(retry, endsWith('ETAPA CONCLUÍDA: R1'));
      expect((await stepRow('R1')).gateAttempts, 1);
      expect(
        (await c.read(specsRepoProvider).getById(spec.id))!.gateResends,
        1,
      );
      expect(
        GateReport.decode((await stepRow('R1')).gateReport)!.summary,
        'commit',
      );

      // 2. The agent commits and repeats the marker: done, R2 starts.
      File('$wt/r1.txt').writeAsStringSync('ok');
      await gitIn(wt, ['add', '.']);
      await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1: tabelas']);
      cli.last.emit(resultLine('Corrigido.\nETAPA CONCLUÍDA: R1'));
      await until(() async => cli.processes.length == 2);
      expect((await states())['R1'], StepStatus.done);
      expect((await states())['R2'], StepStatus.running);
      expect((await stepRow('R2')).gateAttempts, 0);

      // 3. R2 breaks the tests twice: one resend, then waits for the user.
      File('$wt/quebrado.txt').writeAsStringSync('x');
      await gitIn(wt, ['add', '.']);
      await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R2: índices']);
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R2'));
      await until(() async => cli.last.writtenJson.length == 2);
      expect(
        cli.last.writtenJson.last['message']['content'],
        contains('falhou: testes'),
      );
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R2'));
      await until(() async => (await states())['R2'] == StepStatus.needsInput);
      expect(cli.last.writtenJson, hasLength(2));
      expect(cli.processes, hasLength(2));

      // 4. The user fixes it but leaves the file uncommitted.
      await gitIn(wt, ['rm', '-q', '--cached', 'quebrado.txt']);
      File('$wt/quebrado.txt').deleteSync();
      await runner.recheck(spec.id);
      expect((await states())['R2'], StepStatus.needsInput);
      expect(
        GateReport.decode((await stepRow('R2')).gateReport)!.onlyDirtyTree,
        isTrue, // tests pass now; only the staged deletion is left
      );
      await runner.commitLeftovers(spec.id);
      await until(() async => cli.processes.length == 3);
      expect((await states())['R2'], StepStatus.done);
      final log = await gitIn(wt, ['log', '--format=%s', '-1']);
      expect(log.trim(), 'SPEC-001 R2: arquivos restantes da etapa');
    });

    test('no config: the marker alone finishes the step (as before)', () async {
      await c.read(specRunnerProvider).runNext(spec.id);
      await settle();
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
      await settle();
      await settle();
      expect((await states())['R1'], StepStatus.done);
      expect((await stepRow('R1')).gateReport, isNull);
    });

    test('checkpoint: back to the start of a step (commits and files '
        'discarded, uncommitted changes of the start restored); redo sends '
        'the previous attempt', () async {
      final runner = c.read(specRunnerProvider);
      await runner.runNext(spec.id);
      await settle();
      final wt = (await c.read(specsRepoProvider).getById(spec.id))!
          .worktreePath!;
      final r1Start = (await stepRow('R1')).startSha!;
      expect(
        (await gitIn(wt, [
          'rev-parse',
          checkpointRef('SPEC-001', 'R1'),
        ])).trim(),
        r1Start,
      );
      File('$wt/r1.txt').writeAsStringSync('r1');
      await gitIn(wt, ['add', '.']);
      await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1: tabelas']);
      // Uncommitted change of a tracked file when R2 starts.
      File('$wt/a.txt').writeAsStringSync('mexido antes de R2\n');
      // Untracked file that already exists when R2 starts.
      File('$wt/antes.txt').writeAsStringSync('novo antes de R2\n');
      cli.last.emit(resultLine('Feito.\nETAPA CONCLUÍDA: R1'));
      await until(() async => (await states())['R2'] == StepStatus.running);
      final r2 = await stepRow('R2');
      expect(r2.startStash, isNotNull);
      // The snapshot is kept by a ref (safe from `git gc`).
      expect(
        (await gitIn(wt, [
          'rev-parse',
          checkpointStateRef('SPEC-001', 'R2'),
        ])).trim(),
        r2.startStash,
      );

      // R2 work: a commit and a new file.
      File('$wt/r2.txt').writeAsStringSync('r2');
      await gitIn(wt, ['add', 'r2.txt']);
      await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R2: índices']);
      File('$wt/lixo.txt').writeAsStringSync('x');

      final preview = await runner.rewindPreview(spec.id, 'R2');
      expect(preview.commits, ['SPEC-001 R2: índices']);
      expect(preview.files, containsAll(['lixo.txt', 'a.txt']));
      expect(preview.steps, ['R2']);
      expect(preview.restoresStash, isTrue);

      await runner.rewind(spec.id, 'R2');
      await settle();
      expect((await gitIn(wt, ['rev-parse', 'HEAD'])).trim(), r2.startSha);
      expect(File('$wt/r2.txt').existsSync(), isFalse);
      expect(File('$wt/lixo.txt').existsSync(), isFalse);
      expect(File('$wt/a.txt').readAsStringSync(), 'mexido antes de R2\n');
      expect(File('$wt/antes.txt').readAsStringSync(), 'novo antes de R2\n');
      expect((await states())['R1'], StepStatus.done);
      expect((await states())['R2'], StepStatus.pending);
      final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
      expect(sessions.every((s) => s.status.isTerminal), isTrue);

      // Redo R1: R1 and R2 back to pending, a new session with the last
      // answer of R1.
      await runner.redo(spec.id, 'R1');
      await settle();
      expect((await gitIn(wt, ['rev-parse', 'HEAD'])).trim(), r1Start);
      expect((await states())['R1'], StepStatus.running);
      final prompt =
          cli.last.writtenJson.single['message']['content'] as String;
      expect(prompt, contains('<tentativa-anterior>'));
      expect(prompt, contains('Feito.'));
      expect(prompt, contains('Implemente a etapa R1'));
    });

    test('new worktree: copiar / preparar, index and PROMPTORIUM_* in the '
        'session; a failed preparar is retried by the next run', () async {
      File('$repo/.gitignore').writeAsStringSync('.env\n');
      await gitIn(repo, ['add', '.gitignore']);
      await gitIn(repo, ['commit', '-q', '-m', 'ignore']);
      File('$repo/.env').writeAsStringSync('X=1\n');
      Directory('$repo/.promptorium').createSync();
      final cfg = File('$repo/.promptorium/config.yml')
        ..writeAsStringSync(
          'worktree:\n  copiar: [.env]\n  preparar: exit 3\n'
          '  porta-base: 4000\n',
        );
      final runner = c.read(specRunnerProvider);
      await expectLater(
        runner.runNext(spec.id),
        throwsA(
          isA<SpecRunException>().having(
            (e) => e.message,
            'message',
            contains('Falha ao preparar o worktree'),
          ),
        ),
      );
      expect(c.read(worktreePrepProvider)[spec.id]?.error, isNotNull);
      expect(cli.processes, isEmpty);
      var row = (await c.read(specsRepoProvider).getById(spec.id))!;
      expect(row.preparedAt, isNull);
      expect(row.worktreeIndex, 1);

      cfg.writeAsStringSync(
        'worktree:\n  copiar: [.env]\n  preparar: touch pronto\n'
        '  porta-base: 4000\n',
      );
      await runner.runNext(spec.id);
      await settle();
      row = (await c.read(specsRepoProvider).getById(spec.id))!;
      expect(row.preparedAt, isNotNull);
      expect(c.read(worktreePrepProvider)[spec.id], isNull);
      expect(File('${row.worktreePath}/.env').existsSync(), isTrue);
      expect(File('${row.worktreePath}/pronto').existsSync(), isTrue);
      expect(cli.envs.single, {
        'PROMPTORIUM_ROOT': repo,
        'PROMPTORIUM_WORKTREE': row.worktreePath,
        'PROMPTORIUM_SPEC': 'SPEC-001',
        'PROMPTORIUM_PORT': '4001',
      });
    });

    test('gate runs the verificar: of the step criteria and checks them '
        '(F7)', () async {
      File('$repo/specs/SPEC-001-extracao.md').writeAsStringSync(
        specText.replaceFirst(
          '- R4 · Ligar na CLI\n',
          '- R4 · Ligar na CLI\n'
              '\n## Critérios de aceite\n\n'
              '- [ ] r1.txt existe [R1] · verificar: test -f r1.txt\n',
        ),
      );
      Directory('$repo/.promptorium').createSync();
      File('$repo/.promptorium/config.yml')
          .writeAsStringSync('testes: "true"\nverificacao:\n  tentativas: 0\n');
      await c.read(specServiceProvider).sync(ws);
      final runner = c.read(specRunnerProvider);
      await runner.runNext(spec.id);
      await settle();
      final wt = (await c.read(specsRepoProvider).getById(spec.id))!
          .worktreePath!;
      // Commit without r1.txt: the criterion's check fails.
      File('$wt/outro.txt').writeAsStringSync('x');
      await gitIn(wt, ['add', '.']);
      await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1: quase']);
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
      await until(() async => (await states())['R1'] == StepStatus.needsInput);
      final failed = GateReport.decode((await stepRow('R1')).gateReport)!;
      expect(failed.failures.single.name, 'verificar');
      expect(failed.failures.single.command, 'test -f r1.txt');

      File('$wt/r1.txt').writeAsStringSync('x');
      await gitIn(wt, ['add', '.']);
      await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1: r1']);
      await runner.recheck(spec.id);
      await until(() async => (await states())['R1'] == StepStatus.done);
      final marks = await c.read(reviewCommentsRepoProvider).criteria(spec.id);
      expect(marks.single.criterion, 'r1.txt existe [R1]');
      expect(marks.single.checkedBy, 'gate');
    });

    test('memory: the prompt carries it and asks for APRENDIZADO; the line '
        'of the answer and the gate times go to memoria.md (F8)', () async {
      Directory('$repo/.promptorium').createSync();
      File('$repo/.promptorium/memoria.md')
          .writeAsStringSync('- Use drift  <!-- você, 2026-10-01 -->\n');
      File('$repo/.promptorium/config.yml').writeAsStringSync(
        'testes: sleep 5\nverificacao:\n  exigir-commit: false\n'
        '  exigir-arvore-limpa: false\n',
      );
      final runner = c.read(specRunnerProvider);
      await runner.runNext(spec.id);
      await settle();
      final prompt =
          cli.last.writtenJson.single['message']['content'] as String;
      expect(prompt, contains('Memória do projeto'));
      expect(prompt, contains('- Use drift'));
      expect(prompt, contains('APRENDIZADO: <o que aprendeu>'));
      cli.last.emit(
        resultLine('APRENDIZADO: o build precisa de -j1\nETAPA CONCLUÍDA: R1'),
      );
      await until(() async => (await states())['R1'] == StepStatus.done);
      final m = ProjectMemory.loadSync(repo);
      expect(m.entries.map((e) => e.text), [
        'Use drift',
        'o build precisa de -j1',
        '`sleep 5` (testes) passa em ~5 s',
      ]);
      expect(m.entries[1].origin, 'SPEC-001 R1');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('spec file changed while it runs: flagged, no next step until '
        'confirmed (F11)', () async {
      c.listen(workspacesProvider, (_, _) {});
      await c
          .read(appSettingsProvider.notifier)
          .set(AppSettingKeys.activeWorkspace, '${ws.id}');
      await until(() async => c.read(activeWorkspaceProvider) != null);
      c.listen(workspaceWatcherProvider, (_, _) {});
      await c.read(specsRepoProvider).setAutoAdvance(spec.id, false);
      final runner = c.read(specRunnerProvider);
      await runner.runNext(spec.id);
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      File('$repo/specs/SPEC-001-extracao.md').writeAsStringSync(
        specText.replaceFirst('Extrair índices', 'Extrair índices e views'),
      );
      await until(
        () async => c.read(workspaceWatcherProvider).contains(spec.id),
      );
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
      await until(() async => (await states())['R1'] == StepStatus.done);
      await expectLater(
        runner.runNext(spec.id),
        throwsA(
          isA<SpecRunException>().having(
            (e) => e.message,
            'message',
            contains('alterada no disco'),
          ),
        ),
      );
      c.read(workspaceWatcherProvider.notifier).confirm(spec.id);
      await runner.runNext(spec.id);
      await settle();
      expect(
        cli.last.writtenJson.single['message']['content'],
        contains('Extrair índices e views'),
      );
    });

    test('best-of-N: A and B get their own PROMPTORIUM_PORT, apart from the '
        "spec's", () async {
      Directory('$repo/.promptorium').createSync();
      File('$repo/.promptorium/config.yml')
          .writeAsStringSync('worktree:\n  porta-base: 4000\n');
      final runner = c.read(specRunnerProvider);
      await runner.runNext(spec.id, duel: true);
      await settle();
      expect(cli.envs.map((e) => e!['PROMPTORIUM_PORT']), ['4002', '4003']);
      final duel = (await c.read(specDuelsRepoProvider).openOf(spec.id))!;
      await runner.discardDuel(duel.id);
    });

    test('best-of-N: R1 runs in two temporary worktrees; choosing B brings '
        'its commit, removes both and the spec goes on (F15)', () async {
      final runner = c.read(specRunnerProvider);
      await runner.runNext(spec.id, duel: true);
      await settle();
      expect(cli.processes, hasLength(2));
      final row = (await c.read(specsRepoProvider).getById(spec.id))!;
      final duel = (await c.read(specDuelsRepoProvider).openOf(spec.id))!;
      expect(cli.cwds, [duel.worktreeA, duel.worktreeB]);
      expect(cli.envs.last!['PROMPTORIUM_WORKTREE'], duel.worktreeB);
      final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
      expect(sessions.map((s) => s.duelId), [duel.id, duel.id]);
      expect(sessions.map((s) => s.title), [
        'SPEC-001 · R1 · Extrair tabelas · A',
        'SPEC-001 · R1 · Extrair tabelas · B',
      ]);
      // Busy: neither a normal run nor a second duel.
      await expectLater(
        runner.runNext(spec.id),
        throwsA(isA<SpecRunException>()),
      );

      Future<void> attempt(String wt, String file, int i) async {
        File('$wt/$file').writeAsStringSync(file);
        await gitIn(wt, ['add', '.']);
        await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1: $file']);
        cli.processes[i].emit(resultLine('ETAPA CONCLUÍDA: R1'));
      }

      await attempt(duel.worktreeA, 'a.dart', 0);
      await settle();
      expect(
        (await c.read(specDuelsRepoProvider).getById(duel.id))!.state,
        'rodando',
      );
      await attempt(duel.worktreeB, 'b.dart', 1);
      await until(
        () async =>
            (await c.read(specDuelsRepoProvider).getById(duel.id))!.state ==
            'pronto',
      );
      expect((await states())['R1'], StepStatus.needsInput);

      await runner.chooseDuel(duel.id, 'B');
      await until(() async => cli.processes.length == 3);
      expect(File('${row.worktreePath}/b.dart').existsSync(), isTrue);
      expect(File('${row.worktreePath}/a.dart').existsSync(), isFalse);
      expect(Directory(duel.worktreeA).existsSync(), isFalse);
      expect(Directory(duel.worktreeB).existsSync(), isFalse);
      expect((await states())['R1'], StepStatus.done);
      expect(cli.cwds.last, row.worktreePath);
      final done = (await c.read(specDuelsRepoProvider).getById(duel.id))!;
      expect(done.state, 'escolhido');
      expect(done.chosen, 'B');
    });
  });
}
