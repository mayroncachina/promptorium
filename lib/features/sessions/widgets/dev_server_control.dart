import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dev/dev_server.dart';
import '../../../ui/theme/tokens.dart';
import '../session_dev.dart';
import 'preview_tab.dart' show devStatusColor, devStatusLabel;
import 'session_style.dart';

/// Opens [url] in the user's browser (`xdg-open`).
Future<void> openUrl(Uri url) async {
  try {
    await Process.run('xdg-open', ['$url']);
  } catch (e) {
    debugPrint('xdg-open preview: $e');
  }
}

/// The server control of the session header (SPEC-051 R2): state pill and
/// the buttons of each state.
class DevServerControl extends ConsumerWidget {
  const DevServerControl({
    super.key,
    required this.dev,
    required this.onShowLogs,
    this.onOpenPreview,
    this.extra = const [],
  });

  final SessionDev dev;

  /// "Ver logs": the Preview tab.
  final VoidCallback onShowLogs;

  /// "Abrir preview" (null = `xdg-open` of the server's page).
  final void Function(DevServer server)? onOpenPreview;

  /// Buttons shown while the server is up, between "Abrir preview" and
  /// "Parar servidor" ("Apontar").
  final List<Widget> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(devServerTickProvider(dev.worktree));
    final s = ref.watch(devServerProvider(dev.worktree));
    final color = devStatusColor(s.status);
    final pill = Container(
      key: const ValueKey('dev-status'),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (s.status) {
              DevServerStatus.stopped => Icons.stop_circle_outlined,
              DevServerStatus.starting => Icons.hourglass_top,
              DevServerStatus.running => Icons.circle,
              DevServerStatus.failed => Icons.close,
            },
            size: s.status == DevServerStatus.running ? 8 : 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            devStatusLabel(s),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
    void start() => s.start(
      config: dev.config,
      port: dev.port,
      environment: dev.environment,
    );
    // SmallButton fills the width a Wrap offers: each one keeps its own.
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final w in [pill, ...buttons(s, start)]) IntrinsicWidth(child: w),
      ],
    );
  }

  List<Widget> buttons(DevServer s, VoidCallback start) => [
    ...switch (s.status) {
      DevServerStatus.stopped => [
        SmallButton(
          key: const ValueKey('dev-start'),
          label: 'Iniciar servidor',
          icon: Icons.play_arrow,
          color: AppColors.teal,
          onTap: start,
        ),
      ],
      DevServerStatus.starting => [
        SmallButton(
          key: const ValueKey('dev-stop'),
          label: 'Parar',
          onTap: s.stop,
        ),
      ],
      DevServerStatus.running => [
        SmallButton(
          key: const ValueKey('dev-open-preview'),
          label: 'Abrir preview',
          onTap: () => onOpenPreview == null
              ? s.url == null
                    ? null
                    : openUrl(s.url!)
              : onOpenPreview!(s),
        ),
        ...extra,
        SmallButton(
          key: const ValueKey('dev-stop'),
          label: s.external ? 'Esquecer' : 'Parar servidor',
          onTap: s.stop,
        ),
      ],
      DevServerStatus.failed => [
        SmallButton(
          key: const ValueKey('dev-show-logs'),
          label: 'Ver logs',
          onTap: onShowLogs,
        ),
      ],
    },
  ];
}
