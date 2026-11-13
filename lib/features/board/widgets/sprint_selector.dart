import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../board_screen.dart' show boardSelectedSpecProvider;
import '../sprint_rules.dart';
import '../sprint_state.dart';
import 'sprint_dialogs.dart';

/// The sprint selector of the Quadro (SPEC-042 R2–R5): the same choice for
/// Colunas, Grafo and Foco.
class SprintSelector extends ConsumerWidget {
  const SprintSelector({
    super.key,
    required this.workspaceId,
    required this.specs,
    required this.waiting,
  });

  final int workspaceId;

  /// The specs of the board, of every sprint.
  final List<Spec> specs;
  final bool Function(Spec) waiting;

  SprintProgress _progress(SprintFilter filter) =>
      sprintProgress(specs.where(filter.matches), waiting: waiting);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sprints = ref.watch(sprintsProvider(workspaceId)).value ?? const [];
    final filter = ref.watch(boardSprintFilterProvider);
    Sprint? current;
    for (final s in sprints) {
      if (s.id == filter.sprintId) current = s;
    }
    final label = sprints.isEmpty
        ? 'Sprints'
        : current?.name ?? (filter.isNone ? 'Sem sprint' : 'Todas');
    final detail = sprints.isEmpty
        ? ''
        : current != null
        ? _progress(filter).label
        : _progress(filter).count;

    void pick(SprintFilter f) {
      // An open card would pull the Quadro back to its sprint (R9).
      ref.read(boardSelectedSpecProvider.notifier).select(null);
      ref.read(boardSprintProvider.notifier).set(f);
    }

    Widget option(
      SprintFilter f,
      String name, {
      String state = '',
      Color stateColor = AppColors.textSecondary,
      String? count,
      String note = '',
    }) {
      final p = _progress(f);
      final line = [
        if (p.running > 0) '${p.running} em execução',
        if (note.isNotEmpty) note,
      ].join(' · ');
      return MenuItemButton(
        key: ValueKey('sprint-option-${f.stored}'),
        onPressed: () => pick(f),
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(
            f == filter ? AppColors.amberTint : Colors.transparent,
          ),
        ),
        child: SizedBox(
          width: 340,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state,
                      style: TextStyle(fontSize: 12, color: stateColor),
                    ),
                    const Spacer(),
                    Text(
                      count ?? p.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (line.isNotEmpty || p.waiting > 0)
                  Row(
                    children: [
                      if (line.isNotEmpty)
                        Text(
                          line,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      if (line.isNotEmpty && p.waiting > 0)
                        const SizedBox(width: 10),
                      if (p.waiting > 0)
                        Text(
                          '${p.waiting} aguardando você',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.amber,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget action(
      String key,
      String text,
      VoidCallback onTap, {
      Color? color,
    }) => MenuItemButton(
      key: ValueKey('sprint-action-$key'),
      onPressed: onTap,
      child: Text(text, style: TextStyle(fontSize: 13, color: color)),
    );

    final closed = closedSprints(sprints);
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surfaceRaisedSolid),
      ),
      menuChildren: [
        if (sprints.isNotEmpty) ...[
          for (final s in openSprints(sprints))
            option(
              SprintFilter.sprint(s.id),
              s.name,
              state: s.state == SprintState.active ? 'Ativa' : 'Planejada',
              stateColor: s.state == SprintState.active
                  ? AppColors.teal
                  : AppColors.textSecondary,
            ),
          option(
            const SprintFilter.none(),
            'Sem sprint',
            count: _progress(const SprintFilter.none()).count,
          ),
          option(
            const SprintFilter.all(),
            'Todas',
            count: _progress(const SprintFilter.all()).count,
          ),
          if (closed.isNotEmpty) ...[
            const Divider(height: 8),
            SubmenuButton(
              key: const ValueKey('sprint-closed'),
              menuChildren: [
                for (final s in closed)
                  option(SprintFilter.sprint(s.id), s.name, state: 'Concluída'),
              ],
              child: Text(
                'Concluídas · ${closed.length}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
          const Divider(height: 8),
        ],
        action(
          'new',
          'Nova sprint',
          () => showSprintFormDialog(
            context,
            ref,
            workspaceId: workspaceId,
            sprints: sprints,
          ),
          color: AppColors.amber,
        ),
        if (sprints.isNotEmpty)
          action(
            'organize',
            'Organizar sprints',
            () => showOrganizeSprintsDialog(
              context,
              ref,
              specs: specs,
              sprints: sprints,
            ),
          ),
        if (current case final s?) ...[
          if (s.state == SprintState.planned)
            action(
              'activate',
              'Ativar ${s.name}',
              () => ref.read(sprintsRepoProvider).activate(s.id),
            ),
          if (s.state == SprintState.active)
            action(
              'complete',
              'Concluir ${s.name}',
              () => showCompleteSprintDialog(
                context,
                ref,
                sprint: s,
                specs: specs,
                sprints: sprints,
              ),
            ),
          if (s.state != SprintState.done)
            action(
              'edit',
              'Editar ${s.name}',
              () => showSprintFormDialog(
                context,
                ref,
                workspaceId: workspaceId,
                sprints: sprints,
                editing: s,
              ),
            ),
          action(
            'delete',
            'Excluir ${s.name}',
            () => confirmDeleteSprint(
              context,
              ref,
              sprint: s,
              specCount: specs.where((x) => x.sprintId == s.id).length,
            ),
            color: AppColors.red,
          ),
        ],
      ],
      builder: (context, controller, _) => Material(
        key: const ValueKey('board-sprint'),
        color: AppColors.amberTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.amber),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    detail,
                    key: const ValueKey('board-sprint-detail'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                const Icon(Icons.expand_more, size: 16, color: AppColors.amber),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
