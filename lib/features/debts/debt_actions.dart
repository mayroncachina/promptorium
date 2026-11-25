import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../data/db/app_database.dart' show DebtLinksCompanion;
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../../ui/widgets/app_toast.dart';
import '../sessions/widgets/session_style.dart';
import 'debt_files.dart';
import 'debt_service.dart';
import 'widgets/debt_form_dialog.dart';

/// Opens the form filled with [initial] and writes the item (R6, R8, R9,
/// R10, R12). [writeRoot] is the worktree of the spec or session it was
/// born in: the row goes in its commit (R18). Without it, the row goes to
/// the main checkout and the app asks before the own commit. Null when
/// cancelled or failed (a toast says why). [write] replaces the plain
/// [DebtService.create] (an item that also writes its other end, R6, R12).
Future<DebtWritten?> openDebtForm(
  BuildContext context,
  WidgetRef ref, {
  required String repoRoot,
  required DebtDraft initial,
  String? writeRoot,
  DebtLinksCompanion link = const DebtLinksCompanion(),
  String? saveLabel,
  Future<DebtWritten> Function(DebtDraft draft)? write,
}) async {
  final service = ref.read(debtServiceProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final rel = DebtFiles.relPath(service.configOf(repoRoot), initial.kind);
  final branch = writeRoot == null
      ? await _branchOf(repoRoot)
      : await _branchOf(writeRoot);
  if (!context.mounted) return null;
  final draft = await askDebtDraft(
    context,
    ref,
    repoRoot: repoRoot,
    initial: initial,
    saveLabel: saveLabel,
    destination: '$rel${branch == null ? '' : ' · branch $branch'}',
  );
  if (draft == null) return null;
  final dirty = writeRoot == null && await _isDirty(service, repoRoot, rel);
  final DebtWritten written;
  try {
    written = write != null
        ? await write(draft)
        : await service.create(
            repoRoot,
            draft,
            writeRoot: writeRoot,
            link: link,
          );
  } catch (e) {
    messenger?.showAppToast(SnackBar(content: Text('Não deu para gravar: $e')));
    return null;
  }
  if (writeRoot != null) {
    messenger?.showAppToast(
      SnackBar(
        content: Text(
          '${written.code} gravado em $rel da worktree; vai no commit dela.',
        ),
      ),
    );
    return written;
  }
  if (!context.mounted) return written;
  await askOwnCommit(
    context,
    ref,
    repoRoot: repoRoot,
    written: written,
    title: draft.title,
    branch: branch,
    wasDirty: dirty,
  );
  return written;
}

/// Only the form (R6, P2): the draft typed, nothing written. [destination]
/// is the line under the form (the file and the branch, or where it goes
/// later).
Future<DebtDraft?> askDebtDraft(
  BuildContext context,
  WidgetRef ref, {
  required String repoRoot,
  required DebtDraft initial,
  String? saveLabel,
  String? destination,
  bool preview = true,
}) async {
  final service = ref.read(debtServiceProvider);
  String? code;
  if (preview) {
    try {
      code = await service.previewCode(repoRoot, initial.kind);
    } catch (_) {
      code = null;
    }
  }
  if (!context.mounted) return null;
  return showAppDialog<DebtDraft>(
    context: context,
    builder: (_) => DebtFormDialog(
      initial: initial,
      nextCode: code,
      saveLabel: saveLabel,
      destination: destination,
    ),
  );
}

Future<bool> _isDirty(DebtService s, String root, String rel) async {
  try {
    return await s.isDirty(root, rel);
  } catch (_) {
    return false;
  }
}

Future<String?> _branchOf(String root) async {
  try {
    return await GitService(root).currentBranch();
  } catch (_) {
    return null;
  }
}

/// R18, P5: asks before the own commit of an item made by hand; with the
/// file already dirty, only warns.
Future<void> askOwnCommit(
  BuildContext context,
  WidgetRef ref, {
  required String repoRoot,
  required DebtWritten written,
  required String title,
  String? branch,
  required bool wasDirty,
  DebtService? service,
}) async {
  // [service] lets a caller whose widget is gone by now (the strip row of
  // an accepted suggestion) pass it read beforehand.
  final DebtService debts = service ?? ref.read(debtServiceProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (wasDirty) {
    messenger?.showAppToast(
      SnackBar(
        content: Text(
          '${written.code} gravado. O arquivo já tinha alterações; o commit '
          'fica com você.',
        ),
      ),
    );
    return;
  }
  final message = DebtService.commitMessage(written.code, title);
  final ok = await showAppDialog<bool>(
    context: context,
    builder: (_) => DebtCommitDialog(
      code: written.code,
      file: written.relPath,
      branch: branch,
      message: message,
    ),
  );
  if (ok != true) return;
  try {
    final r = await debts.commitOwn(
      repoRoot,
      written.relPath,
      code: written.code,
      title: title,
      wasDirty: false,
    );
    messenger?.showAppToast(
      SnackBar(
        content: Text(switch (r) {
          DebtCommitResult.committed => 'Commit “$message” feito. Sem push.',
          DebtCommitResult.dirty ||
          DebtCommitResult.nothing => 'Nada para commitar.',
        }),
      ),
    );
  } catch (e) {
    messenger?.showAppToast(SnackBar(content: Text('O commit falhou: $e')));
  }
}

/// "Commitar o DT-09?" (R18): only the file, on the main branch, no push.
class DebtCommitDialog extends StatelessWidget {
  const DebtCommitDialog({
    super.key,
    required this.code,
    required this.file,
    required this.message,
    this.branch,
  });

  final String code;
  final String file;
  final String message;
  final String? branch;

  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, -0.3),
    child: Material(
      key: const ValueKey('debt-commit-dialog'),
      color: AppColors.panelSolid,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        width: 480,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Commitar o $code${branch == null ? '' : ' na $branch'}?',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Só o $file entra no commit. O app não faz push.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSolid,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  message,
                  key: const ValueKey('debt-commit-message'),
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallButton(
                    key: const ValueKey('debt-commit-later'),
                    label: 'Agora não',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  AmberButton(
                    key: const ValueKey('debt-commit-ok'),
                    label: 'Commitar',
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
