import 'package:flutter/foundation.dart';

import '../../../core/claude/run_prefs.dart' show defaultEffort;
import '../board_rules.dart';
import 'orchestrator_rules.dart';

/// The ladder of the escalation on the Claude Code (SPEC-035 R9): each rung
/// with its own effort, weakest first.
const escalationLadder = [
  StepRule('haiku', 'low'),
  StepRule('sonnet', 'medium'),
  StepRule('opus', 'high'),
];

/// Efforts of the ladder of the Codex (SPEC-109 R3), when the model takes
/// them.
const codexLadderEfforts = ['low', 'medium', 'high', 'ultra'];

/// The ladder of the provider of [rule] (SPEC-109 R3): [escalationLadder]
/// on the Claude Code; on the Codex, the model of [rule] with the effort
/// going up, or the list of models the person ordered, with the effort of
/// [rule]. Empty = the catalog does not say the efforts.
List<StepRule> ladderFor(StepRule rule, OrchestratorPrefs prefs) {
  if (rule.isClaude) return escalationLadder;
  switch (prefs.codexLadder) {
    case CodexLadder.effort:
      final efforts = prefs.codexEfforts(rule.model);
      return [
        for (final e in codexLadderEfforts)
          if (efforts.contains(e))
            StepRule(rule.model, e, provider: rule.provider),
      ];
    case CodexLadder.models:
      return [
        for (final m in prefs.codexLadderModels)
          StepRule(
            m,
            prefs.codexEfforts(m).contains(rule.effort)
                ? rule.effort
                : defaultEffort,
            provider: rule.provider,
          ),
      ];
  }
}

/// Position of [rule] on [ladder]; on the ladder by effort an effort
/// between two rungs (`xhigh`) counts as the one below. -1 = not on it.
int _rungOf(StepRule rule, List<StepRule> ladder, OrchestratorPrefs prefs) {
  if (rule.isClaude || prefs.codexLadder == CodexLadder.models) {
    return ladder.indexWhere((r) => r.model == rule.model);
  }
  final exact = ladder.indexWhere((r) => r.effort == rule.effort);
  if (exact >= 0) return exact;
  final order = prefs.codexEfforts(rule.model);
  final at = order.indexOf(rule.effort);
  if (at < 0 || rule.effort == defaultEffort) return -1;
  return ladder.lastIndexWhere((r) => order.indexOf(r.effort) < at);
}

/// The rung above [rule] on its provider's ladder; null = the top, or not
/// on it.
StepRule? _above(StepRule rule, OrchestratorPrefs prefs) {
  final ladder = ladderFor(rule, prefs);
  final i = _rungOf(rule, ladder, prefs);
  if (i < 0 || i + 1 >= ladder.length) return null;
  return ladder[i + 1];
}

bool _atTop(StepRule rule, OrchestratorPrefs prefs) {
  final ladder = ladderFor(rule, prefs);
  return ladder.isNotEmpty && _rungOf(rule, ladder, prefs) == ladder.length - 1;
}

/// The top of the ladder of the provider [rule] is on.
StepRule? _topOf(StepRule rule, OrchestratorPrefs prefs) =>
    ladderFor(rule, prefs).lastOrNull;

/// The rung a failed step goes to.
@immutable
class EscalationRung {
  const EscalationRung(
    this.rule, {
    required this.number,
    this.ask = false,
    this.secondOpinion = false,
  });

  /// Model and effort of the rung.
  final StepRule rule;

  /// Which escalation of the step this is (1 = the first).
  final int number;

  /// "Perguntar antes do degrau mais alto" (SPEC-035 R12, SPEC-109 R3): the
  /// step waits for the person before going up.
  final bool ask;

  /// The top of the other provider's ladder (SPEC-109 R4).
  final bool secondOpinion;

  @override
  bool operator ==(Object other) =>
      other is EscalationRung &&
      other.rule == rule &&
      other.number == number &&
      other.ask == ask &&
      other.secondOpinion == secondOpinion;

  @override
  int get hashCode => Object.hash(rule, number, ask, secondOpinion);

  @override
  String toString() => 'EscalationRung(${rule.label}, $number, ask: $ask)';
}

