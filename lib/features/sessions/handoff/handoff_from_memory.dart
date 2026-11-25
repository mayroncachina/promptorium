import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/claude/claude_args.dart';
import '../../../core/memory/handoff.dart';
import '../../../core/providers/provider_availability.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../project/widgets/ai_memory_view.dart' show HandoffContinueAction;
import '../session_manager.dart';
import '../widgets/session_style.dart';
import 'continue_controller.dart';
import 'continue_dialog.dart';
import 'continue_link.dart';
import 'session_summary.dart' show providerWords;

/// The provider a handoff goes to: the other agent of the one that wrote
/// it (Claude ⇄ Codex).
String handoffTarget(Handoff h) => h.fromAgent == 'codex' ? 'claude' : 'codex';

/// The session whose worktree is the handoff's directory (the newest one
/// that can be continued), else null (R13).
Session? sessionOfHandoff(Handoff h, List<Session> sessions) {
  final cwd = h.cwd;
  if (cwd == null) return null;
  Session? best;
  for (final s in sessions) {
    if (!p.equals(s.worktreePath, cwd)) continue;
    if (continueTarget(s.provider) != handoffTarget(h)) continue;
    if (best == null || s.startedAt.isAfter(best.startedAt)) best = s;
  }
  return best;
}

/// "Continuar em…" of the Memória panel (SPEC-098 R11, SPEC-099 R13).
final handoffContinueAction = HandoffContinueAction(
  label: (h) => continueLabel(handoffTarget(h)),
  run: continueFromHandoff,
);

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text(text)));

/// R13: the dialog with this handoff chosen when its directory is the
/// worktree of a known session (that session is the origin); else a new
/// session in the workspace root, with the handoff and no link.
Future<void> continueFromHandoff(BuildContext context, Handoff h) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final ws = container.read(activeWorkspaceProvider);
  if (ws == null) return;
  final sessions = await container
      .read(sessionsRepoProvider)
      .watchByWorkspace(ws.id)
      .first;
  if (!context.mounted) return;
  final origin = sessionOfHandoff(h, sessions);
  if (origin != null) {
    if (origin.specId != null) {
      _snack(context, ContinueReasons.step);
      return;
    }
    await showContinueDialog(context, origin, handoff: h);
    return;
  }
  final target = handoffTarget(h);
  final ok = await showAppDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('continue-root-dialog'),
      backgroundColor: AppColors.panelSolid,
      title: Text(
        continueLabel(target),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 460,
        child: Text(
          'A passagem ${h.shortId} de ${h.agentName} não vem de uma sessão '
          'conhecida. A sessão nova do ${providerWords(target)} abre na raiz '
          'do workspace, com a passagem e sem vínculo. A mensagem inicial '
          'fica no campo até você enviar.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
      actions: [
        SmallButton(
          key: const ValueKey('continue-root-cancel'),
          label: 'Cancelar',
          onTap: () => Navigator.pop(ctx, false),
        ),
        SmallButton(
          key: const ValueKey('continue-root-go'),
          label: continueLabel(target),
          color: AppColors.background,
          background: AppColors.amber,
          border: AppColors.amber,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await startFromHandoff(container, ws, h);
  } catch (e) {
    if (context.mounted) _snack(context, '$e');
  }
}

/// A new session in the workspace root that receives [h] (R13, no link).
Future<String> startFromHandoff(
  ProviderContainer container,
  Workspace ws,
  Handoff h,
) async {
  final target = handoffTarget(h);
  final noSandbox =
      (await container.read(providerAvailabilityProvider(target).future))
          .sandboxWarning !=
      null;
  final mode = convertAccess(
    'acceptEdits',
    target: target,
    worktree: false,
    noSandbox: noSandbox,
  );
  if (mode == null) throw const SessionException(ContinueReasons.noSandboxRoot);
  final record = ContinuationRecord(
    toProvider: target,
    fromProvider: h.fromAgent == 'codex' ? 'codex' : 'claude',
    path: ContinuePath.aiMemory,
    at: DateTime.now(),
    handoff: h,
    sameWorktree: false,
  );
  final id = await container
      .read(sessionManagerProvider.notifier)
      .create(
        NewSessionRequest(
          workspace: ws,
          title: 'Passagem ${h.shortId} (${target == 'codex' ? 'Codex' : 'Claude'})',
          prompt:
              'Continue a partir da passagem ${h.id} do ai-memory, deixada '
              'por ${h.agentName}. Se ela não estiver no seu contexto, '
              'aceite-a com memory_handoff_accept passando handoff_id '
              '"${h.id}". Confira o git status e siga pelos próximos passos.',
          provider: target,
          permissionMode: mode == ClaudePermissionMode.skipPermissions
              ? ClaudePermissionMode.acceptEdits
              : mode,
          useWorktree: false,
          draft: true,
          startEvent: record.toJson(),
        ),
      );
  container.read(selectedSessionProvider.notifier).select(id);
  return id;
}
