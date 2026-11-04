import 'package:flutter/material.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../board_rules.dart';
import '../step_decision.dart';
import '../step_decision_choices.dart';

/// What the Compilar phase of the modal gets (SPEC-033 R9–R11).
@immutable
class StepDecisionCompileRequest {
  const StepDecisionCompileRequest({
    required this.spec,
    required this.step,
    required this.summary,
    required this.decisions,
    required this.choices,
    required this.onBack,
    required this.onChange,
    required this.onClose,
    required this.onSubmit,
  });

  final Spec spec;
  final StepView step;
  final String summary;

  /// Empty when the options failed or did not arrive: the only answer is
  /// "Outra resposta".
  final List<StepDecision> decisions;

  /// Every decision has one, in order.
  final List<StepDecisionChoice> choices;

  /// "Voltar" (also `Backspace`, outside a text field).
  final VoidCallback onBack;

  /// "Mudar": back to the decision of that index.
  final ValueChanged<int> onChange;

  /// Closes the modal and gives the focus back to the balloon.
  final VoidCallback onClose;

  /// Fires on `Ctrl+Enter` during the phase: the primary button.
  final Listenable onSubmit;
}

/// Builds the Compilar phase; [StepDecisionDialog] shows it in place of the
/// options and the preview, between the header and the footer.
typedef StepDecisionCompileBuilder = Widget Function(
  BuildContext context,
  StepDecisionCompileRequest request,
);

/// Extension point of SPEC-033 T4: this is the phase that "Compilar" and
/// `Ctrl+Enter` open once every decision is answered. It has nothing to
/// compile yet.
Widget buildStepDecisionCompile(
  BuildContext context,
  StepDecisionCompileRequest request,
) => Center(
  key: const ValueKey('step-decision-compile'),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'A fase Compilar ainda não está disponível.',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 12),
      SmallButton(
        key: const ValueKey('step-decision-compile-back'),
        label: 'Voltar',
        onTap: request.onBack,
      ),
    ],
  ),
);
