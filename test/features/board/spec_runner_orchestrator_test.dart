import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/readonly_run.dart'
    show PlannerException;
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/board/orchestrator/step_plan.dart';
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
}
