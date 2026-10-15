import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_file.dart' show SpecRequirement;
import '../project_plan.dart';
import '../project_planner.dart';

/// Hand edits of the Roadmap step: a spec (title, phase, objective,
/// requirements, acceptance), a task (title, description, spec, requirement,
/// dependencies) and the "Depois" ideas. Every save goes through
/// [ProjectPlanner.editRoadmap] (normalized, marked as edited).

/// `R1 · texto` per line (an id is made up when missing).
List<SpecRequirement> parseRequirementLines(String text) {
  final out = <SpecRequirement>[];
  final re = RegExp(r'^(R\d+)\s*[·:.\-–—]?\s*(.*)$');
  for (final raw in text.split('\n')) {
    final line = raw.trim().replaceFirst(RegExp(r'^[-*]\s+'), '');
    if (line.isEmpty) continue;
    final m = re.firstMatch(line);
    final used = {for (final r in out) r.id};
    if (m != null && !used.contains(m.group(1))) {
      out.add((id: m.group(1)!, text: m.group(2)!.trim()));
    } else {
      var n = 1;
      while (used.contains('R$n')) {
        n++;
      }
      out.add((id: 'R$n', text: m == null ? line : m.group(2)!.trim()));
    }
  }
  return out;
}

String requirementLines(List<SpecRequirement> reqs) =>
    reqs.map((r) => '${r.id} · ${r.text}').join('\n');

List<String> _lines(String text) => [
  for (final l in text.split('\n'))
    if (l.trim().replaceFirst(RegExp(r'^[-*]\s+'), '').isNotEmpty)
      l.trim().replaceFirst(RegExp(r'^[-*]\s+'), ''),
];

/// Removes [code] from the roadmap (and from the dependencies).
Roadmap withoutTask(Roadmap r, String code) => r.copyWith(
  specs: [
    for (final s in r.specs)
      s.withTasks([
        for (final t in s.tasks)
          if (t.code != code)
            t.withDeps([
              for (final d in t.dependsOn)
                if (d != code) d,
            ]),
      ]),
  ],
);

/// Puts [task] in spec [specIndex]: replaces it in place when it already is
/// there, otherwise moves it to the end of that spec.
Roadmap withTask(Roadmap r, int specIndex, RoadmapTask task) {
  final inPlace = r.specs[specIndex].tasks.any((t) => t.code == task.code);
  return r.copyWith(
    specs: [
      for (final (i, s) in r.specs.indexed)
        s.withTasks([
          for (final t in s.tasks)
            if (t.code != task.code) t else if (inPlace) task,
          if (i == specIndex && !inPlace) task,
        ]),
    ],
  );
}

InputDecoration _field({String? hint}) => InputDecoration(
  isDense: true,
  hintText: hint,
  hintStyle: const TextStyle(color: AppColors.textMuted),
  border: const OutlineInputBorder(),
);

const _label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
const _hint = TextStyle(fontSize: 11, color: AppColors.textMuted);

/// Dialog frame: title, scrollable body, footer with an optional
/// destructive action on the left.
class _EditorFrame extends StatelessWidget {
  const _EditorFrame({
    required this.dialogKey,
    required this.title,
    required this.children,
    required this.onSave,
    this.onDelete,
    this.deleteLabel = 'Excluir',
  });

