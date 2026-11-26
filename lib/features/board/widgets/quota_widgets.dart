import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/capabilities.dart';
import '../../../core/providers/provider_availability.dart';
import '../../../core/providers/quota_source.dart';
import '../../../data/providers.dart';
import '../../../ui/providers/provider_logos.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../orchestrator/orchestrator_rules.dart';
import '../orchestrator/quota_divert.dart';
import '../orchestrator/quota_diverter.dart';
import '../board_rules.dart' show StepView, stepsOf;
import '../board_screen.dart' show SpecCardData;
import '../spec_runner.dart';
import 'run_spec_dialog.dart' show runSpec;

/// Screens of the desvio por cota (SPEC-109 R8, R9, R14).

/// Why steps on [provider] cannot run now (`sem login`…); null = they can,
/// or the check has not answered yet. Only watched for a rule on the Codex.
final planProviderBlockedProvider = Provider.autoDispose
    .family<String?, String>((ref, provider) {
      if (provider == 'claude') return null;
      if (!ref.watch(providerFlowsProvider).allows(provider, AppFlow.runSpec)) {
        return 'desligado em "Executar spec"';
      }
      final a = ref.watch(providerAvailabilityProvider(provider)).value;
      return a == null || a.available ? null : a.label;
    });

/// `5 h 62% · semana 41%` of a reading; null = no reading.
String? quotaBrief(QuotaSnapshot? s, DateTime now) {
  final parts = [
    for (final w in s?.main.windows ?? const [])
      if (w.usedPercent != null)
        '${switch (w.minutes) {
          300 => '5 h',
          10080 => 'semana',
          final int m when m % 60 == 0 => '${m ~/ 60} h',
          _ => 'janela',
        }} ${_expired(w.resetsAt, now) ? '—' : '${(w.usedPercent as double).round()}%'}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

bool _expired(DateTime? at, DateTime now) => at != null && !at.isAfter(now);

/// "Cota agora:" of the plan (R9): the quota of the providers it uses.
class PlanQuotaHeader extends ConsumerWidget {
  const PlanQuotaHeader({super.key, required this.providers});

  final List<String> providers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final known = [
      for (final p in providers)
        if (quotaBrief(ref.watch(quotaSnapshotProvider(p)), now) case final t?)
          (p, t),
    ];
    if (known.isEmpty) return const SizedBox.shrink();
    return Wrap(
      key: const ValueKey('run-spec-quota'),
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Cota agora:',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        for (final (p, text) in known) ...[
          ProviderChip(p, dense: true),
          Text(
            text,
            key: ValueKey('run-spec-quota-$p'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.text,
            ),
          ),
        ],
      ],
    );
  }
}

/// The line of a spec whose step was diverted (R5, R14): on the card and in
/// the list of steps. Nothing when the spec is on its plan.
class SpecDivertLine extends ConsumerWidget {
  const SpecDivertLine({
    super.key,
    required this.specId,
    required this.step,
    this.provider = false,
  });

  final int specId;

  /// The step shown: the line is only of the diverted one.
  final String? step;

