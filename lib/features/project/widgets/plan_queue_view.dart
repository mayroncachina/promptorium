import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/widgets/spec_action_banner.dart' show ActionSpinner;
import '../project_service.dart' show planCommitMessage;
import '../spec_auto_planner.dart';

/// Title of the "Projeto criado" step with the queue (SPEC-037 R8, R9).
String planQueueTitle(AutoPlanQueue q) => q.phase == AutoPlanPhase.stopped
    ? 'Fila parada'
    : q.withPending
    ? 'Concluído com pendências'
    : 'Projeto criado';

String planQueueSubtitle(AutoPlanQueue q) => q.running
    ? 'Arquivos e specs gravados. O agente está refinando e planejando cada '
          'spec.'
    : q.phase == AutoPlanPhase.stopped
    ? 'Os planos prontos ficaram gravados. Nas specs sem plano, retome a fila '
          'ou use Planejar.'
    : q.hasFailures
    ? 'A spec com falha ficou sem plano, e as que dependem dela foram '
          'planejadas sem ele. Tente de novo na linha da spec.'
    : q.withPending
    ? 'Algumas specs foram planejadas sem o plano de uma dependência.'
    : 'Specs refinadas e planejadas. Daqui em diante, o trabalho segue no '
          'Quadro, em Sessões e em Review.';

String planQueuePanelTitle(AutoPlanQueue q) => q.running
    ? 'Em andamento'
    : q.phase == AutoPlanPhase.stopped
    ? 'Fila parada'
    : q.withPending
    ? 'Com pendências'
    : 'Feito';

/// "Planejando 3 de 7 · SPEC-003" and, at the end, how many were planned.
String planQueueHeadline(AutoPlanQueue q) {
  final total = q.items.length;
  if (q.running) {
    final c = q.current;
    if (q.stopping) return 'Parando a fila…';
    return c == null
        ? 'Gravando os planos…'
        : 'Planejando ${q.position} · ${c.code}';
  }
  final planned = '${q.plannedCount} de $total planejadas';
  return q.phase == AutoPlanPhase.stopped ? '$planned · fila parada' : planned;
}

/// A line of the steps panel.
enum PlanStepState { pending, running, done, alert }

typedef PlanStepRow = ({String title, PlanStepState state});

String _writeTitle(bool claudeMd, int specs) =>
    claudeMd ? 'Grava o CLAUDE.md e $specs specs' : 'Grava $specs specs';

/// The steps before "Criar projeto", none of them done.
List<PlanStepRow> planQueuePreview({
  required int specs,
  required bool writeClaudeMd,
  required bool commit,
  required bool firstRun,
}) => [
  (title: _writeTitle(writeClaudeMd, specs), state: PlanStepState.pending),
  if (commit)
    (title: 'Commit “$planCommitMessage”', state: PlanStepState.pending),
  (title: 'Refina e planeja as $specs specs', state: PlanStepState.pending),
  if (commit)
    (title: 'Commit “$specPlansCommitMessage”', state: PlanStepState.pending),
  if (firstRun) (title: 'Abre a primeira sessão', state: PlanStepState.pending),
];

/// The steps with the queue: what was not done has no check mark (R8), and
/// a queue with failures is an alert, never done (R9).
List<PlanStepRow> planQueueRows(AutoPlanQueue q) {
  final total = q.items.length;
  final planned = q.plannedCount;
  final complete = planned == total && !q.withPending;
  final PlanStepRow refine = q.running
      ? (
          title: 'Refina e planeja as $total specs',
          state: PlanStepState.running,
        )
      : complete
      ? (title: 'Refina e planeja as $total specs', state: PlanStepState.done)
      : (
          title: 'Refina e planeja: $planned de $total',
          state: q.phase == AutoPlanPhase.finished
              ? PlanStepState.alert
              : PlanStepState.pending,
        );
  return [
    (title: _writeTitle(q.wroteClaudeMd, total), state: PlanStepState.done),
    if (q.commit)
      (
        title: 'Commit “$planCommitMessage”',
        state: q.initialCommitError == null
            ? PlanStepState.done
            : PlanStepState.alert,
      ),
    refine,
    if (q.commit)
      (
        title: 'Commit “$specPlansCommitMessage”',
        state: q.commitError != null
            ? PlanStepState.alert
            : q.committed
            ? PlanStepState.done
            : PlanStepState.pending,
      ),
    if (q.wantsFirstRun)
      (
        title: 'Abre a primeira sessão',
        state: q.sessionOpened ? PlanStepState.done : PlanStepState.pending,
      ),
  ];
}

Color _segmentColor(AutoPlanStatus s) => switch (s) {
  AutoPlanStatus.ready => AppColors.teal,
  AutoPlanStatus.planning || AutoPlanStatus.partial => AppColors.amber,
  AutoPlanStatus.failed => AppColors.red,
  AutoPlanStatus.queued || AutoPlanStatus.unplanned => AppColors.border,
};

Color _statusColor(AutoPlanStatus s) => switch (s) {
  AutoPlanStatus.ready => AppColors.teal,
  AutoPlanStatus.planning || AutoPlanStatus.partial => AppColors.amber,
  AutoPlanStatus.failed => AppColors.red,
  AutoPlanStatus.queued || AutoPlanStatus.unplanned => AppColors.textSecondary,
};

