import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/session_manager.dart';
import '../board_screen.dart' show SpecCardData;
import '../spec_runner.dart';

/// Whether the card offers "Corrigir e verificar": a step the gate refused
/// waits for the user, no session of the spec is running and no gate is.
bool canFixGate(SpecCardData data, {required bool busy, required bool gate}) =>
    !busy && !gate && data.steps.any((s) => s.gateFailed);

/// Badge of the card (columns and canvas) when the gate refused a step: the
/// failure goes back to the agent, which fixes it, and the gate runs again
/// ([SpecRunner.fixGate]). Nothing when there is nothing to fix.
class GateFixBadge extends ConsumerWidget {
  const GateFixBadge({
    super.key,
    required this.data,
    this.fontSize = 10,
    this.compact = false,
  });

  final SpecCardData data;
  final double fontSize;

  /// Only the icon (narrow header of the column card).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = data.spec, last = data.lastSession;
    final alive =
        last != null &&
        ref.watch(sessionManagerProvider.select((m) => m.isAlive(last.id)));
    final busy =
        alive &&
        (last.status == SessionStatus.running ||
            last.status == SessionStatus.waitingApproval);
    final gate = ref.watch(
      gateRunningProvider.select((g) => g.contains(spec.id)),
    );
    if (!canFixGate(data, busy: busy, gate: gate)) {
      return const SizedBox.shrink();
    }
    final steps = [
      for (final s in data.steps)
        if (s.gateFailed) s.id,
    ].join(', ');
    final label = 'Corrigir $steps e verificar de novo';
    return Tooltip(
      message:
          'Verificação de $steps falhou: o agente recebe a falha, '
          'corrige e a verificação roda de novo',
      child: Semantics(
        container: true,
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('board-gate-fix-${spec.code}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            try {
              await ref.read(specRunnerProvider).fixGate(spec.id);
              messenger?.showSnackBar(
                SnackBar(
                  content: Text('${spec.code}: falha enviada ao agente.'),
                ),
              );
            } catch (e) {
              messenger?.showSnackBar(SnackBar(content: Text('$e')));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.replay, size: fontSize + 2, color: AppColors.red),
                if (!compact) ...[
                  const SizedBox(width: 3),
                  Text(
                    'corrigir',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: AppColors.red,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
