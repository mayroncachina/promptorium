import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/session_manager.dart';
import '../../specs/workspace_watcher.dart';
import '../board_rules.dart' show StepView;
import '../board_screen.dart';
import '../spec_runner.dart' show worktreePrepProvider;
import 'canvas_detail_card.dart';
import 'duel_dialog.dart' show openDuelsProvider;
import 'gate_fix_badge.dart';
import 'spec_canvas.dart';
import 'step_decision_dialog.dart';

/// Why [d] needs the person, for a card that does.
String specAttentionReason(WidgetRef ref, SpecCardData d) {
  final last = d.lastSession;
  final waitingApproval =
      last != null &&
      last.status == SessionStatus.waitingApproval &&
      ref.watch(sessionManagerProvider.select((m) => m.isAlive(last.id)));
  final prep = ref.watch(worktreePrepProvider.select((m) => m[d.spec.id]));
  final changed = ref.watch(
    workspaceWatcherProvider.select((s) => s.contains(d.spec.id)),
  );
  final duelReady =
      (ref.watch(openDuelsProvider(d.spec.workspaceId)).value ?? <SpecDuel>[])
          .any((duel) => duel.specId == d.spec.id && duel.state == 'pronto');
  return boardAttentionReason(
    d,
    waitingApproval: waitingApproval,
    prepFailed: prep?.error != null,
    changedOnDisk: changed,
    duelReady: duelReady,
  );
}

/// Label and colour of the spec's stage pill.
(String, Color) stagePill(SpecStage s) => switch (s) {
  SpecStage.done => ('Feito', CanvasColors.done),
  SpecStage.running => ('Em execução', CanvasColors.running),
  SpecStage.review => ('Review', CanvasColors.review),
  SpecStage.backlog => ('Backlog', AppColors.textSecondary),
};

String stepStatusText(StepView s) => switch (s.status) {
  StepStatus.done => 'feita',
  StepStatus.running => 'em execução',
  StepStatus.needsInput =>
    s.gateFailed ? 'aguardando você · verificação falhou' : 'aguardando você',
  StepStatus.verifying => 'verificando',
  StepStatus.pending => 'pendente',
};

class StagePill extends StatelessWidget {
  const StagePill(this.stage, {super.key, this.neutral = false});
  final SpecStage stage;

  /// On a card that needs the person, so amber is only the attention signal.
  final bool neutral;
  @override
  Widget build(BuildContext context) {
    final (label, stageColor) = stagePill(stage);
    final color = neutral ? AppColors.textSecondary : stageColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Never blinks (R3): the dark text keeps its contrast on amber.
class AttentionBadge extends StatelessWidget {
  const AttentionBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(6, 2, 9, 2),
    decoration: BoxDecoration(
      color: AppColors.amber,
      borderRadius: BorderRadius.circular(11),
      boxShadow: const [
        BoxShadow(color: AppColors.background, spreadRadius: 3),
      ],
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AttentionBubble(size: 13, color: AppColors.onAmber),
        SizedBox(width: 5),
        Text(
          'Precisa de você',
          softWrap: false,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.onAmber,
          ),
        ),
      ],
    ),
  );
}

class SpecNode extends StatelessWidget {
  const SpecNode({
    super.key,
    required this.data,
    required this.selected,
    required this.reason,
    required this.onTap,
    this.pulse,
    this.fitContent = false,
  });
  final SpecCardData data;
  final bool selected;

  /// Why the spec needs the person; null when it does not.
  final String? reason;
  final Animation<double>? pulse;
  final VoidCallback onTap;

