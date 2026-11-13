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
    this.planModel,
    this.planEffort,
    this.escalations = 0,
  });

  /// `R1`; `R3.1` for a sub-step of `R3` (SPEC-033 R16).
  final String id;
  final String text;
  final StepStatus status;
  final String? sessionId;

  /// Last gate of the step (null = never verified).
  final GateReport? gate;

  /// HEAD when its last session started (checkpoint).
  final String? startSha;

  /// Model and effort of the Orquestrador's plan (null = Manual, SPEC-035).
  final String? planModel;
  final String? planEffort;

  /// Rungs of the ladder climbed after failed gates (SPEC-035 R9).
  final int escalations;

  bool get isDone => status == StepStatus.done;

  /// Waits for the user because the gate refused it.
  bool get gateFailed =>
      !isDone && status != StepStatus.verifying && gate != null && !gate!.ok;
}

/// Steps of [spec] in file order, with the state of [rows] (rows of steps
/// no longer in the file are ignored). A requirement split into sub-steps
/// (SPEC-033 R16) is replaced by them, in number order: its own row only
/// records that the requirement passed the gate.
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
    planModel: byStep[id]?.planModel,
    planEffort: byStep[id]?.planEffort,
    escalations: byStep[id]?.escalations ?? 0,
  );
  // Steps added by the app (the reviewer's corrections), after the file's.
  final extra = [
    for (final r in byStep.values)
      if (isReviewStep(r.step) && r.body != null) r,
  ]..sort((a, b) => reviewStepRound(a.step).compareTo(reviewStepRound(b.step)));
  final subSteps = <String, List<SpecStep>>{};
  for (final r in subStepRows(byStep.values)) {
    subSteps.putIfAbsent(parentOf(r.step), () => []).add(r);
  }
  return [
    for (final req in spec.requirements)
      if (subSteps[req.id] case final subs?)
        for (final r in subs) view(r.step, r.body!)
      else
        view(req.id, req.text),
    for (final r in extra) view(r.step, r.body!),
  ];
}

/// `REV1`, `REV2`…: correction steps of the automatic reviewer.
bool isReviewStep(String id) => RegExp(r'^REV\d+$').hasMatch(id);

int reviewStepRound(String id) => int.tryParse(id.substring(3)) ?? 0;

/// `R3.1`, `R3.2`…: the execution of `R3` split by "Dividir a etapa"
/// (SPEC-033 R16). The requirement itself stays whole in the spec.
bool isSubStep(String id) => RegExp(r'^R\d+\.\d+$').hasMatch(id);

/// `R3` for `R3.1`; any other id is its own requirement.
String parentOf(String id) =>
    isSubStep(id) ? id.substring(0, id.indexOf('.')) : id;

int _subStepNumber(String id) =>
    int.tryParse(id.substring(id.indexOf('.') + 1)) ?? 0;

/// Sub-step rows of [rows] (those with their text), by requirement and then
/// by number: `R3.10` comes after `R3.2`.
List<SpecStep> subStepRows(Iterable<SpecStep> rows) => [
  for (final r in rows)
    if (isSubStep(r.step) && r.body != null) r,
]..sort((a, b) => _subStepNumber(a.step).compareTo(_subStepNumber(b.step)));

/// [id] is a sub-step and the others of its requirement are done: finishing
/// it finishes the requirement, so it is the one that goes through the gate.
bool closesRequirement(String id, Iterable<StepView> steps) =>
    isSubStep(id) &&
    steps.every(
      (s) => s.id == id || parentOf(s.id) != parentOf(id) || s.isDone,
    );

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
/// session), else the first step not done. A sub-step is never grouped
/// (SPEC-033 R16). With the Orquestrador's [plans] (model + effort by step
/// id, SPEC-035 R8), the group stops at the first step whose plan differs
/// from the first one's: it never skips a step nor reorders. Empty = all
/// done.
List<String> nextSteps(
  List<StepView> steps, {
  required int singleSessionMax,
  Map<String, Object?> plans = const {},
}) {
  final open = steps.where((s) => !s.isDone).toList();
  if (open.isEmpty) return const [];
  final untouched =
      open.length == steps.length &&
      steps.every((s) => s.status == StepStatus.pending);
  final split = steps.any((s) => isSubStep(s.id));
  if (untouched && !split && steps.length <= singleSessionMax) {
    final first = plans[steps.first.id];
    return [for (final s in steps.takeWhile((s) => plans[s.id] == first)) s.id];
  }
  return [open.first.id];
}

/// The card only shows approved specs taken out of the Bandeja (or
/// finished, or already running): drafts, ideas and approved specs that
/// wait stay in the Bandeja (SPEC-068 R7, R8).
bool isOnBoard(Spec spec, {bool showArchived = false}) =>
    spec.status == SpecStatus.archived
    ? showArchived
    : (spec.status == SpecStatus.approved && !spec.inTray) ||
          spec.status == SpecStatus.done ||
          spec.stage != SpecStage.backlog;

/// Specs of the Bandeja (SPEC-068 R7): not archived and not on the Quadro.
bool isInTray(Spec spec) =>
    spec.status != SpecStatus.archived && !isOnBoard(spec);

/// The Bandeja takes an approved spec to the Backlog; a draft is approved
/// in its spec first (R8).
bool canTakeFromTray(Spec spec) =>
    isInTray(spec) && spec.status == SpecStatus.approved;

