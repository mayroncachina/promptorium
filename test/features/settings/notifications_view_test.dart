import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/system/desktop_notifications.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/notifications/agent_alerts.dart';
import 'package:promptorium/features/sessions/app_notifier.dart';
import 'package:promptorium/features/settings/notifications_view.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// SPEC-086 R15: Configurações › Notificações.

class _Notifier implements AppNotifier {
  final shown = <(String, String, NotificationImage?)>[];
  final clicks = <VoidCallback?>[];

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
    shown.add((title, body, image));
    clicks.add(onClick);
    return shown.length;
  }

  @override
  Future<void> close(int id) async {}
}

void main() {
  test('a seção é achada pelas palavras e marca quando algo foi desligado', () {
    expect(filterSections('robô'), contains(SettingsSection.notifications));
    expect(
      sectionChanged(SettingsSection.notifications, const {}, null),
      isFalse,
    );
    expect(
      sectionChanged(SettingsSection.notifications, const {
        AlertSettingKeys.reminder: 'false',
      }, null),
      isTrue,
    );
  });

  test('a linha do servidor', () {
    expect(serverLine(null), contains('Sem servidor'));
  });

  Future<(ProviderContainer, _Notifier)> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notifier = _Notifier();
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        appNotifierProvider.overrideWithValue(notifier),
      ],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() => c.read(appSettingsProvider.notifier).load());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(child: NotificationsView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (c, notifier);
  }

  testWidgets('as quatro opções começam ligadas e gravam em app_settings', (
    tester,
  ) async {
    final (c, _) = await pump(tester);
    expect(c.read(alertSettingsProvider).robot, isTrue);
    for (final id in ['agents', 'robot', 'reminder', 'sessions']) {
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(ValueKey('settings-notify-$id')))
            .value,
        isTrue,
      );
    }
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('settings-notify-robot')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(c.read(appSettingsProvider)[AlertSettingKeys.robot], 'false');
    expect(c.read(alertSettingsProvider).robot, isFalse);
    expect(find.byKey(const ValueKey('settings-notify-preview')), findsOne);
  });

  testWidgets('"Testar notificação" manda uma de verdade e conta o clique', (
    tester,
  ) async {
    final (c, notifier) = await pump(tester);
    // Without the robot, so the test does not wait for the drawing.
    await tester.runAsync(
      () => c
          .read(appSettingsProvider.notifier)
          .set(AlertSettingKeys.robot, 'false'),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('settings-notify-test')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(notifier.shown, hasLength(1));
    expect(notifier.shown.single.$1, endsWith('precisa de você'));
    expect(notifier.shown.single.$3, isNull);
    expect(find.text('Enviada: clique nela para conferir'), findsOne);
    notifier.clicks.single!();
    await tester.pumpAndSettle();
    expect(find.text('Clique recebido: tudo certo'), findsOne);
  });
}
