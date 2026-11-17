import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../agents/widgets/agent_style.dart';
import '../sessions/restore/restore_service.dart';
import '../sessions/widgets/session_style.dart';
import 'settings_choices.dart';

/// Choices of the group (R14).
const restoreTurnChoices = [10, 20, 50];
const restoreDayChoices = [7, 14, 30];
const restoreSizeChoices = [10, 20, 50, 100];

/// Space of the restore points of a workspace (R14).
final restoreUsageProvider = FutureProvider.autoDispose
    .family<RestoreUsage, int>((ref, workspaceId) async {
      final ws = await ref.read(workspacesRepoProvider).getById(workspaceId);
      if (ws == null) return const RestoreUsage(points: 0, sessions: 0);
      return ref.read(restoreServiceProvider).usage(ws);
    });

/// "38 MB", "512 KB".
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return '${mb >= 10 ? mb.round() : mb.toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// The keys of the group, for "Restaurar padrões da seção".
const restoreSettingKeys = [
  RestoreSettingKeys.enabled,
  RestoreSettingKeys.keepTurns,
  RestoreSettingKeys.maxDays,
  RestoreSettingKeys.maxFileMb,
];

/// Configurações › Sessões › "Pontos de restauração" (SPEC-084 R14).
class RestorePointsSettingsCard extends ConsumerWidget {
  const RestorePointsSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(restoreSettingsProvider);
    final settings = ref.read(appSettingsProvider.notifier);
    final ws = ref.watch(activeWorkspaceProvider);
    const hint = TextStyle(fontSize: 11, color: AppColors.textSecondary);
    const label = TextStyle(fontSize: 13, color: AppColors.text);
    return AgentCard(
      title: 'Pontos de restauração',
      children: [
        const Text('Gravar um ponto antes de cada turno', style: label),
        const SizedBox(height: 2),
        const Text(
          'Guarda os arquivos, inclusive os não rastreados, e o HEAD. Sessões, '
          'etapas de spec e VIBEs.',
          style: hint,
        ),
        const SizedBox(height: 8),
        choices(
          keyPrefix: 'settings-restore-on',
          values: const [('on', 'Ligado'), ('off', 'Desligado')],
          selected: prefs.enabled ? 'on' : 'off',
          onTap: (v) => v == 'on'
              ? settings.remove(RestoreSettingKeys.enabled)
              : settings.set(RestoreSettingKeys.enabled, 'false'),
        ),
        const SizedBox(height: 16),
        const Text('Guardar os últimos turnos por sessão', style: label),
        const SizedBox(height: 2),
        const Text(
          'Os pontos mais velhos saem quando um turno novo começa.',
          style: hint,
        ),
        const SizedBox(height: 8),
        choices(
          keyPrefix: 'settings-restore-turns',
          values: [for (final n in restoreTurnChoices) ('$n', '$n')],
          selected: '${prefs.keepTurns}',
          onTap: (v) => settings.set(RestoreSettingKeys.keepTurns, v),
        ),
        const SizedBox(height: 16),
        const Text('Apagar pontos sem uso depois de', style: label),
        const SizedBox(height: 2),
        const Text(
          'Também saem quando a sessão é integrada, descartada ou apagada.',
          style: hint,
        ),
        const SizedBox(height: 8),
        choices(
          keyPrefix: 'settings-restore-days',
          values: [for (final n in restoreDayChoices) ('$n', '$n dias')],
          selected: '${prefs.maxDays}',
          onTap: (v) => settings.set(RestoreSettingKeys.maxDays, v),
        ),
        const SizedBox(height: 16),
        const Text('Arquivos não rastreados maiores que', style: label),
        const SizedBox(height: 2),
        const Text(
          'Ficam fora do ponto e aparecem como “não volta”.',
          style: hint,
        ),
        const SizedBox(height: 8),
        choices(
          keyPrefix: 'settings-restore-size',
          values: [for (final n in restoreSizeChoices) ('$n', '$n MB')],
          selected: '${prefs.maxFileMb}',
          onTap: (v) => settings.set(RestoreSettingKeys.maxFileMb, v),
        ),
        if (ws != null) ...[const SizedBox(height: 18), _Usage(workspace: ws)],
      ],
    );
  }
}

class _Usage extends ConsumerWidget {
  const _Usage({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(restoreUsageProvider(workspace.id));
    final text = usage.when(
      loading: () => 'Calculando…',
      error: (e, _) => '$e',
      data: (u) {
        final size = u.bytes == null ? '' : '${formatBytes(u.bytes!)} em ';
        return '$size${u.points} ponto${u.points == 1 ? '' : 's'} de '
            '${u.sessions} sess${u.sessions == 1 ? 'ão' : 'ões'} · refs em '
            'refs/promptorium/restore/';
      },
    );
    final empty = usage.value?.points == 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Espaço em ${workspace.name}',
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                key: const ValueKey('settings-restore-usage'),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SmallButton(
          key: const ValueKey('settings-restore-clear'),
          label: 'Apagar todos os pontos deste workspace…',
          color: AppColors.red,
          border: SessionColors.stopBorder,
          onTap: empty ? null : () => _clear(context, ref),
        ),
      ],
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('settings-restore-clear-dialog'),
        backgroundColor: AppColors.panel,
        title: const Text(
          'Apagar todos os pontos?',
          style: TextStyle(fontSize: 16),
        ),
        content: Text(
          'Os pontos de restauração de ${workspace.name} saem do repositório. '
          'Nenhuma sessão vai poder desfazer os turnos já feitos. Os arquivos '
          'e as branches não mudam.',
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('settings-restore-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Apagar os pontos',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(restoreServiceProvider).dropWorkspace(workspace);
    ref.invalidate(restoreUsageProvider(workspace.id));
  }
}
