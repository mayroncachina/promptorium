import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/timeline_provider.dart';
import '../../specs/spec_service.dart';
import '../board_rules.dart';

/// Subagents of a spec, read from the frontmatter of its file. Invalidate
/// after saving the file.
final specSubagentsProvider = FutureProvider.family<List<SpecSubagent>, Spec>((
  ref,
  spec,
) async {
  final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
  if (ws == null) return const [];
  try {
    final text = await ref.read(specServiceProvider).read(ws, spec);
    return text == null ? const [] : SpecDocument.parse(text).subagents;
  } catch (_) {
    return const [];
  }
});

/// Status of the spec's subagents (live: follows the sessions' timelines).
/// Only specs with subagents load their timelines.
List<SubagentStatus> watchSubagentStatuses(
  WidgetRef ref,
  Spec spec,
  List<StepView> steps,
  List<Session> sessions,
) {
  final subs = ref.watch(specSubagentsProvider(spec)).value ?? const [];
  if (subs.isEmpty) return const [];
  return subagentStatuses(
    subs,
    spec: spec,
    steps: steps,
    timelines: [
      for (final s in sessions) ref.watch(sessionTimelineProvider(s.id)).items,
    ],
  );
}

Color subagentColor(SubagentState s) => switch (s) {
  SubagentState.pending => AppColors.textMuted,
  SubagentState.running => AppColors.teal,
  SubagentState.done => AppColors.blue,
  SubagentState.failed => AppColors.red,
  SubagentState.notCalled => AppColors.amber,
};

/// One chip per subagent: `spec-reviewer · fim da spec` + its state.
class SubagentChips extends StatelessWidget {
  const SubagentChips({super.key, required this.statuses});

  final List<SubagentStatus> statuses;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final s in statuses)
        Container(
          key: ValueKey('subagent-chip-${s.subagent.agent}'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: subagentColor(s.state)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${s.subagent.summary} · ${subagentStateLabel(s.state)}',
            style: TextStyle(fontSize: 10, color: subagentColor(s.state)),
          ),
        ),
    ],
  );
}

/// Chips plus what each finished subagent concluded (steps panel).
class SubagentReport extends StatelessWidget {
  const SubagentReport({super.key, required this.statuses});

  final List<SubagentStatus> statuses;

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SUBAGENTES', style: sectionTitleStyleMuted),
        const SizedBox(height: 6),
        SubagentChips(statuses: statuses),
        for (final s in statuses)
          if (s.summary != null) ...[
            const SizedBox(height: 6),
            Text(
              '${s.subagent.agent}: ${s.summary!.length > 280 ? '${s.summary!.substring(0, 280)}…' : s.summary!}',
              key: ValueKey('subagent-summary-${s.subagent.agent}'),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
      ],
    );
  }
}

const sectionTitleStyleMuted = TextStyle(
  fontSize: 10,
  letterSpacing: 0.6,
  fontWeight: FontWeight.w600,
  color: AppColors.textMuted,
);
