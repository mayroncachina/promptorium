import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'step_decision.dart';

/// What the person chose for one decision of a stop (SPEC-033 R8).
@immutable
class StepDecisionChoice {
  const StepDecisionChoice({
    required this.decision,
    this.question = '',
    this.option,
    this.text = '',
  });

  /// Index of the decision in [StepDecisionResult.decisions].
  final int decision;

  /// Empty when "Outra resposta" came before the options did (R14).
  final String question;

  /// Null for "Outra resposta", which has its answer in [text].
  final StepDecisionOption? option;
  final String text;

  bool get isOther => option == null;

  String get title => option?.title ?? text;

  /// "Outra resposta" is only a message to the agent.
  StepDecisionKind get kind => option?.kind ?? StepDecisionKind.answer;

  /// Still an answer to [decision]: a new stop of the same step brings other
  /// questions, and what was chosen for the old ones does not apply. Null
  /// [decision] = the options are not here yet.
  bool fits(StepDecision? decision) {
    if (decision == null) return isOther;
    if (question.isNotEmpty && question != decision.question) return false;
    return isOther || decision.options.any((o) => o.title == option!.title);
  }
}

/// Session and step whose choices are kept. A step that never had a session
/// uses `spec-<id>`, so that `R1` of two specs do not share them.
typedef StepDecisionChoiceKey = (String sessionId, String step);

/// The choices of each stop while the app is open: closing and reopening the
/// modal does not lose them (R8). The list is in decision order.
class StepDecisionChoices
    extends Notifier<Map<StepDecisionChoiceKey, List<StepDecisionChoice>>> {
  @override
  Map<StepDecisionChoiceKey, List<StepDecisionChoice>> build() => const {};

  /// Stores [choice] in the place of the one of the same decision.
  void set(StepDecisionChoiceKey key, StepDecisionChoice choice) {
    state = {
      ...state,
      key: [
        for (final c in state[key] ?? const <StepDecisionChoice>[])
          if (c.decision != choice.decision) c,
        choice,
      ]..sort((a, b) => a.decision.compareTo(b.decision)),
    };
  }

  /// Takes the answer of [decision] back.
  void remove(StepDecisionChoiceKey key, int decision) {
    final left = [
      for (final c in state[key] ?? const <StepDecisionChoice>[])
        if (c.decision != decision) c,
    ];
    state = left.isEmpty ? ({...state}..remove(key)) : {...state, key: left};
  }

  /// The stop is over: Compilar (T4) forgets its choices.
  void clear(StepDecisionChoiceKey key) {
    if (state.containsKey(key)) state = {...state}..remove(key);
  }
}

final stepDecisionChoicesProvider =
    NotifierProvider<
      StepDecisionChoices,
      Map<StepDecisionChoiceKey, List<StepDecisionChoice>>
    >(StepDecisionChoices.new);

/// Draft of "Abrir sessão" (R12): one line per decision, the open ones
/// included; empty when nothing was decided, so the field stays empty.
String stepDecisionDraft(
  List<StepDecision> decisions,
  List<StepDecisionChoice> choices,
) {
  if (choices.isEmpty) return '';
  final total = math.max(decisions.length, choices.last.decision + 1);
  final byDecision = {for (final c in choices) c.decision: c};
  String sentence(String text) => text.endsWith('.') ? text : '$text.';
  return [
    'Decidi pelo modal:',
    for (var i = 0; i < total; i++)
      () {
        final question = i < decisions.length ? decisions[i].question : '';
        final choice = byDecision[i];
        final answer = choice == null
            ? '(ainda não decidi; vamos ver juntos)'
            : sentence(choice.title);
        if (question.isEmpty) return '${i + 1}. $answer';
        return '${i + 1}. $question ${choice == null ? '' : '→ '}$answer';
      }(),
  ].join('\n');
}
