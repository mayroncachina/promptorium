import 'dart:io';

import 'package:dbus/dbus.dart';

/// A notification server on a private DBus (SPEC-086 tests): the real
/// protocol, without the user's session bus.
class FakeNotificationServer extends DBusObject {
  FakeNotificationServer({
    this.capabilities = const ['actions', 'body', 'icon-static'],
  }) : super(DBusObjectPath('/org/freedesktop/Notifications'));

  List<String> capabilities;
  final notifies = <DBusMethodCall>[];
  final closed = <int>[];
  int _next = 1;

  late final DBusServer _server;
  late final DBusClient _owner;
  late final DBusAddress address;

  /// Starts the bus and takes `org.freedesktop.Notifications` on it.
  Future<void> start() async {
    _server = DBusServer();
    address = await _server.listenAddress(
      DBusAddress.unix(dir: Directory.systemTemp),
    );
    _owner = DBusClient(address);
    await _owner.requestName('org.freedesktop.Notifications');
    await _owner.registerObject(this);
  }

  Future<void> stop() async {
    await _owner.close();
    await _server.close();
  }

  /// A client of the same bus, as the app would have.
  DBusClient newClient() => DBusClient(address);

  /// The hints of the newest `Notify`.
  Map<String, DBusValue> get lastHints =>
      notifies.last.values[6].asStringVariantDict();

  List<String> get lastActions =>
      notifies.last.values[5].asStringArray().toList();

  Future<void> invoke(int id, String action, {String? token}) async {
    if (token != null) {
      await emitSignal('org.freedesktop.Notifications', 'ActivationToken', [
        DBusUint32(id),
        DBusString(token),
      ]);
    }
    await emitSignal('org.freedesktop.Notifications', 'ActionInvoked', [
      DBusUint32(id),
      DBusString(action),
    ]);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'org.freedesktop.Notifications') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (call.name) {
      case 'GetCapabilities':
        return DBusMethodSuccessResponse([DBusArray.string(capabilities)]);
      case 'GetServerInformation':
        return DBusMethodSuccessResponse(const [
          DBusString('Falso'),
          DBusString('teste'),
          DBusString('1.0'),
          DBusString('1.2'),
        ]);
      case 'Notify':
        notifies.add(call);
        final replaces = call.values[1].asUint32();
        return DBusMethodSuccessResponse([
          DBusUint32(replaces != 0 ? replaces : _next++),
        ]);
      case 'CloseNotification':
        closed.add(call.values[0].asUint32());
        return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}
