import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/claude/readonly_run.dart'
    show PlannerException;
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/git/repo_setup.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/project/project_service.dart';
import 'package:promptorium/features/project/spec_auto_planner.dart';
import 'package:promptorium/features/project/widgets/plan_queue_view.dart';
import 'package:promptorium/features/specs/spec_action.dart';
import 'package:promptorium/features/specs/spec_design.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../core/git/repo_setup_test.dart' show gitRun;
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

/// A valid answer for [text]: its requirements with the text refined.
Map<String, Object?> answerFor(
  String text, {
  String plan = 'Plano de teste',
  int extra = 0,
  int questions = 0,
}) {
  final doc = SpecDocument.parse(text);
  final reqs = doc.requirements;
  final etapa = {
    'requisito': reqs.first.id,
    'arquivos': ['lib/a.dart'],
    'verificar': 'make t',
  };
  return {
    'objetivo': 'Objetivo refinado de ${doc.id}.',
    'requisitos': [
      for (final r in reqs) {'id': r.id, 'texto': 'Refinado: ${r.text}'},
      for (var i = 0; i < extra; i++)
        {'id': 'R${reqs.length + i + 1}', 'texto': 'Novo'},
    ],
    'criterios': ['Funciona [R1] verificar: make t'],
    'foraDoEscopo': '- Nada mais.',
    'perguntas': [
      for (var i = 0; i < questions; i++)
        {'pergunta': 'Dúvida $i de ${doc.id}?', 'sugestao': ''},
    ],
    'design': '### R1 · $plan de ${doc.id}\n\nEm lib/a.dart.',
    'etapas': [etapa],
  };
}

/// The agent of the queue: without the CLI, but with the real rules of R12.
class FakeDesigner extends SpecDesigner {
  FakeDesigner(super.ref);

  final calls = <({String code, Map<String, String> plans})>[];

  /// Answer of a spec; throws to fail. Null = [answerFor].
  final answers = <String, Object? Function(String text)>{};

  /// Rounds that wait for a test (by spec code).
  final gates = <String, Completer<void>>{};

  /// A round that started and is waiting at its gate.
  final waiting = <String>{};

  @override
  Future<AutoPlanAnswer> refineAndPlan(
    Workspace ws,
    String specText, {
    Map<String, String> dependencyPlans = const {},
    Future<void>? cancelled,
  }) async {
    final code = SpecDocument.parse(specText).id!;
    calls.add((code: code, plans: dependencyPlans));
    final gate = gates[code];
    if (gate != null) {
      waiting.add(code);
      var stopped = false;
      await Future.any([
        gate.future,
        if (cancelled != null) cancelled.then((_) => stopped = true),
      ]);
      waiting.remove(code);
      if (stopped) throw const SpecActionCancelled();
    }
    final answer = answers[code];
    return applyAutoPlanAnswer(
      specText,
      answer == null ? answerFor(specText) : answer(specText),
    );
  }

  List<String> get codes => [for (final c in calls) c.code];
}

/// A → B, A → C, (B, C) → D, then E on its own after A.
const _roadmap = Roadmap(
  specs: [
    RoadmapSpec(
      code: 'S1',
      title: 'Base',
      phase: RoadmapPhase.foundation,
      requirements: [(id: 'R1', text: 'Criar')],
    ),
    RoadmapSpec(
      code: 'S2',
      title: 'Dados',
      phase: RoadmapPhase.mvp,
      requirements: [(id: 'R1', text: 'Tabelas'), (id: 'R2', text: 'Índices')],
      dependsOn: ['S1'],
    ),
    RoadmapSpec(
      code: 'S3',
      title: 'Login',
      phase: RoadmapPhase.mvp,
      requirements: [(id: 'R1', text: 'Entrar')],
      dependsOn: ['S1'],
    ),
    RoadmapSpec(
      code: 'S4',
      title: 'Agenda',
      phase: RoadmapPhase.mvp,
      requirements: [(id: 'R1', text: 'Marcar')],
      dependsOn: ['S2', 'S3'],
    ),
  ],
);

const _plan = ProjectPlanData(
  vision: VisionPlan(summary: 'Agenda', mvp: ['Marcar']),
  stack: StackPlan(claudeMd: '# Agenda'),
  roadmap: _roadmap,
);