  /// Takes the height of its content, with the whole title, instead of
  /// filling a fixed size (the card of the folder, SPEC-036 R4).
  final bool fitContent;
  bool get attention => reason != null;
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final done = data.steps.where((s) => s.isDone).length;
    final node = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: radius,
        border: Border.all(
          width: selected || attention ? 2 : 1,
          color: selected
              ? AppColors.text
              : attention
              ? AppColors.amber
              : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? .5 : .25),
            blurRadius: selected ? 24 : 2,
            offset: Offset(0, selected ? 8 : 1),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('board-open-${data.spec.code}'),
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: fitContent ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              spacing: fitContent ? 8 : 0,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.spec.code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GateFixBadge(data: data, fontSize: 11),
                    const SizedBox(width: 6),
                    StagePill(
                      data.spec.stage,
                      key: ValueKey('canvas-pill-${data.spec.code}'),
                      neutral: attention,
                    ),
                  ],
                ),
                Text(
                  data.spec.title,
                  maxLines: fitContent ? null : 2,
                  overflow: fitContent ? null : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1.3,
                    color: AppColors.text,
                  ),
                ),
                if (reason != null)
                  Text(
                    reason!,
                    key: ValueKey('canvas-reason-${data.spec.code}'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final shown = _fittingSteps(data.steps, box.maxWidth);
                          return Row(
                            children: [
                              for (final step in shown)
                                CanvasDetailCard(
                                  focusable: false,
                                  width: 250,
                                  details: StepDetails(
                                    step: step,
                                    reason: reason,
                                    clickable: true,
                                  ),
                                  child: StepDotButton(
                                    spec: data.spec,
                                    step: step,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        1,
                                        4,
                                        5,
                                        4,
                                      ),
                                      child: CanvasStepDot(
                                        key: ValueKey(
                                          'canvas-dot-${data.spec.code}-${step.id}',
                                        ),
                                        status: step.status,
                                        pulse:
                                            step.status == StepStatus.needsInput
                                            ? pulse
                                            : null,
                                        semanticLabel:
                                            step.status == StepStatus.needsInput
                                            ? 'Etapa ${step.id}: '
                                                  'aguardando você'
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              if (shown.length < data.steps.length)
                                Text(
                                  '+${data.steps.length - shown.length}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),

                    Text(
                      '$done/${data.steps.length}',
                      key: ValueKey('board-progress-${data.spec.code}'),
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (reason == null) return node;
    return Semantics(
      key: ValueKey('canvas-semantics-${data.spec.code}'),
      container: true,
      label:
          '${data.spec.code} · ${data.spec.title} · precisa de você: $reason',
      child: node,
    );
  }
}

/// Width a step takes in the card row: its dot plus the 1 + 5 px padding.
double _stepWidth(StepView s) =>
    (s.status == StepStatus.needsInput ? stepBubbleSize : stepDotSize) + 6;

/// The steps that fit in [maxWidth], leaving room for "+N" when some don't.
List<StepView> _fittingSteps(List<StepView> steps, double maxWidth) {
  final total = steps.fold<double>(0, (w, s) => w + _stepWidth(s));
  if (total <= maxWidth) return steps;
  final out = <StepView>[];
  var used = 0.0;
  for (final s in steps) {
    if (used + _stepWidth(s) > maxWidth - 16) break;
    used += _stepWidth(s);
    out.add(s);
  }
  return out.isEmpty ? [steps.first] : out;
}

class StepDetails extends StatelessWidget {
  const StepDetails({
    super.key,
    required this.step,
    this.reason,
    this.clickable = false,
  });
  final StepView step;

  /// What is missing, for a step that waits for the person (R7).
  final String? reason;

  /// The step opens on click (the card's dots, not the panel's list).
  final bool clickable;
  @override
  Widget build(BuildContext context) {
    if (step.status == StepStatus.needsInput) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AttentionBubble(size: 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Etapa ${step.id} · aguardando você',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              step.gateFailed
                  ? 'A verificação falhou.'
                  : step.text.isNotEmpty
                  ? step.text
                  : reason ?? stepStatusText(step),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          if (clickable)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Clique para abrir a etapa',
                style: TextStyle(color: AppColors.amber),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          step.id,
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            stepStatusText(step),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
        if (step.text.isNotEmpty)
          Text(
            step.text,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

/// A step of the card opens on a click; the balloon also takes the focus, so
/// it opens from the keyboard and the modal can give the focus back to it
/// (SPEC-033 R15). Only the balloon: the other dots are not tab stops.
class StepDotButton extends StatelessWidget {
  const StepDotButton({
    super.key,
    required this.spec,
    required this.step,
    required this.child,
  });
  final Spec spec;
  final StepView step;
  final Widget child;

  @override
  Widget build(BuildContext context) => StepFocusAnchor(
    builder: (context, focus) {
      void open() => openStep(
        context,
        spec,
        step,
        stepOrigin(context),
        returnFocus: focus,
      );
      return FocusableActionDetector(
        focusNode: focus,
        enabled: step.status == StepStatus.needsInput,
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              open();
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: ValueKey('canvas-step-${spec.code}-${step.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: open,
          child: ListenableBuilder(
            listenable: focus,
            child: child,
            builder: (_, child) => DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: focus.hasFocus
                    ? Border.all(color: AppColors.amber)
                    : null,
              ),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
