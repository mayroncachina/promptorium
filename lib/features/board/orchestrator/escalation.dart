import 'package:flutter/foundation.dart';

import '../board_rules.dart';
import 'orchestrator_rules.dart';

/// The ladder of the escalation (SPEC-035 R9): each rung with its own
/// effort, weakest first.
const escalationLadder = [
  StepRule('haiku', 'low'),
  StepRule('sonnet', 'medium'),
  StepRule('opus', 'high'),
];

int _rungOf(String model) =>
    escalationLadder.indexWhere((r) => r.model == model);

/// The rung a failed step goes to.
@immutable
class EscalationRung {
  const EscalationRung(this.rule, {required this.number, this.ask = false});

  /// Model and effort of the rung.
  final StepRule rule;

  /// Which escalation of the step this is (1 = the first).
  final int number;

  /// "Perguntar antes de escalar para Opus" (R12): the step waits for the
  /// person before going up.
  final bool ask;

  @override
  bool operator ==(Object other) =>
      other is EscalationRung &&
      other.rule == rule &&
      other.number == number &&
      other.ask == ask;

  @override
  int get hashCode => Object.hash(rule, number, ask);

  @override
  String toString() => 'EscalationRung(${rule.label}, $number, ask: $ask)';
}

/// The rung above [current] after [escalations] climbs (R9), or null: no
/// escalation left ("Escaladas por etapa"), top of the ladder or a model
/// that is not on it. With 0 escalations it is always null (as before).
EscalationRung? nextRung(
  StepRule current,
  int escalations,
  OrchestratorPrefs prefs,
) {
  if (escalations >= prefs.maxEscalations) return null;
  final i = _rungOf(current.model);
  if (i < 0 || i + 1 >= escalationLadder.length) return null;
  final next = escalationLadder[i + 1];
  return EscalationRung(
    next,
    number: escalations + 1,
    ask: next.model == 'opus' && prefs.askBeforeOpus,
  );
}

/// Why a step that failed in Automático waits for the person (R16).
String escalationStopReason(StepRule current, int escalations) {
  final i = _rungOf(current.model);
  if (i == escalationLadder.length - 1) {
    return '${orchestratorModelLabel(current.model)} é o topo da escada';
  }
  if (i < 0) return '${current.model} não está na escada';
  return escalations == 1
      ? 'a escalada da etapa já foi usada'
      : 'as $escalations escaladas da etapa já foram usadas';
}

/// Models a step went through: the [plan] and one rung per escalation.
List<StepRule> escalationTrail(StepRule plan, int escalations) {
  final out = [plan];
  for (var n = 0; n < escalations; n++) {
    final i = _rungOf(out.last.model);
    if (i < 0 || i + 1 >= escalationLadder.length) break;
    out.add(escalationLadder[i + 1]);
  }
  return out;
}

/// `Sonnet → Opus · high` (R11): the models of [trail] and the effort of
/// the last one.
String escalationTrailLabel(List<StepRule> trail) =>
    '${trail.map((r) => orchestratorModelLabel(r.model)).join(' → ')} · '
    '${trail.last.effort}';

/// The ladder a step climbed after failed gates, `Sonnet → Opus · high`
/// (SPEC-035 R11); null when it did not escalate.
String? stepLadderLabel(StepView step) {
  final model = step.planModel;
  if (model == null || step.escalations <= 0) return null;
  final trail = escalationTrail(
    StepRule(model, step.planEffort ?? ''),
    step.escalations,
  );
  return trail.length < 2 ? null : escalationTrailLabel(trail);
}
