import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_service.dart';
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';
import '../../sessions/new_session_dialog.dart';
import '../../sessions/session_manager.dart' show slugify;
import '../../sessions/widgets/session_style.dart';
import '../../tasks/task_actions.dart';
import '../project_plan.dart';
import '../project_planner.dart';
import '../project_service.dart';
import 'project_widgets.dart';

/// Step 5 · Revisar e criar: what will be written (files, commit, tasks,
/// first session) and, once created, the summary of the project.
class CreateStep extends ConsumerStatefulWidget {
  const CreateStep({
    super.key,
    required this.workspace,
    required this.plan,
    required this.data,
  });

  final Workspace workspace;
  final ProjectPlan plan;
  final ProjectPlanData data;

  @override
  ConsumerState<CreateStep> createState() => _CreateStepState();
}

class _CreateStepState extends ConsumerState<CreateStep> {
  late final bool _claudeMdExists = ref
      .read(projectServiceProvider)
      .hasClaudeMd(widget.workspace);
  late bool _writeClaudeMd = !_claudeMdExists;
  bool _commit = true;
  bool _runFirst = true;
  bool _busy = false;
  String? _error;
  String? _commitError;

  Roadmap get _roadmap => widget.data.roadmap.normalized();

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final MaterializeOutcome out;
    try {
      out = await ref
          .read(projectServiceProvider)
          .materialize(
            widget.workspace,
            writeClaudeMd: _writeClaudeMd,
            commit: _commit,
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _commitError = out.commitError;
    });
    final task = out.firstTask;
    if (_runFirst && task != null) {
      final spec = out.specs.where((s) => s.id == task.specId).firstOrNull;
      await showNewSessionDialog(
        context,
        agent: task.agentName,
        title: taskSessionTitle(task),
        prompt: taskSessionPrompt(task, spec: spec),
        taskId: task.id,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.plan.materializedAt != null;
    final planner = ref.read(projectPlannerProvider.notifier);
    final roadmap = _roadmap;
    final branch = ref
        .watch(currentBranchProvider(widget.workspace.path))
        .value;
    final first = roadmap.firstTask;
    final hasClaudeMd = widget.data.stack.claudeMd.trim().isNotEmpty;
    final files = [
      if (hasClaudeMd && _writeClaudeMd) 'CLAUDE.md',
      for (final s in roadmap.specs)
        'specs/SPEC-…-${slugify(s.title, maxLength: 40)}.md',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StepHeader(
                title: done ? 'Projeto criado' : 'Revisar e criar',
                subtitle: done
                    ? 'Arquivos, specs e tarefas criados. Daqui em diante, o '
                          'trabalho segue em Tarefas, Sessões e Review.'
                    : 'Tudo o que será gravado. Até aqui, o planejamento não '
                          'escreveu nada no repositório.',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  children: [
                    _Section(
                      icon: AppIcons.folder,
                      title: 'Repositório',
                      trailing: 'já existe',
                      child: Text(
                        '${widget.workspace.path}${branch == null ? '' : ' · $branch'}',
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    _Section(
                      icon: AppIcons.specs,
                      title: 'Arquivos · ${files.length}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final f in files)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: f == 'CLAUDE.md' && _claudeMdExists
                                          ? 'M  '
                                          : 'A  ',
                                      style: const TextStyle(
                                        color: AppColors.teal,
                                      ),
                                    ),
                                    TextSpan(text: f),
                                  ],
                                ),
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                  fontSize: 12,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                          if (!done && hasClaudeMd)
                            _Check(
                              key: const ValueKey('project-write-claudemd'),
                              value: _writeClaudeMd,
                              label: _claudeMdExists
                                  ? 'Substituir o CLAUDE.md que já existe'
                                  : 'Gravar o CLAUDE.md',
                              onChanged: (v) =>
                                  setState(() => _writeClaudeMd = v),
                            ),
                          if (!done)
                            _Check(
                              key: const ValueKey('project-commit'),
                              value: _commit,
                              label:
                                  'Commitar em ${branch ?? 'na branch atual'} '
                                  'como “$planCommitMessage”',
                              hint:
                                  'Sem o commit, as sessões não enxergam o '
                                  'CLAUDE.md nem as specs.',
                              onChanged: (v) => setState(() => _commit = v),
                            ),
                        ],
                      ),
                    ),
                    _Section(
                      icon: AppIcons.tasks,
                      title: 'Tarefas · ${roadmap.tasks.length}',
                      child: Text(
                        'No Backlog, ligadas às specs, com '
                        '${roadmap.dependencyCount} dependências. Fundação: '
                        '${roadmap.ofPhase(RoadmapPhase.foundation).expand((s) => s.tasks).length}'
                        ' · MVP: '
                        '${roadmap.ofPhase(RoadmapPhase.mvp).expand((s) => s.tasks).length}.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (!done && first != null)
                      _Section(
                        icon: AppIcons.sessions,
                        title: 'Primeira sessão',
                        highlight: _runFirst,
                        child: _Check(
                          key: const ValueKey('project-run-first'),
                          value: _runFirst,
                          label: 'Abrir a sessão de “${first.title}” ao criar',
                          hint:
                              'Abre o diálogo de nova sessão já preenchido '
                              '(agente, modelo e permissões).',
                          onChanged: (v) => setState(() => _runFirst = v),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: NoticeBox.error(text: _error!),
                      ),
                    if (_commitError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: NoticeBox.warning(
                          text:
                              'Arquivos e tarefas criados, mas o commit '
                              'falhou: $_commitError Faça o commit pelo '
                              'terminal antes de executar as tarefas.',
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    if (!done)
                      SmallButton(
                        label: 'Voltar',
                        height: 36,
                        onTap: _busy
                            ? null
                            : () => planner.goTo(
                                widget.workspace,
                                ProjectStep.roadmap,
                              ),
                      ),
                    const Spacer(),
                    if (done) ...[
                      SmallButton(
                        key: const ValueKey('project-go-specs'),
                        label: 'Ver specs',
                        height: 36,
                        onTap: () => ref
                            .read(navigationProvider.notifier)
                            .go(AppSection.specs),
                      ),
                      const SizedBox(width: 8),
                      AmberButton(
                        key: const ValueKey('project-go-tasks'),
                        label: 'Ver tarefas',
                        height: 36,
                        onTap: () => ref
                            .read(navigationProvider.notifier)
                            .go(AppSection.tasks),
                      ),
                    ] else ...[
                      Flexible(
                        child: Text(
                          '${files.length} arquivos · ${roadmap.tasks.length} '
                          'tarefas${_runFirst && first != null ? ' · 1 sessão' : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      AmberButton(
                        key: const ValueKey('project-create'),
                        label: _busy ? 'Criando…' : 'Criar projeto',
                        height: 36,
                        onTap: _busy ? null : _create,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        SidePanel(
          title: done ? 'Feito' : 'O que acontece',
          width: 320,
          child: _Steps(
            done: done,
            writeClaudeMd: hasClaudeMd && _writeClaudeMd,
            commit: _commit,
            specs: roadmap.specs.length,
            tasks: roadmap.tasks.length,
            first: _runFirst ? first : null,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.highlight = false,
  });

  final AppIconData icon;
  final String title;
  final String? trailing;
  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    // Material (not a colored box): the checkboxes paint their ink on it.
    child: Material(
      color: AppColors.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: highlight ? SessionColors.approvalBorder : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcon(icon, size: 16, color: AppColors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: const TextStyle(fontSize: 11, color: AppColors.teal),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(padding: const EdgeInsets.only(left: 24), child: child),
          ],
        ),
      ),
    ),
  );
}

class _Check extends StatelessWidget {
  const _Check({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.hint,
  });

  final bool value;
  final String label;
  final String? hint;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    value: value,
    onChanged: (v) => onChanged(v ?? false),
    dense: true,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(label, style: const TextStyle(fontSize: 13)),
    subtitle: hint == null
        ? null
        : Text(
            hint!,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
  );
}

class _Steps extends StatelessWidget {
  const _Steps({
    required this.done,
    required this.writeClaudeMd,
    required this.commit,
    required this.specs,
    required this.tasks,
    required this.first,
  });

  final bool done;
  final bool writeClaudeMd;
  final bool commit;
  final int specs;
  final int tasks;
  final RoadmapTask? first;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, String, bool)>[
      if (writeClaudeMd) ('Gravar o CLAUDE.md', 'na raiz do repositório', true),
      ('Gravar $specs specs', 'em specs/, já aprovadas', true),
      if (commit) ('Commit “$planCommitMessage”', 'na branch atual', true),
      (
        'Criar $tasks tarefas no Backlog',
        'com dependências e requisitos',
        true,
      ),
      if (first != null)
        ('Abrir a sessão de ${first!.code}', first!.title, true),
      (
        'Você revisa e faz merge',
        'na tela Review; isso libera as próximas tarefas',
        false,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (final (i, (title, sub, auto)) in steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done && auto
                        ? SessionColors.runningToolBg
                        : Colors.transparent,
                    border: Border.all(
                      color: done && auto
                          ? SessionColors.runningToolBorder
                          : projectRing,
                    ),
                  ),
                  child: done && auto
                      ? AppIcon(AppIcons.check, size: 12, color: AppColors.teal)
                      : Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          color: done && !auto
                              ? AppColors.amber
                              : AppColors.text,
                        ),
                      ),
                      Text(
                        sub,
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
      ],
    );
  }
}
