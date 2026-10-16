import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../project_plan.dart';
import '../project_planner.dart';
import 'project_widgets.dart';
import 'roadmap_editors.dart';

Future<bool> _confirmRegenerate(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Regerar o roadmap?', style: TextStyle(fontSize: 15)),
        content: const Text(
          'Você editou este roadmap. O planner gera um novo do zero e as '
          'suas edições se perdem.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('roadmap-regenerate-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Regerar'),
          ),
        ],
      ),
    ) ??
    false;

/// Step 4 · Roadmap: specs in phases (Fundação first, then MVP; out-of-scope
/// ideas under "Depois") and the execution order. Each spec is a card of the
/// Quadro; its requirements are the steps.
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
    final stepCount = roadmap.stepCount;
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
                    ? '${roadmap.specs.length} specs · $stepCount etapas'
                          '${roadmap.edited ? ' · editado por você' : ''}'
                          ' · clique numa spec para editar'
                    : 'Specs geradas a partir da visão e da stack.',
                actions: [
                  PlannerButton(
                    key: const ValueKey('project-roadmap-again'),
                    label: roadmap.isReady
                        ? 'Regerar com o planner'
                        : 'Gerar roadmap',
                    onTap: busy == null
                        ? () async {
                            if (roadmap.edited) {
                              final ok = await _confirmRegenerate(context);
                              if (!ok) return;
                            }
                            await planner.planRoadmap(workspace);
                          }
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
                    : roadmap.oversized.isNotEmpty
                    ? NoticeBox(
                        text:
                            '${roadmap.oversized.map((s) => s.code).join(', ')} '
                            'tem mais de ${Roadmap.maxRequirements} '
                            'requisitos: grande demais para um PR. Divida em '
                            'duas specs.',
                      )
                    : const NoticeBox(
                        text:
                            'As sessões nascem do último commit da branch '
                            'principal. Por isso a Fundação roda primeiro, e '
                            'as specs do MVP só são liberadas depois do '
                            'merge dela.',
                      ),
              ),
              Expanded(
                child: roadmap.isReady
                    ? _Phases(workspace: workspace, roadmap: roadmap)
                    : const StepEmpty(
                        title: 'Sem roadmap ainda',
                        text:
                            'O planner divide o projeto em specs da Fundação '
                            'e do MVP, com requisitos (as etapas) e '
                            'dependências.',
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
  const _Phases({required this.workspace, required this.roadmap});

  final Workspace workspace;
  final Roadmap roadmap;

  static const minColumn = 260.0;

  List<(int, RoadmapSpec)> _of(RoadmapPhase p) => [
    for (final (i, s) in roadmap.specs.indexed)
      if (s.phase == p) (i, s),
  ];

  @override
  Widget build(BuildContext context) {
    Future<void> addSpec(RoadmapPhase p) => showSpecEditor(
      context,
      workspace: workspace,
      roadmap: roadmap,
      phase: p,
    );
    final columns = [
      _PhaseColumn(
        key: const ValueKey('roadmap-phase-foundation'),
        title: RoadmapPhase.foundation.label,
        badge: 'sequencial',
        badgeColor: AppColors.amber,
        border: SessionColors.approvalBorder,
        subtitle: 'Roda primeiro. Cada merge libera a próxima.',
        workspace: workspace,
        roadmap: roadmap,
        specs: _of(RoadmapPhase.foundation),
        addLabel: 'Spec da Fundação',
        onAdd: () => addSpec(RoadmapPhase.foundation),
      ),
      _PhaseColumn(
        key: const ValueKey('roadmap-phase-mvp'),
        title: RoadmapPhase.mvp.label,
        badge: 'em paralelo',
        badgeColor: AppColors.teal,
        border: AppColors.border,
        subtitle: 'Liberado após o merge da Fundação.',
        workspace: workspace,
        roadmap: roadmap,
        specs: _of(RoadmapPhase.mvp),
        addLabel: 'Spec do MVP',
        onAdd: () => addSpec(RoadmapPhase.mvp),
      ),
      _PhaseColumn(
        key: const ValueKey('roadmap-phase-later'),
        title: 'Depois',
        badge: 'ideias',
        badgeColor: AppColors.textSecondary,
        border: AppColors.border,
        subtitle:
            'Fora do escopo por enquanto. Clique para trazer uma ideia '
            'para o roadmap.',
        workspace: workspace,
        roadmap: roadmap,
        specs: const [],
        ideas: roadmap.later,
        addLabel: 'Editar ideias',
        onAdd: () =>
            showIdeasEditor(context, workspace: workspace, roadmap: roadmap),
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
    super.key,
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.border,
    required this.subtitle,
    required this.workspace,
    required this.roadmap,
    required this.specs,
    required this.addLabel,
    required this.onAdd,
    this.ideas = const [],
  });

  final String title;
  final String badge;
  final Color badgeColor;
  final Color border;
  final String subtitle;
  final Workspace workspace;
  final Roadmap roadmap;

  /// (index in the roadmap, spec).
  final List<(int, RoadmapSpec)> specs;
  final List<String> ideas;
  final String addLabel;
  final VoidCallback onAdd;

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
        for (final (i, s) in specs)
          _SpecCard(
            key: ValueKey('roadmap-spec-$i'),
            spec: s,
            onEdit: () => showSpecEditor(
              context,
              workspace: workspace,
              roadmap: roadmap,
              index: i,
            ),
          ),
        for (final (i, idea) in ideas.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surfaceRaised,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                key: ValueKey('roadmap-idea-$i'),
                onTap: () =>
                    showIdeaDialog(context, workspace: workspace, idea: idea),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    idea,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (specs.isEmpty && ideas.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Nada aqui.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        AddButton(
          key: ValueKey('roadmap-add-$title'),
          label: addLabel,
          onTap: onAdd,
        ),
      ],
    ),
  );
}

class _SpecCard extends StatelessWidget {
  const _SpecCard({super.key, required this.spec, required this.onEdit});

  final RoadmapSpec spec;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('roadmap-spec-edit'),
              onTap: onEdit,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          spec.code,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${spec.requirements.length} etapas',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                spec.requirements.length >
                                    Roadmap.maxRequirements
                                ? AppColors.red
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
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
                    for (final r in spec.requirements)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '${r.id} · ${r.text}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      spec.dependsOn.isEmpty
                          ? 'sem dependências'
                          : 'depende de ${spec.dependsOn.join(', ')}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
              '+ ${waves.length - shown} ondas, liberadas conforme as '
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
        stat('Etapas', '${roadmap.stepCount}'),
        stat('Dependências', '${roadmap.dependencyCount}'),
        stat('Ideias para depois', '${roadmap.later.length}'),
      ],
    );
  }
}
