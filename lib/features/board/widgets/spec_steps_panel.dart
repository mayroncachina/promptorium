import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_service.dart' show selectedSpecProvider;
import '../board_rules.dart';
import '../spec_runner.dart';
import 'gate_report_view.dart';
import 'subagent_status.dart';
import '../board_screen.dart';
import 'run_spec_dialog.dart';

final _specProvider = StreamProvider.family<Spec?, int>(
  (ref, id) => ref.watch(specsRepoProvider).watchById(id),
);

final _stepRowsProvider = StreamProvider.family<List<SpecStep>, int>(
  (ref, id) => ref.watch(specStepsRepoProvider).watchBySpec(id),
);

Color stepStatusColor(StepStatus s) => switch (s) {
  StepStatus.pending => AppColors.textMuted,
  StepStatus.running => AppColors.teal,
  StepStatus.done => AppColors.blue,
  StepStatus.needsInput => AppColors.amber,
  StepStatus.verifying => AppColors.lilac,
};

/// Card details: the steps with their state and session.
Future<void> showSpecDetailDialog(BuildContext context, int specId) =>
    showDialog<void>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (context) => Align(
        alignment: const Alignment(0, -0.3),
        child: Material(
          key: const ValueKey('spec-detail-dialog'),
          color: AppColors.panel,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SizedBox(
            width: 620,
            height: 560,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SpecStepsPanel(specId: specId, inDialog: true),
            ),
          ),
        ),
      ),
    );

/// Steps of a spec (Quadro details and the Specs screen): state, session of
/// each step, auto-advance and the run action.
/// Step selected in the Specs screen (its traceability panel opens; UX v2,
/// U5), with its spec: "R2" of one spec is not "R2" of another. Null = none.
class SelectedStep extends Notifier<({int specId, String step})?> {
  @override
  ({int specId, String step})? build() => null;

  void select(int specId, String step) => state = (specId: specId, step: step);

  void clear() => state = null;
}

final selectedStepProvider =
    NotifierProvider<SelectedStep, ({int specId, String step})?>(
      SelectedStep.new,
    );

/// "Voltar ao início da etapa" / "Refazer etapa": lists what will be
/// discarded and asks first.
Future<void> rewindStepAction(
  BuildContext context,
  WidgetRef ref,
  Spec spec,
  StepView step, {
  required bool redo,
}) async {
  final runner = ref.read(specRunnerProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final RewindPreview preview;
  try {
    preview = await runner.rewindPreview(spec.id, step.id);
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
    return;
  }
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('rewind-dialog'),
      backgroundColor: AppColors.panel,
      title: Text(
        redo ? 'Refazer ${step.id}?' : 'Voltar ao início de ${step.id}?',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A sessão da spec é encerrada e o worktree volta ao ponto '
                'em que ${step.id} começou. Etapas que voltam a pendente: '
                '${preview.steps.join(', ')}.'
                '${redo ? ' Depois, uma sessão nova refaz a etapa com o '
                          'resumo da tentativa anterior.' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                preview.commits.isEmpty
                    ? 'Nenhum commit será descartado.'
                    : 'Commits descartados:',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final c in preview.commits)
                Text(
                  '• $c',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: AppFonts.mono,
                  ),
                ),
              if (preview.files.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Arquivos sem commit descartados:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                for (final f in preview.files)
                  Text(
                    '• $f',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: AppFonts.mono,
                    ),
                  ),
              ],
              if (preview.restoresStash) ...[
                const SizedBox(height: 8),
                const Text(
                  'As alterações sem commit que existiam no início da '
                  'etapa voltam.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          key: const ValueKey('rewind-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            redo ? 'Descartar e refazer' : 'Descartar e voltar',
            style: const TextStyle(color: AppColors.red),
          ),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    if (redo) {
      await runner.redo(spec.id, step.id);
    } else {
      await runner.rewind(spec.id, step.id);
    }
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
  }
}

class SpecStepsPanel extends ConsumerWidget {
  const SpecStepsPanel({
    super.key,
    required this.specId,
    this.inDialog = false,
  });

