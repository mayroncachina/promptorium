import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../spec_service.dart';

/// "Arquivar" / "Desarquivar" a finished spec.
Future<void> archiveSpecAction(
  BuildContext context,
  WidgetRef ref,
  Spec spec, {
  bool restore = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
    if (ws == null) return;
    await ref.read(specServiceProvider).archive(ws, spec, restore: restore);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          restore ? '${spec.code} desarquivada.' : '${spec.code} arquivada.',
        ),
      ),
    );
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// "Excluir" a spec never executed: asks first (the file goes to the trash).
Future<void> deleteSpecAction(
  BuildContext context,
  WidgetRef ref,
  Spec spec,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
  if (ws == null || !context.mounted) return;
  final service = ref.read(specServiceProvider);
  final dependents = await service.dependentsOf(ws, spec);
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(
        'Excluir ${spec.code}?',
        style: const TextStyle(fontSize: 15),
      ),
      content: Text(
        'O arquivo ${spec.path} vai para a lixeira.'
        '${dependents.isEmpty ? '' : '\n\nDepende dela: ${dependents.join(', ')} (a dependência continuará escrita nelas).'}',
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('spec-delete-confirm'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await service.delete(ws, spec);
    messenger?.showSnackBar(SnackBar(content: Text('${spec.code} excluída.')));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
  }
}
