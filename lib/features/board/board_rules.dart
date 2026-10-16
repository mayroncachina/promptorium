import 'package:flutter/foundation.dart';

import '../../data/db/app_database.dart';

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
  });

  /// `R1`.
  final String id;
  final String text;
  final StepStatus status;
  final String? sessionId;

  bool get isDone => status == StepStatus.done;
}

/// Steps of [spec] in file order, with the state of [rows] (rows of steps
/// no longer in the file are ignored).
List<StepView> stepsOf(Spec spec, Iterable<SpecStep> rows) {
  final byStep = {
    for (final r in rows)
      if (r.specId == spec.id) r.step: r,
  };
  return [
    for (final req in spec.requirements)
      StepView(
        id: req.id,
        text: req.text,
        status: byStep[req.id]?.status ?? StepStatus.pending,
        sessionId: byStep[req.id]?.sessionId,
      ),
  ];
}

/// `(done, total)` of [steps].
(int, int) progressOf(List<StepView> steps) =>
    (steps.where((s) => s.isDone).length, steps.length);

Map<String, Spec> specsByCode(Iterable<Spec> specs) => {
  for (final s in specs) s.code: s,
};

/// Codes in `spec.dependsOn` whose spec is not in "Feito" yet. Codes that
/// do not exist in the workspace are ignored (they could never be done).
List<String> specBlockers(Spec spec, Map<String, Spec> byCode) => [
  for (final code in spec.dependsOn)
    if (byCode[code] case final dep? when dep.stage != SpecStage.done) code,
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
bool isOnBoard(Spec spec) =>
    spec.status == SpecStatus.approved ||
    spec.status == SpecStatus.done ||
    spec.stage != SpecStage.backlog;

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
};
