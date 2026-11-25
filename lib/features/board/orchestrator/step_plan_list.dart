import 'package:flutter/material.dart';

import '../../../ui/providers/provider_logos.dart';
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
    this.prefs = const OrchestratorPrefs({}),
    this.codexBlocked,
    this.codexOffered = false,
    this.hasAgent = false,
  });

  /// The rules and the catalog of the Codex (SPEC-109 R9).
  final OrchestratorPrefs prefs;

  /// Why the Codex cannot run now; null = it can.
  final String? codexBlocked;

  /// The line may go to the Codex (it is on the machine, or in the plan).
  final bool codexOffered;

  /// The spec runs with `--agent`: a line on the Codex says it does not
  /// (R10).
  final bool hasAgent;

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
      for (final e in [...entries, ?review])
        _PlanRow(
          entry: e,
          onPick: onPick,
          prefs: prefs,
          codexBlocked: codexBlocked,
          codexOffered: codexOffered,
          hasAgent: hasAgent,
        ),
    ],
  );
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.entry,
    required this.onPick,
    required this.prefs,
    required this.codexBlocked,
    required this.codexOffered,
    required this.hasAgent,
  });

  final OrchestratorPrefs prefs;
  final String? codexBlocked;
  final bool codexOffered;
  final bool hasAgent;
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
                if (!e.rule.isClaude && codexBlocked != null)
                  Text(
                    'Codex indisponível: $codexBlocked',
                    key: ValueKey('step-plan-blocked-${e.step}'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.amber,
                    ),
                  )
                else if (!e.rule.isClaude && hasAgent && !review)
                  Text(
                    'agente só no Claude',
                    key: ValueKey('step-plan-no-agent-${e.step}'),
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
          // R9, R14: who runs the step, by name, before the model.
          if (codexOffered || !e.rule.isClaude)
            PopupMenuButton<String>(
              key: ValueKey('step-plan-provider-${e.step}'),
              tooltip:
                  'Provedor de ${review ? 'revisão' : e.step}: '
                  '${planProviderLabel(e.rule.provider)}',
              color: AppColors.panelSolid,
              padding: EdgeInsets.zero,
              onSelected: (p) {
                if (p != e.rule.provider) {
                  onPick(e.step, stepPlanOn(p, e, prefs));
                }
              },
              itemBuilder: (_) => [
                for (final p in const ['claude', 'codex'])
                  PopupMenuItem(
                    key: ValueKey('step-plan-provider-${e.step}-$p'),
                    value: p,
                    child: ProviderChip(p),
                  ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProviderChip(
                    e.rule.provider,
                    key: ValueKey('step-plan-chip-${e.step}'),
                    dense: true,
                  ),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            )
          else
            ProviderChip(
              e.rule.provider,
              key: ValueKey('step-plan-chip-${e.step}'),
              dense: true,
            ),
          const SizedBox(width: 8),
          SizedBox(
            width: e.rule.isClaude ? 150 : 190,
            child: Semantics(
              label: 'Modelo de ${review ? 'revisão' : e.step}',
              child: DropdownButtonFormField<StepRule>(
                key: ValueKey(
                  'step-plan-model-${e.step}-'
                  '${e.rule.isClaude ? e.rule.label : e.rule.fullLabel}',
                ),
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
                    prefs: prefs,
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
