import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// Desktop notifications straight over DBus (SPEC-086 R4, R5): the
/// `org.freedesktop.Notifications` interface of the Desktop Notifications
/// Specification 1.2 (https://specifications.freedesktop.org/notification-spec/1.2/),
/// with the `image-data` hint, the `default` action (the click),
/// `replaces_id` and the `ActivationToken` signal (spec 1.2, for Wayland).

const _name = 'org.freedesktop.Notifications';
const _interface = 'org.freedesktop.Notifications';
final _path = DBusObjectPath('/org/freedesktop/Notifications');

/// The `.desktop` id of the app (`app_icon` and the `desktop-entry` hint).
const notificationDesktopEntry = 'dev.promptorium.promptorium';

/// The action of a click on the body (spec 1.2, "default").
const notificationDefaultAction = 'default';

/// The only button (R7, R8: no "Aprovar" in the notification).
const notificationOpenAction = 'abrir';

/// The longest body (R16).
const notificationBodyLimit = 120;

/// RGBA pixels, 8 bits per channel, no padding (the `image-data` hint).
@immutable
class NotificationImage {
  const NotificationImage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;

  /// `width × height × 4` bytes.
  final Uint8List rgba;
}

/// One notification to show.
@immutable
class DesktopNotification {
  const DesktopNotification({
    required this.title,
    required this.body,
    this.image,
    this.replacesId = 0,
    this.actions = const [],
    this.noActionsHint,
    this.category,
  });

  final String title;

  /// Plain text (R16): escaped when the server reads markup, cut at
  /// [notificationBodyLimit].
  final String body;
  final NotificationImage? image;

  /// The notification this one replaces (R9), 0 = a new one.
  final int replacesId;

  /// `(key, label)` pairs; [notificationDefaultAction] is the click.
  final List<(String, String)> actions;

  /// What ends the body when the server has no actions (R5).
  final String? noActionsHint;

  /// The `category` hint (`im.received` for "precisa de você").
  final String? category;
}

/// What the server can do (`GetCapabilities`).
@immutable
class NotificationCapabilities {
  const NotificationCapabilities(this.values, {this.server = ''});

  final Set<String> values;

  /// `GNOME Shell 47` (`GetServerInformation`), empty when unknown.
  final String server;

  bool get actions => values.contains('actions');
  bool get markup => values.contains('body-markup');

  /// `image-data` is shown: `icon-static` / `icon-multi` (spec 1.2) or
  /// `body-images`.
  bool get images =>
      values.contains('icon-static') ||
      values.contains('icon-multi') ||
      values.contains('body-images');
}

/// A signal of the server about one of our notifications.
sealed class NotificationEvent {
  const NotificationEvent(this.id);
  final int id;
}

/// `ActionInvoked`: the click ([notificationDefaultAction]) or a button.
class NotificationActionInvoked extends NotificationEvent {
  const NotificationActionInvoked(super.id, this.action);
  final String action;
}

/// `ActivationToken`: sent right before [NotificationActionInvoked], the
/// token that lets the window take the focus on Wayland (R6).
class NotificationActivationToken extends NotificationEvent {
  const NotificationActivationToken(super.id, this.token);
  final String token;
}

/// `NotificationClosed`.
class NotificationClosed extends NotificationEvent {
  const NotificationClosed(super.id, this.reason);

  /// 1 expired, 2 dismissed by the user, 3 closed by `CloseNotification`,
  /// 4 undefined.
  final int reason;
}

