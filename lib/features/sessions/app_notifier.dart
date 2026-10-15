import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

/// Native desktop notifications (overridden in tests).
abstract class AppNotifier {
  /// Shows a notification; [onClick] runs after the window is brought to the
  /// front.
  Future<void> show(String title, String body, {VoidCallback? onClick});
}

/// `local_notifier` 0.1.6 (README "Usage"); `localNotifier.setup` runs in
/// `main`. Needs `libnotify` on Linux. Failures are only logged.
class LocalAppNotifier implements AppNotifier {
  /// Keeps shown notifications alive so their callbacks are not collected.
  final List<LocalNotification> _shown = [];

  @override
  Future<void> show(String title, String body, {VoidCallback? onClick}) async {
    try {
      final n = LocalNotification(title: title, body: body);
      n.onClick = () async {
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (e) {
          debugPrint('notificação: falha ao focar a janela — $e');
        }
        onClick?.call();
      };
      n.onClose = (_) => _shown.remove(n);
      _shown.add(n);
      if (_shown.length > 20) _shown.removeAt(0);
      await n.show();
    } catch (e) {
      debugPrint('notificação: $e');
    }
  }
}

/// Does nothing (tests / when notifications are unavailable).
class NoopAppNotifier implements AppNotifier {
  const NoopAppNotifier();

  @override
  Future<void> show(String title, String body, {VoidCallback? onClick}) async {}
}

final appNotifierProvider = Provider<AppNotifier>((ref) => LocalAppNotifier());
