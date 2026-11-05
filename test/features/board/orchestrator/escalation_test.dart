import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/orchestrator/escalation.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/board/step_gate.dart';

import '../step_decision_dialog_test.dart' as modal;
import 'orchestrator_fixture.dart';

/// A runner whose step waits before Opus (R12).
class _AskingRunner extends SpecRunner {
  _AskingRunner(super.ref);

  final escalated = <String>[];

  @override
  Future<EscalationRung?> pendingEscalation(int specId, String step) async =>
      const EscalationRung(StepRule('opus', 'high'), number: 2, ask: true);

  @override
  Future<String> escalate(int specId, String step) async {
    escalated.add(step);
    return 's2';
  }
}

/// Gate with one resend (the commit check fails without a commit).
const _gate = 'testes: "true"\nverificacao:\n  tentativas: 1\n';

OrchestratorPrefs _prefs({int escalations = 2, bool ask = false}) =>
    OrchestratorPrefs({
      AppSettingKeys.orchestratorEscalations: '$escalations',
      AppSettingKeys.orchestratorAskBeforeOpus: ask ? '1' : '0',
    });

void main() {
  group('nextRung', () {
    const haiku = StepRule('haiku', 'low');
    const sonnet = StepRule('sonnet', 'medium');
    const opus = StepRule('opus', 'high');

    test('one rung up, with the effort of the rung, up to the limit', () {
      final p = _prefs();
      expect(nextRung(haiku, 0, p), const EscalationRung(sonnet, number: 1));
      expect(nextRung(const StepRule('haiku', 'high'), 0, p)?.rule, sonnet);
      expect(nextRung(sonnet, 1, p), const EscalationRung(opus, number: 2));
      expect(nextRung(sonnet, 2, p), isNull);
      expect(nextRung(sonnet, 1, _prefs(escalations: 1)), isNull);
      expect(nextRung(haiku, 0, _prefs(escalations: 0)), isNull);
    });

    test('top of the ladder, unknown models and "perguntar antes"', () {
      final p = _prefs(ask: true);
      expect(nextRung(opus, 0, p), isNull);
      expect(nextRung(const StepRule('claude-x', 'low'), 0, p), isNull);
      expect(nextRung(haiku, 0, p)?.ask, isFalse);
      expect(nextRung(sonnet, 0, p)?.ask, isTrue);
      expect(escalationStopReason(opus, 0), 'Opus é o topo da escada');
      expect(
        escalationStopReason(sonnet, 2),
        'as 2 escaladas da etapa já foram usadas',
      );
    });

    test('the trail of R11', () {
      expect(
        escalationTrailLabel(escalationTrail(sonnet, 1)),
        'Sonnet → Opus · high',
      );
      expect(
        escalationTrailLabel(escalationTrail(haiku, 2)),
        'Haiku → Sonnet → Opus · high',
      );
      expect(escalationTrail(opus, 2), [opus]);
      expect(
        stepLadderLabel(
          const StepView(
            id: 'R1',
            text: 'x',
            planModel: 'sonnet',
            planEffort: 'medium',
            escalations: 1,
          ),
        ),
        'Sonnet → Opus · high',
      );
      expect(
        stepLadderLabel(
          const StepView(id: 'R1', text: 'x', planModel: 'sonnet'),
        ),
        isNull,
      );
    });
  });

  group('escalation in the runner (temporary repo, fake CLI)', () {
    late OrchestratorFixture f;

    tearDown(() => f.dispose());

    /// R1 fails the gate twice (first try and the resend).
    Future<void> failTwice() async {
      final wt = await f.worktree();
      // An uncommitted change: the diff of the attempt.
      File('$wt/a.txt').writeAsStringSync('mudou\n');
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
      await waitFor(() async => (await f.row('R1')).gateAttempts == 1);
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
    }

    Future<void> setPrefs({int escalations = 2, bool ask = false}) async {
      final n = f.c.read(orchestratorPrefsProvider.notifier);
      await n.setMaxEscalations(escalations);
      await n.setAskBeforeOpus(ask);
    }

    test('failing after the resends goes up one rung: a new session at the '
        'start of the step, with the report and the diff; the timeline and '
        'the progress show it; the next step goes back to the plan', () async {
      f = await OrchestratorFixture.create(config: _gate);
      await setPrefs();
      await f.plan({
        for (final r in ['R1', 'R2', 'R3', 'R4'])
          r: (StepKind.mecanica, 'haiku', 'low'),
      });
      final runner = f.c.read(specRunnerProvider);
      final first = await runner.runNext(f.spec.id);
      await settle();
      final start = (await f.row('R1')).startSha;
      await failTwice();
      await waitFor(() async => f.cli.processes.length == 2);

      expect(f.modelOf(1), ('sonnet', 'medium'));
      final prompt = f.prompt(1);
      expect(prompt, contains('Implemente a etapa R1'));
      expect(
        prompt,
        contains('Tentativa anterior desta etapa, com Haiku · low'),
      );
      expect(prompt, contains('Verificação falhou'));
      expect(prompt, contains('Diff da tentativa'));
      expect(prompt, contains('+mudou'));
      // Back at the start of the step.
      final wt = await f.worktree();
      expect(File('$wt/a.txt').readAsStringSync(), startsWith('linha 1'));
      final row = await f.row('R1');
      expect(row.escalations, 1);
      expect(row.gateAttempts, 0);
      expect(row.startSha, start);
      expect(row.planModel, 'haiku');
      expect(
        stepLadderLabel((await f.views()).first),
        'Haiku → Sonnet · medium',
      );
      final notes = await f.notes(first);
      expect(notes, contains(startsWith('Verificação falhou')));
      expect(
        notes,
        contains('Reenvio 1 de 1: a falha de R1 volta para esta sessão.'),
      );
      expect(notes, contains(startsWith('Escalada 1 de 2: R1 sobe de Haiku')));
      final second = (await f.sessions()).last;
      expect(second.model, 'sonnet');
      expect(await f.notes(second.id), contains(startsWith('Escalada 1 de 2')));
      var runs = await f.c.read(stepRunsRepoProvider).bySpec(f.spec.id);
      expect(runs.map((r) => (r.step, r.model, r.result, r.sessionId)), [
        ('R1', 'haiku', StepRunResult.escalated, first),
      ]);

      // Sonnet passes; R2 goes back to the plan (R13), in a new session.
      await f.commit('R1');
      f.cli.last.emit(contextAnswer(20000));
      f.cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
      await waitFor(() async => f.cli.processes.length == 3);
      expect(f.modelOf(2), ('haiku', 'low'));
      expect(
        await f.notes(second.id),
        contains(
          'R2 vai para uma sessão nova: o plano muda de Sonnet · medium '
          'para Haiku · low.',
        ),
      );
      runs = await f.c.read(stepRunsRepoProvider).bySpec(f.spec.id);
      expect(runs.last.result, StepRunResult.passed);
      expect(runs.last.model, 'sonnet');
    });

    test('with 0 escalations nothing changes: the step waits for the '
        'person', () async {
      f = await OrchestratorFixture.create(config: _gate);
      await setPrefs(escalations: 0);
      await f.plan({'R1': (StepKind.mecanica, 'haiku', 'low')});
      final first = await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      await failTwice();
      await waitFor(
        () async => (await f.states())['R1'] == StepStatus.needsInput,
      );
      await settle();
      expect(f.cli.processes, hasLength(1));
      expect((await f.row('R1')).escalations, 0);
      expect(await f.notes(first), isNot(contains(startsWith('Escalada'))));
      expect(
        (await f.c.read(stepRunsRepoProvider).bySpec(f.spec.id)).single.result,
        StepRunResult.failed,
      );
    });

    test('Manual does not escalate', () async {
      f = await OrchestratorFixture.create(config: _gate);
      await setPrefs();
      await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      await failTwice();
      await waitFor(
        () async => (await f.states())['R1'] == StepStatus.needsInput,
      );
      await settle();
      expect(f.cli.processes, hasLength(1));
      final run = (await f.c.read(stepRunsRepoProvider).bySpec(f.spec.id))
          .single;
      expect((run.kind, run.result), (null, StepRunResult.failed));
    });

    test('"Perguntar antes de escalar para Opus": the step waits and '
        '"Escalar para Opus" goes up', () async {
      f = await OrchestratorFixture.create(config: _gate);
      await setPrefs(ask: true);
      await f.plan({'R1': (StepKind.implementacao, 'sonnet', 'medium')});
      final runner = f.c.read(specRunnerProvider);
      final first = await runner.runNext(f.spec.id);
      await settle();
      await failTwice();
      await waitFor(
        () async => (await f.states())['R1'] == StepStatus.needsInput,
      );
      await settle();
      expect(f.cli.processes, hasLength(1));
      expect(
        await f.notes(first),
        contains(
          'R1 aguarda você antes de escalar de Sonnet · medium para '
          'Opus · high ("Escalar para Opus").',
        ),
      );
      final rung = await runner.pendingEscalation(f.spec.id, 'R1');
      expect(
        rung,
        const EscalationRung(StepRule('opus', 'high'), number: 1, ask: true),
      );
      await runner.escalate(f.spec.id, 'R1');
      await settle();
      expect(f.cli.processes, hasLength(2));
      expect(f.modelOf(1), ('opus', 'high'));
      expect((await f.row('R1')).escalations, 1);
      expect(await runner.pendingEscalation(f.spec.id, 'R1'), isNull);
    });

    test('at the top of the ladder the step waits with the report of the '
        'last attempt', () async {
      f = await OrchestratorFixture.create(config: _gate);
      await setPrefs();
      await f.plan({'R1': (StepKind.altoRisco, 'opus', 'high')});
      final first = await f.c.read(specRunnerProvider).runNext(f.spec.id);
      await settle();
      await failTwice();
      await waitFor(
        () async => (await f.states())['R1'] == StepStatus.needsInput,
      );
      await settle();
      expect(f.cli.processes, hasLength(1));
      final report = GateReport.decode((await f.row('R1')).gateReport)!;
      expect(report.ok, isFalse);
      expect((await f.views()).first.gateFailed, isTrue);
      expect(
        await f.notes(first),
        contains('R1 aguarda você: Opus é o topo da escada.'),
      );
      expect(
        await f.c.read(specRunnerProvider).pendingEscalation(f.spec.id, 'R1'),
        isNull,
      );
    });
  });

  testWidgets('the modal of SPEC-033 has "Escalar para Opus", which goes up '
      'and closes', (tester) async {
    _AskingRunner? runner;
    await modal.openModal(
      tester,
      overrides: [
        specRunnerProvider.overrideWith((ref) => runner = _AskingRunner(ref)),
      ],
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await modal.settle(tester);
    final button = find.byKey(const ValueKey('step-decision-escalate'));
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('Escalar para Opus')),
      findsOneWidget,
    );
    await tester.tap(button);
    await modal.settle(tester);
    expect(runner!.escalated, ['R3']);
    expect(modal.dialog, findsNothing);
  });
}