/// Headline and bar of the queue: one segment per spec.
class PlanQueueProgress extends StatelessWidget {
  const PlanQueueProgress({super.key, required this.queue});

  final AutoPlanQueue queue;

  @override
  Widget build(BuildContext context) {
    final n = queue.questions;
    final note = queue.running
        ? 'Pode sair desta tela: a fila continua'
        : n == 0
        ? null
        : n == 1
        ? '1 pergunta em aberto nas specs'
        : '$n perguntas em aberto nas specs';
    return Container(
      key: const ValueKey('project-queue-progress'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: queue.running
              ? SessionColors.approvalBorder
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The note goes to the next line when both do not fit (R11).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                planQueueHeadline(queue),
                key: const ValueKey('project-queue-headline'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              if (note != null)
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, item) in queue.items.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: _segmentColor(item.status),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One line per spec (R8, R9, R12).
class PlanQueueList extends StatelessWidget {
  const PlanQueueList({super.key, required this.queue, required this.onRetry});

  final AutoPlanQueue queue;
  final ValueChanged<AutoPlanItem> onRetry;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in queue.items.indexed) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.border),
          _Line(
            item: item,
            onRetry: queue.running ? null : () => onRetry(item),
          ),
        ],
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.item, required this.onRetry});

  final AutoPlanItem item;
  final VoidCallback? onRetry;

  String get _detail => switch (item.status) {
    AutoPlanStatus.failed => item.error ?? 'Falhou.',
    AutoPlanStatus.partial =>
      'Planejada sem o plano de ${item.missingPlans.join(', ')}',
    _ =>
      item.dependsOn.isEmpty
          ? 'Sem dependências'
          : 'Depende de ${item.dependsOn.join(', ')}',
  };

  Widget get _icon => switch (item.status) {
    AutoPlanStatus.planning => const ActionSpinner(),
    AutoPlanStatus.ready => AppIcon(
      AppIcons.check,
      size: 15,
      color: AppColors.teal,
    ),
    AutoPlanStatus.partial => AppIcon(
      AppIcons.warning,
      size: 15,
      color: AppColors.amber,
    ),
    AutoPlanStatus.failed => AppIcon(
      AppIcons.close,
      size: 15,
      color: AppColors.red,
    ),
    AutoPlanStatus.queued || AutoPlanStatus.unplanned => const _Ring(),
  };

  /// Chips, status and "Tentar de novo".
  List<Widget> get _trailing {
    final added = item.addedRequirements;
    final questions = item.questions;
    return [
      if (added > 0)
        _Chip(
          added == 1 ? '+1 requisito' : '+$added requisitos',
          color: AppColors.textSecondary,
          border: AppColors.border,
        ),
      if (questions > 0)
        _Chip(
          questions == 1 ? '1 pergunta' : '$questions perguntas',
          color: AppColors.amber,
          border: SessionColors.approvalBorder,
        ),
      Text(
        item.status.label,
        key: ValueKey('project-queue-status-${item.code}'),
        style: TextStyle(fontSize: 12, color: _statusColor(item.status)),
      ),
      if (item.status == AutoPlanStatus.failed)
        SmallButton(
          key: ValueKey('project-queue-retry-${item.code}'),
          label: 'Tentar de novo',
          onTap: onRetry,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('project-queue-${item.code}'),
    color: item.status == AutoPlanStatus.planning ? AppColors.amberTint : null,
    padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // At 1100×700 the Projeto rail leaves little room (R11): the end of
        // the line goes under the texts instead of cutting them.
        final wide = constraints.maxWidth >= _wideLine;
        return Row(
          children: [
            SizedBox(width: 16, child: Center(child: _icon)),
            const SizedBox(width: 12),
            SizedBox(
              width: 76,
              child: Text(
                item.code,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    _detail,
                    key: ValueKey('project-queue-detail-${item.code}'),
                    style: TextStyle(
                      fontSize: 11,
                      color: item.status == AutoPlanStatus.failed
                          ? AppColors.red
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (!wide) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: _trailing,
                    ),
                  ],
                ],
              ),
            ),
            if (wide)
              for (final w in _trailing) ...[const SizedBox(width: 8), w],
          ],
        );
      },
    ),
  );
}

/// Room a line needs to keep chips, status and button beside the texts.
const _wideLine = 720.0;

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.color, required this.border});

  final String text;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: border),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );
}

/// A step not done: an empty circle.
class _Ring extends StatelessWidget {
  const _Ring();

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.textMuted, width: 1.5),
    ),
  );
}

/// Steps panel of the queue.
class PlanQueueSteps extends StatelessWidget {
  const PlanQueueSteps({super.key, required this.rows});

  final List<PlanStepRow> rows;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    children: [
      for (final (i, row) in rows.indexed)
        Padding(
          key: ValueKey('project-queue-step-$i-${row.state.name}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Center(
                  child: switch (row.state) {
                    PlanStepState.pending => const _Ring(),
                    PlanStepState.running => const ActionSpinner(),
                    PlanStepState.done => AppIcon(
                      AppIcons.check,
                      size: 15,
                      color: AppColors.teal,
                    ),
                    PlanStepState.alert => AppIcon(
                      AppIcons.warning,
                      size: 15,
                      color: AppColors.amber,
                    ),
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  row.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: row.state == PlanStepState.running
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: row.state == PlanStepState.pending
                        ? AppColors.textSecondary
                        : AppColors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