/// The rung above [current] after [escalations] climbs (R9), or null: no
/// escalation left ("Escaladas por etapa"), top of the ladder or a model
/// that is not on it. With 0 escalations it is always null (as before).
///
/// The ladder is the one of the provider of [current] (SPEC-109 R3). With
/// "No topo da escada, tentar o outro provedor" on, a step at the top that
/// is still on the provider of its [plan] gets the top of the ladder of
/// [reserve], its rule on the other provider (R4): once, since there it no
/// longer is on the plan's provider. [reserve] null = no second opinion
/// (sem reserva, or the other provider cannot run).
EscalationRung? nextRung(
  StepRule current,
  int escalations,
  OrchestratorPrefs prefs, {
  StepRule? plan,
  StepRule? reserve,
}) {
  if (escalations >= prefs.maxEscalations) return null;
  final next = _above(current, prefs);
  if (next != null) {
    return EscalationRung(
      next,
      number: escalations + 1,
      ask: prefs.askBeforeOpus && _atTop(next, prefs),
    );
  }
  if (!prefs.secondOpinion ||
      reserve == null ||
      !_atTop(current, prefs) ||
      current.provider != (plan ?? current).provider ||
      reserve.provider == current.provider) {
    return null;
  }
  final top = _topOf(reserve, prefs) ?? reserve;
  return EscalationRung(
    top,
    number: escalations + 1,
    ask: prefs.askBeforeOpus,
    secondOpinion: true,
  );
}

/// Why a step that failed in Automático waits for the person (R16).
String escalationStopReason(
  StepRule current,
  int escalations, [
  OrchestratorPrefs prefs = const OrchestratorPrefs({}),
]) {
  final name = current.isClaude
      ? orchestratorModelLabel(current.model)
      : current.label;
  if (_atTop(current, prefs)) return '$name é o topo da escada';
  if (_above(current, prefs) == null) {
    return '${current.isClaude ? current.model : current.label} não está na '
        'escada';
  }
  return escalations == 1
      ? 'a escalada da etapa já foi usada'
      : 'as $escalations escaladas da etapa já foram usadas';
}

/// Rules a step went through: the [plan] and one rung per escalation; past
/// the top, the second opinion on [reserve] (SPEC-109 R4).
List<StepRule> escalationTrail(
  StepRule plan,
  int escalations, [
  OrchestratorPrefs prefs = const OrchestratorPrefs({}),
  StepRule? reserve,
]) {
  final out = [plan];
  for (var n = 0; n < escalations; n++) {
    final next = _above(out.last, prefs);
    if (next != null && out.last.provider == plan.provider) {
      out.add(next);
      continue;
    }
    if (prefs.secondOpinion &&
        reserve != null &&
        reserve.provider != plan.provider &&
        out.last.provider == plan.provider) {
      out.add(_topOf(reserve, prefs) ?? reserve);
    }
    break;
  }
  return out;
}

/// `Sonnet → Opus · high` (R11): the models of [trail] and the effort of
/// the last one. On the Codex by effort, `gpt-6.2-sol · low → medium`; a
/// trail across providers says each one's (SPEC-109 R4).
String escalationTrailLabel(List<StepRule> trail) {
  final providers = {for (final r in trail) r.provider};
  if (providers.length > 1) return trail.map((r) => r.fullLabel).join(' → ');
  final models = {for (final r in trail) r.model};
  if (!trail.last.isClaude && models.length == 1) {
    return '${trail.first.label} → ${trail.skip(1).map((r) => r.effort).join(' → ')}';
  }
  return '${trail.map((r) => orchestratorModelLabel(r.model)).join(' → ')} · '
      '${trail.last.effort}';
}

/// The ladder a step climbed after failed gates, `Sonnet → Opus · high`
/// (SPEC-035 R11); null when it did not escalate. [prefs] gives the ladder
/// of the Codex (SPEC-109 R3).
String? stepLadderLabel(
  StepView step, [
  OrchestratorPrefs prefs = const OrchestratorPrefs({}),
]) {
  final model = step.planModel;
  if (model == null || step.escalations <= 0) return null;
  final trail = escalationTrail(
    StepRule(
      model,
      step.planEffort ?? '',
      provider: step.planProvider ?? 'claude',
    ),
    step.escalations,
    prefs,
  );
  return trail.length < 2 ? null : escalationTrailLabel(trail);
}