  final Key dialogKey;
  final String title;
  final List<Widget> children;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, -0.5),
    child: Material(
      key: dialogKey,
      color: AppColors.panel,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.sizeOf(context).height - 80,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  if (onDelete != null)
                    Flexible(
                      child: TextButton(
                        key: const ValueKey('roadmap-editor-delete'),
                        onPressed: onDelete,
                        child: Text(
                          deleteLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.red),
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('roadmap-editor-save'),
                    onPressed: onSave,
                    child: const Text('Salvar'),
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

// --- spec ------------------------------------------------------------------------

/// Edits spec [index] of [roadmap], or creates one in [phase] (index null).
Future<void> showSpecEditor(
  BuildContext context, {
  required Workspace workspace,
  required Roadmap roadmap,
  int? index,
  RoadmapPhase phase = RoadmapPhase.mvp,
}) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => _SpecEditor(
    workspace: workspace,
    roadmap: roadmap,
    index: index,
    phase: phase,
  ),
);

class _SpecEditor extends ConsumerStatefulWidget {
  const _SpecEditor({
    required this.workspace,
    required this.roadmap,
    required this.index,
    required this.phase,
  });

  final Workspace workspace;
  final Roadmap roadmap;
  final int? index;
  final RoadmapPhase phase;

  @override
  ConsumerState<_SpecEditor> createState() => _SpecEditorState();
}

class _SpecEditorState extends ConsumerState<_SpecEditor> {
  RoadmapSpec? get _spec =>
      widget.index == null ? null : widget.roadmap.specs[widget.index!];

  late final _title = TextEditingController(text: _spec?.title ?? '');
  late final _objective = TextEditingController(text: _spec?.objective ?? '');
  late final _reqs = TextEditingController(
    text: requirementLines(_spec?.requirements ?? const []),
  );
  late final _acceptance = TextEditingController(
    text: (_spec?.acceptance ?? const []).join('\n'),
  );
  late RoadmapPhase _phase = _spec?.phase ?? widget.phase;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _objective, _reqs, _acceptance]) {
      c.dispose();
    }
    super.dispose();
  }

  ProjectPlanner get _planner => ref.read(projectPlannerProvider.notifier);

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Informe o título da spec.');
      return;
    }
    final i = widget.index;
    await _planner.editRoadmap(widget.workspace, (r) {
      final edited = RoadmapSpec(
        title: title,
        phase: _phase,
        objective: _objective.text.trim(),
        requirements: parseRequirementLines(_reqs.text),
        acceptance: _lines(_acceptance.text),
        tasks: i == null ? const [] : r.specs[i].tasks,
      );
      return r.copyWith(
        specs: [
          for (final (j, s) in r.specs.indexed) j == i ? edited : s,
          if (i == null) edited,
        ],
      );
    });
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final i = widget.index!;
    await _planner.editRoadmap(
      widget.workspace,
      (r) => r.copyWith(
        specs: [
          for (final (j, s) in r.specs.indexed)
            if (j != i) s,
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _spec?.tasks.length ?? 0;
    return _EditorFrame(
      dialogKey: const ValueKey('roadmap-spec-editor'),
      title: _spec == null ? 'Nova spec' : 'Editar spec',
      onSave: _save,
      onDelete: _spec == null ? null : _delete,
      deleteLabel: tasks == 0
          ? 'Excluir spec'
          : 'Excluir spec e $tasks ${tasks == 1 ? 'tarefa' : 'tarefas'}',
      children: [
        const Text('Título', style: _label),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('roadmap-spec-title'),
          controller: _title,
          autofocus: _spec == null,
          style: const TextStyle(fontSize: 13, color: AppColors.text),
          decoration: _field(),
        ),
        const SizedBox(height: 12),
        const Text('Fase', style: _label),
        const SizedBox(height: 6),
        SegmentedButton<RoadmapPhase>(
          key: const ValueKey('roadmap-spec-phase'),
          showSelectedIcon: false,
          segments: [
            for (final p in RoadmapPhase.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {_phase},
          onSelectionChanged: (s) => setState(() => _phase = s.first),
        ),
        const SizedBox(height: 4),
        const Text(
          'Fundação roda primeiro, uma tarefa por vez; o MVP só começa '
          'depois do merge dela.',
          style: _hint,
        ),
        const SizedBox(height: 12),
        const Text('Objetivo', style: _label),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('roadmap-spec-objective'),
          controller: _objective,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontSize: 13, color: AppColors.text),
          decoration: _field(),
        ),
        const SizedBox(height: 12),
        const Text('Requisitos (um por linha)', style: _label),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('roadmap-spec-requirements'),
          controller: _reqs,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 12,
            color: AppColors.text,
          ),
          decoration: _field(hint: 'R1 · Cadastrar receitas com fotos'),
        ),
        const SizedBox(height: 4),
        const Text(
          'O id (R1, R2…) liga as tarefas ao requisito; sem id, um é criado.',
          style: _hint,
        ),
        const SizedBox(height: 12),
        const Text('Critérios de aceite (um por linha)', style: _label),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('roadmap-spec-acceptance'),
          controller: _acceptance,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(fontSize: 13, color: AppColors.text),
          decoration: _field(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ],
      ],
    );
  }
}

// --- task ------------------------------------------------------------------------

/// Edits task [code], or creates one in spec [specIndex] (code null).
Future<void> showTaskEditor(
  BuildContext context, {
  required Workspace workspace,
  required Roadmap roadmap,
  required int specIndex,
  String? code,
}) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => _TaskEditor(
    workspace: workspace,
    roadmap: roadmap,
    specIndex: specIndex,
    code: code,
  ),
);

