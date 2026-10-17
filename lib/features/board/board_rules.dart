import 'package:flutter/foundation.dart';

import '../../data/db/app_database.dart';
import '../sessions/timeline.dart';
import '../specs/spec_file.dart';
import 'step_gate.dart';

/// Pure rules of the Quadro: the spec is the card, its requirements are the
/// steps (plano "specs no quadro").

/// One step of a card: the requirement of the file + its stored state.
@immutable
class StepView {
  const StepView({
    required this.id,
    required this.text,
    this.status = StepStatus.pending,
    this.sessionId,
    this.gate,
    this.startSha,
  });

  /// `R1`.
  final String id;
  final String text;
  final StepStatus status;
  final String? sessionId;

  /// Last gate of the step (null = never verified).
  final GateReport? gate;

  /// HEAD when its last session started (checkpoint).
  final String? startSha;

  bool get isDone => status == StepStatus.done;

  /// Waits for the user because the gate refused it.
  bool get gateFailed =>
      !isDone && status != StepStatus.verifying && gate != null && !gate!.ok;
}

/// Steps of [spec] in file order, with the state of [rows] (rows of steps
/// no longer in the file are ignored).
List<StepView> stepsOf(Spec spec, Iterable<SpecStep> rows) {
  final byStep = {
    for (final r in rows)
      if (r.specId == spec.id) r.step: r,
  };
  StepView view(String id, String text) => StepView(
    id: id,
    text: text,
    status: byStep[id]?.status ?? StepStatus.pending,
    sessionId: byStep[id]?.sessionId,
    gate: GateReport.decode(byStep[id]?.gateReport),
    startSha: byStep[id]?.startSha,
  );
  // Steps added by the app (the reviewer's corrections), after the file's.
  final extra = [
    for (final r in byStep.values)
      if (isReviewStep(r.step) && r.body != null) r,
  ]..sort((a, b) => reviewStepRound(a.step).compareTo(reviewStepRound(b.step)));
  return [
    for (final req in spec.requirements) view(req.id, req.text),
    for (final r in extra) view(r.step, r.body!),
  ];
}

/// `REV1`, `REV2`…: correction steps of the automatic reviewer.
bool isReviewStep(String id) => RegExp(r'^REV\d+$').hasMatch(id);

int reviewStepRound(String id) => int.tryParse(id.substring(3)) ?? 0;

/// `(done, total)` of [steps].
(int, int) progressOf(List<StepView> steps) =>
    (steps.where((s) => s.isDone).length, steps.length);

Map<String, Spec> specsByCode(Iterable<Spec> specs) => {
  for (final s in specs) s.code: s,
};

/// Codes in `spec.dependsOn` whose spec is not in "Feito" yet. Codes that
/// do not exist in the workspace are ignored (they could never be done).
List<String> specBlockers(
  Spec spec,
  Map<String, Spec> byCode, {
  bool reviewUnblocks = false,
}) => [
  for (final code in spec.dependsOn)
    if (byCode[code] case final dep?
        when dep.stage != SpecStage.done &&
            !(reviewUnblocks && dep.stage == SpecStage.review))
      code,
];

bool isSpecBlocked(Spec spec, Map<String, Spec> byCode) =>
    specBlockers(spec, byCode).isNotEmpty;

/// Steps the next session should do: every step when nothing was done yet
/// and the spec has at most [singleSessionMax] steps (small spec = one
/// session), else the first step not done. Empty = all done.
List<String> nextSteps(List<StepView> steps, {required int singleSessionMax}) {
  final open = steps.where((s) => !s.isDone).toList();
  if (open.isEmpty) return const [];
  final untouched =
      open.length == steps.length &&
      steps.every((s) => s.status == StepStatus.pending);
  if (untouched && steps.length <= singleSessionMax) {
    return [for (final s in steps) s.id];
  }
  return [open.first.id];
}

