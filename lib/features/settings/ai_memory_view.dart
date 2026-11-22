import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/memory/ai_memory_cli.dart';
import '../../core/memory/ai_memory_state.dart';
import '../../ui/theme/tokens.dart';
import '../sessions/widgets/session_style.dart';
import 'ai_memory_links.dart';

/// Opens a URL or a folder outside the app (`xdg-open`). Tests replace it.
typedef AiMemoryOpener = Future<void> Function(String target);

final aiMemoryOpenerProvider = Provider<AiMemoryOpener>(
  (ref) => (target) async {
    try {
      await Process.run('xdg-open', [target]);
    } catch (e) {
      debugPrint('ai-memory: xdg-open falhou: $e');
    }
  },
);

/// Color of the status dot of each state.
Color aiMemoryStatusColor(AiMemoryStatus s) => switch (s) {
  AiMemoryStatus.connected => AppColors.teal,
  AiMemoryStatus.outdated => AppColors.yellow,
  AiMemoryStatus.serverDown => AppColors.red,
  AiMemoryStatus.notInstalled => AppColors.textMuted,
};

/// Bordered panel of the ai-memory screens.
class AiMemoryBox extends StatelessWidget {
  const AiMemoryBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = AppColors.panel,
    this.border = AppColors.border,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: child,
  );
}

/// A command to copy (mono, dark box) — the app only shows it (R1, R5).
class AiMemoryCommandBox extends StatelessWidget {
  const AiMemoryCommandBox(this.command, {super.key});

  final String command;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: SessionColors.terminalPanel,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: SelectableText(
      command,
      style: const TextStyle(
        fontSize: 12,
        height: 1.5,
        fontFamily: AppFonts.mono,
        color: AppColors.text,
      ),
    ),
  );
}

/// Copies [text] and confirms with a snack bar.
Future<void> copyAiMemoryText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text('Copiado.'), duration: Duration(seconds: 2)),
  );
}

/// "~/.local/bin/ai-memory" for paths under HOME.
String aiMemoryTildePath(String path, Map<String, String> env) {
  final home = env['HOME'];
  if (home != null && home.isNotEmpty && path.startsWith('$home/')) {
    return '~${path.substring(home.length)}';
  }
  return path;
}

/// Configurações → Memória (ai-memory) (SPEC-098 P8, mock 2).
class AiMemorySettingsView extends ConsumerWidget {
  const AiMemorySettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detection = ref.watch(aiMemoryDetectionProvider);
    final d = detection.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d == null)
          AiMemoryBox(
            child: Text(
              detection.hasError
                  ? 'Não foi possível verificar o ai-memory.'
                  : 'Procurando o ai-memory…',
              key: const ValueKey('ai-memory-checking'),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          )
        else ...[
          AiMemoryStatusCard(detection: d),
          if (d.installed) ...[
            const SizedBox(height: 12),
            const AiMemoryLinksView(),
          ],
        ],
      ],
    );
  }
}

/// Version, state, binary and server, with the fix of each bad state and
/// "Verificar de novo" (R1, R2; mocks 2 and 4).
class AiMemoryStatusCard extends ConsumerWidget {
  const AiMemoryStatusCard({super.key, required this.detection});

  final AiMemoryDetection detection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = detection;
    final env = ref.watch(aiMemoryEnvironmentProvider);
    final fix = d.fixCommand;
    final recheck = SmallButton(
      key: const ValueKey('ai-memory-recheck'),
      label: 'Verificar de novo',
      icon: Icons.refresh,
      onTap: () => recheckAiMemory(ref),
    );
    final github = SmallButton(
      key: const ValueKey('ai-memory-github'),
      label: 'Projeto no GitHub',
      icon: Icons.open_in_new,
      onTap: () => ref.read(aiMemoryOpenerProvider)(aiMemoryRepoUrl),
    );
    return AiMemoryBox(
      key: ValueKey('ai-memory-status-${d.status.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Dot(aiMemoryStatusColor(d.status)),
              const SizedBox(width: 10),
              Text(
                d.installed ? d.title : 'ai-memory',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 8),
              if (d.status == AiMemoryStatus.outdated)
                const AiMemoryPill('versão antiga', AppColors.yellow)
              else
                Text(
                  d.status.label,
                  key: const ValueKey('ai-memory-status-label'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              if (d.status == AiMemoryStatus.connected) ...[
                Flexible(
                  child: Text(
                    '  ·  ${aiMemoryTildePath(d.executable!, env)}  ·  '
                    '${d.serverUrl}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: AppFonts.mono,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              if (d.status == AiMemoryStatus.connected) ...[
                const SizedBox(width: 8),
                recheck,
                const SizedBox(width: 6),
                github,
              ],
            ],
          ),
          if (d.status != AiMemoryStatus.connected) ...[
            const SizedBox(height: 8),
            Text(
              d.message,
              key: const ValueKey('ai-memory-status-message'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            if (fix != null) ...[
              const SizedBox(height: 10),
              AiMemoryCommandBox(fix, key: const ValueKey('ai-memory-fix')),
              const SizedBox(height: 10),
              Row(
                children: [
                  SmallButton(
                    key: const ValueKey('ai-memory-copy-fix'),
                    label: 'Copiar',
                    icon: Icons.copy,
                    onTap: () => copyAiMemoryText(context, fix),
                  ),
                  if (!d.installed) ...[const SizedBox(width: 6), github],
                  const Spacer(),
                  recheck,
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Small rounded state label ("ligado", "aguardando confiança").
class AiMemoryPill extends StatelessWidget {
  const AiMemoryPill(this.text, this.color, {super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color.withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );
}
