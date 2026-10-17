import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_icon.dart';
import '../sessions/widgets/session_style.dart';
import 'new_project_dialog.dart';
import 'project_plan.dart';
import 'project_planner.dart';
import 'project_service.dart';
import 'widgets/create_step.dart';
import 'widgets/project_config_view.dart';
import 'widgets/project_health_view.dart';
import 'widgets/project_memory_view.dart';
import 'widgets/spec_metrics_view.dart';
import 'widgets/project_widgets.dart';
import 'widgets/roadmap_step.dart';
import 'widgets/stack_step.dart';
import 'widgets/vision_step.dart';

/// Projeto: plans a project with the planner (Visão → Stack e convenções →
/// Roadmap → Revisar e criar) and turns the plan into CLAUDE.md, specs and
/// tasks (canvas "Promptorium — Novo projeto").
class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return ColoredBox(
        color: AppColors.background,
        child: StepEmpty(
          title: 'Nenhum workspace',
          text:
              'Crie um projeto novo ou selecione um workspace na barra de '
              'título para planejá-lo.',
          action: AmberButton(
            key: const ValueKey('project-new'),
            label: 'Novo projeto…',
            onTap: () => showNewProjectDialog(context),
          ),
        ),
      );
    }
    final plan = ref.watch(projectPlanProvider(ws.id));
    return ColoredBox(
      color: AppColors.background,
      child: switch (plan) {
        AsyncData(value: null)
            when ref.watch(hasExistingCodeProvider(ws.path)).value ?? false =>
          DefaultTabController(
            length: 4,
            child: Column(
              children: [
                const TabBar(
                  key: ValueKey('project-tabs'),
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(key: ValueKey('project-tab-health'), text: 'Saúde'),
                    Tab(text: 'Configuração'),
                    Tab(key: ValueKey('project-tab-memory'), text: 'Memória'),
                    Tab(key: ValueKey('project-tab-metrics'), text: 'Métricas'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ProjectHealthView(workspace: ws),
                      ProjectConfigView(
                        key: ValueKey('project-config-${ws.id}'),
                        workspace: ws,
                        intro:
                            'Este repositório já tem código: não é preciso '
                            'planejar do zero. Ajuste como o Promptorium '
                            'trabalha nele; as specs você cria na tela Specs.',
                        onPlan: () =>
                            ref.read(projectPlannerProvider.notifier).start(ws),
                      ),
                      ProjectMemoryView(workspace: ws),
                      SpecMetricsView(workspace: ws),
                    ],
                  ),
                ),
              ],
            ),
          ),
        AsyncData(value: null) => StepEmpty(
          title: 'Planejar ${ws.name}',
          text:
              'Converse com o planner sobre o projeto. Ele monta a visão, '
              'propõe a stack e o CLAUDE.md e divide o trabalho em specs e '
              'tarefas. Nada é gravado no repositório até você confirmar.',
          action: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              SmallButton(
                label: 'Novo projeto…',
                height: 34,
                onTap: () => showNewProjectDialog(context),
              ),
              AmberButton(
                key: const ValueKey('project-start'),
                label: 'Começar planejamento',
                height: 34,
                onTap: () =>
                    ref.read(projectPlannerProvider.notifier).start(ws),
              ),
            ],
          ),
        ),
        AsyncData(:final value?) => _PlanView(workspace: ws, plan: value),
        AsyncError(:final error) => StepEmpty(
          title: 'Erro ao ler o plano',
          text: '$error',
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.workspace, required this.plan});

  final Workspace workspace;
  final ProjectPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ProjectPlanData.decode(plan.data);
    final done = plan.materializedAt != null;
    var step = done ? ProjectStep.create : ProjectStep.fromName(plan.step);
    // A step whose input disappeared (e.g. regenerated) falls back.
    while (!data.reachable(step)) {
      step = ProjectStep.values[step.index - 1];
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stepper(workspace: workspace, plan: plan, data: data, current: step),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey('project-step-${step.name}'),
            child: switch (step) {
              ProjectStep.vision => VisionStep(
                workspace: workspace,
                data: data,
              ),
              ProjectStep.stack => StackStep(workspace: workspace, data: data),
              ProjectStep.roadmap => RoadmapStep(
                workspace: workspace,
                data: data,
              ),
              ProjectStep.create => CreateStep(
                workspace: workspace,
                plan: plan,
                data: data,
              ),
            },
          ),
        ),
      ],
    );
  }
}