  final int specId;
  final bool inDialog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(_specProvider(specId)).value;
    if (spec == null) return const SizedBox.shrink();
    final rows = ref.watch(_stepRowsProvider(specId)).value ?? const [];
    final steps = stepsOf(spec, rows);
    final all = ref.watch(specsProvider(spec.workspaceId)).value ?? const [];
    final sessions = [
      for (final s
          in ref.watch(sessionsProvider(spec.workspaceId)).value ??
              const <Session>[])
        if (s.specId == spec.id) s,
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final data = SpecCardData(
      spec: spec,
      steps: steps,
      sessions: sessions,
      blockers: specBlockers(spec, specsByCode(all)),
    );
    final (done, total) = progressOf(steps);
    final last = data.lastSession;
    final busy =
        last != null &&
        ref.watch(sessionManagerProvider.select((m) => m.isAlive(last.id))) &&
        (last.status == SessionStatus.running ||
            last.status == SessionStatus.waitingApproval);
    final canRun =
        !busy &&
        data.blockers.isEmpty &&
        total > 0 &&
        done < total &&
        spec.stage != SpecStage.done;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              spec.code,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Dot(specStageColor(spec.stage)),
            const SizedBox(width: 6),
            Text(
              specStageLabel(spec.stage),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$done/$total etapas'
                '${data.cost > 0 ? ' · ${formatCost(data.cost)}' : ''}',
                key: const ValueKey('steps-progress'),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (inDialog) ...[
          const SizedBox(height: 4),
          Text(
            spec.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
        if (data.blockers.isNotEmpty && spec.stage != SpecStage.done) ...[
          const SizedBox(height: 6),
          Text(
            'Depende de ${data.blockers.join(', ')} (ainda fora de Feito).',
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ],
        if (spec.branch != null) ...[
          const SizedBox(height: 6),
          Text(
            'Branch ${spec.branch}',
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: steps.isEmpty
              ? const Center(
                  child: Text(
                    'A spec não tem requisitos. Escreva linhas "- R1 · …" na '
                    'seção Requisitos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: steps.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) =>
                      _StepRow(spec: spec, step: steps[i], inDialog: inDialog),
                ),
        ),
        Builder(
          builder: (context) {
            final subs = watchSubagentStatuses(ref, spec, steps, sessions);
            if (subs.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SubagentReport(statuses: subs),
            );
          },
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            key: const ValueKey('steps-auto-advance'),
            value: spec.autoAdvance,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) =>
                ref.read(specsRepoProvider).setAutoAdvance(spec.id, v ?? true),
            title: const Text(
              'Avanço automático: etapa concluída abre a próxima',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          runSpacing: 6,
          children: [
            if (inDialog) ...[
              SmallButton(
                key: const ValueKey('steps-open-spec'),
                label: 'Abrir spec',
                onTap: () {
                  ref.read(selectedSpecProvider.notifier).select(spec.id);
                  ref.read(navigationProvider.notifier).go(AppSection.specs);
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(width: 8),
            ],
            if (!busy && steps.any((s) => s.gateFailed)) ...[
              if (steps
                  .where((s) => s.gateFailed)
                  .every((s) => s.gate!.onlyDirtyTree))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SmallButton(
                    key: const ValueKey('steps-commit-leftovers'),
                    label: 'Commitar o que sobrou',
                    onTap: () => _gateAction(
                      context,
                      () =>
                          ref.read(specRunnerProvider).commitLeftovers(spec.id),
                    ),
                  ),
                ),
              // Only the test count failed: the user may accept the drop
              // (SPEC-023 R3).
              if (steps
                  .where((s) => s.gateFailed)
                  .every((s) => s.gate!.onlyTestCount))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SmallButton(
                    key: const ValueKey('steps-accept-test-drop'),
                    label: 'Aceitar a redução',
                    semanticLabel:
                        'Aceitar a redução da contagem de testes e aprovar '
                        'a etapa',
                    color: AppColors.amber,
                    focusColor: AppColors.amberTint,
                    onTap: () => _gateAction(
                      context,
                      () =>
                          ref.read(specRunnerProvider).acceptTestDrop(spec.id),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SmallButton(
                  key: const ValueKey('steps-gate-fix'),
                  label: 'Corrigir e verificar',
                  onTap: () => _gateAction(
                    context,
                    () => ref.read(specRunnerProvider).fixGate(spec.id),
                  ),
                ),
              ),
              SmallButton(
                key: const ValueKey('steps-recheck'),
                label: 'Verificar de novo',
                onTap: () => _gateAction(
                  context,
                  () => ref.read(specRunnerProvider).recheck(spec.id),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (canRun)
              AmberButton(
                key: const ValueKey('steps-run'),
                label: sessions.isEmpty ? 'Executar' : 'Continuar',
                onTap: () async {
                  if (inDialog) Navigator.of(context).pop();
                  await runSpec(context, ref, data);
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// Runs a gate action; its failure becomes a snackbar.
Future<void> _gateAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
  }
}

class _StepRow extends ConsumerWidget {
  const _StepRow({
    required this.spec,
    required this.step,
    required this.inDialog,
  });

  final Spec spec;
  final StepView step;
  final bool inDialog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected =
        !inDialog &&
        ref.watch(selectedStepProvider) == (specId: spec.id, step: step.id);
    return InkWell(
      key: ValueKey('step-${step.id}'),
      onTap: inDialog
          ? null
          : () {
              final n = ref.read(selectedStepProvider.notifier);
              selected ? n.clear() : n.select(spec.id, step.id);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? SessionColors.selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: _row(context, ref),
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Dot(stepStatusColor(step.status)),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 32,
        child: Text(
          step.id,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              step.text,
              style: TextStyle(
                fontSize: 13,
                color: step.isDone ? AppColors.textSecondary : AppColors.text,
              ),
            ),
            if (step.gate case final g?) ...[
              const SizedBox(height: 4),
              GateChips(report: g, keyPrefix: 'step-gate-${step.id}'),
            ],
          ],
        ),
      ),
      const SizedBox(width: 8),
      Text(
        stepStatusLabel(step.status),
        key: ValueKey('step-status-${step.id}'),
        style: TextStyle(fontSize: 11, color: stepStatusColor(step.status)),
      ),
      if (step.sessionId != null)
        IconButton(
          key: ValueKey('step-session-${step.id}'),
          tooltip: 'Ver sessão',
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.open_in_new, color: AppColors.textSecondary),
          onPressed: () {
            if (inDialog) Navigator.of(context).pop();
            openSession(ref, step.sessionId!);
          },
        ),
      SizedBox(
        width: 24,
        child: PopupMenuButton<String>(
          key: ValueKey('step-menu-${step.id}'),
          padding: EdgeInsets.zero,
          iconSize: 14,
          tooltip: 'Marcar',
          color: AppColors.panel,
          icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
          onSelected: (v) => switch (v) {
            'done' =>
              ref
                  .read(specStepsRepoProvider)
                  .set(spec.id, step.id, StepStatus.done),
            'pending' =>
              ref
                  .read(specStepsRepoProvider)
                  .set(spec.id, step.id, StepStatus.pending),
            _ => rewindStepAction(context, ref, spec, step, redo: v == 'redo'),
          },
          itemBuilder: (_) => [
            if (!step.isDone)
              const PopupMenuItem(
                value: 'done',
                child: Text(
                  'Marcar como concluída',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (step.status != StepStatus.pending)
              const PopupMenuItem(
                value: 'pending',
                child: Text(
                  'Voltar para pendente',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (step.startSha != null &&
                spec.worktreePath != null &&
                spec.stage != SpecStage.done) ...[
              const PopupMenuItem(
                value: 'rewind',
                child: Text(
                  'Voltar ao início da etapa…',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const PopupMenuItem(
                value: 'redo',
                child: Text('Refazer etapa…', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