/// Plain text for the server: runs of spaces collapsed, cut at [limit]
/// runes with "…", escaped when the server reads markup (R16).
String notificationText(String text, {int? limit, bool markup = false}) {
  var t = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  if (limit != null) {
    final runes = t.runes.toList();
    if (runes.length > limit) {
      t = '${String.fromCharCodes(runes.take(limit - 1)).trimRight()}…';
    }
  }
  if (!markup) return t;
  return t
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// The DBus client of the notification server. Never throws: without a
/// session bus or a server, [show] returns null and the app logs it once
/// (R5).
class DesktopNotifications {
  DesktopNotifications({
    DBusClient Function()? client,
    void Function(String message)? log,
  }) : _clientFactory = client ?? DBusClient.session,
       _log = log ?? debugPrint;

  final DBusClient Function() _clientFactory;
  final void Function(String message) _log;
  final _events = StreamController<NotificationEvent>.broadcast();
  final _subscriptions = <StreamSubscription<DBusSignal>>[];
  DBusClient? _client;
  Future<NotificationCapabilities?>? _caps;
  bool _unavailableLogged = false;

  /// The signals about the notifications of this app (and others': the ids
  /// tell them apart).
  Stream<NotificationEvent> get events => _events.stream;

  /// What the server can do; null = no server (read once, R5).
  Future<NotificationCapabilities?> capabilities() => _caps ??= _connect();

  Future<NotificationCapabilities?> _connect() async {
    try {
      final client = _clientFactory();
      _client = client;
      final caps = await client.callMethod(
        destination: _name,
        path: _path,
        interface: _interface,
        name: 'GetCapabilities',
        replySignature: DBusSignature('as'),
      );
      var server = '';
      try {
        final info = await client.callMethod(
          destination: _name,
          path: _path,
          interface: _interface,
          name: 'GetServerInformation',
          replySignature: DBusSignature('ssss'),
        );
        final v = info.values;
        server = '${v[0].asString()} ${v[2].asString()}'.trim();
      } catch (_) {}
      _listen(client);
      return NotificationCapabilities(
        caps.values.first.asStringArray().toSet(),
        server: server,
      );
    } catch (e) {
      _unavailable(e);
      final client = _client;
      _client = null;
      if (client != null) unawaited(client.close().catchError((_) {}));
      return null;
    }
  }

  void _unavailable(Object e) {
    if (_unavailableLogged) return;
    _unavailableLogged = true;
    _log('notificações do sistema indisponíveis: $e');
  }

  void _listen(DBusClient client) {
    Stream<DBusSignal> signal(String name, String signature) =>
        DBusSignalStream(
          client,
          interface: _interface,
          name: name,
          path: _path,
          signature: DBusSignature(signature),
        );
    void add(NotificationEvent e) {
      if (!_events.isClosed) _events.add(e);
    }

    void onError(Object e) => _log('notificações: sinal inválido — $e');
    _subscriptions.addAll([
      signal('ActionInvoked', 'us').listen(
        (s) => add(
          NotificationActionInvoked(
            s.values[0].asUint32(),
            s.values[1].asString(),
          ),
        ),
        onError: onError,
      ),
      signal('ActivationToken', 'us').listen(
        (s) => add(
          NotificationActivationToken(
            s.values[0].asUint32(),
            s.values[1].asString(),
          ),
        ),
        onError: onError,
      ),
      signal('NotificationClosed', 'uu').listen(
        (s) => add(
          NotificationClosed(s.values[0].asUint32(), s.values[1].asUint32()),
        ),
        onError: onError,
      ),
    ]);
  }

  /// Shows [n] and returns its id (the same as `replacesId` when the server
  /// replaced it); null when there is no server or the call failed.
  Future<int?> show(DesktopNotification n) async {
    final caps = await capabilities();
    final client = _client;
    if (caps == null || client == null) return null;
    final actions = caps.actions ? n.actions : const <(String, String)>[];
    var body = n.body;
    if (!caps.actions && n.actions.isNotEmpty && n.noActionsHint != null) {
      body = '$body · ${n.noActionsHint}';
    }
    final image = caps.images ? n.image : null;
    try {
      final reply = await client.callMethod(
        destination: _name,
        path: _path,
        interface: _interface,
        name: 'Notify',
        values: [
          const DBusString('Promptorium'),
          DBusUint32(n.replacesId),
          const DBusString(notificationDesktopEntry),
          DBusString(notificationText(n.title, limit: 80)),
          DBusString(
            notificationText(
              body,
              limit: notificationBodyLimit,
              markup: caps.markup,
            ),
          ),
          DBusArray.string([
            for (final (key, label) in actions) ...[key, label],
          ]),
          DBusDict.stringVariant({
            'desktop-entry': const DBusString(notificationDesktopEntry),
            // Never critical (R14): the server's "Não perturbe" decides.
            'urgency': const DBusByte(1),
            if (n.category != null) 'category': DBusString(n.category!),
            if (image != null) 'image-data': imageDataValue(image),
          }),
          const DBusInt32(-1),
        ],
        replySignature: DBusSignature('u'),
      );
      return reply.values.first.asUint32();
    } catch (e) {
      _log('notificação: $e');
      return null;
    }
  }

  /// Closes the notification [id] (R12). Never throws.
  Future<void> close(int id) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.callMethod(
        destination: _name,
        path: _path,
        interface: _interface,
        name: 'CloseNotification',
        values: [DBusUint32(id)],
        replySignature: DBusSignature(''),
      );
    } catch (e) {
      _log('notificação: falha ao fechar — $e');
    }
  }

  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _events.close();
    final client = _client;
    _client = null;
    await client?.close();
  }
}

/// The `image-data` hint: `(iiibiiay)` — width, height, rowstride, has
/// alpha, bits per sample, channels, pixels (spec 1.2, "Icons and Images").
DBusValue imageDataValue(NotificationImage image) => DBusStruct([
  DBusInt32(image.width),
  DBusInt32(image.height),
  DBusInt32(image.width * 4),
  const DBusBoolean(true),
  const DBusInt32(8),
  const DBusInt32(4),
  DBusArray.byte(image.rgba),
]);
