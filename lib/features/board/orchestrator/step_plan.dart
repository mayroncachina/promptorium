import 'package:flutter/foundation.dart';

import '../../../data/db/app_database.dart';
import '../../../data/repos/spec_steps_repo.dart';
import '../board_rules.dart';
import 'orchestrator_rules.dart';
import 'step_classifier.dart';

/// One line of the plan of Executar in Automático (SPEC-035 R4): the step,
/// its kind and the model + effort it runs with. Copied to `spec_steps`
/// (`kind`, `plan_model`, `plan_effort`, `plan_hash`, `user_picked`) when
/// the dialog is confirmed.
@immutable
class StepPlanEntry {
  const StepPlanEntry({
    required this.step,
    required this.title,
    required this.kind,
    required this.suggested,
    this.reason = '',
    this.pick,
    this.hash,
  });

  /// `R1`, `R3.1`, `REV1`.
  final String step;
  final String title;
  final StepKind kind;

  /// Reason of the classification (empty = the kind's hint).
  final String reason;

  /// The rule of [kind] when the plan was made.
  final StepRule suggested;

  /// What the person chose in the line ("você escolheu"); null = the rule.
  final StepRule? pick;

  /// [stepTextHash] of the classified text: the requirement's, for a
  /// sub-step; null for `REV<n>`, which is not classified.
  final String? hash;

  /// Model and effort the step runs with.
  StepRule get rule => pick ?? suggested;

  /// The person changed the line to something other than the rule (R4).
  bool get userPicked => pick != null && pick != suggested;

  /// `Mecânica: troca de nomes em 6 arquivos`.
  String get why => '${kind.label}: ${reason.isEmpty ? kind.hint : reason}';

  @override
  String toString() => 'StepPlanEntry($step, ${kind.name}, ${rule.label})';
}

/// The plan of the open [steps] of [spec] with the [kinds] of the
/// classification, the rules of [prefs] and the [picks] of the person (by
/// step id), in the order of the queue (R8: the plan never reorders). A
/// sub-step takes the kind of its requirement; a `REV<n>` uses Implementação.
/// A requirement the classification did not return is Implementação.
List<StepPlanEntry> buildStepPlan({
  required Spec spec,
  required List<StepView> steps,
  required Map<String, StepClassification> kinds,
  required OrchestratorPrefs prefs,
  Map<String, StepRule> picks = const {},
}) => [
  for (final s in steps)
    if (!s.isDone) _entry(s, kinds[parentOf(s.id)], prefs, picks[s.id]),
];

StepPlanEntry _entry(
  StepView s,
  StepClassification? c,
  OrchestratorPrefs prefs,
  StepRule? pick,
) {
  if (isReviewStep(s.id)) {
    return StepPlanEntry(
      step: s.id,
      title: s.text,
      kind: StepKind.implementacao,
      reason: 'correção pedida pela revisão automática',
      suggested: prefs.rule(StepKind.implementacao),
      pick: pick,
    );
  }
  final kind = c?.kind ?? StepKind.implementacao;
  final parent = parentOf(s.id);
  return StepPlanEntry(
    step: s.id,
    title: s.text,
    kind: kind,
    reason: [
      if (parent != s.id) 'subetapa de $parent',
      if (c != null && c.reason.isNotEmpty) c.reason,
    ].join(': '),
    suggested: prefs.rule(kind),
    pick: pick,
    hash: c?.hash,
  );
}

/// Sessions of a plan (R5): neighbour steps with the same model and effort
/// count as one.
int planSessions(Iterable<StepRule> rules) {
  var sessions = 0;
  StepRule? last;
  for (final r in rules) {
    if (r != last) sessions++;
    last = r;
  }
  return sessions;
}

/// "3 sessões: etapas vizinhas com o mesmo modelo seguem na mesma sessão".
String planSessionsLabel(int sessions) =>
    '${sessions == 1 ? '1 sessão' : '$sessions sessões'}: etapas vizinhas '
    'com o mesmo modelo seguem na mesma sessão';

/// Choices of the selector of a line: every model of the ladder with every
/// effort, plus [current] when it is not one of them.
List<StepRule> stepPlanChoices([StepRule? current]) => [
  for (final (m, _) in orchestratorModels)
    for (final e in orchestratorEfforts) StepRule(m, e),
  if (current != null &&
      !(orchestratorModels.any((m) => m.$1 == current.model) &&
          orchestratorEfforts.contains(current.effort)))
    current,
];

/// Kind and rule a step runs with in Automático (SPEC-035 R8).
typedef StepRunPlan = ({StepKind kind, StepRule rule});

/// The spec runs in Automático: some step has a plan in `spec_steps`
/// (Executar in Manual removes them, [clearStoredPlan]).
bool runsInAuto(Iterable<SpecStep> rows) =>
    rows.any((r) => r.planModel != null);

StepRunPlan? _own(SpecStep? r, OrchestratorPrefs prefs) {
  final model = r?.planModel;
  if (model == null) return null;
  final kind = StepKind.parse(r!.kind);
  return (
    kind: kind,
    rule: StepRule(model, r.planEffort ?? prefs.rule(kind).effort),
  );
}

/// The plan of [step] among the [rows] of its spec, or null (Manual: the
/// step runs with the model of the form). A step without its own row in a
/// spec that runs in Automático gets one from [prefs]: a sub-step takes the
/// plan of its requirement (or the kind of a planned sibling), a `REV<n>`
/// and anything else the rule Implementação (R8).
StepRunPlan? stepRunPlan(
  String step,
  Iterable<SpecStep> rows,
  OrchestratorPrefs prefs,
) {
  final byStep = {for (final r in rows) r.step: r};
  if (_own(byStep[step], prefs) case final p?) return p;
  if (!runsInAuto(rows)) return null;
  if (isSubStep(step)) {
    final parent = parentOf(step);
    if (_own(byStep[parent], prefs) case final p?) return p;
    for (final r in rows) {
      if (!isSubStep(r.step) || parentOf(r.step) != parent) continue;
      if (_own(r, prefs) case final p?) {
        return (kind: p.kind, rule: prefs.rule(p.kind));
      }
    }
  }
  const kind = StepKind.implementacao;
  return (kind: kind, rule: prefs.rule(kind));
}

/// Copies the [plan] to `spec_steps`: each step gets its kind, model,
/// effort, hash and "você escolheu", and starts from the bottom of the
/// ladder.
Future<void> storePlanEntries(
  SpecStepsRepo repo,
  int specId,
  List<StepPlanEntry> plan,
) async {
  for (final e in plan) {
    await repo.setPlan(
      specId,
      e.step,
      kind: e.kind.name,
      model: e.rule.model,
      effort: e.rule.effort,
      hash: e.hash,
      userPicked: e.userPicked,
    );
  }
  await repo.resetEscalations(specId, [for (final e in plan) e.step]);
}

/// Removes the plan left by an earlier run in Automático: the steps run
/// with the model of the form again.
Future<void> clearStoredPlan(SpecStepsRepo repo, int specId) async {
  final planned = [
    for (final r in await repo.bySpec(specId))
      if (r.kind != null || r.planModel != null) r.step,
  ];
  if (planned.isNotEmpty) await repo.clearPlan(specId, planned);
}