/// A spec never executed (no worktree, still in Backlog) may be deleted.
bool canDeleteSpec(Spec spec) =>
    spec.stage == SpecStage.backlog && spec.worktreePath == null;

/// A finished spec (merged, in "Feito") may be archived.
bool canArchiveSpec(Spec spec) =>
    spec.stage == SpecStage.done && spec.status != SpecStatus.archived;

/// Number of a spec: the last digits of its code (`SPEC-035` → 35; 0 = none).
int specNumber(String code) =>
    int.tryParse(RegExp(r'(\d+)(?!.*\d)').firstMatch(code)?[1] ?? '') ?? 0;

/// `035` of `SPEC-035`, or the whole code when it has no number.
String specShortCode(String code) =>
    RegExp(r'(\d+)(?!.*\d)').firstMatch(code)?[1] ?? code;

/// Newest spec first: by number, then by code.
int compareNewestFirst(Spec a, Spec b) {
  final byNumber = specNumber(b.code).compareTo(specNumber(a.code));
  return byNumber != 0 ? byNumber : b.code.compareTo(a.code);
}

/// Status of a line of the folder (SPEC-036 R2).
enum FolderStatus { attention, done, running, review, backlog }

/// "Aguardando você" comes before the stage of the spec.
FolderStatus folderStatus(SpecStage stage, {required bool attention}) =>
    attention
    ? FolderStatus.attention
    : switch (stage) {
        SpecStage.done => FolderStatus.done,
        SpecStage.running => FolderStatus.running,
        SpecStage.review => FolderStatus.review,
        SpecStage.backlog => FolderStatus.backlog,
      };

String folderStatusLabel(FolderStatus s) => switch (s) {
  FolderStatus.attention => 'Aguardando você',
  FolderStatus.done => 'Feito',
  FolderStatus.running => 'Em execução',
  FolderStatus.review => 'Review',
  FolderStatus.backlog => 'Backlog',
};

/// A dependency drawn on the stage: [to] depends on [from].
@immutable
class StageEdge {
  const StageEdge(this.from, this.to, {required this.skips});

  final Spec from, to;

  /// Jumps over at least one level (SPEC-036 R10).
  final bool skips;
}

/// What the stage shows of a spec: the spec at the top and, below it, every
/// spec that depends on it, directly or not (SPEC-036 R9).
@immutable
class StageLayout {
  const StageLayout(this.levels, this.edges, {this.running = false});

  /// The specs in execution, side by side and without a root (R12).
  StageLayout.runningSpecs(List<Spec> specs)
    : this([specs], const [], running: true);

  final bool running;

  /// `levels[0]` is the root alone; a spec is in the level of the longest
  /// path from the root.
  final List<List<Spec>> levels;
  final List<StageEdge> edges;

  Spec get root => levels.first.first;
  int get dependents => levels.skip(1).fold(0, (n, l) => n + l.length);
  Iterable<Spec> get specs => levels.expand((l) => l);
}

/// Places [root] and what depends on it. Codes that are not in [specs] are
/// ignored, and a dependency that closes a cycle is left out.
StageLayout stageLayout(Spec root, Iterable<Spec> specs) {
  final dependents = <String, List<Spec>>{};
  for (final s in specs) {
    for (final code in s.dependsOn) {
      dependents.putIfAbsent(code, () => []).add(s);
    }
  }
  final order = <Spec>[];
  final open = <String>{}, seen = <String>{};
  final kept = <(Spec, Spec)>[];
  void visit(Spec s) {
    seen.add(s.code);
    open.add(s.code);
    for (final d in dependents[s.code] ?? const <Spec>[]) {
      if (open.contains(d.code)) continue;
      kept.add((s, d));
      if (!seen.contains(d.code)) visit(d);
    }
    open.remove(s.code);
    order.add(s);
  }

  visit(root);
  final level = {root.code: 0};
  final out = <String, List<Spec>>{};
  for (final (from, to) in kept) {
    out.putIfAbsent(from.code, () => []).add(to);
  }
  for (final s in order.reversed) {
    for (final d in out[s.code] ?? const <Spec>[]) {
      final next = level[s.code]! + 1;
      if (next > (level[d.code] ?? 0)) level[d.code] = next;
    }
  }
  final levels = <List<Spec>>[
    for (var i = 0; i <= level.values.fold(0, (a, b) => a > b ? a : b); i++) [],
  ];
  for (final s in order) {
    levels[level[s.code]!].add(s);
  }
  for (final l in levels) {
    l.sort((a, b) => compareNewestFirst(b, a));
  }
  return StageLayout(levels, [
    for (final (from, to) in kept)
      StageEdge(from, to, skips: level[to.code]! - level[from.code]! > 1),
  ]);
}

/// When a card of the stage leaves the folder: 90 ms per level and 45 ms per
/// card of the level (SPEC-036 R9).
Duration stageCardDelay(int level, int index) =>
    Duration(milliseconds: 90 * level + 45 * index);

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
  // A split requirement is done with its sub-steps.
  bool stepDone(String? id) {
    final own = steps.where((s) => parentOf(s.id) == id);
    return own.isNotEmpty && own.every((s) => s.isDone);
  }

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
