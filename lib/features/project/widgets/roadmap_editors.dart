import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../project_plan.dart';
import '../project_planner.dart';

/// Hand edits of the Roadmap step: a spec (title, phase, objective,
/// requirements = its steps, acceptance, dependencies) and the "Depois"
/// ideas. Every save goes through [ProjectPlanner.editRoadmap] (normalized,
/// marked as edited).

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

/// Removes the spec at [index] (and its code from the dependencies of the
/// others).
Roadmap withoutSpec(Roadmap r, int index) {
  final code = r.specs[index].code;
  return r.copyWith(
    specs: [
      for (final (j, s) in r.specs.indexed)
        if (j != index)
          s.copyWith(
            dependsOn: [
              for (final d in s.dependsOn)
                if (d != code) d,
            ],
          ),
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
  late final Set<String> _deps = {...?_spec?.dependsOn};
  late final String _code = _spec?.code ?? widget.roadmap.nextSpecCode();
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
        code: _code,
        title: title,
        phase: _phase,
        objective: _objective.text.trim(),
        requirements: parseRequirementLines(_reqs.text),
        acceptance: _lines(_acceptance.text),
        // Keep the roadmap order of the other specs.
        dependsOn: [
          for (final o in r.specs)
            if (_deps.contains(o.code) && o.code != _code) o.code,
        ],
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
    await _planner.editRoadmap(widget.workspace, (r) => withoutSpec(r, i));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final others = [
      for (final o in widget.roadmap.specs)
        if (o.code != _code) o,
    ];
    final steps = parseRequirementLines(_reqs.text).length;
    return _EditorFrame(
      dialogKey: const ValueKey('roadmap-spec-editor'),
      title: _spec == null ? 'Nova spec' : 'Editar spec $_code',
      onSave: _save,
      onDelete: _spec == null ? null : _delete,
      deleteLabel: 'Excluir spec',
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
          'Fundação roda primeiro, uma spec por vez; o MVP só começa depois do '
          'merge dela.',
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
        const Text('Requisitos = etapas (um por linha)', style: _label),
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
          onChanged: (_) => setState(() {}),
          decoration: _field(hint: 'R1 · Cadastrar receitas com fotos'),
        ),
        const SizedBox(height: 4),
        Text(
          steps > Roadmap.maxRequirements
              ? '$steps etapas: grande demais para um PR. Divida em duas '
                    'specs (máximo ${Roadmap.maxRequirements}).'
              : 'Cada requisito vira uma etapa, executada numa sessão '
                    'própria, em ordem. Sem id (R1, R2…), um é criado.',
          key: const ValueKey('roadmap-spec-steps-hint'),
          style: steps > Roadmap.maxRequirements
              ? _hint.copyWith(color: AppColors.red)
              : _hint,
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
        const SizedBox(height: 12),
        const Text('Depende de', style: _label),
        const SizedBox(height: 6),
        if (others.isEmpty)
          const Text('Não há outras specs.', style: _hint)
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in others)
                FilterChip(
                  key: ValueKey('roadmap-spec-dep-${o.code}'),
                  label: Text(
                    '${o.code} · ${o.title.length > 32 ? '${o.title.substring(0, 32)}…' : o.title}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _deps.contains(o.code),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _deps.add(o.code);
                    } else {
                      _deps.remove(o.code);
                    }
                  }),
                ),
            ],
          ),
        if (_phase == RoadmapPhase.mvp) ...[
          const SizedBox(height: 6),
          const Text(
            'Spec do MVP sem dependências espera toda a Fundação.',
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
        'Ficam no plano sem virar specs. Para trazer uma para o roadmap, '
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
                      child: const Text('Gerar a spec com o planner'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'O planner escreve requisitos (as etapas), critérios e '
                      'liga as dependências às specs que já existem.',
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
                        'Criar spec vazia (eu escrevo os requisitos)',
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
