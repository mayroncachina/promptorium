import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/desktop_notifications.dart';
import '../../core/system/window_activation.dart';
import '../../core/tray_backend_native.dart' show WindowManagerTrayWindow;

export '../../core/system/desktop_notifications.dart' show NotificationImage;

/// The click: no button, it is the body of the notification (spec 1.2).
const clickAction = (notificationDefaultAction, 'Abrir');

/// The "Abrir" button of the notifications that need the person (R7).
const openAction = (notificationOpenAction, 'Abrir');

/// Native desktop notifications (overridden in tests).
abstract class AppNotifier {
  /// Shows a notification and returns its id (null when nothing was shown).
  /// [onClick] runs after the window is brought to the front. [replaces]
  /// updates a notification already open (SPEC-086 R9); [image] goes in the
  /// `image-data` hint (R3).
  Future<int?> show(
    String title,
    String body, {
    VoidCallback? onClick,
    NotificationImage? image,
    int? replaces,
    List<(String, String)> actions = const [clickAction],
    String? noActionsHint,
    String? category,
  });

  /// Closes the notification [id] (R12).
  Future<void> close(int id);
}

/// Notifications over DBus (SPEC-086 R4): the click (`default`) and "Abrir"
/// bring the window to the front with the activation token (R6), then run
/// the notification's `onClick`. Failures are only logged.
class DbusAppNotifier implements AppNotifier {
  DbusAppNotifier(this.server, {required this.activation}) {
    _events = server.events.listen(_onEvent);
  }

  final DesktopNotifications server;
  final WindowActivation activation;
  late final StreamSubscription<NotificationEvent> _events;

  /// The callback of each notification still open (the newest 50).
  final _clicks = <int, VoidCallback?>{};
  final _tokens = <int, String>{};

  @override
  Future<int?> show(
    String title,
    String body, {
    VoidCallback? onClick,
    NotificationImage? image,
    int? replaces,
    List<(String, String)> actions = const [clickAction],
    String? noActionsHint,
    String? category,
  }) async {
    final id = await server.show(
      DesktopNotification(
        title: title,
        body: body,
        image: image,
        replacesId: replaces ?? 0,
        actions: actions,
        noActionsHint: noActionsHint,
        category: category,
      ),
    );
    if (id == null) return null;
    _clicks.remove(id);
    _clicks[id] = onClick;
    if (_clicks.length > 50) _clicks.remove(_clicks.keys.first);
    return id;
  }

  @override
  Future<void> close(int id) async {
    _clicks.remove(id);
    _tokens.remove(id);
    await server.close(id);
  }

  Future<void> _onEvent(NotificationEvent e) async {
    switch (e) {
      case NotificationActivationToken(:final id, :final token):
        if (_clicks.containsKey(id)) _tokens[id] = token;
      case NotificationActionInvoked(:final id, :final action):
        if (!_clicks.containsKey(id)) return;
        if (action != notificationDefaultAction &&
            action != notificationOpenAction) {
          return;
        }
        final onClick = _clicks[id];
        await activation.present(_tokens.remove(id));
        try {
          onClick?.call();
        } catch (err) {
          debugPrint('notificação: falha ao abrir — $err');
        }
      case NotificationClosed(:final id):
        _clicks.remove(id);
        _tokens.remove(id);
    }
  }

  Future<void> dispose() => _events.cancel();
}

/// Does nothing (tests / when notifications are unavailable).
class NoopAppNotifier implements AppNotifier {
  const NoopAppNotifier();

  @override
  Future<int?> show(
    String title,
    String body, {
    VoidCallback? onClick,
    NotificationImage? image,
    int? replaces,
    List<(String, String)> actions = const [clickAction],
    String? noActionsHint,
    String? category,
  }) async => null;

  @override
  Future<void> close(int id) async {}
}

/// The DBus client of the notification server, one for the app.
final desktopNotificationsProvider = Provider<DesktopNotifications>((ref) {
  final server = DesktopNotifications();
  ref.onDispose(() => unawaited(server.dispose()));
  return server;
});

/// Under `flutter test` nothing reaches the real session bus.
final appNotifierProvider = Provider<AppNotifier>((ref) {
  if (!Platform.isLinux || Platform.environment.containsKey('FLUTTER_TEST')) {
    return const NoopAppNotifier();
  }
  final notifier = DbusAppNotifier(
    ref.watch(desktopNotificationsProvider),
    activation: WindowActivation(window: const WindowManagerTrayWindow()),
  );
  ref.onDispose(() => unawaited(notifier.dispose()));
  return notifier;
});