class _TaskEditor extends ConsumerStatefulWidget {
  const _TaskEditor({
    required this.workspace,
    required this.roadmap,
    required this.specIndex,
    required this.code,
  });

  final Workspace workspace;
  final Roadmap roadmap;
  final int specIndex;
  final String? code;

  @override
  ConsumerState<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<_TaskEditor> {
  RoadmapTask? get _task => widget.code == null
      ? null
      : widget.roadmap.tasks.where((t) => t.code == widget.code).firstOrNull;

  late final _title = TextEditingController(text: _task?.title ?? '');
  late final _description = TextEditingController(
    text: _task?.description ?? '',
  );
  late int _spec = widget.specIndex;
  late String _requirement = _task?.requirement ?? '';
  late final Set<String> _deps = {...?_task?.dependsOn};
  late final String _code = widget.code ?? widget.roadmap.nextTaskCode();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  ProjectPlanner get _planner => ref.read(projectPlannerProvider.notifier);

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Informe o título da tarefa.');
      return;
    }
    final reqs = widget.roadmap.specs[_spec].requirements;
    final task = RoadmapTask(
      code: _code,
      title: title,
      description: _description.text.trim(),
      requirement: reqs.any((r) => r.id == _requirement) ? _requirement : '',
      dependsOn: [
        // Keep the roadmap order of the other tasks.
        for (final t in widget.roadmap.tasks)
          if (_deps.contains(t.code) && t.code != _code) t.code,
      ],
    );
    await _planner.editRoadmap(
      widget.workspace,
      (r) => withTask(r, _spec, task),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await _planner.editRoadmap(widget.workspace, (r) => withoutTask(r, _code));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.roadmap;
    final spec = r.specs[_spec];
    final others = [
      for (final t in r.tasks)
        if (t.code != _code) t,
    ];
    return _EditorFrame(
      dialogKey: const ValueKey('roadmap-task-editor'),
      title: _task == null ? 'Nova tarefa' : 'Editar tarefa $_code',
      onSave: _save,
      onDelete: _task == null ? null : _delete,
      deleteLabel: 'Excluir tarefa',
      children: [
        const Text('Título', style: _label),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('roadmap-task-title'),
          controller: _title,
          autofocus: _task == null,
          style: const TextStyle(fontSize: 13, color: AppColors.text),
          decoration: _field(hint: 'No imperativo: Criar o projeto…'),
        ),
        const SizedBox(height: 12),
        const Text('Descrição (o que fazer e como verificar)', style: _label),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('roadmap-task-description'),
          controller: _description,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(fontSize: 13, color: AppColors.text),
          decoration: _field(),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Spec', style: _label),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('roadmap-task-spec'),
                    initialValue: _spec,
                    isExpanded: true,
                    decoration: _field(),
                    items: [
                      for (final (i, s) in r.specs.indexed)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            '${s.phase.label} · ${s.title}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      if (v != null) _spec = v;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Requisito', style: _label),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: ValueKey('roadmap-task-requirement-$_spec'),
                    initialValue:
                        spec.requirements.any((q) => q.id == _requirement)
                        ? _requirement
                        : '',
                    isExpanded: true,
                    decoration: _field(),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('—', style: TextStyle(fontSize: 12)),
                      ),
                      for (final q in spec.requirements)
                        DropdownMenuItem(
                          value: q.id,
                          child: Text(
                            '${q.id} · ${q.text}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _requirement = v ?? ''),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Depende de', style: _label),
        const SizedBox(height: 6),
        if (others.isEmpty)
          const Text('Não há outras tarefas.', style: _hint)
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in others)
                FilterChip(
                  key: ValueKey('roadmap-task-dep-${t.code}'),
                  label: Text(
                    '${t.code} · ${t.title.length > 32 ? '${t.title.substring(0, 32)}…' : t.title}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _deps.contains(t.code),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _deps.add(t.code);
                    } else {
                      _deps.remove(t.code);
                    }
                  }),
                ),
            ],
          ),
        if (spec.phase == RoadmapPhase.mvp) ...[
          const SizedBox(height: 6),
          const Text(
            'Tarefa do MVP sem dependências espera toda a Fundação.',
            style: _hint,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ],
      ],
    );
  }
}

// --- ideas -----------------------------------------------------------------------

Future<void> showIdeasEditor(
  BuildContext context, {
  required Workspace workspace,
  required Roadmap roadmap,
}) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => _IdeasEditor(workspace: workspace, roadmap: roadmap),
);

class _IdeasEditor extends ConsumerStatefulWidget {
  const _IdeasEditor({required this.workspace, required this.roadmap});

