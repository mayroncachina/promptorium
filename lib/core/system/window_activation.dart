import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../tray_service.dart' show TrayWindow;

/// Brings the window to the front after a click on a notification
/// (SPEC-086 R6). On Wayland the focus needs the activation token of the
/// `ActivationToken` signal (xdg-activation); the native side
/// (`linux/runner/my_application.cc`, channel `promptorium/window`) passes
/// it to GTK with `gtk_window_set_startup_id` and `gtk_window_present`.
/// Without a token, or without the channel, it falls back to window_manager's
/// show and focus.
class WindowActivation {
  WindowActivation({
    required this.window,
    this.channel = const MethodChannel('promptorium/window'),
    void Function(String message)? log,
  }) : _log = log ?? debugPrint;

  final TrayWindow window;
  final MethodChannel channel;
  final void Function(String message) _log;

  /// Shows, restores and focuses the window, with [token] when there is one.
  Future<void> present(String? token) async {
    try {
      await window.show();
      if (await window.isMinimized()) await window.restore();
    } catch (e) {
      _log('janela: falha ao mostrar — $e');
    }
    if (token != null && token.isNotEmpty) {
      try {
        await channel.invokeMethod<bool>('present', {'token': token});
        return;
      } catch (e) {
        _log('janela: token de ativação recusado — $e');
      }
    }
    try {
      await window.focus();
    } catch (e) {
      _log('janela: falha ao focar — $e');
    }
  }
}
