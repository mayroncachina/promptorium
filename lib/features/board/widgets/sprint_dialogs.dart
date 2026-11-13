import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_file.dart' show foldText;
import '../board_rules.dart';
import '../board_screen.dart' show boardSelectedSpecProvider;
import '../sprint_rules.dart';
import '../sprint_state.dart';

/// "Nova sprint" and editing (SPEC-042 R4). The new sprint opens on the
/// Quadro.
Future<void> showSprintFormDialog(
  BuildContext context,
  WidgetRef ref, {
  required int workspaceId,
  required List<Sprint> sprints,
  Sprint? editing,
}) async {
  final name = TextEditingController(
    text: editing?.name ?? nextSprintName(sprints),
  );
  final goal = TextEditingController(text: editing?.goal ?? '');
  final saved = await showAppDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('sprint-form'),
      backgroundColor: AppColors.panel,
      title: Text(
        editing == null ? 'Nova sprint' : 'Editar ${editing.name}',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (editing == null && sprints.isEmpty) ...[
              const Text(
                'A primeira sprint já fica ativa. Depois, use Organizar '
                'sprints para escolher as specs dela.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const ValueKey('sprint-name'),
              controller: name,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Nome'),
              onSubmitted: (_) => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('sprint-goal'),
              controller: goal,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Objetivo (opcional)',
                hintText: 'O que esta sprint precisa entregar',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        AmberButton(
          key: const ValueKey('sprint-save'),
          label: editing == null ? 'Criar sprint' : 'Salvar',
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  final text = name.text.trim();
  final objective = goal.text.trim().isEmpty ? null : goal.text.trim();
  name.dispose();
  goal.dispose();
  if (saved != true || text.isEmpty) return;
  final repo = ref.read(sprintsRepoProvider);
  if (editing != null) {
    await repo.rename(editing.id, name: text, goal: objective);
    return;
  }
  final sprint = await repo.create(
    workspaceId: workspaceId,
    name: text,
    goal: objective,
  );
  await ref
      .read(boardSprintProvider.notifier)
      .set(SprintFilter.sprint(sprint.id));
}

/// Asks before deleting; the specs stay, in "Sem sprint" (R4).
Future<void> confirmDeleteSprint(
  BuildContext context,
  WidgetRef ref, {
  required Sprint sprint,
  required int specCount,
}) async {
  final ok = await showAppDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('sprint-delete'),
      backgroundColor: AppColors.panel,
      title: Text(
        'Excluir ${sprint.name}?',
        style: const TextStyle(fontSize: 16),
      ),
      content: Text(
        specCount == 0
            ? 'Nenhuma spec está nesta sprint.'
            : specCount == 1
            ? '1 spec vai para Sem sprint. Nenhuma spec é apagada.'
            : '$specCount specs vão para Sem sprint. Nenhuma spec é apagada.',
        style: const TextStyle(fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          key: const ValueKey('sprint-delete-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Excluir sprint',
            style: TextStyle(color: AppColors.red),
          ),
        ),
      ],
    ),
  );
  if (ok == true) await ref.read(sprintsRepoProvider).delete(sprint.id);
}

/// Moves [specs] to [target] (null = "Sem sprint") and tells it, with
/// "Desfazer" (R5) and the warning of a dependency left behind (R12).
Future<void> moveSpecsToSprint(
  BuildContext context,
  WidgetRef ref, {
  required List<Spec> specs,
  required Sprint? target,
  required List<Sprint> sprints,
  required List<Spec> all,
}) async {
  if (specs.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repo = ref.read(sprintsRepoProvider);
  final previous = {for (final s in specs) s.id: s.sprintId};
  final warnings = moveWarnings(specs, target, specsByCode(all), sprints);
  // A card left open would pull the Quadro after the spec (R9).
  final selected = ref.read(boardSelectedSpecProvider);
  if (previous.containsKey(selected)) {
    ref.read(boardSelectedSpecProvider.notifier).select(null);
  }
  await repo.moveSpecs(previous.keys, target?.id);
  final where = target?.name ?? 'Sem sprint';
  final moved = specs.length == 1
      ? '${specs.single.code} foi para ${target == null ? '' : 'a '}$where'
      : '${specs.length} specs foram para ${target == null ? '' : 'a '}$where';
  messenger?.showAppToast(
    SnackBar(
      key: const ValueKey('sprint-moved'),
      content: Text([moved, ...warnings].join('\n')),
      action: SnackBarAction(
        label: 'Desfazer',
        onPressed: () async {
          for (final e in previous.entries) {
            await repo.moveSpecs([e.key], e.value);
          }
        },
      ),
    ),
  );
}

/// "Concluir sprint" (R10): what was not done goes to the sprint chosen, with
/// the next planned one suggested; activating it is a choice.
Future<void> showCompleteSprintDialog(
  BuildContext context,
  WidgetRef ref, {
  required Sprint sprint,
  required List<Spec> specs,
  required List<Sprint> sprints,
}) => showAppDialog<void>(
  context: context,
  builder: (_) =>
      _CompleteDialog(sprint: sprint, specs: specs, sprints: sprints),
);

class _CompleteDialog extends ConsumerStatefulWidget {
  const _CompleteDialog({
    required this.sprint,
    required this.specs,
    required this.sprints,
  });

  final Sprint sprint;
  final List<Spec> specs;
  final List<Sprint> sprints;

  @override
  ConsumerState<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends ConsumerState<_CompleteDialog> {
  late final Sprint? _next = nextPlannedSprint(widget.sprint, widget.sprints);
  late int? _target = _next?.id;
  bool _activate = false;

  @override
  Widget build(BuildContext context) {
    final inSprint = [
      for (final s in widget.specs)
        if (s.sprintId == widget.sprint.id) s,
    ];
    final undone = [
      for (final s in inSprint)
        if (s.stage != SpecStage.done) s,
    ];
    final done = inSprint.length - undone.length;
    final running = undone.where((s) => s.stage == SpecStage.running);
    final next = _next;
    return AlertDialog(
      key: const ValueKey('sprint-complete'),
      backgroundColor: AppColors.panel,
      title: Text(
        'Concluir ${widget.sprint.name}',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Text(
                '${done == 1 ? '1 spec feita fica' : '$done specs feitas ficam'} '
                'nesta sprint. ${undone.isEmpty
                    ? 'Nenhuma ficou por fazer.'
                    : undone.length == 1
                    ? '1 ainda não foi feita.'
                    : '${undone.length} ainda não foram feitas.'}',
                style: const TextStyle(fontSize: 13),
              ),
              for (final s in undone)
                Row(
                  children: [
                    Text(
                      s.code,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      specStageLabel(s.stage),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              if (undone.isNotEmpty) ...[
                Text(
                  undone.length == 1
                      ? 'Mover a spec para'
                      : 'Mover as ${undone.length} specs para',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                RadioGroup<int?>(
                  groupValue: _target,
                  onChanged: (v) => setState(() => _target = v),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in openSprints(widget.sprints))
                        if (s.id != widget.sprint.id)
                          RadioListTile<int?>(
                            key: ValueKey('sprint-complete-to-${s.id}'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: s.id,
                            title: Text(
                              s.id == next?.id
                                  ? '${s.name} · próxima da lista'
                                  : s.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      const RadioListTile<int?>(
                        key: ValueKey('sprint-complete-to-none'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: null,
                        title: Text(
                          'Sem sprint',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              for (final s in running)
                Text(
                  '${s.code} continua em execução depois de mudar de sprint.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              if (next != null)
                CheckboxListTile(
                  key: const ValueKey('sprint-complete-activate'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _activate,
                  onChanged: (v) => setState(() => _activate = v ?? false),
                  title: Text(
                    'Ativar a ${next.name} ao concluir',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        AmberButton(
          key: const ValueKey('sprint-complete-confirm'),
          label: 'Concluir sprint',
          onTap: () async {
            final navigator = Navigator.of(context);
            await ref
                .read(sprintsRepoProvider)
                .complete(
                  widget.sprint.id,
                  moveTo: _target,
                  activate: _activate ? next?.id : null,
                );
            // The Quadro goes where the work went.
            final goTo = _activate ? next?.id : _target;
            await ref
                .read(boardSprintProvider.notifier)
                .set(
                  goTo == null
                      ? const SprintFilter.all()
                      : SprintFilter.sprint(goTo),
                );
            navigator.pop();
          },
        ),
      ],
    );
  }
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// Disabled inside the field, so that `/` reaches it.
class _FocusSearchAction extends Action<_FocusSearchIntent> {
  _FocusSearchAction(this.field);

  final FocusNode field;

  @override
  bool isEnabled(_FocusSearchIntent intent) => !field.hasFocus;

  @override
  Object? invoke(_FocusSearchIntent intent) {
    field.requestFocus();
    return null;
  }
}

/// "Organizar sprints" (R5): distributes many specs at once.
Future<void> showOrganizeSprintsDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<Spec> specs,
  required List<Sprint> sprints,
}) => showAppDialog<void>(
  context: context,
  builder: (_) => _OrganizeDialog(specs: specs, sprints: sprints),
);

class _OrganizeDialog extends ConsumerStatefulWidget {
  const _OrganizeDialog({required this.specs, required this.sprints});

  final List<Spec> specs;
  final List<Sprint> sprints;

  @override
  ConsumerState<_OrganizeDialog> createState() => _OrganizeDialogState();
}

class _OrganizeDialogState extends ConsumerState<_OrganizeDialog> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _selected = <int>{};
  SprintFilter _source = const SprintFilter.none();
  late int? _target = openSprints(widget.sprints).firstOrNull?.id;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _name(SprintFilter f) => f.isAll
      ? 'Todas'
      : f.isNone
      ? 'Sem sprint'
      : widget.sprints.firstWhere((s) => s.id == f.sprintId).name;

  List<Spec> get _visible {
    final query = foldText(_search.text.trim());
    return [
      for (final s in widget.specs)
        if (_source.matches(s) &&
            (query.isEmpty || foldText('${s.code} ${s.title}').contains(query)))
          s,
    ];
  }

  Sprint? get _targetSprint {
    for (final s in widget.sprints) {
      if (s.id == _target) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final chosen = [
      for (final s in widget.specs)
        if (_selected.contains(s.id)) s,
    ];
    final warnings = moveWarnings(
      chosen,
      _targetSprint,
      specsByCode(widget.specs),
      widget.sprints,
    );
    final open = openSprints(widget.sprints);
    return Shortcuts(
      shortcuts: const {
        CharacterActivator('/'): _FocusSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _FocusSearchIntent(),
      },
      child: Actions(
        actions: {_FocusSearchIntent: _FocusSearchAction(_searchFocus)},
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            key: const ValueKey('sprint-organize'),
            backgroundColor: AppColors.panel,
            title: const Text(
              'Organizar sprints',
              style: TextStyle(fontSize: 16),
            ),
            content: SizedBox(
              width: 680,
              height: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selecione as specs e escolha para onde elas vão.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('sprint-organize-search'),
                          controller: _search,
                          focusNode: _searchFocus,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Buscar por número ou título',
                            suffixText: '/',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      PopupMenuButton<SprintFilter>(
                        key: const ValueKey('sprint-organize-source'),
                        tooltip: 'Mostrar',
                        color: AppColors.panelSolid,
                        onSelected: (f) => setState(() => _source = f),
                        itemBuilder: (_) => [
                          for (final f in [
                            const SprintFilter.none(),
                            for (final s in widget.sprints)
                              SprintFilter.sprint(s.id),
                            const SprintFilter.all(),
                          ])
                            PopupMenuItem(
                              value: f,
                              child: Text(
                                _name(f),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            'Mostrando: ${_name(_source)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhuma spec para mostrar.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final s in visible)
                                CheckboxListTile(
                                  key: ValueKey('sprint-organize-${s.code}'),
                                  dense: true,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  value: _selected.contains(s.id),
                                  onChanged: (on) => setState(
                                    () => on == true
                                        ? _selected.add(s.id)
                                        : _selected.remove(s.id),
                                  ),
                                  title: Text(
                                    '${s.code}  ${s.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  secondary: Text(
                                    specStageLabel(s.stage),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  for (final w in warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '$w. Dá para mover assim mesmo.',
                        key: const ValueKey('sprint-organize-warning'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.amber,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              Text(
                chosen.length == 1
                    ? '1 selecionada'
                    : '${chosen.length} selecionadas',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<int>(
                key: const ValueKey('sprint-organize-target'),
                tooltip: 'Mover para',
                color: AppColors.panelSolid,
                onSelected: (id) =>
                    setState(() => _target = id < 0 ? null : id),
                itemBuilder: (_) => [
                  for (final s in open)
                    PopupMenuItem(
                      value: s.id,
                      child: Text(s.name, style: const TextStyle(fontSize: 12)),
                    ),
                  const PopupMenuItem(
                    value: -1,
                    child: Text('Sem sprint', style: TextStyle(fontSize: 12)),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    'Mover para: ${_targetSprint?.name ?? 'Sem sprint'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              AmberButton(
                key: const ValueKey('sprint-organize-move'),
                label: chosen.length == 1
                    ? 'Mover 1 spec'
                    : 'Mover ${chosen.length} specs',
                onTap: chosen.isEmpty
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        await moveSpecsToSprint(
                          context,
                          ref,
                          specs: chosen,
                          target: _targetSprint,
                          sprints: widget.sprints,
                          all: widget.specs,
                        );
                        navigator.pop();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
