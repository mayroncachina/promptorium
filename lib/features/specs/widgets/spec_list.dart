import 'package:flutter/material.dart';

import '../../../data/db/app_database.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_pressable.dart';
import '../../board/board_rules.dart';
import '../../sessions/widgets/session_style.dart';
import '../spec_file.dart';

/// Status colors of the mockup (Aprovada teal, Em revisão amber, …).
Color specStatusColor(SpecStatus s) => switch (s) {
  SpecStatus.approved => AppColors.teal,
  SpecStatus.review => AppColors.amber,
  SpecStatus.draft => AppColors.textSecondary,
  SpecStatus.idea => AppColors.textMuted,
  SpecStatus.done => AppColors.blue,
  SpecStatus.archived => AppColors.textMuted,
};

/// Label and color of [spec] in the list: "Planejada" in yellow while it
/// has a plan and is not approved (SPEC-062 R2), else its status.
({String label, Color color, bool planned}) specListStatus(Spec spec) =>
    specIsPlanned(spec.status, hasPlan: spec.hasPlan)
    ? (label: plannedLabel, color: AppColors.yellow, planned: true)
    : (
        label: specStatusLabel(spec.status),
        color: specStatusColor(spec.status),
        planned: false,
      );

/// "4 etapas · 3 concluídas" / "sem requisitos".
String specStepsMeta(Spec spec, List<SpecStep> rows) {
  final steps = stepsOf(spec, rows);
  if (steps.isEmpty) return 'sem requisitos';
  final (done, total) = progressOf(steps);
  final running = steps.where((s) => s.status == StepStatus.running).length;
  final head = '$total ${total == 1 ? 'etapa' : 'etapas'}';
  if (running > 0) return '$head · $running em execução';
  return '$head · $done ${done == 1 ? 'concluída' : 'concluídas'}';
}

/// Left column of the Specs screen.
class SpecList extends StatelessWidget {
  const SpecList({
    super.key,
    required this.specs,
    required this.selectedId,
    required this.stepRows,
    required this.onSelect,
    this.archived = 0,
    this.folder = 'specs',
    this.showArchived = false,
    this.onToggleArchived,
  });

  /// Archived specs of the workspace and whether they are listed.
  final String folder;
  final int archived;
  final bool showArchived;
  final VoidCallback? onToggleArchived;

  final List<Spec> specs;
  final int? selectedId;
  final List<SpecStep> stepRows;
  final ValueChanged<Spec> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                const Expanded(child: Text('SPECS', style: sectionTitleStyle)),
                if (archived > 0 || showArchived)
                  TextButton(
                    key: const ValueKey('specs-archived-toggle'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: onToggleArchived,
                    child: Text(
                      showArchived
                          ? 'Ocultar arquivadas'
                          : 'Arquivadas ($archived)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: specs.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Nenhuma spec em $folder/. Coloque arquivos nesta pasta ou use "Nova spec".',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: specs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (_, i) {
                      final s = specs[i];
                      final active = s.id == selectedId;
                      return AppPressable(
                        borderRadius: BorderRadius.circular(8),
                        hoverTint: AppPressable.tint,
                        child: Material(
                          color: active
                              ? SessionColors.selectedBg
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: active
                                  ? SessionColors.selectedBorder
                                  : Colors.transparent,
                            ),
                          ),
                          child: InkWell(
                            key: ValueKey('spec-item-${s.code}'),
                            borderRadius: BorderRadius.circular(8),
                            hoverColor: Colors.transparent,
                            onTap: () => onSelect(s),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          s.code,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: AppFonts.mono,
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Spacer(),
                                      // The status is short: it keeps its
                                      // width, the code gives way.
                                      _StatusText(
                                        specListStatus(s),
                                        key: ValueKey(
                                          'spec-item-status-${s.code}',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    s.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    specStepsMeta(s, stepRows),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The status of an item; "Planejada" has a dot before it, so it does not
/// rely on the color alone (SPEC-062 R2).
class _StatusText extends StatelessWidget {
  const _StatusText(this.status, {super.key});

  final ({String label, Color color, bool planned}) status;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (status.planned) ...[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: status.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
      ],
      Text(
        status.label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(fontSize: 11, color: status.color),
      ),
    ],
  );
}