  /// Shows the badge and the rule too (the list of steps; the card has its
  /// own badge).
  final bool provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(specDivertProvider(specId));
    if (d == null || d.step != step) return const SizedBox.shrink();
    return Semantics(
      label: d.spoken,
      liveRegion: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Tooltip(
          message: d.why,
          child: Wrap(
            key: ValueKey('spec-divert-$specId-${provider ? 'step' : 'card'}'),
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (provider) ...[
                ProviderChip(d.to.provider, dense: true),
                Text(
                  d.to.label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              Text(
                d.cardText(),
                style: const TextStyle(fontSize: 11, color: AppColors.amber),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The plan of a step on the Codex, in the list of steps (R9). Nothing for
/// the Claude Code (the plans of before) nor for a diverted step.
class StepPlanLine extends ConsumerWidget {
  const StepPlanLine({super.key, required this.step, required this.specId});

  final StepView step;
  final int specId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = step.planProvider, model = step.planModel;
    if (provider == null || provider == 'claude' || model == null) {
      return const SizedBox.shrink();
    }
    if (ref.watch(specDivertProvider(specId))?.step == step.id) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        key: ValueKey('step-plan-line-${step.id}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          ProviderChip(provider, dense: true),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              StepRule(model, step.planEffort ?? '', provider: provider).label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A step that waits for quota (R8): the renewals and the three actions.
/// Nothing goes to another provider by itself.
class QuotaWaitPanel extends ConsumerWidget {
  const QuotaWaitPanel({
    super.key,
    required this.specId,
    this.onDone,
    this.compact = false,
  });

  final int specId;

  /// After an action that started the step.
  final VoidCallback? onDone;

  /// On the card: only the renewals and the main action.
  final bool compact;

  Future<void> _do(
    BuildContext context,
    Future<Object?> Function() action, {
    bool started = false,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      if (started) onDone?.call();
    } catch (e) {
      messenger
        ?..hideCurrentSnackBar()
        ..showAppToast(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wait = ref.watch(specQuotaWaitProvider(specId));
    if (wait == null) return const SizedBox.shrink();
    final runner = ref.read(specRunnerProvider);
    final at = wait.firstRenewal;
    final resume = wait.resumeAt;
    final schedule = resume != null
        ? SmallButton(
            key: ValueKey('quota-wait-cancel-$specId'),
            label: 'Retomada às ${quotaClock(resume)} · Cancelar',
            onTap: () =>
                _do(context, () => runner.scheduleResume(specId, on: false)),
          )
        : AmberButton(
            key: ValueKey('quota-wait-resume-$specId'),
            label: at == null
                ? 'Retomar quando renovar'
                : 'Retomar quando renovar · ${quotaClock(at)}',
            onTap: at == null
                ? null
                : () => _do(context, () => runner.scheduleResume(specId)),
          );
    final now = SmallButton(
      key: ValueKey('quota-wait-now-$specId'),
      label: 'Executar agora com…',
      onTap: () async {
        final choices = await runner.runNowChoices(specId);
        if (!context.mounted || choices.isEmpty) return;
        final rule = await showAppDialog<StepRule>(
          context: context,
          barrierColor: AppColors.scrim,
          builder: (_) => _RunNowDialog(step: wait.step, choices: choices),
        );
        if (rule == null || !context.mounted) return;
        await _do(context, () => runner.runNow(specId, rule), started: true);
      },
    );
    return Semantics(
      container: true,
      label: '${wait.step} aguardando você. ${wait.title}. ${wait.detail()}.',
      child: Container(
        key: ValueKey('quota-wait-$specId'),
        padding: EdgeInsets.all(compact ? 8 : 12),
        decoration: BoxDecoration(
          color: AppColors.amberTint,
          border: Border.all(color: SessionColors.approvalBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact)
              Text(
                'aguardando você · ${wait.step}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.amber,
                ),
              ),
            Text(
              '${wait.title}.',
              style: TextStyle(
                fontSize: compact ? 11 : 13,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            for (final b in wait.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProviderChip(b.provider, dense: true),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        b.detail(),
                        key: ValueKey('quota-wait-$specId-${b.provider}'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                schedule,
                now,
                SmallButton(
                  key: ValueKey('quota-wait-manual-$specId'),
                  label: 'Usar Manual',
                  onTap: () => _do(
                    context,
                    () => runSpecManual(context, ref, specId),
                    started: true,
                  ),
                ),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 8),
              Text(
                'Nada cai em silêncio para outro provedor.'
                '${wait.sessionId == null ? '' : ' Ao seguir, a etapa volta ao '
                          'início; o que a tentativa deixou fica guardado no '
                          'git.'}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Executar agora com…" (R8): the plan of the step and its reserve.
class _RunNowDialog extends StatelessWidget {
  const _RunNowDialog({required this.step, required this.choices});

  final String step;
  final List<StepRule> choices;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    key: const ValueKey('quota-run-now'),
    backgroundColor: AppColors.panelSolid,
    title: Text(
      'Executar $step agora com',
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    children: [
      for (final (i, r) in choices.indexed)
        SimpleDialogOption(
          key: ValueKey('quota-run-now-${r.provider}'),
          onPressed: () => Navigator.of(context).pop(r),
          child: Row(
            children: [
              ProviderChip(r.provider, dense: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${r.label} · ${i == 0 ? 'plano' : 'reserva'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// "Usar Manual" (R8): Executar in Manual, with the provider to choose (the
/// plan of the spec goes away). Nothing happens when the person cancels.
Future<void> runSpecManual(
  BuildContext context,
  WidgetRef ref,
  int specId,
) async {
  final spec = await ref.read(specsRepoProvider).getById(specId);
  final rows = await ref.read(specStepsRepoProvider).bySpec(specId);
  final sessions = await ref.read(sessionsRepoProvider).bySpec(specId);
  if (spec == null || !context.mounted) return;
  await runSpec(
    context,
    ref,
    SpecCardData(
      spec: spec,
      steps: stepsOf(spec, rows),
      sessions: sessions,
      blockers: const [],
    ),
    ask: true,
    manual: true,
  );
}

/// A step waiting for quota, opened from a balloon, a segment or a row: in
/// place of the decision modal, which has nothing to decide (R8).
Future<void> showQuotaWait(BuildContext context, Spec spec) =>
    showAppDialog<void>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('quota-wait-dialog'),
        backgroundColor: AppColors.panelSolid,
        title: Text(
          '${spec.code} · ${spec.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 560,
          child: QuotaWaitPanel(
            specId: spec.id,
            onDone: () {
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
