import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/board/widgets/autopilot_preview.dart';

import 'sprint_rules_test.dart' show sprint;

Spec s(
  int id, {
  SpecStage stage = SpecStage.backlog,
  SpecStatus status = SpecStatus.approved,
  List<String> deps = const [],
  int? sprintId,
}) => Spec(
  hasPlan: false,
  inTray: false,
  kind: SpecKind.spec,
  id: id,
  workspaceId: 1,
  code: 'SPEC-${id.toString().padLeft(3, '0')}',
  title: 't$id',
  status: status,
  path: 'p',
  stage: stage,
  requirements: const [],
  dependsOn: deps,
  autoAdvance: false,
  reviewRounds: 0,
  gateResends: 0,
  rejectedHunks: 0,
  sprintId: sprintId,
);

List<String> codes(Iterable<Spec> l) => [for (final x in l) x.code];

/// SPEC-064 R1, R3, R7: the plan of "Executar tudo".
void main() {
  test('R1: the real case: SPEC-002 waits for SPEC-001', () {
    final p = autopilotPlan([
      s(1),
      s(2, deps: ['SPEC-001']),
      s(3),
    ], null);
    expect(codes(p.start), ['SPEC-001', 'SPEC-003']);
    expect(codes(p.wait.map((w) => w.spec)), ['SPEC-002']);
    expect(p.wait.single.waitingFor, ['SPEC-001']);
    expect(
      autopilotWaitText(p.wait.single, UnblockAt.review),
      'depois da SPEC-001 chegar em Review',
    );
    expect(p.count, 3);
  });

  test('R3: a dependency in Review releases with Review, not with Feito', () {
    final all = [
      s(1, stage: SpecStage.review),
      s(2, deps: ['SPEC-001']),
    ];
    expect(codes(autopilotPlan(all, null).start), ['SPEC-002']);
    final feito = autopilotPlan(all, null, unblockAt: UnblockAt.done);
    expect(feito.start, isEmpty);
    expect(feito.wait.single.waitingFor, ['SPEC-001']);
    expect(
      autopilotWaitText(feito.wait.single, UnblockAt.done),
      'depois da SPEC-001 chegar em Feito',
    );
    // Done releases in both.
    final done = [
      s(1, stage: SpecStage.done, status: SpecStatus.done),
      s(2, deps: ['SPEC-001']),
    ];
    expect(codes(autopilotPlan(done, null, unblockAt: UnblockAt.done).start), [
      'SPEC-002',
    ]);
  });

  test('R1: two dependencies in Review wait for a merge', () {
    final p = autopilotPlan([
      s(1, stage: SpecStage.review),
      s(2, stage: SpecStage.review),
      s(3, deps: ['SPEC-001', 'SPEC-002']),
    ], null);
    expect(p.start, isEmpty);
    expect(
      p.wait.single.reason,
      'depende de SPEC-001 e SPEC-002 em Review: falta o merge de ao menos '
      'uma',
    );
  });

  test('R1: the parallel limit queues the rest', () {
    final p = autopilotPlan(
      [s(1, stage: SpecStage.running), s(2), s(3)],
      null,
      parallel: 2,
    );
    expect(codes(p.start), ['SPEC-002']);
    expect(p.wait.single.reason, 'na fila: limite de 2 em paralelo');
  });

  test(
    'R1: not approved, outside the sprint, dependency in another sprint',
    () {
      final active = sprint(1, state: SprintState.active);
      final p = autopilotPlan([
        s(1, sprintId: 1),
        s(2, sprintId: 1, status: SpecStatus.draft),
        s(3, sprintId: 2),
        s(4, sprintId: 1, deps: ['SPEC-003']),
      ], active);
      expect(codes(p.start), ['SPEC-001']);
      final why = {for (final k in p.skip) k.spec.code: k.reason};
      expect(why['SPEC-002'], 'ainda não foi aprovada');
      expect(why['SPEC-003'], 'está fora da sprint ativa');
      expect(why['SPEC-004'], 'depende de SPEC-003, que está em outra sprint');
    },
  );

  test('R1: the automatic plan holds a spec', () {
    final p = autopilotPlan([s(1)], null, locked: (_) => true);
    expect(p.wait.single.planning, isTrue);
  });

  test('R7: nothing to do', () {
    final p = autopilotPlan([
      s(1, status: SpecStatus.draft),
      s(2, stage: SpecStage.done, status: SpecStatus.done),
    ], null);
    expect(p.nothingToDo, isTrue);
    expect(p.skip, hasLength(1));
  });
}
