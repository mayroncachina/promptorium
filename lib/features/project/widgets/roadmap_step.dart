import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../project_plan.dart';
import '../project_planner.dart';
import 'project_widgets.dart';

/// Step 4 · Roadmap: specs and tasks in phases (Fundação first, then MVP;
/// out-of-scope ideas under "Depois") and the execution order.
class RoadmapStep extends ConsumerWidget {
  const RoadmapStep({super.key, required this.workspace, required this.data});

  final Workspace workspace;
  final ProjectPlanData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(
      projectPlannerProvider.select((m) => m[workspace.id]),
    );
    final busy = activity?.busy;
    final planner = ref.read(projectPlannerProvider.notifier);
    final roadmap = data.roadmap;
    final taskCount = roadmap.tasks.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StepHeader(
                title: 'Roadmap',
                subtitle: roadmap.isReady
                    ? '${roadmap.specs.length} specs · $taskCount tarefas'
                    : 'Specs e tarefas geradas a partir da visão e da stack.',
                actions: [
                  PlannerButton(
                    key: const ValueKey('project-roadmap-again'),
                    label: roadmap.isReady
                        ? 'Regerar com o planner'
                        : 'Gerar roadmap',
                    onTap: busy == null
                        ? () => planner.planRoadmap(workspace)
                        : null,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: busy != null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: PlannerBusy(busy),
                      )
                    : activity?.error != null
                    ? NoticeBox.error(
                        text: activity!.error!,
                        action: SmallButton(
                          label: 'Fechar',
                          onTap: () => planner.clearError(workspace.id),
                        ),
                      )
                    : const NoticeBox(
                        text:
                            'As sessões nascem do último commit da branch '
                            'principal. Por isso a Fundação roda primeiro, e '
                            'as tarefas do MVP só são liberadas depois do '
                            'merge dela.',
                      ),
              ),
              Expanded(
                child: roadmap.isReady
                    ? _Phases(roadmap: roadmap)
                    : const StepEmpty(
                        title: 'Sem roadmap ainda',
                        text:
                            'O planner divide o projeto em specs da Fundação '
                            'e do MVP, com tarefas e dependências.',
                      ),
              ),
            ],
          ),
        ),
        SidePanel(
          title: 'Ordem de execução',
          width: 300,
          footer: StepNav(
            onBack: () => planner.goTo(workspace, ProjectStep.stack),
            nextKey: const ValueKey('project-roadmap-next'),
            nextLabel: 'Próximo: Revisar e criar',
            onNext: roadmap.isReady && busy == null
                ? () => planner.goTo(workspace, ProjectStep.create)
                : null,
          ),
          child: roadmap.isReady
              ? _Summary(roadmap: roadmap)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _Phases extends StatelessWidget {
  const _Phases({required this.roadmap});

  final Roadmap roadmap;

  static const minColumn = 260.0;

  @override
  Widget build(BuildContext context) {
    final columns = [
      _PhaseColumn(
        title: RoadmapPhase.foundation.label,
        badge: 'sequencial',
        badgeColor: AppColors.amber,
        border: SessionColors.approvalBorder,
        subtitle: 'Roda primeiro. Cada merge libera a próxima.',
        specs: roadmap.ofPhase(RoadmapPhase.foundation),
      ),
      _PhaseColumn(
        title: RoadmapPhase.mvp.label,
        badge: 'em paralelo',
        badgeColor: AppColors.teal,
        border: AppColors.border,
        subtitle: 'Liberado após o merge da Fundação.',
        specs: roadmap.ofPhase(RoadmapPhase.mvp),
      ),
      _PhaseColumn(
        title: 'Depois',
        badge: 'ideias',
        badgeColor: AppColors.textSecondary,
        border: AppColors.border,
        subtitle: 'Fora do escopo do MVP. Não viram tarefas.',
        specs: const [],
        ideas: roadmap.later,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final width = math.max(c.maxWidth, minColumn * 3 + 14 * 2 + 40);
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: c.maxHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, col) in columns.indexed) ...[
                      if (i > 0) const SizedBox(width: 14),
                      Expanded(child: col),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhaseColumn extends StatelessWidget {
  const _PhaseColumn({
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.border,
    required this.subtitle,
    required this.specs,
    this.ideas = const [],
  });

  final String title;
  final String badge;
  final Color badgeColor;
  final Color border;
  final String subtitle;
  final List<RoadmapSpec> specs;
  final List<String> ideas;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.panel,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const Spacer(),
            Text(badge, style: TextStyle(fontSize: 11, color: badgeColor)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        for (final s in specs) _SpecCard(spec: s),
        for (final idea in ideas)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              idea,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        if (specs.isEmpty && ideas.isEmpty)
          const Text(
            'Nada aqui.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
      ],
    ),
  );
}

class _SpecCard extends StatelessWidget {
  const _SpecCard({required this.spec});

  final RoadmapSpec spec;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          spec.title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        if (spec.objective.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            spec.objective,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (final t in spec.tasks)
          Container(
            key: ValueKey('project-roadmap-task-${t.code}'),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      t.code,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    if (t.requirement.isNotEmpty)
                      Text(
                        t.requirement,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  t.title,
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  t.dependsOn.isEmpty
                      ? 'sem dependências'
                      : 'depende de ${t.dependsOn.join(', ')}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.roadmap});

  final Roadmap roadmap;

  @override
  Widget build(BuildContext context) {
    final waves = roadmap.waves();
    const shown = 5;
    Widget stat(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (final (i, w) in waves.take(shown).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.amberTint,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.amber,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    w.length == 1
                        ? '${w.single.code} sozinha · ${w.single.title}'
                        : '${w.map((t) => t.code).join(', ')} lado a lado',
                    style: const TextStyle(fontSize: 12, color: AppColors.text),
                  ),
                ),
              ],
            ),
          ),
        if (waves.length > shown)
          Padding(
            padding: const EdgeInsets.only(left: 30, bottom: 8),
            child: Text(
              '+ ${waves.length - shown} etapas, liberadas conforme as '
              'dependências',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text('RESUMO', style: sectionTitleStyle),
        const SizedBox(height: 10),
        stat(
          'Specs da Fundação',
          '${roadmap.ofPhase(RoadmapPhase.foundation).length}',
        ),
        stat('Specs do MVP', '${roadmap.ofPhase(RoadmapPhase.mvp).length}'),
        stat('Tarefas', '${roadmap.tasks.length}'),
        stat('Dependências', '${roadmap.dependencyCount}'),
        stat('Ideias para depois', '${roadmap.later.length}'),
      ],
    );
  }
}
