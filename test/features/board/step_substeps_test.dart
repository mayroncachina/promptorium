import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/review/review_logic.dart';
import 'package:promptorium/features/sessions/timeline.dart' show AppEventTypes;
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/widgets/step_trace_panel.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

const specText = '''---
id: SPEC-001
status: aprovada
---

# Extração do schema

## Objetivo

Ler o schema.

## Requisitos

- R1 · Extrair tabelas
- R2 · Extrair índices
- R3 · Extrair generators
- R4 · Ligar na CLI

## Design

### R1 · Tabelas

Em lib/tables.dart.

### R3 · Generators

Em lib/generators.dart.

## Critérios de aceite

- [ ] r3.txt existe [R3] · verificar: test -f r3.txt
''';

String resultLine(String text) {
  final j = jsonDecode(
    fixtureLines().firstWhere((l) => l.contains('"result"')),
  ) as Map<String, dynamic>;
  j['result'] = text;
  return jsonEncode(j);
}

/// Top-level answer that leaves the context well below the limit.
String smallContext() => jsonEncode({
  'type': 'assistant',
  'message': {
    'id': 'msg-small',
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': 'Feito.'},
    ],
    'usage': {
      'input_tokens': 2,
      'cache_read_input_tokens': 10000,
      'cache_creation_input_tokens': 1000,
      'output_tokens': 50,
    },
  },
});

Spec specOf({List<SpecRequirement>? requirements}) => Spec(
  hasPlan: false,
  inTray: false,
  id: 1,
  workspaceId: 1,
  code: 'SPEC-001',
  title: 'Extração do schema',
  status: SpecStatus.approved,
  path: 'specs/SPEC-001-x.md',
  stage: SpecStage.running,
  requirements:
      requirements ??
      const [
        (id: 'R1', text: 'Extrair tabelas'),
        (id: 'R3', text: 'Extrair generators'),
        (id: 'R4', text: 'Ligar na CLI'),
      ],
  dependsOn: const [],
  autoAdvance: true,
  reviewRounds: 0,
  gateResends: 0,
  rejectedHunks: 0,
);

SpecStep row(
  String step, {
  String? body,
  StepStatus status = StepStatus.pending,
}) => SpecStep(
  specId: 1,
  step: step,
  status: status,
  gateAttempts: 0,
  body: body,
  userPicked: false,
  escalations: 0,
);

