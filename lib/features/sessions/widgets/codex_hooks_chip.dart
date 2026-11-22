import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/managed_hooks.dart';
import '../../../core/codex/codex_hooks.dart';
import '../../../ui/theme/tokens.dart';
import 'session_style.dart';

/// Color of a hook state (teal = before the tool, amber = after the turn).
Color hookWhenColor(HookWhen w) => switch (w) {
  HookWhen.beforeTool => AppColors.teal,
  HookWhen.afterTurn => AppColors.amber,
  HookWhen.unavailable => AppColors.textMuted,
};

Color codexHookModeColor(CodexHookMode m) => switch (m) {
  CodexHookMode.native => AppColors.teal,
  CodexHookMode.partial || CodexHookMode.postTurn => AppColors.amber,
  CodexHookMode.off => AppColors.textMuted,
};

/// SPEC-103 R9: the chip of a live Codex session with what `hooks/list`
/// said ("Hooks nativos" in teal, "Hooks só pós-turno" in amber). A click
/// lists each hook and its substitute.
class CodexHooksChip extends ConsumerWidget {
  const CodexHooksChip({super.key, required this.sessionId, this.yolo = false});

  final String sessionId;

  /// The session runs in YOLO (no approvals: no prior block without hooks).
  final bool yolo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      codexHookStatusProvider.select((m) => m[sessionId]),
    );
    if (status == null) return const SizedBox.shrink();
    final color = codexHookModeColor(status.mode);
    return Tooltip(
      message: status.tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('codex-hooks-chip-$sessionId'),
          borderRadius: BorderRadius.circular(5),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => CodexHooksDialog(status: status, yolo: yolo),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Dot(color, size: 6),
                const SizedBox(width: 5),
                Text(
                  status.mode.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Hooks desta sessão": each hook with its Codex event (native) or the
/// app's substitute (post-turn), and where the state came from.
class CodexHooksDialog extends StatelessWidget {
  const CodexHooksDialog({super.key, required this.status, this.yolo = false});

  final CodexHookStatus status;
  final bool yolo;

  @override
  Widget build(BuildContext context) {
    final at = status.at;
    return Dialog(
      key: const ValueKey('codex-hooks-dialog'),
      backgroundColor: AppColors.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Hooks desta sessão',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Text(
                    'hooks/list${at == null ? '' : ' · ${formatClock(at)}'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final h in ManagedHook.values)
                if (status.planned.contains(h)) _row(h),
              if (status.planned.isEmpty)
                const Text(
                  'Todos os hooks do app estão desligados em Automações.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              const SizedBox(height: 10),
              Text(
                status.mode == CodexHookMode.native
                    ? 'Origem: sessionFlags · confiança só desta sessão. '
                          'Nada é escrito no ~/.codex.'
                    : '${status.reason ?? status.tooltip} Nada é escrito no '
                          '~/.codex e o app nunca usa --trust.',
                key: const ValueKey('codex-hooks-dialog-origin'),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              for (final p in status.problems)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    p,
                    style: const TextStyle(fontSize: 11, color: AppColors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ManagedHook h) {
    final when = status.whenOf(h, yolo: yolo);
    final color = hookWhenColor(when);
    final detail = switch (when) {
      HookWhen.beforeTool => codexHookEvent(h),
      HookWhen.afterTurn => hookSubstitute(h, yolo: yolo),
      HookWhen.unavailable =>
        h == ManagedHook.block && yolo
            ? 'indisponível no YOLO'
            : 'indisponível (sem python3)',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              h.label,
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
          Dot(color, size: 6),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              detail,
              key: ValueKey('codex-hooks-row-${h.name}'),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
