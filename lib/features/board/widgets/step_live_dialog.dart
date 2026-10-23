import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/widgets/session_style.dart';
import '../../sessions/widgets/timeline_view.dart';
import '../board_rules.dart';
import '../board_screen.dart' show openSession, specStepsProvider;
import '../spec_runner.dart';
import 'gate_report_view.dart';

/// A step of a card (segment of the bar in the columns, dot in the canvas)
/// followed live: its state, last gate and the timeline of its session;
/// with a live session, a message goes straight to it.
Future<void> showStepLiveDialog(
  BuildContext context, {
  required Spec spec,
  required String step,
}) => showDialog<void>(
  context: context,
  builder: (_) => StepLiveDialog(spec: spec, step: step),
);

class StepLiveDialog extends ConsumerStatefulWidget {
  const StepLiveDialog({super.key, required this.spec, required this.step});

  final Spec spec;
  final String step;

  @override
  ConsumerState<StepLiveDialog> createState() => _StepLiveDialogState();
}

class _StepLiveDialogState extends ConsumerState<StepLiveDialog> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send(String sessionId) async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    _message.clear();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(sessionManagerProvider.notifier).send(sessionId, text);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _fix() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(specRunnerProvider).fixGate(widget.spec.id);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.spec.workspaceId;
    final spec =
        (ref.watch(specsProvider(ws)).value ?? const <Spec>[])
            .where((s) => s.id == widget.spec.id)
            .firstOrNull ??
        widget.spec;
    final rows = ref.watch(specStepsProvider(ws)).value ?? const [];
    final step = stepsOf(
      spec,
      rows,
    ).where((s) => s.id == widget.step).firstOrNull;
    final sessionId = step?.sessionId;
    final session = sessionId == null
        ? null
        : (ref.watch(sessionsProvider(ws)).value ?? const <Session>[])
              .where((s) => s.id == sessionId)
              .firstOrNull;
    final alive =
        sessionId != null &&
        ref.watch(sessionManagerProvider.select((m) => m.isAlive(sessionId)));
    final busy =
        alive &&
        (session?.status == SessionStatus.running ||
            session?.status == SessionStatus.waitingApproval);
    final gate = ref.watch(
      gateRunningProvider.select((g) => g.contains(spec.id)),
    );
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      key: const ValueKey('step-live-dialog'),
      backgroundColor: AppColors.panel,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: size.width < 840 ? size.width - 48 : 760,
        height: size.height * .75,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '${spec.code} · ${widget.step}',
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (step != null)
                    Text(
                      gate && step.status == StepStatus.verifying
                          ? 'verificando agora'
                          : step.gateFailed
                          ? 'verificação falhou'
                          : stepStatusLabel(step.status),
                      key: const ValueKey('step-live-status'),
                      style: TextStyle(
                        fontSize: 12,
                        color: step.gateFailed
                            ? AppColors.red
                            : AppColors.textSecondary,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    key: const ValueKey('step-live-close'),
                    tooltip: 'Fechar',
                    iconSize: 18,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (step != null)
                Text(
                  step.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              if (step?.gate case final g?) ...[
                const SizedBox(height: 8),
                GateChips(report: g, keyPrefix: 'step-live-gate'),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: sessionId == null
                      ? const Center(
                          child: Text(
                            'Esta etapa ainda não teve sessão.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : TimelineView(
                          sessionId: sessionId,
                          root: session?.worktreePath,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (alive)
                    Expanded(
                      child: TextField(
                        key: const ValueKey('step-live-input'),
                        controller: _message,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Mensagem para a sessão…',
                        ),
                        onSubmitted: (_) => _send(sessionId),
                      ),
                    )
                  else
                    const Spacer(),
                  if (alive) ...[
                    const SizedBox(width: 8),
                    AmberButton(
                      key: const ValueKey('step-live-send'),
                      label: 'Enviar',
                      onTap: () => _send(sessionId),
                    ),
                  ],
                  if (step != null && step.gateFailed && !busy && !gate) ...[
                    const SizedBox(width: 8),
                    SmallButton(
                      key: const ValueKey('step-live-fix'),
                      label: 'Corrigir e verificar',
                      onTap: _fix,
                    ),
                  ],
                  if (sessionId != null) ...[
                    const SizedBox(width: 8),
                    SmallButton(
                      key: const ValueKey('step-live-open'),
                      label: 'Abrir sessão',
                      onTap: () {
                        Navigator.of(context).pop();
                        openSession(ref, sessionId);
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
