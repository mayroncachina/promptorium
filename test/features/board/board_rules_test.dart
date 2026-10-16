import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/specs/spec_file.dart';

Spec spec(
  int id,
  String code, {
  SpecStage stage = SpecStage.backlog,
  SpecStatus status = SpecStatus.approved,
  List<String> deps = const [],
  int steps = 0,
}) => Spec(
  id: id,
  workspaceId: 1,
  code: code,
  title: code,
  status: status,
  path: 'specs/$code.md',
  stage: stage,
  requirements: [for (var i = 1; i <= steps; i++) (id: 'R$i', text: 't$i')],
  dependsOn: deps,
  autoAdvance: true,
);

SpecStep row(int spec, String step, StepStatus status) =>
    SpecStep(specId: spec, step: step, status: status);

void main() {
  test('steps follow the file; state comes from the rows', () {
    final s = spec(1, 'SPEC-001', steps: 3);
    final steps = stepsOf(s, [
      row(1, 'R2', StepStatus.done),
      row(1, 'R9', StepStatus.done), // no longer in the file
      row(2, 'R1', StepStatus.done), // other spec
    ]);
    expect(steps.map((v) => (v.id, v.status)), [
      ('R1', StepStatus.pending),
      ('R2', StepStatus.done),
      ('R3', StepStatus.pending),
    ]);
    expect(progressOf(steps), (1, 3));
  });

  test('next steps: small untouched spec = all in one session; else the '
      'first open one', () {
    List<StepView> v(int n, [Map<String, StepStatus> st = const {}]) => [
      for (var i = 1; i <= n; i++)
        StepView(id: 'R$i', text: '', status: st['R$i'] ?? StepStatus.pending),
    ];
    expect(nextSteps(v(3), singleSessionMax: 3), ['R1', 'R2', 'R3']);
    expect(nextSteps(v(4), singleSessionMax: 3), ['R1']);
    expect(nextSteps(v(3, {'R1': StepStatus.done}), singleSessionMax: 3), [
      'R2',
    ]);
    expect(
      nextSteps(v(3, {'R1': StepStatus.needsInput}), singleSessionMax: 3),
      ['R1'],
    );
    expect(
      nextSteps(
        v(2, {'R1': StepStatus.done, 'R2': StepStatus.done}),
        singleSessionMax: 3,
      ),
      isEmpty,
    );
    expect(nextSteps(v(0), singleSessionMax: 3), isEmpty);
  });

  test('a spec is blocked while a dependency is not in Feito', () {
    final a = spec(1, 'SPEC-001', stage: SpecStage.done);
    final b = spec(2, 'SPEC-002', stage: SpecStage.review);
    final c = spec(3, 'SPEC-003', deps: ['SPEC-001', 'SPEC-002', 'SPEC-099']);
    final byCode = specsByCode([a, b, c]);
    expect(specBlockers(c, byCode), ['SPEC-002']);
    expect(isSpecBlocked(a, byCode), isFalse);
    // Autopilot: a dependency in Review already releases the next spec.
    expect(specBlockers(c, byCode, reviewUnblocks: true), isEmpty);
  });

  test('only approved / finished / started specs are on the board', () {
    expect(isOnBoard(spec(1, 'S', status: SpecStatus.approved)), isTrue);
    expect(isOnBoard(spec(1, 'S', status: SpecStatus.draft)), isFalse);
    expect(isOnBoard(spec(1, 'S', status: SpecStatus.idea)), isFalse);
    expect(
      isOnBoard(
        spec(1, 'S', status: SpecStatus.draft, stage: SpecStage.running),
      ),
      isTrue,
    );
  });

  test('subagentStatuses: running / done / failed / not called / pending', () {
    final sp = spec(1, 'SPEC-001', stage: SpecStage.review);
    const subs = [
      SpecSubagent(agent: 'rev', when: SubagentWhen.specEnd),
      SpecSubagent(agent: 'tw', when: SubagentWhen.afterEach),
      SpecSubagent(agent: 'x', when: SubagentWhen.atStep, step: 'R2'),
    ];
    const steps = [
      StepView(id: 'R1', text: 'a', status: StepStatus.done),
      StepView(id: 'R2', text: 'b'),
    ];
    ToolItem call(String agent, {String? result, bool error = false}) =>
        ToolItem(id: agent, name: 'Agent', input: {'subagent_type': agent})
          ..result = result
          ..isError = error;
    var st = subagentStatuses(
      subs,
      spec: sp,
      steps: steps,
      timelines: [
        [call('rev', result: 'APROVADO')],
        [call('tw')],
      ],
    );
    expect(st.map((s) => s.state), [
      SubagentState.done,
      SubagentState.running,
      SubagentState.pending, // R2 not done yet
    ]);
    expect(st.first.summary, 'APROVADO');
    st = subagentStatuses(
      subs,
      spec: sp,
      steps: steps,
      timelines: [
        [call('rev', result: 'erro', error: true)],
      ],
    );
    expect(st.map((s) => s.state), [
      SubagentState.failed,
      SubagentState.notCalled, // a step is done and tw was never called
      SubagentState.pending,
    ]);
  });
}
