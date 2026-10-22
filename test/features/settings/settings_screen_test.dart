import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/core/claude/run_prefs.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/settings_screen.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

void main() {
  test(
    '"alterado" compares values: the default picked again is not a change',
    () {
      final idle = AppSettingKeys.idleMinutes;
      final model = AppSettingKeys.runModel(RunKind.session.name);
      expect(
        sectionChanged(SettingsSection.sessions, {
          idle: '${RunPrefs.defaultIdleMinutes}',
        }, null),
        isFalse,
      );
      expect(
        sectionChanged(SettingsSection.consumption, {model: 'sonnet'}, null),
        isFalse,
      );
      expect(
        sectionChanged(SettingsSection.consumption, {model: 'opus'}, null),
        isTrue,
      );
    },
  );

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

    // Sections (UX v2, U9): consumption first; the project one is disabled
    // without a workspace.
    expect(
      find.byKey(const ValueKey('settings-nav-consumption')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-changed-consumption')),
      findsNothing,
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
    expect(
      find.byKey(const ValueKey('settings-changed-consumption')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const ValueKey('settings-reset')));
    await tester.tap(find.byKey(const ValueKey('settings-reset')));
    await tester.pump();
    prefs = c.read(runPrefsProvider);
    expect(prefs.model(RunKind.session), 'sonnet');
    expect(prefs.effort(RunKind.planner), 'medium');
    expect(prefs.autocompact, '200k');

    expect(
      find.byKey(const ValueKey('settings-changed-consumption')),
      findsNothing,
    );

    // Search narrows the sections; Automações: each managed hook can be
    // turned off and marks the section as changed.
    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      'hook',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('settings-nav-consumption')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('settings-nav-automations')));
    await tester.pump();
    final format = find.byKey(const ValueKey('automation-format'));
    await tester.ensureVisible(format);
    await tester.tap(format);
    await tester.pump();
    expect(c.read(appSettingsProvider)[ManagedHook.format.settingKey], '0');
    expect(
      find.byKey(const ValueKey('settings-changed-automations')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-section-project')),
      findsNothing,
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  });

  testWidgets('Execução de specs (SPEC-017 R5): steps in one session, the '
      'context limit and the plugins / MCP servers of the app runs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    final settings = c.read(appSettingsProvider.notifier);
    await tester.runAsync(() => settings.load());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    Future<void> tap(String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }

    await tap('settings-nav-specRuns');
    expect(
      find.byKey(const ValueKey('settings-plugins-empty')),
      findsOneWidget,
    );
    expect(find.textContaining('abaixo de 60 mil tokens'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-changed-specRuns')),
      findsNothing,
    );

    await tap('settings-continue-context-80');
    await tap('settings-single-steps-2');
    expect(settings.get(AppSettingKeys.continueContextTokens), '80');
    expect(settings.get(AppSettingKeys.singleSessionSteps), '2');
    expect(c.read(runPrefsProvider).continueContextTokens, 80000);
    expect(find.textContaining('Spec com até 2 requisitos'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-changed-specRuns')),
      findsOneWidget,
    );

    // What the last system/init listed shows up with a switch each.
    await tester.runAsync(
      () => settings.set(
        AppSettingKeys.knownExtensions,
        encodeKnownExtensions((
          plugins: const [
            KnownPlugin(
              id: 'claude-mem@thedotmack',
              version: '13.9.2',
              tools: 22,
            ),
          ],
          servers: const [KnownMcpServer(name: 'youtrack', source: 'user')],
        )),
      ),
    );
    await tester.pump();
    expect(find.text('22 ferramentas MCP em toda chamada'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('settings-plugin-claude-mem@thedotmack')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('settings-mcp-youtrack')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    expect(c.read(runExtensionsProvider).plugins, {'claude-mem@thedotmack'});
    expect(c.read(runExtensionsProvider).mcpServers, {'youtrack'});

    // On again: out of the list.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('settings-mcp-youtrack')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    expect(c.read(runExtensionsProvider).mcpServers, isEmpty);

    await tap('settings-reset-spec-runs');
    await tester.pump();
    expect(settings.get(AppSettingKeys.continueContextTokens), isNull);
    expect(c.read(runExtensionsProvider).plugins, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
