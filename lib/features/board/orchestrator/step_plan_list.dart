import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../widgets/step_decision_parts.dart' show StepDecisionShimmer;
import 'orchestrator_rules.dart';
import 'step_plan.dart';

/// The plan of Executar in Automático (SPEC-035 R4): one line per step with
/// the id, the title, the kind and reason, and the model + effort in a
/// selector; [review], when the automatic reviewer is on in the project, is
/// the last line and is not a step of the queue.
class StepPlanList extends StatelessWidget {
  const StepPlanList({
    super.key,
    required this.entries,
    required this.onPick,
    this.review,
  });

  final List<StepPlanEntry> entries;
  final StepPlanEntry? review;

  /// The person changed the selector of a line (`review` for [review]).
  final void Function(String step, StepRule rule) onPick;

  /// Step id of the line of the automatic reviewer.
  static const reviewStep = 'review';

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('step-plan-list'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final e in entries) _PlanRow(entry: e, onPick: onPick),
      if (review case final r?) _PlanRow(entry: r, onPick: onPick),
    ],
  );
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.entry, required this.onPick});

  final StepPlanEntry entry;
  final void Function(String step, StepRule rule) onPick;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final review = e.step == StepPlanList.reviewStep;
    return Container(
      key: ValueKey('step-plan-${e.step}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              review ? 'REV' : e.step,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  e.why,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (e.userPicked) ...[
            const SizedBox(width: 8),
            Text(
              'você escolheu',
              key: ValueKey('step-plan-picked-${e.step}'),
              style: const TextStyle(fontSize: 12, color: AppColors.amber),
            ),
          ],
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: Semantics(
              label: 'Modelo de ${review ? 'revisão' : e.step}',
              child: DropdownButtonFormField<StepRule>(
                key: ValueKey('step-plan-model-${e.step}-${e.rule.label}'),
                initialValue: e.rule,
                isDense: true,
                isExpanded: true,
                dropdownColor: AppColors.panelSolid,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
                items: [
                  for (final r in stepPlanChoices(
                    suggested: e.suggested,
                    current: e.rule,
                  ))
                    DropdownMenuItem(
                      value: r,
                      child: Text(r.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (r) {
                  if (r != null) onPick(e.step, r);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The plan while the steps are classified (R3): one line per step.
class StepPlanSkeleton extends StatelessWidget {
  const StepPlanSkeleton({super.key, required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    Widget bone(double? width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: SessionColors.selectedBorder,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return StepDecisionShimmer(
      key: const ValueKey('step-plan-skeleton'),
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  bone(26, 12),
                  const SizedBox(width: 12),
                  Expanded(child: bone(null, 12)),
                  const SizedBox(width: 12),
                  bone(120, 22),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