/// The card only shows approved (or finished) specs: drafts and ideas stay
/// in the Specs screen.
bool isOnBoard(Spec spec, {bool showArchived = false}) =>
    spec.status == SpecStatus.archived
    ? showArchived
    : spec.status == SpecStatus.approved ||
          spec.status == SpecStatus.done ||
          spec.stage != SpecStage.backlog;

/// A spec never executed (no worktree, still in Backlog) may be deleted.
bool canDeleteSpec(Spec spec) =>
    spec.stage == SpecStage.backlog && spec.worktreePath == null;

/// A finished spec (merged, in "Feito") may be archived.
bool canArchiveSpec(Spec spec) =>
    spec.stage == SpecStage.done && spec.status != SpecStatus.archived;

/// Labels of the columns.
String specStageLabel(SpecStage s) => switch (s) {
  SpecStage.backlog => 'Backlog',
  SpecStage.running => 'Em execução',
  SpecStage.review => 'Review',
  SpecStage.done => 'Feito',
};

String stepStatusLabel(StepStatus s) => switch (s) {
  StepStatus.pending => 'pendente',
  StepStatus.running => 'rodando',
  StepStatus.done => 'concluída',
  StepStatus.needsInput => 'aguardando você',
  StepStatus.verifying => 'verificando',
};

/// State of a subagent configured on a spec.
enum SubagentState {
  /// Its moment did not come yet.
  pending,
  running,
  done,

  /// Every call ended in error.
  failed,

  /// Its moment passed and the agent never called it.
  notCalled,
}

String subagentStateLabel(SubagentState s) => switch (s) {
  SubagentState.pending => 'pendente',
  SubagentState.running => 'rodando',
  SubagentState.done => 'feito',
  SubagentState.failed => 'falhou',
  SubagentState.notCalled => 'não foi chamado',
};

@immutable
class SubagentStatus {
  const SubagentStatus(
    this.subagent,
    this.state, {
    this.summary,
    this.calls = 0,
  });

  final SpecSubagent subagent;
  final SubagentState state;

  /// Answer of the last finished call (what the subagent concluded).
  final String? summary;
  final int calls;
}

/// Calls (`Task` / `Agent` tool) of [agent] in [items], nested ones included.
Iterable<ToolItem> _callsOf(String agent, Iterable<TimelineItem> items) sync* {
  for (final i in items) {
    if (i is! ToolItem) continue;
    if (i.isSubagent && '${i.input['subagent_type'] ?? ''}' == agent) yield i;
    yield* _callsOf(agent, i.children);
  }
}

/// Status of each of [subs] from the timelines of the spec's sessions and
/// the state of its steps: a call seen = running / done / failed; no call
/// and the moment already passed = "não foi chamado".
List<SubagentStatus> subagentStatuses(
  List<SpecSubagent> subs, {
  required Spec spec,
  required List<StepView> steps,
  required Iterable<List<TimelineItem>> timelines,
}) {
  bool stepDone(String? id) => steps.any((s) => s.id == id && s.isDone);
  bool passed(SpecSubagent a) => switch (a.when) {
    SubagentWhen.specEnd =>
      spec.stage == SpecStage.review || spec.stage == SpecStage.done,
    SubagentWhen.atStep => stepDone(a.step),
    _ => steps.any((s) => s.isDone),
  };
  return [
    for (final a in subs)
      () {
        final calls = [for (final t in timelines) ..._callsOf(a.agent, t)];
        if (calls.isEmpty) {
          return SubagentStatus(
            a,
            passed(a) ? SubagentState.notCalled : SubagentState.pending,
          );
        }
        final finished = calls.where((c) => c.done).toList();
        final ok = finished.where((c) => !c.isError).toList();
        final state = calls.any((c) => !c.done)
            ? SubagentState.running
            : ok.isNotEmpty
            ? SubagentState.done
            : SubagentState.failed;
        final text = (ok.isNotEmpty ? ok.last : finished.lastOrNull)?.result;
        return SubagentStatus(
          a,
          state,
          calls: calls.length,
          summary: text == null || text.trim().isEmpty ? null : text.trim(),
        );
      }(),
  ];
}
