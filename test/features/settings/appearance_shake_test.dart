import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/attention_shake.dart';
import 'package:promptorium/features/settings/settings_screen.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// SPEC-054 R7: "Tremer cards que precisam de você" in Aparência.
void main() {
  test('the option is found by its words and marks the section', () {
    expect(filterSections('tremor'), [SettingsSection.appearance]);
    expect(
      sectionChanged(SettingsSection.appearance, const {
        'aparencia.tremor': 'false',
      }, null),
      isTrue,
    );
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool reduced = false,
  }) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() => c.read(appSettingsProvider.notifier).load());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const Scaffold(body: SettingsScreen()),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('Desligado turns the shake off; Ligado clears the key', (
    tester,
  ) async {
    final c = await pump(tester);
    expect(c.read(attentionShakeEnabledProvider), isTrue);
    final off = find.byKey(const ValueKey('settings-shake-off'));
    await tester.ensureVisible(off);
    await tester.tap(off);
    await tester.pump();
    expect(c.read(attentionShakeEnabledProvider), isFalse);
    expect(c.read(appSettingsProvider)['aparencia.tremor'], 'false');
    await tester.tap(find.byKey(const ValueKey('settings-shake-on')));
    await tester.pump();
    expect(
      c.read(appSettingsProvider).containsKey('aparencia.tremor'),
      isFalse,
    );
  });

  testWidgets('with reduced motion it shows Desligado and does not change', (
    tester,
  ) async {
    final c = await pump(tester, reduced: true);
    final on = find.byKey(const ValueKey('settings-shake-on'));
    await tester.ensureVisible(on);
    await tester.tap(on);
    await tester.pump();
    expect(
      c.read(appSettingsProvider).containsKey('aparencia.tremor'),
      isFalse,
    );
    expect(
      find.textContaining('O sistema pede movimento reduzido'),
      findsOneWidget,
    );
  });
}