class _Stepper extends ConsumerWidget {
  const _Stepper({
    required this.workspace,
    required this.plan,
    required this.data,
    required this.current,
  });

  final Workspace workspace;
  final ProjectPlan plan;
  final ProjectPlanData data;
  final ProjectStep current;

  String _summary(ProjectStep s) {
    switch (s) {
      case ProjectStep.vision:
        final n = data.vision.mvp.length;
        return n == 0 ? s.hint : 'MVP com $n funcionalidades';
      case ProjectStep.stack:
        final d = data.stack.decisions;
        if (d.isEmpty) return s.hint;
        final open = d.where((x) => x.isUndecided).length;
        final names = d
            .where((x) => !x.isUndecided)
            .take(2)
            .map((x) => x.choice)
            .join(' · ');
        return open == 0 ? names : '$names · $open a decidir';
      case ProjectStep.roadmap:
        final r = data.roadmap;
        return r.isReady
            ? '${r.specs.length} specs · ${r.stepCount} etapas'
            : s.hint;
      case ProjectStep.create:
        return s.hint;
    }
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Descartar o plano?', style: TextStyle(fontSize: 15)),
        content: Text(
          plan.materializedAt == null
              ? 'A conversa, a stack e o roadmap deste workspace serão '
                    'apagados. Nada no repositório muda.'
              : 'Só o rascunho do planejamento é apagado. O CLAUDE.md, as '
                    'specs e as tarefas já criadas ficam.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('project-discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(projectPlannerProvider.notifier).discard(workspace);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(
      projectPlannerProvider.select((m) => m[workspace.id]?.isBusy ?? false),
    );
    final done = plan.materializedAt != null;
    final planner = ref.read(projectPlannerProvider.notifier);
    return Container(
      width: 232,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      // Short windows: the column scrolls instead of overflowing; otherwise
      // the Spacer keeps the actions at the bottom.
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (data.vision.name.isEmpty
                                  ? 'Projeto'
                                  : data.vision.name)
                              .toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sectionTitleStyle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          workspace.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _StepItem(
                    number: 1,
                    title: 'Pasta e repositório',
                    subtitle: 'git init · commit inicial',
                    state: _StepState.done,
                  ),
                  for (final s in ProjectStep.values)
                    _StepItem(
                      key: ValueKey('project-stepper-${s.name}'),
                      number: s.index + 2,
                      title: s.label,
                      subtitle: _summary(s),
                      state: s == current
                          ? _StepState.current
                          : done || s.index < current.index
                          ? _StepState.done
                          : _StepState.todo,
                      onTap: !done && !busy && s != current && data.reachable(s)
                          ? () => planner.goTo(workspace, s)
                          : null,
                    ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    key: const ValueKey('project-config-open'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierColor: AppColors.scrim,
                      builder: (ctx) => Dialog(
                        backgroundColor: AppColors.panel,
                        child: SizedBox(
                          width: 680,
                          height: 620,
                          child: ProjectConfigView(workspace: workspace),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.tune, size: 16),
                    label: const Text(
                      'Configuração do projeto',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('project-memory-open'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierColor: AppColors.scrim,
                      builder: (ctx) => Dialog(
                        backgroundColor: AppColors.panel,
                        child: SizedBox(
                          width: 680,
                          height: 620,
                          child: ProjectMemoryView(workspace: workspace),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.psychology_outlined, size: 16),
                    label: const Text(
                      'Memória do projeto',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('project-metrics-open'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierColor: AppColors.scrim,
                      builder: (ctx) => Dialog(
                        backgroundColor: AppColors.panel,
                        child: SizedBox(
                          width: 900,
                          height: 620,
                          child: SpecMetricsView(workspace: workspace),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.insights_outlined, size: 16),
                    label: const Text(
                      'Métricas',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  if (plan.costUsd > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                      child: Text(
                        'Planner · ${formatCost(plan.costUsd)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      done
                          ? 'Projeto criado. O plano fica aqui como referência.'
                          : 'O planner só lê o repositório. Nada é gravado até '
                                'Criar projeto.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('project-discard'),
                    onPressed: busy ? null : () => _discard(context, ref),
                    child: const Text(
                      'Descartar plano',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('project-delete'),
                    onPressed: busy
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            barrierColor: AppColors.scrim,
                            builder: (_) =>
                                DeleteProjectDialog(workspace: workspace),
                          ),
                    child: const Text(
                      'Apagar projeto',
                      style: TextStyle(fontSize: 12, color: AppColors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, current, todo }

class _StepItem extends StatelessWidget {
  const _StepItem({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.state,
    this.onTap,
  });

  final int number;
  final String title;
  final String subtitle;
  final _StepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final current = state == _StepState.current;
    final Widget badge = switch (state) {
      _StepState.done => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SessionColors.runningToolBg,
          border: Border.all(color: SessionColors.runningToolBorder),
        ),
        child: AppIcon(AppIcons.check, size: 12, color: AppColors.teal),
      ),
      _StepState.current => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.amber,
        ),
        child: Text(
          '$number',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.onAmber,
          ),
        ),
      ),
      _StepState.todo => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: projectRing),
        ),
        child: Text(
          '$number',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ),
    };
    return Semantics(
      selected: current,
      button: onTap != null,
      child: Material(
        color: current ? AppColors.amberTint : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                badge,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: current
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: current ? AppColors.amber : AppColors.text,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
          ),
        ),
      ),
    );
  }
}

/// "Apagar projeto": shows what goes away and asks for the project name.
class DeleteProjectDialog extends ConsumerStatefulWidget {
  const DeleteProjectDialog({super.key, required this.workspace});

  final Workspace workspace;

  @override
  ConsumerState<DeleteProjectDialog> createState() =>
      _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends ConsumerState<DeleteProjectDialog> {
  final _name = TextEditingController();
  late final Future<DeleteSummary> _summary = ref
      .read(projectServiceProvider)
      .deleteSummary(widget.workspace);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(projectServiceProvider).deleteProject(widget.workspace);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.workspace;
    final unsafe = isUnsafeProjectPath(ws.path);
    final typed = _name.text.trim() == ws.name;
    const body = TextStyle(fontSize: 13, color: AppColors.text, height: 1.45);
    const muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Align(
      alignment: const Alignment(0, -0.5),
      child: Material(
        key: const ValueKey('delete-project-dialog'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: SessionColors.stopBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(
                  'Apagar o projeto ${ws.name}?',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.red,
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Isto vai:', style: muted),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: '• Mover a pasta '),
                          TextSpan(
                            text: ws.path,
                            style: const TextStyle(fontFamily: AppFonts.mono),
                          ),
                          const TextSpan(
                            text: ' para a lixeira (dá para restaurar de lá).',
                          ),
                        ],
                      ),
                      style: body,
                    ),
                    FutureBuilder<DeleteSummary>(
                      future: _summary,
                      builder: (context, snap) {
                        final s = snap.data;
                        return Text(
                          s == null
                              ? '• Remover do Promptorium o plano, as specs, as '
                                    'tarefas, as sessões e as conversas.'
                              : '• Remover do Promptorium o plano, '
                                    '${s.specs} specs, ${s.tasks} tarefas, '
                                    '${s.sessions} sessões e as conversas '
                                    '(sessões vivas são paradas).\n'
                                    '• Apagar ${s.worktrees} worktrees de sessão.',
                          style: body,
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Commits já enviados para um repositório remoto '
                      'continuam lá.',
                      style: muted,
                    ),
                    const SizedBox(height: 14),
                    if (unsafe)
                      Text(
                        'Por segurança, ${ws.path} não pode ser apagada pelo '
                        'app.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.red,
                        ),
                      )
                    else ...[
                      Text(
                        'Para confirmar, digite o nome do projeto: ${ws.name}',
                        style: muted,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        key: const ValueKey('delete-project-name'),
                        controller: _name,
                        enabled: !_busy,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          color: AppColors.text,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('delete-project-confirm'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: AppColors.onAmber,
                      ),
                      onPressed: !unsafe && typed && !_busy ? _delete : null,
                      child: Text(_busy ? 'Apagando…' : 'Apagar projeto'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
