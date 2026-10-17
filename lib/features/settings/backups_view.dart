import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../sessions/widgets/session_style.dart';

/// Folder of the database (null = unknown, e.g. tests without
/// path_provider).
final databaseFolderProvider = FutureProvider<Directory?>((ref) async {
  try {
    return await databaseDirectory();
  } catch (_) {
    return null;
  }
});

/// Configurações → Banco de dados: the copies made before each migration
/// and "Restaurar" (applied on the next launch).
class BackupsCard extends ConsumerStatefulWidget {
  const BackupsCard({super.key});

  @override
  ConsumerState<BackupsCard> createState() => _BackupsCardState();
}

class _BackupsCardState extends ConsumerState<BackupsCard> {
  String? _pending;

  Future<void> _restore(Directory dir, File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Restaurar backup?', style: TextStyle(fontSize: 16)),
        content: Text(
          'Na próxima vez que o Promptorium abrir, o banco volta a '
          '${f.uri.pathSegments.last}. O banco atual fica guardado como '
          '.antes-da-restauracao.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('backup-restore-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restaurar ao reabrir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await requestRestore(dir, f);
    if (mounted) setState(() => _pending = f.path);
  }

  @override
  Widget build(BuildContext context) {
    final dir = ref.watch(databaseFolderProvider).value;
    if (dir == null) return const SizedBox.shrink();
    final backups = listBackups(dir);
    return AgentCard(
      title: 'Banco de dados · backups',
      children: [
        Text(
          'Antes de cada atualização do banco o app guarda uma cópia em '
          '${dir.path}.',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        if (backups.isEmpty)
          const Text(
            'Nenhum backup ainda.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        for (final f in backups)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    f.uri.pathSegments.last,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                    ),
                  ),
                ),
                SmallButton(
                  label: _pending == f.path ? 'Ao reabrir' : 'Restaurar',
                  onTap: _pending == f.path ? null : () => _restore(dir, f),
                ),
              ],
            ),
          ),
        if (_pending != null)
          const Text(
            'Feche e abra o Promptorium para concluir a restauração.',
            style: TextStyle(fontSize: 12, color: AppColors.amber),
          ),
      ],
    );
  }
}
