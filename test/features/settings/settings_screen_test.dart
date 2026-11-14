import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/core/claude/run_prefs.dart';
import 'package:promptorium/core/mcp/app_mcp_config.dart';
import 'package:promptorium/core/mcp/app_mcp_server.dart';
import 'package:promptorium/core/mcp/app_mcp_tools.dart';
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
    // Tall: the card of the Promptorium MCP (SPEC-052) comes first.
    tester.view.physicalSize = const Size(1100, 2400);
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

  testWidgets('Servidor MCP do Promptorium (SPEC-052 R10): on by default, '
      'the tools and their approval, the limit, and turning it off takes '
      '--mcp-config out of the new runs', (tester) async {
    tester.view.physicalSize = const Size(1300, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = AppMcpServer(_NoTools());
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        appMcpServerProvider.overrideWithValue(server),
      ],
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
    await tester.tap(find.byKey(const ValueKey('settings-nav-specRuns')));
    await tester.pump();

    expect(find.text('SERVIDOR MCP DO PROMPTORIUM'), findsOneWidget);
    final on = tester.widget<Checkbox>(
      find.byKey(const ValueKey('settings-app-mcp-on')),
    );
    expect(on.value, isTrue);
    expect(find.text('Sobe com a próxima sessão ou conversa'), findsOneWidget);
    for (final t in appMcpCatalog) {
      expect(find.text(t.name), findsOneWidget);
      expect(find.text(t.summary), findsOneWidget);
      final approval = tester.widget<Text>(
        find.byKey(ValueKey('settings-app-mcp-approval-${t.name}')),
      );
      expect(approval.data, t.write ? 'Sempre pede' : 'Liberada');
    }

    // The limit of R9.
    await tester.enterText(
      find.byKey(const ValueKey('settings-app-mcp-limit')),
      '4',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(settings.get(AppSettingKeys.mcpCreationLimit), '4');
    expect(appMcpCreationLimit(c.read(appSettingsProvider)), 4);
    expect(
      find.byKey(const ValueKey('settings-changed-specRuns')),
      findsOneWidget,
    );

    // Off: the next runs get no file.
    await tester.tap(find.byKey(const ValueKey('settings-app-mcp-on')));
    await tester.pump();
    expect(settings.get(AppSettingKeys.mcpServer), '0');
    expect(
      find.text('Desligado: as próximas execuções não recebem o servidor.'),
      findsOneWidget,
    );
    final link = await tester.runAsync(
      () => openMcpRun(
        c.read(_refProvider),
        workspaceId: 1,
        sessionId: 's',
        access: McpAccess.write,
      ),
    );
    expect(link, isNull);
    expect(server.running, isFalse);

    // On again, by the reset of the section too.
    await tester.tap(find.byKey(const ValueKey('settings-reset-spec-runs')));
    await tester.pump();
    expect(settings.get(AppSettingKeys.mcpServer), isNull);
    expect(settings.get(AppSettingKeys.mcpCreationLimit), isNull);
    expect(tester.takeException(), isNull);
  });
}

/// The Ref of a provider, to call [openMcpRun] from a test.
final _refProvider = Provider<Ref>((ref) => ref);

/// The toolbox is never called here.
class _NoTools implements McpToolbox {
  @override
  List<McpToolDef> get catalog => appMcpCatalog;

  @override
  Future<McpToolOutcome> call(McpGrant g, String t, Map<String, Object?> a) =>
      throw UnimplementedError();
}
