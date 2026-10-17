import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/claude/run_prefs.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/settings_screen.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

void main() {
  test('RunPrefs defaults and stored values', () {
    const d = RunPrefs({});
    expect(d.model(RunKind.session), 'sonnet');
    expect(d.modelArg(RunKind.planner), isNull); // inherit
    expect(d.effort(RunKind.conversation), 'medium');
    expect(d.autocompact, '200k');
    const s = RunPrefs({
      'claude.model.planner': 'opus',
      'claude.effort.session': 'default',
      'claude.autocompact': 'auto',
    });
    expect(s.modelArg(RunKind.planner), 'opus');
    expect(effortArg(s.effort(RunKind.session)), isNull);
    expect(s.autocompact, 'auto');
  });

  testWidgets('Configurações stores model, effort and auto-compact; '
      'Restaurar padrões clears them', (tester) async {
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
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('settings-model-session-opus')));
    await tester.tap(
      find.byKey(const ValueKey('settings-effort-planner-high')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-autocompact-300k')),
    );
    await tester.tap(find.byKey(const ValueKey('settings-autocompact-300k')));
    await tester.pump();
    var prefs = c.read(runPrefsProvider);
    expect(prefs.model(RunKind.session), 'opus');
    expect(prefs.effort(RunKind.planner), 'high');
    expect(prefs.autocompact, '300k');

    await tester.ensureVisible(find.byKey(const ValueKey('settings-reset')));
    await tester.tap(find.byKey(const ValueKey('settings-reset')));
    await tester.pump();
    prefs = c.read(runPrefsProvider);
    expect(prefs.model(RunKind.session), 'sonnet');
    expect(prefs.effort(RunKind.planner), 'medium');
    expect(prefs.autocompact, '200k');

    // Automações: each managed hook can be turned off.
    final format = find.byKey(const ValueKey('automation-format'));
    await tester.ensureVisible(format);
    await tester.tap(format);
    await tester.pump();
    expect(c.read(appSettingsProvider)[ManagedHook.format.settingKey], '0');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  });
}
