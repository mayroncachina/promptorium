import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/secrets/secret_guard.dart';
import '../../core/secrets/secret_scanner.dart';
import '../../data/providers.dart';
import '../../ui/widgets/app_dialog.dart';
import '../../ui/widgets/app_toast.dart';
import '../../ui/widgets/secret_findings_dialog.dart';
import 'secret_actions.dart';
import 'secret_blocks.dart';

/// Shows the window of findings of a commit / push of the app or of the
/// Código (SPEC-085 R5, R6, R9, R11). Returns true when nothing is left:
/// the caller redoes the action.
Future<bool> resolveSecretsFound(
  BuildContext context,
  WidgetRef ref,
  SecretsFound e, {
  bool manual = false,
  String? title,
}) async {
  final actions = ref.read(secretActionsProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ws = await ref.read(workspacesRepoProvider).getById(e.workspaceId);
  if (!context.mounted) return false;

  Future<void> open(SecretFinding f) async {
    final why = await actions.open(e.worktree, f);
    if (why != null) {
      messenger?.showAppToast(SnackBar(content: Text(why)));
    }
  }

  final ok = await showAppDialog<bool>(
    context: context,
    builder: (dialog) => SecretFindingsDialog(
      findings: e.findings,
      manual: manual,
      push: e.kind == SecretCheckKind.push,
      title: title,
      onOpen: (f) async {
        Navigator.of(dialog).pop(false);
        await open(f);
      },
      onRemove: (f) async {
        if (f.isFile && e.kind != SecretCheckKind.push) {
          await actions.untrackFile(e.worktree, f.path);
          return true;
        }
        // The app does not rewrite code (nor history): the file opens at
        // the line.
        Navigator.of(dialog).pop(false);
        await open(f);
        return false;
      },
      onIgnore: (f) async {
        final choice = await showSecretWaiverDialog(
          dialog,
          finding: f,
          workspaceName: ws?.name ?? 'este workspace',
          manual: manual,
          confirmLabel: 'Ignorar e continuar',
        );
        if (choice == null) return false;
        await actions.waive(
          workspaceId: e.workspaceId,
          finding: f,
          reason: choice.reason,
          byValue: choice.byValue,
          origin: manual ? 'manual' : 'app',
        );
        return true;
      },
    ),
  );
  if (ok == true) {
    ref.read(secretBlocksProvider.notifier).remove(appSecretKey(e.worktree));
  }
  return ok == true;
}

/// Runs [action]; when the Vigia de segredos stops it, shows the window and
/// runs it again once everything was handled. Null = the person closed the
/// window with findings left.
Future<T?> withSecretGuard<T>(
  BuildContext context,
  WidgetRef ref,
  Future<T> Function() action, {
  bool manual = false,
  String? title,
}) async {
  for (var round = 0; round < 5; round++) {
    try {
      return await action();
    } on SecretsFound catch (e) {
      if (!context.mounted) return null;
      if (!await resolveSecretsFound(
        context,
        ref,
        e,
        manual: manual,
        title: title,
      )) {
        return null;
      }
      if (!context.mounted) return null;
    }
  }
  return null;
}

/// The window from a request "Segredo encontrado" of the app (Início).
Future<void> openPendingSecret(
  BuildContext context,
  WidgetRef ref,
  PendingSecret p,
) async {
  final wt = p.worktree;
  if (wt == null) return;
  await resolveSecretsFound(
    context,
    ref,
    SecretsFound(
      findings: p.findings,
      kind: p.action == 'push' ? SecretCheckKind.push : SecretCheckKind.commit,
      worktree: wt,
      workspaceId: p.workspaceId,
    ),
  );
}