  final Workspace workspace;
  final Roadmap roadmap;

  @override
  ConsumerState<_IdeasEditor> createState() => _IdeasEditorState();
}

class _IdeasEditorState extends ConsumerState<_IdeasEditor> {
  late final _text = TextEditingController(
    text: widget.roadmap.later.join('\n'),
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _EditorFrame(
    dialogKey: const ValueKey('roadmap-ideas-editor'),
    title: 'Depois (fora do MVP)',
    onSave: () async {
      await ref
          .read(projectPlannerProvider.notifier)
          .editRoadmap(
            widget.workspace,
            (r) => r.copyWith(later: _lines(_text.text)),
          );
      if (context.mounted) Navigator.of(context).pop();
    },
    children: [
      const Text('Uma ideia por linha', style: _label),
      const SizedBox(height: 6),
      TextField(
        key: const ValueKey('roadmap-ideas'),
        controller: _text,
        autofocus: true,
        minLines: 4,
        maxLines: 12,
        style: const TextStyle(fontSize: 13, color: AppColors.text),
        decoration: _field(),
      ),
      const SizedBox(height: 4),
      const Text(
        'Ficam no plano sem virar tarefas. Para trazer uma para o roadmap, '
        'clique nela.',
        style: _hint,
      ),
    ],
  );
}

/// Actions of one "Depois" idea: plan it with the planner, turn it into an
/// empty spec, or remove it.
Future<void> showIdeaDialog(
  BuildContext context, {
  required Workspace workspace,
  required String idea,
}) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => _IdeaDialog(workspace: workspace, idea: idea),
);

class _IdeaDialog extends ConsumerStatefulWidget {
  const _IdeaDialog({required this.workspace, required this.idea});

  final Workspace workspace;
  final String idea;

  @override
  ConsumerState<_IdeaDialog> createState() => _IdeaDialogState();
}

class _IdeaDialogState extends ConsumerState<_IdeaDialog> {
  RoadmapPhase _phase = RoadmapPhase.mvp;

  ProjectPlanner get _planner => ref.read(projectPlannerProvider.notifier);

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(
      projectPlannerProvider.select(
        (m) => m[widget.workspace.id]?.isBusy ?? false,
      ),
    );
    return Align(
      alignment: const Alignment(0, -0.5),
      child: Material(
        key: const ValueKey('roadmap-idea-dialog'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(
                  'Trazer a ideia para o roadmap',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.idea,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Fase da nova spec', style: _label),
                    const SizedBox(height: 6),
                    SegmentedButton<RoadmapPhase>(
                      key: const ValueKey('roadmap-idea-phase'),
                      showSelectedIcon: false,
                      segments: [
                        for (final p in RoadmapPhase.values)
                          ButtonSegment(value: p, label: Text(p.label)),
                      ],
                      selected: {_phase},
                      onSelectionChanged: (s) =>
                          setState(() => _phase = s.first),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('roadmap-idea-plan'),
                      onPressed: busy
                          ? null
                          : () {
                              _close();
                              _planner.planIdea(
                                widget.workspace,
                                widget.idea,
                                _phase,
                              );
                            },
                      child: const Text('Gerar spec e tarefas com o planner'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'O planner escreve requisitos, critérios e tarefas e '
                      'liga as dependências às tarefas que já existem.',
                      style: _hint,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      key: const ValueKey('roadmap-idea-empty'),
                      onPressed: busy
                          ? null
                          : () async {
                              await _planner.ideaToSpec(
                                widget.workspace,
                                widget.idea,
                                _phase,
                              );
                              if (mounted) _close();
                            },
                      child: const Text(
                        'Criar spec vazia (eu escrevo as tarefas)',
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    TextButton(
                      key: const ValueKey('roadmap-idea-remove'),
                      onPressed: busy
                          ? null
                          : () async {
                              await _planner.removeIdea(
                                widget.workspace,
                                widget.idea,
                              );
                              if (mounted) _close();
                            },
                      child: const Text(
                        'Remover ideia',
                        style: TextStyle(color: AppColors.red),
                      ),
                    ),
                    const Spacer(),
                    TextButton(onPressed: _close, child: const Text('Fechar')),
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

/// Small "+ …" text button of the roadmap columns.
class AddButton extends StatelessWidget {
  const AddButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SmallButton(
    label: '+ $label',
    onTap: onTap,
    height: 28,
    expand: true,
    color: AppColors.amber,
    background: Colors.transparent,
  );
}
