import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/readonly_run.dart'
    show PlannerException;
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/usage_tracker.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/automation_pause.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/board/orchestrator/quota_divert.dart';
import 'package:promptorium/features/board/orchestrator/quota_diverter.dart';
import 'package:promptorium/features/board/orchestrator/step_plan.dart';
import 'package:promptorium/features/board/spec_run_provider.dart';
import 'package:promptorium/features/board/spec_runner.dart';

import '../../core/git/git_test_utils.dart';
import 'orchestrator/orchestrator_fixture.dart';

SpecStep _row(
  String step, {
  String? kind,
  String? model,
  String? effort,
  String? body,
}) => SpecStep(
  specId: 1,
  step: step,
  status: StepStatus.pending,
  gateAttempts: 0,
  userPicked: false,
  escalations: 0,
  kind: kind,
  planModel: model,
  planEffort: effort,
  body: body,
);

const _reviewSpec = '''---
id: SPEC-001
status: aprovada
---

# Saudações

## Requisitos

- R1 · Criar ola.txt
- R2 · Criar tchau.txt
''';

String _verdict(Map<String, Object?> data) {
  final j = jsonDecode(resultLine(jsonEncode(data), cost: 0.02)) as Map;
  j['structured_output'] = data;
  return jsonEncode(j);
}