void main() {
  group('pure', () {
    test('isSubStep and parentOf', () {
      expect(isSubStep('R3.1'), isTrue);
      expect(isSubStep('R3.10'), isTrue);
      for (final id in ['R3', 'REV1', 'R3.', 'R3.1.2', 'REV1.1']) {
        expect(isSubStep(id), isFalse, reason: id);
      }
      expect(parentOf('R3.10'), 'R3');
      expect(parentOf('R3'), 'R3');
      expect(parentOf('REV1'), 'REV1');
    });

    test('stepsOf: the sub-steps take the place of the requirement, the '
        'others and the reviewer steps stay where they were', () {
      final steps = stepsOf(specOf(), [
        row('R3', status: StepStatus.pending),
        row('R3.2', body: 'b', status: StepStatus.running),
        row('R3.1', body: 'a', status: StepStatus.done),
        row('REV1', body: 'corrigir'),
      ]);
      expect(steps.map((s) => s.id), ['R1', 'R3.1', 'R3.2', 'R4', 'REV1']);
      expect(steps[1].text, 'a');
      expect(steps[1].isDone, isTrue);
      expect(steps[2].status, StepStatus.running);
    });

    test('stepsOf: number order, not text order; a row without text is not '
        'a sub-step; a requirement out of the file takes its sub-steps', () {
      final ids = stepsOf(specOf(), [
        row('R3.10', body: 'j'),
        row('R3.2', body: 'b'),
        row('R3.1', body: 'a'),
      ]).map((s) => s.id);
      expect(ids, ['R1', 'R3.1', 'R3.2', 'R3.10', 'R4']);
      expect(stepsOf(specOf(), [row('R3.1')]).map((s) => s.id), [
        'R1',
        'R3',
        'R4',
      ]);
      expect(stepsOf(specOf(), [row('R9.1', body: 'x')]).map((s) => s.id), [
        'R1',
        'R3',
        'R4',
      ]);
    });

    test('nextSteps: a sub-step is never grouped, even in a small spec', () {
      const small = [
        StepView(id: 'R1', text: 'a'),
        StepView(id: 'R2', text: 'b'),
      ];
      expect(nextSteps(small, singleSessionMax: 3), ['R1', 'R2']);
      const split = [
        StepView(id: 'R1.1', text: 'a'),
        StepView(id: 'R1.2', text: 'b'),
        StepView(id: 'R2', text: 'c'),
      ];
      expect(nextSteps(split, singleSessionMax: 3), ['R1.1']);
      expect(
        nextSteps(const [
          StepView(id: 'R1.1', text: 'a', status: StepStatus.done),
          StepView(id: 'R1.2', text: 'b'),
        ], singleSessionMax: 3),
        ['R1.2'],
      );
    });

    test('closesRequirement: only with the other sub-steps done', () {
      const steps = [
        StepView(id: 'R1', text: 'x'),
        StepView(id: 'R3.1', text: 'a', status: StepStatus.done),
        StepView(id: 'R3.2', text: 'b'),
        StepView(id: 'R3.3', text: 'c'),
      ];
      expect(closesRequirement('R3.2', steps), isFalse);
      expect(closesRequirement('R3.3', steps), isFalse);
      expect(closesRequirement('R1', steps), isFalse);
      expect(
        closesRequirement('R3.3', [
          for (final s in steps)
            if (s.id != 'R3.2') s,
        ]),
        isTrue,
      );
    });

    test('ids with a dot: marker, session steps, commits and refs', () {
      expect(parseStepMarker('ETAPA CONCLUÍDA: R3.1'), {'R3.1'});
      expect(parseStepMarker('etapas concluidas: r3.1 e R3.10.'), {
        'R3.1',
        'R3.10',
      });
      expect(parseStepMarker('ETAPA CONCLUÍDA: R3.'), {'R3'});
      expect(parseSessionSteps('R3.1,R3.2'), ['R3.1', 'R3.2']);
      expect(
        checkpointRef('SPEC-001', 'R3.1'),
        'refs/promptorium/SPEC-001/R3.1-inicio',
      );
      final byStep = commitsByStep('SPEC-001', [
        GitLogEntry(
          sha: 'a',
          shortSha: 'a',
          subject: 'SPEC-001 R3.1: primeira parte',
          author: 'x',
          date: DateTime(2026),
        ),
      ]);
      expect(byStep.keys, ['R3.1']);
    });

    test('progress counts sub-steps; attention names the sub-step', () {
      final steps = stepsOf(specOf(), [
        row('R1', status: StepStatus.done),
        row('R3.1', body: 'a', status: StepStatus.done),
        row('R3.2', body: 'b', status: StepStatus.needsInput),
      ]);
      expect(progressOf(steps), (2, 4));
      expect(
        boardAttentionReason(
          SpecCardData(
            spec: specOf(),
            steps: steps,
            sessions: const [],
            blockers: const [],
          ),
        ),
        'R3.2 aguardando você',
      );
    });

    test('trace: a sub-step shows the criteria and the design of its '
        'requirement', () {
      expect(criteriaOfStep(specText, 'R3.1').single.text, contains('r3.txt'));
      expect(
        designExcerpt(SpecDocument.parse(specText).design, 'R3.1'),
        contains('R3 · Generators'),
      );
    });

    test('subagents: one tied to a split requirement runs with its last '
        'sub-step and only then counts as due', () {
      const subs = [
        SpecSubagent(agent: 'rev', when: SubagentWhen.atStep, step: 'R3'),
      ];
      const steps = [
        StepView(id: 'R3.1', text: 'a', status: StepStatus.done),
        StepView(id: 'R3.2', text: 'b'),
        StepView(id: 'R4', text: 'c'),
      ];
      expect(subagentPlan(subs, steps: steps, todo: ['R3.2']), hasLength(1));
      expect(
        subagentPlan(
          subs,
          steps: const [
            StepView(id: 'R3.1', text: 'a'),
            StepView(id: 'R3.2', text: 'b'),
          ],
          todo: ['R3.1'],
        ),
        isEmpty,
      );
    });

    test(
      'prompt: the text of the sub-step and of the requirement, the list '
      'with the finished ones checked and the excerpt of the requirement',
      () {
        const steps = [
          StepView(id: 'R3.1', text: 'Ler', status: StepStatus.done),
          StepView(id: 'R3.2', text: 'Gravar'),
          StepView(id: 'R3.3', text: 'Ligar'),
        ];
        final p = specStepPrompt(
          spec: specOf(),
          specText: specText,
          steps: steps,
          todo: ['R3.2'],
        );
        expect(p, contains('- R3.2 · Gravar'));
        expect(p, contains('- R3 · Extrair generators'));
        expect(
          p,
          contains(
            '- [x] R3.1 · Ler\n'
            '- [ ] R3.2 · Gravar (agora)\n'
            '- [ ] R3.3 · Ligar\n',
          ),
        );
        expect(p, contains('Faça só esta subetapa'));
        expect(p, contains('## Requisitos desta sessão\n\n- R3 · Extrair'));
        expect(p, contains('Em lib/generators.dart.'));
        expect(p, isNot(contains('Em lib/tables.dart.')));
        expect(p, contains('"SPEC-001 R3.2: <resumo do que mudou>"'));
        expect(p, contains('linha exata: ETAPA CONCLUÍDA: R3.2'));
        // The requirement's check only passes with the last sub-step.
        expect(p, contains('rode só os testes dos arquivos que você mudou'));

        final last = specStepPrompt(
          spec: specOf(),
          specText: specText,
          steps: [
            for (final s in steps)
              StepView(
                id: s.id,
                text: s.text,
                status: s.id == 'R3.3' ? StepStatus.pending : StepStatus.done,
              ),
          ],
          todo: ['R3.3'],
        );
        expect(last, contains('É a última subetapa'));
        expect(
          last,
          contains('rode só os testes desta etapa: `test -f r3.txt`'),
        );
        expect(
          specSessionTitle(specOf(), steps, ['R3.2']),
          'SPEC-001 · R3.2 · Gravar',
        );
      },
    );
  });

  group('SpecRunner (temporary repo, fake CLI)', () {
    late Directory tmp;
    late String repo;
    late FakeCli cli;
    late ProviderContainer c;
    late Workspace ws;
    late Spec spec;

    void config(String yaml) {
      Directory('$repo/.promptorium').createSync(recursive: true);
      File('$repo/.promptorium/config.yml').writeAsStringSync(yaml);
    }

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-substeps-');
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
      final steps = c.read(specStepsRepoProvider);
      await steps.setAll(spec.id, ['R1', 'R2'], StepStatus.done);
      await steps.addSubSteps(spec.id, 'R3', ['Ler', 'Gravar']);
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

    Future<SpecStep> stepRow(String step) async =>
        (await c.read(specStepsRepoProvider).bySpec(spec.id))
            .firstWhere((r) => r.step == step);

    Future<void> until(Future<bool> Function() cond) async {
      final end = DateTime.now().add(const Duration(seconds: 45));
      while (!await cond()) {
        if (DateTime.now().isAfter(end)) fail('condição não atingida');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await settle();
    }

    Future<String> worktree() async =>
        (await c.read(specsRepoProvider).getById(spec.id))!.worktreePath!;

    Future<void> commit(String wt, String file, String subject) async {
      File('$wt/$file').writeAsStringSync('x');
      await gitIn(wt, ['add', '.']);
      await gitIn(wt, ['commit', '-q', '-m', subject]);
    }

    Future<List<String>> sessionSteps() async => [
      for (final s in await c.read(sessionsRepoProvider).bySpec(spec.id))
        s.steps ?? '',
    ];

    Future<List<String>> notes(String sessionId) async => [
      for (final e in await c.read(sessionsRepoProvider).events(sessionId))
        if (e.type == AppEventTypes.note)
          (jsonDecode(e.json) as Map)['text'] as String,
    ];

    test('concluding R3.1 does not run the gate and the next sub-step gets '
        'its own session; R3.2 runs the gate of R3; a failure goes back to '
        'R3.2 after the resends; passing closes R3 and moves on', () async {
      config(
        'testes: "true"\n'
        'verificacao:\n'
        '  tentativas: 1\n',
      );
      final runner = c.read(specRunnerProvider);
      final first = await runner.runNext(spec.id);
      await settle();
      final s1 = (await c.read(sessionsRepoProvider).getById(first))!;
      expect(s1.steps, 'R3.1');
      expect(s1.title, 'SPEC-001 · R3.1 · Ler');
      final sent = cli.last.writtenJson.single['message']['content'] as String;
      expect(sent, contains('- [ ] R3.1 · Ler (agora)'));
      expect((await states())['R3.1'], StepStatus.running);
      expect((await stepRow('R3')).status, StepStatus.pending);
      final wt = await worktree();

      // No commit at all: a gate would have refused it. Small context: a
      // plain step would have continued in this session.
      cli.last.emit(smallContext());
      cli.last.emit(resultLine('Pronto.\nETAPA CONCLUÍDA: R3.1'));
      await until(() async => cli.processes.length == 2);
      expect((await states())['R3.1'], StepStatus.done);
      expect((await stepRow('R3.1')).gateReport, isNull);
      expect((await stepRow('R3')).status, StepStatus.pending);
      expect(await sessionSteps(), ['R3.1', 'R3.2']);
      expect(
        await notes(first),
        contains(
          'R3.2 vai para uma sessão nova: cada subetapa roda numa sessão '
          'própria.',
        ),
      );
      expect(
        cli.last.writtenJson.single['message']['content'],
        contains('- [x] R3.1 · Ler\n- [ ] R3.2 · Gravar (agora)'),
      );

      // Committed, but the criterion of R3 fails: resent as usual.
      await commit(wt, 'outro.txt', 'SPEC-001 R3.2: quase');
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R3.2'));
      await until(() async => cli.last.writtenJson.length == 2);
      final retry = cli.last.writtenJson.last['message']['content'] as String;
      expect(retry, contains('falhou: verificar'));
      expect(retry, endsWith('ETAPA CONCLUÍDA: R3.2'));
      expect((await stepRow('R3.2')).gateAttempts, 1);

      // Attempts used up: R3.2 waits for the user with the report.
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R3.2'));
      await until(
        () async => (await states())['R3.2'] == StepStatus.needsInput,
      );
      final failed = GateReport.decode((await stepRow('R3.2')).gateReport)!;
      expect(failed.failures.single.command, 'test -f r3.txt');
      expect((await stepRow('R3')).status, StepStatus.pending);
      expect(cli.processes, hasLength(2));
      expect(
        await c.read(reviewCommentsRepoProvider).criteria(spec.id),
        isEmpty,
      );

      // Fixed by hand: the gate passes, R3 is done, its criterion is
      // checked and R4 starts.
      await commit(wt, 'r3.txt', 'SPEC-001 R3.2: r3');
      await runner.recheck(spec.id);
      await until(() async => cli.processes.length == 3);
      expect((await states())['R3.2'], StepStatus.done);
      expect((await stepRow('R3')).status, StepStatus.done);
      expect((await stepRow('R3')).doneAt, isNotNull);
      expect(
        (await c.read(reviewCommentsRepoProvider).criteria(spec.id))
            .single
            .checkedBy,
        'gate',
      );
      expect(await sessionSteps(), ['R3.1', 'R3.2', 'R4']);
    });

    test('the last sub-step of the spec, no gate: its requirement is done '
        'and the card goes to Review', () async {
      await c.read(specStepsRepoProvider).set(spec.id, 'R4', StepStatus.done);
      final runner = c.read(specRunnerProvider);
      await runner.runNext(spec.id);
      await settle();
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R3.1'));
      await until(() async => cli.processes.length == 2);
      expect((await stepRow('R3')).status, StepStatus.pending);
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R3.2'));
      await until(() async => (await states())['R3.2'] == StepStatus.done);
      expect((await stepRow('R3')).status, StepStatus.done);
      expect(
        (await c.read(specsRepoProvider).getById(spec.id))!.stage,
        SpecStage.review,
      );
    });

    test(
      'without the marker a sub-step waits for the user, like any step',
      () async {
        await c.read(specRunnerProvider).runNext(spec.id);
        await settle();
        cli.last.emit(resultLine('Qual banco devo usar?'));
        await until(
          () async => (await states())['R3.1'] == StepStatus.needsInput,
        );
        expect(cli.processes, hasLength(1));
      },
    );

    test('checkpoint: the refs of a sub-step exist and going back to R3.1 '
        'reopens the sub-steps and the requirement, which keep their text; '
        'redo starts R3.1 again', () async {
      final runner = c.read(specRunnerProvider);
      await runner.runNext(spec.id);
      await settle();
      final wt = await worktree();
      final head = (await gitIn(wt, ['rev-parse', 'HEAD'])).trim();
      expect(
        (await gitIn(wt, [
          'rev-parse',
          'refs/promptorium/SPEC-001/R3.1-inicio',
        ])).trim(),
        head,
      );
      await commit(wt, 'a.txt', 'SPEC-001 R3.1: a');
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R3.1'));
      await until(() async => cli.processes.length == 2);
      await commit(wt, 'b.txt', 'SPEC-001 R3.2: b');
      await c.read(specsRepoProvider).setAutoAdvance(spec.id, false);
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R3.2'));
      await until(() async => (await states())['R3.2'] == StepStatus.done);
      expect((await stepRow('R3')).status, StepStatus.done);

      final preview = await runner.rewindPreview(spec.id, 'R3.1');
      expect(preview.steps, ['R3.1', 'R3.2']);
      expect(preview.commits, hasLength(2));

      await runner.rewind(spec.id, 'R3.1');
      expect((await gitIn(wt, ['rev-parse', 'HEAD'])).trim(), head);
      expect(await states(), {
        'R1': StepStatus.done,
        'R2': StepStatus.done,
        'R3.1': StepStatus.pending,
        'R3.2': StepStatus.pending,
        'R4': StepStatus.pending,
      });
      expect((await stepRow('R3')).status, StepStatus.pending);
      expect((await stepRow('R3.1')).body, 'Ler');

      await runner.redo(spec.id, 'R3.1');
      await settle();
      expect((await sessionSteps()).last, 'R3.1');
    });

    test(
      'Desfazer: the requirement comes back to the queue as it was',
      () async {
        final steps = c.read(specStepsRepoProvider);
        await steps.removeSubSteps(spec.id, 'R3');
        await steps.set(spec.id, 'R3', StepStatus.needsInput, sessionId: 'x');
        await steps.setGate(spec.id, ['R3'], report: 'relatório', attempts: 2);
        final previous = await stepRow('R3');

        final ids = await steps.addSubSteps(spec.id, 'R3', ['a', 'b', 'c']);
        expect(ids, ['R3.1', 'R3.2', 'R3.3']);
        var row = await stepRow('R3');
        expect(row.status, StepStatus.pending);
        expect(row.gateReport, isNull);
        expect((await states()).keys, [
          'R1',
          'R2',
          'R3.1',
          'R3.2',
          'R3.3',
          'R4',
        ]);
        expect((await states())['R3.2'], StepStatus.pending);

        // A new split replaces the earlier one.
        await steps.addSubSteps(spec.id, 'R3', ['x', 'y']);
        expect((await states()).keys, ['R1', 'R2', 'R3.1', 'R3.2', 'R4']);
        expect((await stepRow('R3.1')).body, 'x');

        await steps.removeSubSteps(spec.id, 'R3', previous: previous);
        expect((await states()).keys, ['R1', 'R2', 'R3', 'R4']);
        row = await stepRow('R3');
        expect(row.status, StepStatus.needsInput);
        expect(row.sessionId, 'x');
        expect(row.gateReport, 'relatório');
        expect(row.gateAttempts, 2);
      },
    );

    test('removing the sub-steps of R3 leaves those of R30 alone', () async {
      final steps = c.read(specStepsRepoProvider);
      await steps.addSubSteps(spec.id, 'R30', ['a', 'b']);
      await steps.removeSubSteps(spec.id, 'R3');
      expect(
        (await steps.bySpec(spec.id)).map((r) => r.step),
        containsAll(['R30.1', 'R30.2']),
      );
      expect(
        (await steps.bySpec(spec.id)).map((r) => r.step),
        isNot(contains('R3.1')),
      );
    });
  });
}
