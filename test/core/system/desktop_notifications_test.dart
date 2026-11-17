import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/system/desktop_notifications.dart';
import 'package:promptorium/core/system/window_activation.dart';
import 'package:promptorium/core/tray_service.dart';
import 'package:promptorium/features/sessions/app_notifier.dart';

import 'fake_notification_server.dart';

/// SPEC-086 R4, R5, R6: the notification over DBus, against a server on a
/// private bus.

class _Window implements TrayWindow {
  final calls = <String>[];
  bool minimized = true;

  @override
  Future<bool> isVisible() async => true;
  @override
  Future<bool> isMinimized() async => minimized;
  @override
  Future<bool> isFocused() async => false;
  @override
  Future<void> show() async => calls.add('show');
  @override
  Future<void> restore() async => calls.add('restore');
  @override
  Future<void> focus() async => calls.add('focus');
  @override
  Future<void> hide() async => calls.add('hide');
}

NotificationImage _image() =>
    NotificationImage(width: 128, height: 128, rgba: Uint8List(128 * 128 * 4));

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationServer server;
  late DesktopNotifications client;
  final logs = <String>[];

  setUp(() async {
    logs.clear();
    server = FakeNotificationServer();
    await server.start();
    client = DesktopNotifications(client: server.newClient, log: logs.add);
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  test(
    'Notify leva image-data 128 × 128, desktop-entry, urgência e ações',
    () async {
      final id = await client.show(
        DesktopNotification(
          title: 'Ada precisa de você',
          body: 'SPEC-031 · Pagamento com Stripe — quer executar flutter test',
          image: _image(),
          actions: const [clickAction, openAction],
          category: 'im.received',
        ),
      );
      expect(id, 1);
      final call = server.notifies.single;
      expect(call.values[0].asString(), 'Promptorium');
      expect(call.values[2].asString(), 'dev.promptorium.promptorium');
      expect(call.values[3].asString(), 'Ada precisa de você');
      expect(server.lastActions, ['default', 'Abrir', 'abrir', 'Abrir']);
      final hints = server.lastHints;
      expect(hints['desktop-entry']!.asString(), 'dev.promptorium.promptorium');
      expect(hints['urgency']!.asByte(), 1);
      expect(hints['category']!.asString(), 'im.received');
      final image = hints['image-data']!.asStruct();
      expect(image[0].asInt32(), 128);
      expect(image[1].asInt32(), 128);
      expect(image[2].asInt32(), 128 * 4);
      expect(image[3].asBoolean(), isTrue);
      expect(image[4].asInt32(), 8);
      expect(image[5].asInt32(), 4);
      expect(image[6].asByteArray().length, 128 * 128 * 4);
    },
  );

  test(
    'replaces_id atualiza a mesma notificação e CloseNotification fecha',
    () async {
      final id = await client.show(
        const DesktopNotification(title: 'a', body: 'b'),
      );
      final again = await client.show(
        DesktopNotification(title: 'a · 2 pedidos', body: 'c', replacesId: id!),
      );
      expect(again, id);
      expect(server.notifies.last.values[1].asUint32(), id);
      await client.close(id);
      expect(server.closed, [id]);
    },
  );

  test(
    'o corpo é texto puro de até 120 caracteres, escapado com markup',
    () async {
      server.capabilities = ['actions', 'body', 'body-markup'];
      await client.show(
        DesktopNotification(title: 't', body: '<b>${'x' * 200}</b> & y'),
      );
      final body = server.notifies.last.values[4].asString();
      expect(body, startsWith('&lt;b&gt;'));
      expect(body, endsWith('…'));
      expect(notificationText('a' * 200, limit: 120).runes.length, 120);
      expect(notificationText('<i>', markup: false), '<i>');
    },
  );

  test('sem "actions": sai sem botão e com o texto do R5', () async {
    server.capabilities = ['body', 'icon-static'];
    await client.show(
      const DesktopNotification(
        title: 'Ada precisa de você',
        body: 'SPEC-031 · quer executar flutter test',
        actions: [clickAction, openAction],
        noActionsHint: 'Abra o Promptorium para responder',
      ),
    );
    expect(server.lastActions, isEmpty);
    expect(
      server.notifies.last.values[4].asString(),
      endsWith('Abra o Promptorium para responder'),
    );
  });

  test('sem suporte a imagem: sai com o ícone do app', () async {
    server.capabilities = ['actions', 'body'];
    await client.show(
      DesktopNotification(title: 't', body: 'b', image: _image()),
    );
    expect(server.lastHints.containsKey('image-data'), isFalse);
    expect(server.notifies.last.values[2].asString(), notificationDesktopEntry);
  });

  test('sem servidor: nada quebra e registra uma vez', () async {
    final none = DesktopNotifications(
      client: () => DBusClient(DBusAddress.unix(path: '/nonexistent/bus')),
      log: logs.add,
    );
    expect(
      await none.show(const DesktopNotification(title: 't', body: 'b')),
      isNull,
    );
    expect(
      await none.show(const DesktopNotification(title: 't', body: 'b')),
      isNull,
    );
    await none.close(3);
    expect(logs.where((l) => l.contains('indisponíveis')), hasLength(1));
    await none.dispose();
  });

  test('capacidades e nome do servidor', () async {
    final caps = await client.capabilities();
    expect(caps!.actions, isTrue);
    expect(caps.images, isTrue);
    expect(caps.server, 'Falso 1.0');
  });

  group('DbusAppNotifier', () {
    late _Window window;
    late List<MethodCall> native;
    const channel = MethodChannel('promptorium/window/test');

    setUp(() {
      window = _Window();
      native = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            native.add(call);
            return true;
          });
    });

    DbusAppNotifier notifier() => DbusAppNotifier(
      client,
      activation: WindowActivation(window: window, channel: channel),
    );

    test(
      'o clique (default) traz a janela com o token e chama o alvo',
      () async {
        final n = notifier();
        var clicked = 0;
        final id = await n.show(
          'Sessão concluída',
          'x',
          onClick: () => clicked++,
        );
        await server.invoke(id!, 'default', token: 'tok-123');
        await _until(() => clicked > 0);
        expect(clicked, 1);
        expect(window.calls, ['show', 'restore']);
        expect(native.single.method, 'present');
        expect(native.single.arguments, {'token': 'tok-123'});
        await n.dispose();
      },
    );

    test(
      '"abrir" faz o mesmo; sem token cai no focus do window_manager',
      () async {
        final n = notifier();
        var clicked = 0;
        final id = await n.show(
          'Ada precisa de você',
          'x',
          onClick: () => clicked++,
          actions: const [clickAction, openAction],
        );
        await server.invoke(id!, 'abrir');
        await _until(() => clicked > 0);
        expect(clicked, 1);
        expect(native, isEmpty);
        expect(window.calls.last, 'focus');
        await n.dispose();
      },
    );

    test('ações de notificações de outros apps são ignoradas', () async {
      final n = notifier();
      var clicked = 0;
      await n.show('t', 'b', onClick: () => clicked++);
      await server.invoke(99, 'default');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(clicked, 0);
      expect(window.calls, isEmpty);
      await n.dispose();
    });

    test('fechar remove o alvo do clique', () async {
      final n = notifier();
      var clicked = 0;
      final id = await n.show('t', 'b', onClick: () => clicked++);
      await n.close(id!);
      expect(server.closed, [id]);
      await server.invoke(id, 'default');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(clicked, 0);
      await n.dispose();
    });
  });

  test('sob flutter test, o app não fala com o DBus da sessão real', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(appNotifierProvider), isA<NoopAppNotifier>());
  });
}