void main() {
  late Directory tmp;
  late ProviderContainer c;
  late FakeDesigner designer;
  late Workspace ws;

  SpecAutoPlanner planner() => c.read(specAutoPlannerProvider.notifier);
  AutoPlanQueue queue() => c.read(specAutoPlannerProvider).queues[ws.id]!;
  AutoPlanItem item(String code) =>
      queue().items.firstWhere((i) => i.code == code);
  Future<String> git(List<String> args) async {
    final r = await gitRun('git', ['-C', ws.path, ...args]);
    return '${r.stdout}'.trim();
  }

  Future<List<String>> subjects() async =>
      (await git(['log', '--format=%s'])).split('\n');
  Future<Spec> specOf(String code) async =>
      (await c.read(specsRepoProvider).getByCode(ws.id, code))!;
  Future<String> textOf(String code) async =>
      File('${ws.path}/${(await specOf(code)).path}').readAsString();
  Future<SpecDocument> docOf(String code) async =>
      SpecDocument.parse(await textOf(code));

  Future<MaterializeOutcome> create({bool commit = true}) async {
    ws = await c
        .read(projectServiceProvider)
        .createProject(parent: tmp.path, name: 'agenda');
    await c
        .read(projectPlansRepoProvider)
        .update(ws.id, ProjectPlansCompanion(data: Value(_plan.encode())));
    return c.read(projectServiceProvider).materialize(ws, commit: commit);
  }

  Future<void> run({bool commit = true, int? firstRun}) async {
    final out = await create(commit: commit);
    await planner().start(
      ws,
      out.specs,
      commit: commit,
      firstRunSpecId: firstRun,
    );
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-autoplan-');
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        processRunnerProvider.overrideWithValue(gitRun),
        repoSetupProvider.overrideWithValue(RepoSetup(run: gitRun)),
        gitServiceFactoryProvider.overrideWithValue(
          (root) =>
              GitService(root, run: gitRun, worktreesBase: '${tmp.path}/wt'),
        ),
        specDesignerProvider.overrideWith(
          (ref) => designer = FakeDesigner(ref),
        ),
      ],
    );
    c.read(specDesignerProvider);
    await c.read(appSettingsProvider.notifier).load();
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  group('R5, R6, R7: the queue', () {
    test('R5: refines and plans every spec of the roadmap, and without the '
        'queue no spec changes', () async {
      final out = await create();
      for (final s in out.specs) {
        final doc = await docOf(s.code);
        expect(doc.design, isNull);
        expect(doc.autoPlanned, isFalse);
      }
      expect(designer.calls, isEmpty);

      await planner().start(ws, out.specs);
      expect(designer.codes, [for (final s in out.specs) s.code]);
      for (final s in out.specs) {
        final doc = await docOf(s.code);
        expect(doc.design, contains('Plano de teste'));
        expect(doc.stepPlans, isNotEmpty);
        expect(doc.objective, startsWith('Objetivo refinado'));
        expect(doc.autoPlanned, isTrue);
      }
      expect(queue().phase, AutoPlanPhase.finished);
      expect(queue().plannedCount, 4);
    });

    test('R5: only the specs given are planned, never ones that already '
        'existed', () async {
      final out = await create();
      final old = await c
          .read(specServiceProvider)
          .create(
            ws,
            title: 'Antiga',
            body: '---\nid: SPEC-099\n---\n# Antiga\n',
          );
      await planner().start(ws, out.specs);
      expect(designer.codes, isNot(contains('SPEC-099')));
      expect(
        await File('${ws.path}/${old.path}').readAsString(),
        '---\nid: SPEC-099\n---\n# Antiga\n',
      );
    });

    test('R6: a spec comes after its dependencies, whatever the order '
        'given, and gets their plans', () async {
      final out = await create();
      await planner().start(ws, out.specs.reversed.toList());
      final order = designer.codes;
      expect(order.indexOf('SPEC-001'), lessThan(order.indexOf('SPEC-002')));
      expect(order.indexOf('SPEC-002'), lessThan(order.indexOf('SPEC-004')));
      expect(order.indexOf('SPEC-003'), lessThan(order.indexOf('SPEC-004')));
      final last = designer.calls.firstWhere((x) => x.code == 'SPEC-004');
      expect(last.plans.keys, unorderedEquals(['SPEC-002', 'SPEC-003']));
      expect(last.plans['SPEC-002'], contains('Plano de teste de SPEC-002'));
      expect(
        designer.calls.firstWhere((x) => x.code == 'SPEC-001').plans,
        isEmpty,
      );
    });

    test('R6: autoPlanOrder moves a spec after its dependencies, and survives '
        'a cycle', () async {
      final target = await c
          .read(workspacesRepoProvider)
          .add(path: tmp.path, name: 'ordem');
      var n = 0;
      Future<Spec> s(String code, List<String> deps) => c
          .read(specsRepoProvider)
          .insert(
            workspaceId: target.id,
            code: '$code${n++}',
            title: code,
            path: 'specs/$code$n.md',
            dependsOn: deps,
          );
      final a = await s('A', const []);
      final b = await s('B', [a.code]);
      final other = await s('C', const []);
      expect(
        [
          for (final x in autoPlanOrder([other, b, a])) x.id,
        ],
        [other.id, a.id, b.id],
      );
      final x = await s('X', const ['Y1000']);
      final y = await s('Y', [x.code]);
      final cycle = [
        x.copyWith(dependsOn: [y.code]),
        y,
      ];
      expect([for (final i in autoPlanOrder(cycle)) i.id], [x.id, y.id]);
    });

    test('R6: one spec at a time', () async {
      final out = await create();
      designer.gates['SPEC-001'] = Completer<void>();
      final done = planner().start(ws, out.specs);
      await until(() async => designer.waiting.contains('SPEC-001'));
      expect(designer.codes, ['SPEC-001']);
      expect(item('SPEC-001').status, AutoPlanStatus.planning);
      expect(item('SPEC-002').status, AutoPlanStatus.queued);
      expect(planQueueHeadline(queue()), 'Planejando 1 de 4 · SPEC-001');
      designer.gates['SPEC-001']!.complete();
      await done;
    });

    test('R7: saved at once, still approved, and one commit "Plano das '
        'specs" at the end', () async {
      final out = await create();
      final before = (await subjects()).length;
      designer.gates['SPEC-002'] = Completer<void>();
      final done = planner().start(ws, out.specs);
      await until(() async => designer.waiting.contains('SPEC-002'));
      // SPEC-001 is on disk before the queue ends; nothing is committed yet.
      expect((await docOf('SPEC-001')).design, isNotNull);
      expect((await subjects()).length, before);
      designer.gates['SPEC-002']!.complete();
      await done;

      final log = await subjects();
      expect(log.first, specPlansCommitMessage);
      expect(log.length, before + 1);
      expect(await git(['status', '--porcelain']), isEmpty);
      final files = await git(['show', '--name-only', '--format=', 'HEAD']);
      expect(files.split('\n'), hasLength(4));
      for (final s in out.specs) {
        final spec = await specOf(s.code);
        expect(spec.status, SpecStatus.approved);
        expect((await docOf(s.code)).status, SpecStatus.approved);
      }
      expect(queue().committed, isTrue);
    });

    test('R7: no commit without the option', () async {
      await run(commit: false);
      expect(await subjects(), isNot(contains(specPlansCommitMessage)));
      expect(queue().committed, isFalse);
      expect((await docOf('SPEC-001')).design, isNotNull);
    });

    test('R7: a failed commit shows and undoes nothing', () async {
      final out = await create();
      File('${ws.path}/.git/hooks/pre-commit')
        ..writeAsStringSync('#!/bin/sh\necho recusado >&2\nexit 1\n')
        ..createSync();
      await Process.run('chmod', ['+x', '${ws.path}/.git/hooks/pre-commit']);
      await planner().start(ws, out.specs);
      expect(queue().commitError, isNotNull);
      expect(queue().phase, AutoPlanPhase.finished);
      expect((await docOf('SPEC-004')).design, isNotNull);
      expect(await subjects(), isNot(contains(specPlansCommitMessage)));
      final rows = planQueueRows(queue());
      expect(
        rows.firstWhere((r) => r.title.contains('Plano das specs')).state,
        PlanStepState.alert,
      );
    });
  });

  group('R8: stopping and resuming', () {
    test('"Parar a fila" keeps the plans ready in the commit, shows "Fila '
        'parada" and leaves the steps not done without a check', () async {
      final out = await create();
      designer.gates['SPEC-003'] = Completer<void>();
      final done = planner().start(ws, out.specs, firstRunSpecId: 1);
      await until(() async => designer.waiting.contains('SPEC-003'));
      planner().stop(ws.id);
      await done;

      expect(queue().phase, AutoPlanPhase.stopped);
      expect(planQueueTitle(queue()), 'Fila parada');
      expect(planQueueHeadline(queue()), '2 de 4 planejadas · fila parada');
      expect(item('SPEC-001').status, AutoPlanStatus.ready);
      expect(item('SPEC-003').status, AutoPlanStatus.unplanned);
      expect(item('SPEC-004').status, AutoPlanStatus.unplanned);
      expect(AutoPlanStatus.unplanned.label, 'Sem plano');

      // The two plans ready are committed, the round stopped wrote nothing.
      expect((await subjects()).first, specPlansCommitMessage);
      final files = await git(['show', '--name-only', '--format=', 'HEAD']);
      expect(files.split('\n'), hasLength(2));
      expect((await docOf('SPEC-003')).design, isNull);

      final rows = planQueueRows(queue());
      expect(
        rows.firstWhere((r) => r.title.startsWith('Refina')).title,
        'Refina e planeja: 2 de 4',
      );
      expect(
        rows.firstWhere((r) => r.title.startsWith('Refina')).state,
        PlanStepState.pending,
      );
      expect(
        rows.firstWhere((r) => r.title.startsWith('Abre')).state,
        PlanStepState.pending,
      );
    });

    test('the specs are free once the queue stops', () async {
      final out = await create();
      designer.gates['SPEC-001'] = Completer<void>();
      final done = planner().start(ws, out.specs);
      await until(() async => designer.waiting.contains('SPEC-001'));
      final id = out.specs.last.id;
      expect(
        c.read(specAutoPlannerProvider).lockOf(id)?.reason,
        autoPlanQueueReason,
      );
      planner().stop(ws.id);
      await done;
      expect(c.read(specAutoPlannerProvider).lockOf(id), isNull);
    });

    test(
      '"Retomar a fila" plans only the specs left, with a new commit',
      () async {
        final out = await create();
        designer.gates['SPEC-003'] = Completer<void>();
        final done = planner().start(ws, out.specs);
        await until(() async => designer.waiting.contains('SPEC-003'));
        planner().stop(ws.id);
        await done;
        designer.gates.clear();
        designer.calls.clear();

        await planner().resume(ws);
        expect(designer.codes, ['SPEC-003', 'SPEC-004']);
        expect(queue().phase, AutoPlanPhase.finished);
        expect(queue().plannedCount, 4);
        expect(planQueueTitle(queue()), 'Projeto criado');
        final log = await subjects();
        expect(log.where((s) => s == specPlansCommitMessage), hasLength(2));
        final files = await git(['show', '--name-only', '--format=', 'HEAD']);
        expect(files.split('\n'), hasLength(2));
      },
    );
  });

  group('R9: failures', () {
    void failOnce(String code) {
      var failed = false;
      designer.answers[code] = (text) {
        if (failed) return answerFor(text);
        failed = true;
        throw const PlannerException('O agente caiu.');
      };
    }

    test('a failure does not stop the others: the spec stays without a plan '
        'and the dependents are partial', () async {
      failOnce('SPEC-002');
      await run();
      expect(designer.codes, hasLength(4));
      expect(item('SPEC-002').status, AutoPlanStatus.failed);
      expect(item('SPEC-002').error, 'O agente caiu.');
      expect((await docOf('SPEC-002')).design, isNull);
      expect((await docOf('SPEC-002')).autoPlanned, isFalse);
      expect(item('SPEC-003').status, AutoPlanStatus.ready);
      final last = item('SPEC-004');
      expect(last.status, AutoPlanStatus.partial);
      expect(last.missingPlans, ['SPEC-002']);
      expect(AutoPlanStatus.partial.label, 'Plano parcial');
      // It went on without the plan that was missing.
      final call = designer.calls.firstWhere((x) => x.code == 'SPEC-004');
      expect(call.plans.keys, ['SPEC-003']);
    });

    test('the end says "Concluído com pendências" and N de M, and the panel '
        'is an alert, never done', () async {
      failOnce('SPEC-002');
      await run();
      expect(planQueueTitle(queue()), 'Concluído com pendências');
      expect(planQueueHeadline(queue()), '3 de 4 planejadas');
      expect(planQueuePanelTitle(queue()), 'Com pendências');
      final row = planQueueRows(queue())
          .firstWhere((r) => r.title.startsWith('Refina'));
      expect(row.title, 'Refina e planeja: 3 de 4');
      expect(row.state, PlanStepState.alert);
    });

    test('"Tentar de novo" redoes the spec and its dependents, with a new '
        'commit of only those', () async {
      failOnce('SPEC-002');
      await run();
      expect((await subjects()).first, specPlansCommitMessage);
      designer.calls.clear();

      await planner().retry(ws, specId: item('SPEC-002').specId);
      expect(designer.codes, ['SPEC-002', 'SPEC-004']);
      expect(item('SPEC-002').status, AutoPlanStatus.ready);
      expect(item('SPEC-002').error, isNull);
      expect(item('SPEC-004').status, AutoPlanStatus.ready);
      expect(item('SPEC-004').missingPlans, isEmpty);
      expect(
        designer.calls.last.plans.keys,
        unorderedEquals(['SPEC-002', 'SPEC-003']),
      );
      final log = await subjects();
      expect(log.where((s) => s == specPlansCommitMessage), hasLength(2));
      final files = (await git(['show', '--name-only', '--format=', 'HEAD']))
          .split('\n');
      expect(files, hasLength(2));
      expect(files.join(), contains('SPEC-002'));
      expect(files.join(), contains('SPEC-004'));
      expect(planQueueTitle(queue()), 'Projeto criado');
    });

    test('"Tentar de novo" of the footer redoes every failure', () async {
      failOnce('SPEC-002');
      failOnce('SPEC-003');
      await run();
      designer.calls.clear();
      await planner().retry(ws);
      expect(designer.codes, ['SPEC-002', 'SPEC-003', 'SPEC-004']);
      expect(queue().plannedCount, 4);
    });

    test('a dependent that failed too is redone with the spec', () async {
      failOnce('SPEC-002');
      failOnce('SPEC-004');
      await run();
      designer.calls.clear();
      await planner().retry(ws, specId: item('SPEC-002').specId);
      expect(designer.codes, ['SPEC-002', 'SPEC-004']);
      expect(item('SPEC-004').status, AutoPlanStatus.ready);
    });

    test('a dependent saved by hand meanwhile is not redone', () async {
      failOnce('SPEC-002');
      await run();
      final spec = await specOf('SPEC-004');
      final text = (await docOf('SPEC-004')).withAutoPlan(false);
      await c.read(specServiceProvider).save(ws, spec, text);
      designer.calls.clear();

      await planner().retry(ws, specId: item('SPEC-002').specId);
      expect(designer.codes, ['SPEC-002']);
      expect(await textOf('SPEC-004'), text);
      expect(item('SPEC-004').status, AutoPlanStatus.partial);
    });

    test(
      'the file changed during the round: failure, and the change stays',
      () async {
        final out = await create();
        designer.gates['SPEC-001'] = Completer<void>();
        final done = planner().start(ws, out.specs);
        await until(() async => designer.waiting.contains('SPEC-001'));
        final file = File('${ws.path}/${(await specOf('SPEC-001')).path}');
        final typed = '${file.readAsStringSync()}\nTexto digitado.\n';
        file.writeAsStringSync(typed);
        designer.gates['SPEC-001']!.complete();
        await done;
        expect(item('SPEC-001').status, AutoPlanStatus.failed);
        expect(file.readAsStringSync(), typed);
      },
    );
  });

  group('R10: the first session', () {
    test('waits for the end of the queue and comes out once', () async {
      final out = await create();
      designer.gates['SPEC-002'] = Completer<void>();
      final done = planner().start(ws, out.specs, firstRunSpecId: 7);
      await until(() async => designer.waiting.contains('SPEC-002'));
      expect(c.read(specAutoPlannerProvider).firstRunReady, isEmpty);
      expect(planner().takeFirstRun(ws.id), isNull);
      designer.gates['SPEC-002']!.complete();
      await done;
      expect(c.read(specAutoPlannerProvider).firstRunReady, [ws.id]);
      expect(planner().takeFirstRun(ws.id), 7);
      expect(planner().takeFirstRun(ws.id), isNull);
      expect(queue().sessionOpened, isTrue);
      expect(planQueueRows(queue()).last, (
        title: 'Abre a primeira sessão',
        state: PlanStepState.done,
      ));
    });

    test('opens with failures, not after "Parar a fila", even if it is '
        'resumed', () async {
      designer.answers['SPEC-002'] = (_) =>
          throw const PlannerException('Falhou.');
      await run(firstRun: 7);
      expect(planner().takeFirstRun(ws.id), 7);

      planner().forget(ws.id);
      final specs = [await specOf('SPEC-001'), await specOf('SPEC-003')];
      designer.answers.clear();
      designer.gates['SPEC-003'] = Completer<void>();
      final done = planner().start(ws, specs, firstRunSpecId: 7);
      await until(() async => designer.waiting.contains('SPEC-003'));
      planner().stop(ws.id);
      await done;
      expect(c.read(specAutoPlannerProvider).firstRunReady, isEmpty);
      designer.gates.clear();
      await planner().resume(ws);
      expect(queue().phase, AutoPlanPhase.finished);
      expect(c.read(specAutoPlannerProvider).firstRunReady, isEmpty);
    });
  });

  group('R12: the rules of the round', () {
    test('the round writes the refined spec, and existing requirements '
        'keep their number', () async {
      designer.answers['SPEC-002'] = (t) =>
          answerFor(t, extra: 1, questions: 2);
      await run();
      final doc = await docOf('SPEC-002');
      expect(doc.objective, 'Objetivo refinado de SPEC-002.');
      expect([for (final r in doc.requirements) r.id], ['R1', 'R2', 'R3']);
      expect(doc.requirements.first.text, 'Refinado: Tabelas');
      expect(doc.section('Fora do escopo'), '- Nada mais.');
      expect(doc.section('Critérios de aceite'), contains('- [ ] Funciona'));
      expect([for (final q in doc.openQuestions) q.id], ['P1', 'P2']);
      expect(item('SPEC-002').addedRequirements, 1);
      expect(item('SPEC-002').questions, 2);
      expect(queue().questions, 2);
      // The table follows the file: the new requirement is a step.
      expect((await specOf('SPEC-002')).requirements, hasLength(3));
    });

    test('id, status and depende-de do not change', () async {
      await run();
      final doc = await docOf('SPEC-004');
      expect(doc.id, 'SPEC-004');
      expect(doc.rawStatus, 'aprovada');
      expect(doc.dependsOn, ['SPEC-002', 'SPEC-003']);
    });

    Future<void> refuses(
      Object? Function(String text) answer,
      String message,
    ) async {
      final out = await create();
      designer.answers['SPEC-002'] = answer;
      final before = await textOf('SPEC-002');
      await planner().start(ws, out.specs);
      expect(item('SPEC-002').status, AutoPlanStatus.failed);
      expect(item('SPEC-002').error, contains(message));
      expect(await textOf('SPEC-002'), before);
    }

    test('an answer that removes a requirement is a failure and leaves the '
        'spec as it was', () async {
      await refuses((t) {
        final a = answerFor(t);
        (a['requisitos']! as List).removeLast();
        return a;
      }, 'A resposta removeu o requisito R2. A spec ficou como estava.');
    });

    test('an answer with more than 6 requirements is a failure', () async {
      await refuses((t) => answerFor(t, extra: 5), 'passou de 6 requisitos');
    });

    test('an open question does not stop the queue', () async {
      designer.answers['SPEC-001'] = (t) => answerFor(t, questions: 1);
      await run();
      expect(item('SPEC-001').status, AutoPlanStatus.ready);
      expect(queue().phase, AutoPlanPhase.finished);
    });

    group('applyAutoPlanAnswer', () {
      const spec =
          '---\nid: SPEC-001\nstatus: aprovada\ndepende-de: [SPEC-009]\n---\n\n'
          '# A\n\n## Objetivo\n\nFazer.\n\n## Requisitos\n\n- R1 · x\n\n'
          '## Critérios de aceite\n\n- [ ] ok [R1]\n\n'
          '## Perguntas em aberto\n\n- P1 · Antiga?\n';

      void refused(Map<String, Object?> Function(Map<String, Object?>) edit) {
        expect(
          () => applyAutoPlanAnswer(spec, edit(answerFor(spec))),
          throwsA(isA<PlannerException>()),
        );
      }

      test('sections in order, the old question kept, a repeated one not '
          'counted', () {
        final a = answerFor(spec);
        a['perguntas'] = [
          {'pergunta': 'Antiga?', 'sugestao': ''},
          {'pergunta': 'Nova?', 'sugestao': 'Sim'},
        ];
        final out = applyAutoPlanAnswer(spec, a);
        expect(out.questions, 1);
        expect(out.addedRequirements, 0);
        final doc = SpecDocument.parse(out.text);
        expect([for (final q in doc.openQuestions) q.id], ['P1', 'P2']);
        expect(doc.openQuestions.last.suggestion, 'Sim');
        final t = out.text;
        final order = [
          '## Objetivo',
          '## Requisitos',
          '## Fora do escopo',
          '## Plano',
          '## Etapas',
          '## Critérios de aceite',
          '## Perguntas em aberto',
        ].map(t.indexOf).toList();
        expect(order, [...order]..sort());
        expect(order, isNot(contains(-1)));
      });

      test('other answers out of the rules', () {
        refused((a) => a..['objetivo'] = ' ');
        refused((a) => a..['foraDoEscopo'] = '');
        refused((a) => a..['criterios'] = <String>[]);
        refused((a) => a..['design'] = '');
        refused((a) => a..['etapas'] = <Object>[]);
        refused((a) => a..['design'] = 'Texto\n\n## Requisitos\n\n- R9 · y');
        refused(
          (a) => a
            ..['requisitos'] = [
              {'id': 'R1', 'texto': 'a'},
              {'id': 'R1', 'texto': 'b'},
            ],
        );
        refused(
          (a) => a
            ..['requisitos'] = [
              {'id': 'R1', 'texto': ' '},
            ],
        );
        refused(
          (a) => a
            ..['requisitos'] = [
              {'id': 'R1', 'texto': 'a'},
              {'id': 'X', 'texto': 'b'},
            ],
        );
        expect(
          () => applyAutoPlanAnswer(spec, null),
          throwsA(isA<PlannerException>()),
        );
      });
    });

    test('refineAndPlan: read-only run with the rules, the plans of the '
        'dependencies and the budget of Planejar', () async {
      final cli = FakeCli();
      final d = Directory.systemTemp.createTempSync('promptorium-round-');
      addTearDown(() => d.deleteSync(recursive: true));
      final own = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          claudeProcessStarterProvider.overrideWithValue(cli.start),
          runSettingsDirProvider.overrideWithValue('${d.path}/run'),
        ],
      );
      addTearDown(own.dispose);
      await own.read(appSettingsProvider.notifier).load();
      final target = Workspace(
        id: 1,
        path: d.path,
        name: 'w',
        createdAt: DateTime(2026),
      );
      final cancel = Completer<void>();
      final round = own
          .read(specDesignerProvider)
          .refineAndPlan(
            target,
            '# Spec\n',
            dependencyPlans: const {'SPEC-001': 'O plano da base'},
            cancelled: cancel.future,
          );
      final stopped = expectLater(round, throwsA(isA<SpecActionCancelled>()));
      await until(() async => cli.processes.isNotEmpty);
      final args = cli.args.single.join(' ');
      expect(args, contains('--json-schema'));
      expect(args, contains('foraDoEscopo'));
      expect(args, contains('--max-budget-usd 1 '));
      expect(args, contains(autoPlanPrompt));
      expect(utf8.decode(cli.last.stdinBytes), contains('O plano da base'));
      expect(SpecDesigner.autoPlanBudgetUsd, SpecDesigner.budgetUsd);
      cancel.complete();
      await stopped;
    });

    test('the rules are the same as "Refinar com IA"', () {
      expect(autoPlanPrompt, contains(specRefineRules));
      expect(autoPlanPrompt, contains(designPrompt));
    });
  });

  group('R13: planning again', () {
    Future<void> finish(String code) async {
      await c.read(specServiceProvider).markDone(ws, await specOf(code));
    }

    Future<void> settled() async {
      await until(
        () async => c.read(specAutoPlannerProvider).replanning.isEmpty,
      );
    }

    test('finishing the last dependency plans the spec once, and the ones '
        'before it do not', () async {
      await run();
      designer.calls.clear();
      await finish('SPEC-001');
      await settled();
      // SPEC-002 and SPEC-003 depended only on it.
      expect(designer.codes, ['SPEC-002', 'SPEC-003']);
      designer.calls.clear();

      await finish('SPEC-002');
      await settled();
      expect(designer.calls, isEmpty);

      await finish('SPEC-003');
      await settled();
      expect(designer.codes, ['SPEC-004']);
      expect(designer.calls.single.plans, isEmpty);
      final doc = await docOf('SPEC-004');
      expect(doc.autoPlanned, isTrue);
      expect(doc.status, SpecStatus.approved);
      final subject = (await subjects()).first;
      expect(subject, planUpdatedCommitMessage('SPEC-004'));
      final files = await git(['show', '--name-only', '--format=', 'HEAD']);
      expect(files, (await specOf('SPEC-004')).path);
    });

    test('runs only once, even if a dependency finishes again', () async {
      await run();
      await finish('SPEC-001');
      await settled();
      designer.calls.clear();
      final service = c.read(specServiceProvider);
      await service.reopen(ws, await specOf('SPEC-001'));
      await finish('SPEC-001');
      await settled();
      expect(designer.calls, isEmpty);
    });

    test('a spec saved by hand is not planned again', () async {
      await run();
      final spec = await specOf('SPEC-002');
      await c
          .read(specServiceProvider)
          .save(ws, spec, (await docOf('SPEC-002')).withAutoPlan(false));
      designer.calls.clear();
      await finish('SPEC-001');
      await settled();
      expect(designer.codes, ['SPEC-003']);
    });

    test('a clone does not inherit the mark', () async {
      await run();
      final clone = cloneSpecText(
        await textOf('SPEC-002'),
        newCode: 'SPEC-050',
        originalCode: 'SPEC-002',
        doneIds: const {},
      );
      expect(SpecDocument.parse(clone).autoPlanned, isFalse);
    });

    test('a spec that already started is not planned again', () async {
      await run();
      final spec = await specOf('SPEC-002');
      await c.read(specsRepoProvider).setStage(spec.id, SpecStage.running);
      designer.calls.clear();
      await finish('SPEC-001');
      await settled();
      expect(designer.codes, ['SPEC-003']);
    });

    test('specs released together share one queue, one at a time, and both '
        'wait with the reason', () async {
      await run();
      designer.calls.clear();
      designer.gates['SPEC-002'] = Completer<void>();
      await finish('SPEC-001');
      await until(() async => designer.waiting.contains('SPEC-002'));
      expect(designer.codes, ['SPEC-002']);
      for (final code in ['SPEC-002', 'SPEC-003']) {
        final id = (await specOf(code)).id;
        expect(
          c.read(specAutoPlannerProvider).lockOf(id)?.reason,
          autoPlanUpdateReason,
        );
      }
      designer.gates['SPEC-002']!.complete();
      await settled();
      expect(designer.codes, ['SPEC-002', 'SPEC-003']);
    });

    test('a failure keeps the previous plan, frees the spec and marks it '
        'until a new round works', () async {
      await run();
      final before = await textOf('SPEC-002');
      designer.answers['SPEC-002'] = (_) =>
          throw const PlannerException('Sem saldo.');
      await finish('SPEC-001');
      await settled();
      final id = (await specOf('SPEC-002')).id;
      expect(await textOf('SPEC-002'), before);
      final state = c.read(specAutoPlannerProvider);
      expect(state.lockOf(id), isNull);
      expect(state.failures[id]?.code, 'SPEC-002');
      expect(state.failures[id]?.commitFailed, isFalse);

      designer.answers.clear();
      await planner().retryReplan(ws, id);
      expect(c.read(specAutoPlannerProvider).failures, isEmpty);
      expect((await subjects()).first, 'Plano atualizado: SPEC-002');
    });

    test('a spec that starts no longer shows the failure', () async {
      await run();
      designer.answers['SPEC-002'] = (_) =>
          throw const PlannerException('Sem saldo.');
      await finish('SPEC-001');
      await settled();
      final id = (await specOf('SPEC-002')).id;
      planner().clearFailure(id);
      expect(c.read(specAutoPlannerProvider).failures, isEmpty);
    });

    test('D8: commits even without the option of the creation, and a spec '
        'never committed fails in the warning', () async {
      await run(commit: false);
      await finish('SPEC-001');
      await settled();
      final id = (await specOf('SPEC-002')).id;
      final failure = c.read(specAutoPlannerProvider).failures[id];
      expect(failure?.commitFailed, isTrue);
      expect((await docOf('SPEC-002')).design, contains('Plano de teste'));
    });
  });
}
