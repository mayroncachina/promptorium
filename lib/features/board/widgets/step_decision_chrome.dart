import 'package:flutter/material.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../board_rules.dart';
import '../step_decision.dart';
import 'spec_canvas.dart' show AttentionHalo, CanvasStepDot;
import 'step_decision_parts.dart';

/// Top of the modal (R3): the step, the progress of the decisions (R8), the
/// requirement and "O que aconteceu".
class StepDecisionHeader extends StatelessWidget {
  const StepDecisionHeader({
    super.key,
    required this.spec,
    required this.step,
    required this.state,
    required this.index,
    required this.total,
    required this.pulse,
    required this.onClose,
  });

  final Spec spec;
  final StepView step;
  final StepDecisionState state;
  final int index;
  final int total;

  /// The single pulse of the bubble (R2); null without animations.
  final Animation<double>? pulse;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(2),
              child: AttentionHalo(
                enabled: pulse != null,
                pulse: pulse,
                radius: 5,
                child: CanvasStepDot(
                  key: const ValueKey('step-decision-bubble'),
                  status: StepStatus.needsInput,
                  pulse: pulse,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              spec.code,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const Text(
              ' · ',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            Expanded(
              child: Text(
                'Etapa ${stepNumber(step.id)} · aguardando você',
                key: const ValueKey('step-decision-status'),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.amber,
                ),
              ),
            ),
            if (total > 1) _progress(),
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: 32,
              child: IconButton(
                key: const ValueKey('step-decision-close'),
                tooltip: 'Fechar (Esc)',
                padding: EdgeInsets.zero,
                iconSize: 18,
                color: AppColors.textSecondary,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${step.id} · ${step.text}',
          key: const ValueKey('step-decision-requirement'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        ..._summary(),
      ],
    ),
  );

  List<Widget> _summary() {
    final summary = state.result?.summary ?? '';
    final Widget? child = step.gateFailed
        ? StepDecisionGateSummary(stepId: step.id, report: step.gate!)
        : state.status == StepDecisionStatus.loading
        ? const StepDecisionSummary(summary: '', loading: true)
        : summary.isEmpty
        ? null
        : StepDecisionSummary(summary: summary, loading: false);
    return [
      if (child != null) ...[
        const SizedBox(height: 10),
        Semantics(container: true, child: child),
      ],
    ];
  }

  Widget _progress() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Decisão ${index + 1} de $total',
        key: const ValueKey('step-decision-progress'),
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(width: 8),
      for (var i = 0; i < total; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        Container(
          width: 22,
          height: 4,
          decoration: BoxDecoration(
            color: i <= index ? AppColors.amber : SessionColors.selectedBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    ],
  );
}

/// Bottom of the modal: the keys (R6), "Abrir sessão" (R12) and, by state,
/// "Tentar de novo", "Outra resposta" (R14) and "Compilar".
class StepDecisionFooter extends StatelessWidget {
  const StepDecisionFooter({
    super.key,
    required this.status,
    required this.deciding,
    required this.missing,
    required this.otherOpen,
    required this.showKeys,
    required this.onRetry,
    required this.onOther,
    required this.onOpenSession,
    required this.onCompile,
  });

  final StepDecisionStatus status;

  /// False in the Compilar phase, which has its own buttons.
  final bool deciding;

  /// Decisions still without an answer.
  final int missing;
  final bool otherOpen;
  final bool showKeys;
  final VoidCallback onRetry;
  final VoidCallback onOther;

  /// Null when the step has no session.
  final VoidCallback? onOpenSession;
  final VoidCallback onCompile;

  @override
  Widget build(BuildContext context) {
    final ready = status == StepDecisionStatus.ready;
    final session = IntrinsicWidth(
      child: SmallButton(
        key: const ValueKey('step-decision-open-session'),
        label: 'Abrir sessão',
        height: 34,
        fontSize: 13,
        background: AppColors.surfaceRaised,
        icon: Icons.group_outlined,
        trailing: const StepKbd('Ctrl+O'),
        onTap: onOpenSession,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: showKeys && deciding ? const _KeyLegend() : const SizedBox(),
          ),
          const SizedBox(width: 12),
          // Wraps instead of overflowing in a narrow window.
          Expanded(
            flex: 3,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (deciding && status == StepDecisionStatus.failed)
                  IntrinsicWidth(
                    child: AmberButton(
                      key: const ValueKey('step-decision-retry'),
                      label: 'Tentar de novo',
                      height: 34,
                      onTap: onRetry,
                    ),
                  ),
                if (deciding &&
                    status == StepDecisionStatus.loading &&
                    !otherOpen)
                  IntrinsicWidth(
                    child: SmallButton(
                      key: const ValueKey('step-decision-other-button'),
                      label: 'Outra resposta',
                      height: 34,
                      fontSize: 13,
                      background: AppColors.surfaceRaised,
                      trailing: const StepKbd('5'),
                      onTap: onOther,
                    ),
                  ),
                if (onOpenSession != null)
                  session
                else
                  Tooltip(
                    message: 'Esta etapa ainda não tem sessão',
                    child: session,
                  ),
                if (deciding && ready && missing > 0)
                  Text(
                    missing == 1
                        ? 'Falta 1 decisão'
                        : 'Faltam $missing decisões',
                    key: const ValueKey('step-decision-missing'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (deciding && (ready || missing == 0))
                  IntrinsicWidth(
                    child: SmallButton(
                      key: const ValueKey('step-decision-compile-button'),
                      label: 'Compilar',
                      height: 34,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onAmber,
                      background: AppColors.amber,
                      border: AppColors.amber,
                      icon: Icons.check,
                      trailing: const StepKbd('Ctrl+Enter', onAmber: true),
                      onTap: missing == 0 ? onCompile : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The keys of the modal (R6).
class _KeyLegend extends StatelessWidget {
  const _KeyLegend();

  static const _keys = [
    ('1–4', 'escolher'),
    ('5', 'outra'),
    ('↑↓', 'mover'),
    ('Enter', 'confirmar'),
    ('⌫', 'voltar'),
    ('Esc', 'fechar'),
  ];

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Atalhos',
    child: Wrap(
      key: const ValueKey('step-decision-keys'),
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final (key, label) in _keys)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StepKbd(key),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}