void main() {
  const prefs = OrchestratorPrefs({});

  group('pure', () {
    test('stepRunPlan: own plan; sub-step takes the requirement; REV<n> and '
        'unplanned steps use Implementação; Manual has none', () {
      final rows = [
        _row('R1', kind: 'mecanica', model: 'haiku', effort: 'low'),
        _row('R3', kind: 'altoRisco', model: 'opus', effort: 'high'),
        _row('R3.1', body: 'a'),
        _row('REV1', body: 'corrigir'),
      ];
      expect(stepRunPlan('R1', rows, prefs), (
        kind: StepKind.mecanica,
        rule: const StepRule('haiku', 'low'),
      ));
      expect(stepRunPlan('R3.1', rows, prefs), (
        kind: StepKind.altoRisco,
        rule: const StepRule('opus', 'high'),
      ));
      expect(stepRunPlan('REV1', rows, prefs), (
        kind: StepKind.implementacao,
        rule: const StepRule('sonnet', 'medium'),
      ));
      expect(stepRunPlan('R2', rows, prefs)?.kind, StepKind.implementacao);
      // A sibling planned when the requirement was already split.
      final split = [
        _row('R3.1', body: 'a', kind: 'documentacao', model: 'haiku'),
        _row('R3.2', body: 'b'),
      ];
      expect(stepRunPlan('R3.2', split, prefs)?.kind, StepKind.documentacao);
      // Manual: no step has a plan.
      expect(stepRunPlan('R1', [_row('R1'), _row('REV1')], prefs), isNull);
      expect(stepRunPlan('REV1', [_row('R1'), _row('REV1')], prefs), isNull);
    });

    test('nextSteps cuts the group at the first different plan and never '
        'skips a step', () {
      final steps = [
        for (final id in ['R1', 'R2', 'R3']) StepView(id: id, text: id),
      ];
      const a = StepRule('haiku', 'low'), b = StepRule('sonnet', 'medium');
      expect(nextSteps(steps, singleSessionMax: 3), ['R1', 'R2', 'R3']);
      expect(
        nextSteps(
          steps,
          singleSessionMax: 3,
          plans: {'R1': a, 'R2': a, 'R3': b},
        ),
        ['R1', 'R2'],
      );
      expect(
        nextSteps(
          steps,
          singleSessionMax: 3,
          plans: {'R1': a, 'R2': b, 'R3': a},
        ),
        ['R1'],
      );
    });
  });

  group('SpecRunner in Automático (temporary repo, fake CLI)', () {
    late OrchestratorFixture f;

    tearDown(() => f.dispose());

    test('each step runs with the plan, always in the Claude Code; equal '
        'neighbours stay in the session, a different plan opens a new one in '
        'the same worktree', () async {
      f = await OrchestratorFixture.create();
      await f.plan({
        'R1': (StepKind.mecanica, 'haiku', 'low'),
        'R2': (StepKind.mecanica, 'haiku', 'low'),
        'R3': (StepKind.implementacao, 'sonnet', 'medium'),
        'R4': (StepKind.altoRisco, 'opus', 'high'),
      });
      final runner = f.c.read(specRunnerProvider);
      // The form's provider and model do not apply to a planned step.
      final id = await runner.runNext(
        f.spec.id,
        provider: 'codex',
        model: 'gpt-5',
        effort: 'xhigh',
      );
      await settle();
      expect(f.modelOf(0), ('haiku', 'low'));
      var sessions = await f.sessions();
      expect(sessions.single.provider, 'claude');
      expect(sessions.single.steps, 'R1');

      // R2 has the same plan: same session.
      f.cli.last.emit(contextAnswer(30000));
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
      await waitFor(() async => (await f.states())['R2'] == StepStatus.running);
      expect(f.cli.processes, hasLength(1));
      expect((await f.sessions()).single.steps, 'R1,R2');

      // R3 changes the plan: a new session in the same worktree.
      f.cli.last.emit(contextAnswer(31000));
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: R2'));
      await waitFor(() async => f.cli.processes.length == 2);
      expect(f.modelOf(1), ('sonnet', 'medium'));
      expect(
        await f.notes(id),
        contains(
          'R3 vai para uma sessão nova: o plano muda de Haiku · low para '
          'Sonnet · medium.',
        ),
      );
      final wt = await f.worktree();
      expect(f.cli.cwds, everyElement(wt));

      f.cli.last.emit(contextAnswer(20000));
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: R3'));
      await waitFor(() async => f.cli.processes.length == 3);
      expect(f.modelOf(2), ('opus', 'high'));
      sessions = await f.sessions();
      expect(sessions.map((s) => (s.steps, s.model, s.effort, s.provider)), [
        ('R1,R2', 'haiku', 'low', 'claude'),
        ('R3', 'sonnet', 'medium', 'claude'),
        ('R4', 'opus', 'high', 'claude'),
      ]);
      // One attempt per finished step (no gate in the project).
      final runs = await f.c.read(stepRunsRepoProvider).bySpec(f.spec.id);
      expect(runs.map((r) => (r.step, r.kind, r.model, r.result)), [
        ('R1', 'mecanica', 'haiku', StepRunResult.passed),
        ('R2', 'mecanica', 'haiku', StepRunResult.passed),
        ('R3', 'implementacao', 'sonnet', StepRunResult.passed),
      ]);
    });

    test('a small untouched spec groups only the first equal plans', () async {
      f = await OrchestratorFixture.create(specText: _reviewSpec);
      await f.plan({
        'R1': (StepKind.mecanica, 'haiku', 'low'),
        'R2': (StepKind.implementacao, 'sonnet', 'medium'),
      });
      await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      expect((await f.sessions()).single.steps, 'R1');
      expect(f.modelOf(0), ('haiku', 'low'));
    });

    test('a sub-step created during the run takes the plan of its '
        'requirement, and keeps it', () async {
      f = await OrchestratorFixture.create();
      await f.plan({
        for (final r in ['R1', 'R2', 'R3', 'R4'])
          r: (StepKind.altoRisco, 'opus', 'high'),
      });
      final repo = f.c.read(specStepsRepoProvider);
      await repo.addSubSteps(f.spec.id, 'R1', ['parte a', 'parte b']);
      await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      expect((await f.sessions()).single.steps, 'R1.1');
      expect(f.modelOf(0), ('opus', 'high'));
      final sub = await f.row('R1.1');
      expect(
        (sub.kind, sub.planModel, sub.planEffort),
        ('altoRisco', 'opus', 'high'),
      );
    });

    test('the automatic reviewer uses the line Revisão and REV<n> the rule '
        'Implementação; in Manual, the model of the project', () async {
      f = await OrchestratorFixture.create(
        specText: _reviewSpec,
        config: 'revisor:\n  ligado: true\n  modelo: haiku\n  rodadas: 2\n',
      );
      await gitIn(f.repo, ['add', '.']);
      await gitIn(f.repo, ['commit', '-q', '-m', 'spec']);
      await f.plan({
        'R1': (StepKind.mecanica, 'sonnet', 'low'),
        'R2': (StepKind.mecanica, 'sonnet', 'low'),
      });
      await storeReviewRule(
        f.c.read(appSettingsProvider.notifier),
        f.spec.id,
        const StepRule('opus', 'high'),
      );
      await f.c
          .read(orchestratorPrefsProvider.notifier)
          .setRule(StepKind.implementacao, const StepRule('haiku', 'high'));
      await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      expect(f.modelOf(0), ('sonnet', 'low'));
      final wt = await f.worktree();
      File('$wt/ola.txt').writeAsStringSync('ola\n');
      await gitIn(wt, ['add', '.']);
      await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1, R2: ola']);
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1, R2'));

      await waitFor(() async => f.cli.processes.length == 2);
      expect(f.modelOf(1), ('opus', 'high'));
      f.cli.last.emit(
        _verdict({
          'veredito': 'corrigir',
          'resumo': 'Falta tchau.txt.',
          'comentarios': [
            {
              'arquivo': 'tchau.txt',
              'linha': 0,
              'texto': 'crie tchau.txt',
              'severidade': 'alta',
              'requisito': 'R2',
            },
          ],
        }),
      );
      await waitFor(() async => f.cli.processes.length == 3);
      expect((await f.sessions()).last.steps, 'REV1');
      expect(f.modelOf(2), ('haiku', 'high'));
      expect((await f.row('REV1')).kind, 'implementacao');

      // Manual: Executar removes the plan, the reviewer uses `modelo:`.
      await clearStoredPlan(f.c.read(specStepsRepoProvider), f.spec.id);
      File('$wt/tchau.txt').writeAsStringSync('tchau\n');
      await gitIn(wt, ['add', '.']);
      await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 REV1: tchau']);
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: REV1'));
      await waitFor(() async => f.cli.processes.length == 4);
      expect(f.modelOf(3).$1, 'haiku');
      expect(f.modelOf(3).$2, isNot('high'));
    });

    test('R19: with "Abrir Executar em Automático" on, the autopilot '
        'classifies and runs with the plan', () async {
      final classifier = FakeClassifier(
        kinds: {'R1': 'mecanica', 'R2': 'altoRisco'},
      );
      f = await OrchestratorFixture.create(classifier: classifier);
      await f.c.read(orchestratorPrefsProvider.notifier).setAutoByDefault(true);
      await f.c.read(autopilotProvider.notifier).start(f.ws.id);
      await waitFor(() async => f.cli.processes.isNotEmpty);
      expect(classifier.calls, 1);
      expect(f.modelOf(0), ('haiku', 'low'));
      final r2 = await f.row('R2');
      expect(
        (r2.kind, r2.planModel, r2.planEffort),
        ('altoRisco', 'opus', 'high'),
      );
    });

    test('R19: a failed classification does not stop the spec: the model of '
        'Sessões, and the timeline says why', () async {
      final classifier = FakeClassifier(
        error: const PlannerException('O provedor claude encerrou.'),
      );
      f = await OrchestratorFixture.create(classifier: classifier);
      await f.c
          .read(appSettingsProvider.notifier)
          .set(AppSettingKeys.runModel('session'), 'opus');
      await f.c.read(orchestratorPrefsProvider.notifier).setAutoByDefault(true);
      await f.c.read(autopilotProvider.notifier).start(f.ws.id);
      await waitFor(() async => f.cli.processes.isNotEmpty);
      expect(f.modelOf(0).$1, 'opus');
      expect(
        runsInAuto(await f.c.read(specStepsRepoProvider).bySpec(f.spec.id)),
        isFalse,
      );
      final s = (await f.sessions()).single;
      expect(
        (await f.notes(s.id)).single,
        startsWith('Orquestrador: não deu para classificar as etapas'),
      );
    });

    test('R19: off, the autopilot does not classify', () async {
      final classifier = FakeClassifier();
      f = await OrchestratorFixture.create(classifier: classifier);
      await f.c.read(autopilotProvider.notifier).start(f.ws.id);
      await waitFor(() async => f.cli.processes.isNotEmpty);
      expect(classifier.calls, 0);
      expect(f.modelOf(0).$1, 'sonnet');
      expect(
        runsInAuto(await f.c.read(specStepsRepoProvider).bySpec(f.spec.id)),
        isFalse,
      );
    });

    test('R20: "Refazer etapa" and the duel keep the model the step used '
        'last', () async {
      f = await OrchestratorFixture.create();
      await f.plan({
        for (final r in ['R1', 'R2', 'R3', 'R4'])
          r: (StepKind.mecanica, 'haiku', 'low'),
      });
      final runner = f.c.read(specRunnerProvider);
      await runner.runNext(f.spec.id);
      await settle();
      f.cli.last.emit(resultLine('Qual banco?'));
      await waitFor(
        () async => (await f.states())['R1'] == StepStatus.needsInput,
      );
      // The plan changes after the attempt: the redo keeps haiku.
      await f.plan({'R1': (StepKind.altoRisco, 'opus', 'high')});
      await runner.redo(f.spec.id, 'R1');
      await settle();
      expect(f.cli.processes, hasLength(2));
      expect(f.modelOf(1), ('haiku', 'low'));
      expect(f.prompt(1), contains('Tentativa anterior desta etapa'));

      f.cli.last.emit(resultLine('Ainda não sei.'));
      await waitFor(
        () async => (await f.states())['R1'] == StepStatus.needsInput,
      );
      await runner.runNext(f.spec.id, duel: true);
      await waitFor(() async => f.cli.processes.length == 4);
      expect(f.modelOf(2), ('haiku', 'low'));
      expect(f.modelOf(3), ('haiku', 'low'));
    });
  });

  group('SPEC-109: desvio por cota (temporary repo, fake CLIs)', () {
    late OrchestratorFixture f;

    tearDown(() => f.dispose());

    const opus = StepRule('opus', 'high');
    const sonnet = StepRule('sonnet', 'medium');
    const sol = StepRule('gpt-6.2-sol', 'high', provider: 'codex');
    final renew = DateTime.now().add(const Duration(hours: 3));

    Future<void> plan([Map<String, (StepKind, StepRule)>? rules]) =>
        f.planRules(
          rules ??
              {
                'R1': (StepKind.altoRisco, opus),
                'R2': (StepKind.altoRisco, opus),
                'R3': (StepKind.implementacao, sonnet),
                'R4': (StepKind.implementacao, sonnet),
              },
        );

    /// The Claude session hits the limit in the middle of its step.
    void claudeLimit({DateTime? at}) {
      f.cli.last
        ..emit(rateLimitLine(at ?? renew))
        ..emit(failedLine("You've hit your limit"));
    }

    Future<String> git(String dir, List<String> args) async {
      final r = await Process.run('git', args, workingDirectory: dir);
      return '${r.stdout}'.trim();
    }

    Future<List<StepRun>> runs() =>
        f.c.read(stepRunsRepoProvider).bySpec(f.spec.id);

    test('with everything at the default, a limit leaves the step waiting '
        'as before: no diversion, nothing stored, no Codex', () async {
      f = await OrchestratorFixture.create(codex: true);
      await plan();
      await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      final wt = await f.worktree();
      File('$wt/novo.txt').writeAsStringSync('em andamento');
      claudeLimit();
      await waitFor(
        () async => (await f.states())['R1'] == StepStatus.needsInput,
      );
      expect(f.servers, isEmpty);
      expect(await f.sessions(), hasLength(1));
      // The work in progress stays in the worktree.
      expect(File('$wt/novo.txt').existsSync(), isTrue);
      expect(await runs(), isEmpty);
      final settings = f.c.read(appSettingsProvider);
      expect(
        settings.keys.where(
          (k) =>
              k.contains('quotaHit') ||
              k.endsWith('.divert') ||
              k.endsWith('.quotaWait'),
        ),
        isEmpty,
      );
    });

    test('R5: the limit ends the session, the worktree goes back to the '
        'start of the step and the step goes on in the other provider with '
        'the package; nothing outside the worktree changes', () async {
      f = await OrchestratorFixture.create(codex: true);
      await gitIn(f.repo, ['add', '.']);
      await gitIn(f.repo, ['commit', '-q', '-m', 'spec']);
      await f.prefs.setDivertOnQuota(true);
      await plan();
      final runner = f.c.read(specRunnerProvider);
      await runner.runNext(f.spec.id);
      await settle();
      await f.commit('R1');
      f.cli.last.emit(contextAnswer(20000));
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
      await waitFor(() async => (await f.states())['R2'] == StepStatus.running);
      final wt = await f.worktree();
      final r1 = await git(wt, ['rev-parse', 'HEAD']);

      // What must not change: the root of the project (HEAD, staged, not
      // committed and untracked files) and another worktree.
      final other = '${f.tmp.path}/outra';
      await gitIn(f.repo, ['worktree', 'add', '-q', '-b', 'outra', other]);
      for (final d in [f.repo, other]) {
        File('$d/a.txt').writeAsStringSync('mudado em $d');
        File('$d/meu.txt').writeAsStringSync('sem commit');
        File('$d/pronto.txt').writeAsStringSync('no index');
        await gitIn(d, ['add', 'pronto.txt']);
      }
      Future<List<String>> outside() async => [
        for (final d in [f.repo, other]) ...[
          await git(d, ['rev-parse', 'HEAD']),
          await git(d, ['branch', '--show-current']),
          await git(d, ['status', '--porcelain']),
          await git(d, ['diff']),
          await git(d, ['diff', '--cached']),
          File('$d/meu.txt').readAsStringSync(),
        ],
      ];
      final before = await outside();

      // The attempt of R2: a commit, a change and a new file.
      await f.commit('R2');
      File('$wt/r1.txt').writeAsStringSync('estragado');
      File('$wt/parcial.txt').writeAsStringSync('meio caminho');
      claudeLimit();
      await waitFor(() async => f.servers.isNotEmpty);
      await waitFor(() async => (await f.states())['R2'] == StepStatus.running);

      // The worktree is back at the start of R2; R1 stays done.
      expect(await git(wt, ['rev-parse', 'HEAD']), r1);
      expect(await git(wt, ['status', '--porcelain']), '');
      expect(File('$wt/r1.txt').readAsStringSync(), 'R1');
      expect(File('$wt/r2.txt').existsSync(), isFalse);
      expect(File('$wt/parcial.txt').existsSync(), isFalse);
      expect((await f.states())['R1'], StepStatus.done);
      expect(await outside(), before);

      // A new session, in the same worktree, with the reserve of the kind.
      final sessions = await f.sessions();
      expect(sessions, hasLength(2));
      expect(
        sessions.map((s) => (s.provider, s.model, s.effort, s.worktreePath)),
        [('claude', 'opus', 'high', wt), ('codex', 'gpt-6.2-sol', 'high', wt)],
      );
      expect(sessions.last.steps, 'R2');
      expect(sessions.last.parentSessionId, sessions.first.id);
      expect(f.codexCwds.single, wt);

      // The package: the spec, the finished steps, the partial diff (new
      // files included) and the state of git.
      final prompt = f.codexPrompt(f.servers.single);
      expect(prompt, contains('- R1 · Extrair tabelas'));
      expect(prompt, contains('<spec>'));
      expect(prompt, contains('interrompida porque a cota dele acabou'));
      expect(prompt, contains('+meio caminho'));
      expect(prompt, contains('r2.txt'));
      expect(prompt, contains('de volta ao início da etapa'));
      // What was undone is kept.
      const ref = 'refs/promptorium/SPEC-001/R2-cota';
      expect(await git(wt, ['show', '$ref:parcial.txt']), 'meio caminho');

      // The timeline of both says it; it is neither a failure nor an
      // escalation.
      for (final s in sessions) {
        expect(
          await f.notes(s.id),
          contains(
            allOf(
              startsWith('Cota do Claude esgotada (janela de 5 h, renova '),
              contains('R2 seguiu no Codex · gpt-6.2-sol · high'),
              contains('não conta como reprovação nem como escalada'),
            ),
          ),
        );
      }
      expect((await f.row('R2')).escalations, 0);
      expect((await f.row('R2')).gateAttempts, 0);
      final all = await runs();
      expect(
        all.map((r) => (r.step, r.provider, r.model, r.result, r.diverted)),
        [
          ('R1', 'claude', 'opus', StepRunResult.passed, null),
          ('R2', 'claude', 'opus', StepRunResult.diverted, 'quota'),
        ],
      );
      final divert = f.c.read(quotaDiverterProvider).divertOf(f.spec.id)!;
      expect((divert.step, divert.from, divert.to), ('R2', 'claude', sol));

      // The end of R2 on the Codex is recorded as such, without US\$.
      await f.commit('R2');
      f.servers.single
        ..answer('ETAPA CONCLUÍDA: R2')
        ..completeTurn();
      await waitFor(() async => (await f.states())['R3'] == StepStatus.running);
      final last = (await runs()).last;
      expect(
        (last.step, last.provider, last.result, last.diverted, last.costUsd),
        ('R2', 'codex', StepRunResult.passed, 'quota', null),
      );

      // R7: the quota of the Claude did not renew: R3 stays there, with the
      // reserve of its own kind.
      var s3 = (await f.sessions()).last;
      expect(
        (s3.provider, s3.model, s3.effort),
        ('codex', 'gpt-6.2-sol', 'medium'),
      );
      expect(
        (await f.notes(s3.id)).where((n) => n.contains('o desvio vale até')),
        hasLength(1),
      );
      // It renewed: R4 goes back to the plan.
      await f.c
          .read(quotaDiverterProvider)
          .recordHit(
            QuotaHit(
              provider: 'claude',
              at: DateTime.now().subtract(const Duration(hours: 5)),
              minutes: 300,
              resetsAt: DateTime.now().subtract(const Duration(minutes: 1)),
            ),
          );
      await f.c
          .read(rateLimitProvider.notifier)
          .record(
            AgentEvent.fromJson(
              jsonDecode(rateLimitLine(renew, status: 'allowed', used: 0.02))
                  as Map<String, dynamic>,
            ) as RateLimit,
          );
      f.servers.last
        ..answer('ETAPA CONCLUÍDA: R3')
        ..completeTurn();
      await waitFor(() async => (await f.states())['R4'] == StepStatus.running);
      s3 = (await f.sessions()).last;
      expect(
        (s3.provider, s3.model, s3.effort),
        ('claude', 'sonnet', 'medium'),
      );
      expect(s3.worktreePath, wt);
      expect(
        await f.notes(s3.id),
        contains(
          'Cota do Claude renovou · R4 volta ao plano: '
          'Claude · Sonnet · medium.',
        ),
      );
      expect(f.c.read(quotaDiverterProvider).divertOf(f.spec.id), isNull);
    });

    test('the automatic rewind refuses anything but the worktree of the '
        'spec', () async {
      f = await OrchestratorFixture.create(codex: true);
      await gitIn(f.repo, ['add', '.']);
      await gitIn(f.repo, ['commit', '-q', '-m', 'spec']);
      final d = f.c.read(quotaDiverterProvider);
      final plain = Directory('${f.repo}/pasta')..createSync();
      expect(await d.notOwnWorktree(f.repo, f.repo), contains('raiz'));
      expect(
        await d.notOwnWorktree(f.repo, plain.path),
        contains('não é a raiz de um worktree'),
      );
      final elsewhere = Directory('${f.tmp.path}/alheio')..createSync();
      await gitIn(elsewhere.path, ['init', '-q']);
      expect(
        await d.notOwnWorktree(f.repo, elsewhere.path),
        contains('não é um worktree deste projeto'),
      );

      // A spec whose worktree folder lost its `.git` (git would climb to
      // the repository above it): nothing is undone, the step waits.
      await f.prefs.setDivertOnQuota(true);
      await plan();
      final id = await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      final wt = await f.worktree();
      expect(await d.notOwnWorktree(f.repo, wt), isNull);
      File('$wt/meu.txt').writeAsStringSync('trabalho');
      File('$wt/.git').deleteSync();
      claudeLimit();
      await waitFor(
        () async =>
            (await f.notes(id))
                .any((n) => n.contains('o desvio por cota não foi feito')),
      );
      expect((await f.states())['R1'], StepStatus.needsInput);
      expect(f.servers, isEmpty);
      expect(File('$wt/meu.txt').readAsStringSync(), 'trabalho');
      expect(
        await git(f.repo, ['status', '--porcelain']),
        isNot(contains('D ')),
      );
    });

    test('R5: the limit of the Codex sends the step to the Claude, and the '
        'YOLO of the Codex never goes with it', () async {
      f = await OrchestratorFixture.create(
        codex: true,
        codexStatus: const ProviderAvailability(
          ProviderStatus.ready,
          'ok',
          sandboxWarning: 'sem sandbox',
        ),
      );
      await f.prefs.setDivertOnQuota(true);
      const luna = StepRule('gpt-6-luna', 'low', provider: 'codex');
      await plan({
        'R1': (StepKind.mecanica, luna),
        'R2': (StepKind.mecanica, luna),
        'R3': (StepKind.mecanica, luna),
        'R4': (StepKind.mecanica, luna),
      });
      await f.c.read(providerAvailabilityProvider('codex').future);
      await f.c
          .read(appSettingsProvider.notifier)
          .set(
            AppSettingKeys.specAutoMode(f.spec.id),
            ClaudePermissionMode.acceptEdits.cliValue,
          );
      await f.c
          .read(specRunnerProvider)
          .runNext(f.spec.id, mode: ClaudePermissionMode.acceptEdits);
      await settle();
      var s = (await f.sessions()).single;
      expect((s.provider, s.model, s.effort), ('codex', 'gpt-6-luna', 'low'));
      // Without the sandbox the Codex only runs in YOLO (decision 15).
      expect(s.permissionMode, ClaudePermissionMode.skipPermissions.cliValue);
      f.servers.last
        ..emit(codexRateLine(renew, reached: 'rate_limit_reached'))
        ..emit(codexLimitTurn(f.servers.last.threadId));
      await waitFor(() async => f.cli.processes.isNotEmpty);
      s = (await f.sessions()).last;
      expect((s.provider, s.model), ('claude', 'haiku'));
      expect(s.permissionMode, ClaudePermissionMode.acceptEdits.cliValue);
      expect(
        (await f.notes(s.id)).first,
        contains('R1 seguiu no Claude · Haiku · low'),
      );
      // The reserve of Mecânica on the Claude is its line of the table.
      expect(f.modelOf(0), ('haiku', 'low'));
    });

    test('R5: a limit the Codex only tells in the reading '
        '(ordinaryUsageAllowed = false)', () async {
      f = await OrchestratorFixture.create(
        codex: true,
        codexQuotaRead: {
          'ordinaryUsageAllowed': false,
          'rateLimits': {
            'limitId': 'codex',
            'primary': {
              'usedPercent': 97,
              'windowDurationMins': 300,
              'resetsAt': renew.millisecondsSinceEpoch ~/ 1000,
            },
          },
        },
      );
      await f.prefs.setDivertOnQuota(true);
      const luna = StepRule('gpt-6-luna', 'low', provider: 'codex');
      await plan({
        for (final r in ['R1', 'R2', 'R3', 'R4']) r: (StepKind.mecanica, luna),
      });
      await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      f.servers.last.emit(
        jsonEncode({
          'method': 'turn/completed',
          'params': {
            'threadId': f.servers.last.threadId,
            'turn': {
              'id': 'turn-1',
              'status': 'failed',
              'error': {'message': 'stream error'},
            },
          },
        }),
      );
      await waitFor(() async => f.cli.processes.isNotEmpty);
      expect((await f.sessions()).last.provider, 'claude');
    });

    test('R6: the preventive diversion happens at the boundary, never in '
        'the middle; a step under way ends where it started', () async {
      f = await OrchestratorFixture.create(codex: true);
      await f.prefs.setDivertAbove(true);
      await plan();
      await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      // 93% in the middle of R1: nothing happens.
      f.cli.last.emit(
        rateLimitLine(renew, status: 'allowed_warning', used: 0.93),
      );
      await settle();
      expect(f.servers, isEmpty);
      expect((await f.states())['R1'], StepStatus.running);
      f.cli.last.emit(contextAnswer(20000));
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
      await waitFor(() async => f.servers.isNotEmpty);
      await waitFor(() async => (await f.states())['R2'] == StepStatus.running);
      final sessions = await f.sessions();
      expect(sessions.last.provider, 'codex');
      expect(
        (await f.notes(sessions.last.id)).first,
        startsWith(
          'Claude · janela de 5 h em 93% ≥ 90% · R2 começou no Codex · '
          'gpt-6.2-sol · high',
        ),
      );
      expect(
        (await runs()).map((r) => (r.step, r.provider, r.result, r.diverted)),
        [
          ('R1', 'claude', StepRunResult.passed, null),
          ('R2', 'claude', StepRunResult.diverted, 'threshold'),
        ],
      );
    });

    test('R8: without quota in both the step waits with the renewals and '
        'the three actions; nothing goes to another provider', () async {
      f = await OrchestratorFixture.create(codex: true);
      await f.prefs.setDivertOnQuota(true);
      await plan();
      final runner = f.c.read(specRunnerProvider);
      final diverter = f.c.read(quotaDiverterProvider);
      final codexRenew = DateTime.now().add(const Duration(hours: 1));
      await diverter.recordHit(
        QuotaHit(
          provider: 'codex',
          at: DateTime.now(),
          minutes: 300,
          resetsAt: codexRenew,
        ),
      );
      final id = await runner.runNext(f.spec.id);
      await settle();
      final wt = await f.worktree();
      File('$wt/parcial.txt').writeAsStringSync('meio caminho');
      claudeLimit();
      await waitFor(() async => diverter.waitOf(f.spec.id) != null);
      expect((await f.states())['R1'], StepStatus.needsInput);
      expect(f.servers, isEmpty);
      expect(f.cli.processes, hasLength(1));
      // While it waits nothing was undone.
      expect(File('$wt/parcial.txt').existsSync(), isTrue);
      var wait = diverter.waitOf(f.spec.id)!;
      expect(wait.bothOut, isTrue);
      expect(wait.firstRenewal!.difference(codexRenew).inSeconds, 0);
      expect(
        (await f.notes(id)).last,
        startsWith(
          'R1 aguarda você: sem cota nos dois provedores (Claude renova ',
        ),
      );
      // The three actions: the choices of "Executar agora com…" and the
      // scheduled resume ("Usar Manual" opens Executar).
      expect(await runner.runNowChoices(f.spec.id), [opus, sol]);
      await runner.scheduleResume(f.spec.id);
      wait = diverter.waitOf(f.spec.id)!;
      expect(wait.resumeAt!.difference(codexRenew).inSeconds, 0);
      await runner.resumeDue();
      expect(f.servers, isEmpty, reason: 'not yet');

      // R12: paused, it is neither resumed nor scheduled.
      final pause = f.c.read(automationPausedProvider.notifier);
      await pause.set(true);
      await runner.resumeDue(now: codexRenew.add(const Duration(minutes: 1)));
      expect(f.servers, isEmpty);
      await runner.scheduleResume(f.spec.id, on: false);
      await expectLater(
        runner.scheduleResume(f.spec.id),
        throwsA(isA<SpecRunException>()),
      );
      await pause.set(false);
      await runner.scheduleResume(f.spec.id);

      // The Codex renewed: the step goes on there, from its start.
      await diverter.recordHit(
        QuotaHit(
          provider: 'codex',
          at: DateTime.now().subtract(const Duration(hours: 5)),
          resetsAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      await runner.resumeDue(now: codexRenew.add(const Duration(minutes: 1)));
      await settle();
      expect(f.servers, hasLength(1));
      expect((await f.sessions()).last.provider, 'codex');
      expect(diverter.waitOf(f.spec.id), isNull);
      expect(File('$wt/parcial.txt').existsSync(), isFalse);
      expect(
        f.codexPrompt(f.servers.single),
        contains('interrompida porque a cota acabou'),
      );
    });

    test('R8: "Executar agora com…" is an explicit choice, and acting '
        'cancels the scheduled resume', () async {
      f = await OrchestratorFixture.create(codex: true);
      await f.prefs.setDivertOnQuota(true);
      await plan();
      final runner = f.c.read(specRunnerProvider);
      final diverter = f.c.read(quotaDiverterProvider);
      for (final p in ['claude', 'codex']) {
        await diverter.recordHit(
          QuotaHit(
            provider: p,
            at: DateTime.now(),
            minutes: 300,
            resetsAt: renew,
          ),
        );
      }
      // At the boundary: the step does not even start.
      await expectLater(
        runner.runNext(f.spec.id),
        throwsA(
          isA<SpecRunException>().having(
            (e) => e.message,
            'message',
            contains('R1 aguarda você: sem cota nos dois provedores'),
          ),
        ),
      );
      expect((await f.states())['R1'], StepStatus.needsInput);
      await runner.scheduleResume(f.spec.id);
      await runner.runNow(f.spec.id, opus);
      await settle();
      expect(f.modelOf(0), ('opus', 'high'));
      expect(diverter.waitOf(f.spec.id), isNull);
      await runner.resumeDue(now: renew.add(const Duration(minutes: 1)));
      expect(await f.sessions(), hasLength(1));
    });

    test('R12: "Pausar automáticos" holds the diversion too', () async {
      f = await OrchestratorFixture.create(codex: true);
      await f.prefs.setDivertOnQuota(true);
      await f.prefs.setDivertAbove(true);
      await plan();
      await f.c.read(automationPausedProvider.notifier).set(true);
      await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      claudeLimit();
      await waitFor(
        () async => (await f.states())['R1'] == StepStatus.needsInput,
      );
      expect(f.servers, isEmpty);
      expect(f.c.read(quotaDiverterProvider).waitOf(f.spec.id), isNull);
    });

    test(
      'while the extra usage goes on, a rejected window is not a limit',
      () async {
        f = await OrchestratorFixture.create(codex: true);
        await f.prefs.setDivertOnQuota(true);
        await plan();
        await f.c.read(specRunnerProvider).runNext(f.spec.id);
        await settle();
        f.cli.last
          ..emit(rateLimitLine(renew, overage: true))
          ..emit(resultLine('Preciso de uma decisão sua.'));
        await waitFor(
          () async => (await f.states())['R1'] == StepStatus.needsInput,
        );
        expect(f.servers, isEmpty);
      },
    );

    test('R10: steps of both providers in the same worktree, each in its own '
        'session; a planned Codex step that cannot run says why', () async {
      f = await OrchestratorFixture.create(codex: true);
      const luna = StepRule('gpt-6-luna', 'low', provider: 'codex');
      await plan({
        'R1': (StepKind.mecanica, luna),
        'R2': (StepKind.mecanica, luna),
        'R3': (StepKind.implementacao, sonnet),
        'R4': (StepKind.mecanica, luna),
      });
      await f.c
          .read(specRunnerProvider)
          .runNext(f.spec.id, mode: ClaudePermissionMode.acceptEdits);
      await settle();
      expect(f.codexModel(f.servers.single), ('gpt-6-luna', 'low'));
      // A run in Automático is recorded as `claude`: the next steps read
      // their plan.
      expect(
        recordedSpecProvider(f.c.read(appSettingsProvider), f.spec.id),
        'claude',
      );
      // Same provider, model and effort: the same session (below the limit).
      f.servers.single.emit(
        jsonEncode({
          'method': 'thread/tokenUsage/updated',
          'params': {
            'threadId': f.servers.single.threadId,
            'turnId': 'turn-1',
            'tokenUsage': {
              'last': {'totalTokens': 20000, 'inputTokens': 20000},
              'total': {'totalTokens': 20000, 'inputTokens': 20000},
              'modelContextWindow': 400000,
            },
          },
        }),
      );
      f.servers.single
        ..answer('ETAPA CONCLUÍDA: R1')
        ..completeTurn();
      await waitFor(() async => (await f.states())['R2'] == StepStatus.running);
      expect(f.servers, hasLength(1));
      // Another provider: a new session.
      f.servers.single
        ..answer('ETAPA CONCLUÍDA: R2')
        ..completeTurn();
      await waitFor(() async => f.cli.processes.isNotEmpty);
      await waitFor(() async => (await f.states())['R3'] == StepStatus.running);
      expect(f.modelOf(0), ('sonnet', 'medium'));
      f.cli.last.emit(contextAnswer(20000));
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: R3'));
      await waitFor(() async => f.servers.length == 2);
      final wt = await f.worktree();
      final sessions = await f.sessions();
      expect(sessions.map((s) => (s.provider, s.steps, s.worktreePath)), [
        ('codex', 'R1,R2', wt),
        ('claude', 'R3', wt),
        ('codex', 'R4', wt),
      ]);
      expect(
        await f.notes(sessions.first.id),
        contains(
          'R3 vai para uma sessão nova: o plano muda de Codex · gpt-6-luna '
          '· low para Claude · Sonnet · medium.',
        ),
      );
    });

    test('R9: a planned Codex step does not go elsewhere in silence', () async {
      f = await OrchestratorFixture.create(
        codex: true,
        codexStatus: const ProviderAvailability(
          ProviderStatus.loginRequired,
          'rode codex login',
        ),
      );
      const luna = StepRule('gpt-6-luna', 'low', provider: 'codex');
      await plan({'R1': (StepKind.mecanica, luna)});
      await expectLater(
        f.c.read(specRunnerProvider).runNext(f.spec.id),
        throwsA(
          isA<SpecRunException>().having(
            (e) => e.message,
            'message',
            'R1 está no Codex, que não pode rodar agora: login pendente.',
          ),
        ),
      );
      expect(f.cli.processes, isEmpty);
      expect(await f.sessions(), isEmpty);
    });
  });
}
