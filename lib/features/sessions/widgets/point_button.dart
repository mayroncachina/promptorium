import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dev/dev_server.dart';
import '../../../core/dev/preview_browser.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../picked_elements.dart';
import '../session_dev.dart';
import 'session_style.dart';

/// "Abrir preview" with the app's Chromium (R6); without Chrome / Chromium,
/// `xdg-open` (R9).
Future<void> openPreviewWindow(
  WidgetRef ref,
  BuildContext context,
  DevServer server,
) async {
  final url = server.url;
  if (url == null) return;
  try {
    await ref
        .read(previewBrowserProvider)
        .open(worktree: server.worktree, url: url, server: server);
  } catch (e) {
    if (context.mounted) _toast(context, '$e');
  }
}

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showAppToast(SnackBar(content: Text(msg)));

/// "Apontar" (R7): turns the picker on in the preview window; the element
/// clicked goes to the session's composer (R8). A second click turns it off.
/// Off, with the reason, without Chrome / Chromium (R9).
class PointButton extends ConsumerWidget {
  const PointButton({
    super.key,
    required this.sessionId,
    required this.dev,
    this.onPicked,
  });

  final String sessionId;
  final SessionDev dev;

  /// After an element was attached (the session shows the Timeline).
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(previewBrowserTickProvider);
    final browser = ref.watch(previewBrowserProvider);
    final reason = ref.watch(previewUnavailableProvider).value;
    final picking = browser.isPicking(dev.worktree);
    final button = picking
        ? SmallButton(
            key: const ValueKey('dev-point'),
            label: 'Apontando…',
            icon: Icons.near_me_outlined,
            color: AppColors.amber,
            border: AppColors.amber,
            onTap: () => browser.cancelPick(dev.worktree),
          )
        : SmallButton(
            key: const ValueKey('dev-point'),
            label: 'Apontar',
            icon: Icons.near_me_outlined,
            color: reason == null ? AppColors.onAmber : AppColors.textMuted,
            background: reason == null ? AppColors.amber : AppColors.panel,
            border: reason == null ? AppColors.amber : AppColors.border,
            onTap: reason == null ? () => _point(context, ref) : null,
          );
    return Tooltip(
      message:
          reason ??
          (picking
              ? 'Clique num elemento na janela do preview · Esc ou Apontar '
                    'cancela'
              : 'Clique num elemento do preview para anexá-lo ao pedido'),
      child: button,
    );
  }

  Future<void> _point(BuildContext context, WidgetRef ref) => pointElement(
    ref,
    context,
    sessionId: sessionId,
    dev: dev,
    then: onPicked,
  );
}

/// "Apontar" / "Apontar outro": the element clicked in the preview goes to
/// the composer of [sessionId] (R7, R8).
Future<void> pointElement(
  WidgetRef ref,
  BuildContext context, {
  required String sessionId,
  required SessionDev dev,
  VoidCallback? then,
}) async {
  final server = ref.read(devServerProvider(dev.worktree));
  final url = server.url;
  if (url == null || !server.isUp) {
    _toast(context, 'Inicie o servidor antes de apontar.');
    return;
  }
  try {
    final el = await ref
        .read(previewBrowserProvider)
        .pick(worktree: dev.worktree, url: url, server: server);
    if (el == null) return;
    ref.read(pickedElementsProvider(sessionId).notifier).add(el);
    then?.call();
    if (context.mounted) _toast(context, '${el.selector} anexado ao pedido');
  } catch (e) {
    if (context.mounted) _toast(context, '$e');
  }
}
