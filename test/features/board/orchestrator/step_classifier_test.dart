import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/readonly_run.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/board/orchestrator/step_classifier.dart';

import '../../../helpers/test_db.dart';

const _spec = '''---
id: SPEC-012
---

# Relatório

## Requisitos

- R1 · Renomear as constantes de status
- R2 · Criar a tabela de relatórios
- R3 · Exportar para CSV
''';

Result _result(Object output) => AgentEvent.fromJson({
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'total_cost_usd': 0.01,
  'result': jsonEncode(output),
  'structured_output': output,
}) as Result;

Map<String, Object?> _out(List<(String, String, String)> steps) => {
  'steps': [
    for (final (id, kind, reason) in steps)
      {'id': id, 'kind': kind, 'reason': reason},
  ],
};

/// One call of the fake read-only run.
class _Call {
  _Call(this.prompt, this.options, this.cancelled);

  final String prompt;
  final ClaudeOptions options;
  final Future<void>? cancelled;
  final answer = Completer<Result>();
}

void main() {
  late Directory tmp;
  late ProviderContainer c;
  late Spec spec;
  late List<_Call> calls;

  List<StepView> views([Map<String, String> texts = const {}]) => [
    for (final r in spec.requirements)
      StepView(id: r.id, text: texts[r.id] ?? r.text),
  ];

  StepClassifier classifier() => c.read(stepClassifierProvider.notifier);

  StepClassifierState state() => c.read(stepClassificationProvider(spec.id));

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Waits for the run of the [n]th call (the spec file is read first).
  Future<void> called(int n) async {
    for (var i = 0; i < 400 && calls.length < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(calls, hasLength(n));
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-classifier-');
    File('${tmp.path}/specs/SPEC-012.md')
      ..createSync(recursive: true)
      ..writeAsStringSync(_spec);
    calls = [];
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseOverride(memoryDatabase()),
        stepClassifierRunProvider.overrideWithValue((
          ref, {
          required cwd,
          required options,
          required prompt,
          timeout = plannerTimeout,
          workspaceId,
          providerId,
          cancelled,
        }) {
          final call = _Call(prompt, options, cancelled);
          calls.add(call);
          cancelled?.then((_) {
            if (!call.answer.isCompleted) {
              call.answer.completeError(
                const PlannerException('Verificação cancelada.'),
              );
            }
          });
          return call.answer.future;
        }),
      ],
    );
    final ws = await c
        .read(workspacesRepoProvider)
        .add(path: tmp.path, name: 'w');
    spec = await c
        .read(specsRepoProvider)
        .insert(
          workspaceId: ws.id,
          code: 'SPEC-012',
          title: 'Relatório',
          path: 'specs/SPEC-012.md',
          requirements: const [
            (id: 'R1', text: 'Renomear as constantes de status'),
            (id: 'R2', text: 'Criar a tabela de relatórios'),
            (id: 'R3', text: 'Exportar para CSV'),
          ],
        );
    // Keeps the autoDispose state alive between reads.
    c.listen(stepClassificationProvider(spec.id), (_, _) {});
  });

  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('pure: one kind per step; an unknown kind, Revisão or a step left '
      'out is Implementação; no valid step is an error', () {
    const targets = [
      (id: 'R1', text: 'a'),
      (id: 'R2', text: 'b'),
      (id: 'R3', text: 'c'),
      (id: 'R4', text: 'd'),
    ];
    final r = parseStepClassification(
      _out([
        ('R1', 'mecanica', 'troca de nomes\nsegunda linha'),
        ('R2', 'qualquer', 'x'),
        ('R3', 'revisao', 'y'),
      ]),
      targets,
    );
    expect(r.error, isNull);
    expect(r.kinds.keys, ['R1', 'R2', 'R3', 'R4']);
    expect(r.kinds['R1']!.kind, StepKind.mecanica);
    expect(r.kinds['R1']!.reason, 'troca de nomes');
    expect(r.kinds['R1']!.hash, stepTextHash('a'));
    expect(r.kinds['R2']!.kind, StepKind.implementacao);
    expect(r.kinds['R3']!.kind, StepKind.implementacao);
    expect(r.kinds['R4']!.kind, StepKind.implementacao);
    expect(parseStepClassification({'steps': []}, targets).error, isNotNull);
    expect(parseStepClassification(null, targets).error, isNotNull);
  });

  test('pure: sub-steps go as their requirement, REV<n> and done steps are '
      'not sent', () {
    final steps = [
      const StepView(id: 'R1', text: 'x', status: StepStatus.done),
      const StepView(id: 'R2.1', text: 'parte 1'),
      const StepView(id: 'R2.2', text: 'parte 2'),
      const StepView(id: 'R3', text: 'Exportar para CSV'),
      const StepView(id: 'REV1', text: 'Corrigir'),
    ];
    expect(classifierTargets(spec, steps), [
      (id: 'R2', text: 'Criar a tabela de relatórios'),
      (id: 'R3', text: 'Exportar para CSV'),
    ]);
  });

  test('a read-only run with --json-schema and the classifier model; one '
      'kind per step', () async {
    await c
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.orchestratorClassifierModel, 'sonnet');
    final done = classifier().classify(spec, views());
    await called(1);
    expect(state().status, StepClassifierStatus.loading);
    final call = calls.single;
    expect(call.options.model, 'sonnet');
    expect(call.options.appendSystemPrompt, stepClassifierPrompt);
    expect(jsonDecode(call.options.jsonSchema!), stepClassifierSchema);
    expect(call.prompt, contains(_spec.trimRight()));
    expect(call.prompt, contains('- R2: Criar a tabela de relatórios'));

    call.answer.complete(
      _result(
        _out([
          ('R1', 'mecanica', 'troca de nomes'),
          ('R2', 'altoRisco', 'migração de banco'),
          ('R3', 'outro', 'serviço novo'),
        ]),
      ),
    );
    final r = await done;
    expect(state().status, StepClassifierStatus.ready);
    expect(
      {for (final e in r.kinds.entries) e.key: e.value.kind},
      {
        'R1': StepKind.mecanica,
        'R2': StepKind.altoRisco,
        'R3': StepKind.implementacao,
      },
    );
  });

  test('reopening without changing the requirement does not run again; '
      'changing the text runs only for that step', () async {
    final first = classifier().classify(spec, views());
    await called(1);
    calls.single.answer.complete(
      _result(
        _out([
          ('R1', 'mecanica', 'a'),
          ('R2', 'altoRisco', 'b'),
          ('R3', 'implementacao', 'c'),
        ]),
      ),
    );
    await first;
    classifier().cancel(spec.id);
    await settle();

    final again = await classifier().classify(spec, views());
    expect(calls, hasLength(1));
    expect(again.kinds['R2']!.kind, StepKind.altoRisco);
    classifier().cancel(spec.id);
    await settle();

    final changed = classifier().classify(
      spec,
      views({'R2': 'Criar a tabela, sem migração'}),
    );
    await called(2);
    expect(calls.last.prompt, contains('- R2: Criar a tabela, sem migração'));
    expect(calls.last.prompt, isNot(contains('- R1:')));
    calls.last.answer.complete(_result(_out([('R2', 'implementacao', 'd')])));
    final r = await changed;
    expect(r.kinds['R1']!.kind, StepKind.mecanica);
    expect(r.kinds['R2']!.kind, StepKind.implementacao);
  });

  test('the kinds and reasons of a confirmed plan in spec_steps are reused '
      'when the text did not change (after a restart)', () async {
    final repo = c.read(specStepsRepoProvider);
    for (final r in spec.requirements) {
      await repo.setPlan(
        spec.id,
        r.id,
        kind: StepKind.documentacao.name,
        model: 'haiku',
        effort: 'low',
        hash: stepTextHash(r.text),
        reason: r.id == 'R1' ? null : 'motivo salvo de ${r.id}',
      );
    }
    final rows = await repo.watchByWorkspace(spec.workspaceId).first;
    final r = await classifier().classify(spec, views(), rows: rows);
    expect(calls, isEmpty);
    expect(r.kinds['R3']!.kind, StepKind.documentacao);
    expect(r.kinds['R3']!.reason, 'motivo salvo de R3');
    // A row without a reason: the plan shows the hint of the kind.
    expect(r.kinds['R1']!.reason, isEmpty);
    classifier().cancel(spec.id);
    await settle();

    final changed = classifier().classify(
      spec,
      views({'R3': 'Exportar para CSV e JSON'}),
      rows: rows,
    );
    await called(1);
    expect(calls.single.prompt, contains('- R3: Exportar para CSV e JSON'));
    calls.single.answer.complete(_result(_out([('R3', 'implementacao', 'x')])));
    expect((await changed).kinds['R3']!.kind, StepKind.implementacao);
  });

  test('a failure is a result with error, not cached; "Tentar de novo" runs '
      'again', () async {
    final first = classifier().classify(spec, views());
    await called(1);
    calls.single.answer.completeError(
      const PlannerException('O planner terminou com erro (error).'),
    );
    final r = await first;
    expect(r.error, 'o planner terminou com erro (error)');
    expect(state().status, StepClassifierStatus.failed);
    expect(c.read(stepClassifierProvider)[spec.id]?.result?.error, r.error);

    final retry = classifier().retry(spec, views());
    await settle();
    expect(state().status, StepClassifierStatus.loading);
    await called(2);
    calls.last.answer.complete(_result(_out([('R1', 'mecanica', 'a')])));
    expect((await retry).error, isNull);
    expect(state().status, StepClassifierStatus.ready);
  });

  test('closing the dialog cancels the run and forgets the state', () async {
    final run = classifier().classify(spec, views());
    await called(1);
    classifier().cancel(spec.id);
    final r = await run;
    expect(r.error, 'classificação cancelada');
    await settle();
    expect(c.read(stepClassifierProvider).containsKey(spec.id), isFalse);
  });
}
