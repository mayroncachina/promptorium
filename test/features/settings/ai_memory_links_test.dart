import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/memory/ai_memory_cli.dart';
import 'package:promptorium/core/memory/ai_memory_state.dart';
import 'package:promptorium/core/memory/ai_memory_wiring.dart';
import 'package:promptorium/core/providers/agent_registry.dart'
    show providerFlowsProvider, ProviderFlows;
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/ai_memory_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// SPEC-098 T3: hooks and MCP per agent (R3), "Ligar" with a preview that
/// runs the installers only after the confirmation (R4), "Desligar" that
/// only shows the command (R5, P5), and the executions of the app (R6, R7).
void main() {
  const connected = AiMemoryDetection(
    status: AiMemoryStatus.connected,
    executable: '/home/u/.local/bin/ai-memory',
    version: '3.5.1',
  );

  AiMemoryWiring wiring({
    AiMemoryLink claudeHooks = AiMemoryLink.on,
    AiMemoryLink claudeMcp = AiMemoryLink.on,
    AiMemoryLink codexHooks = AiMemoryLink.awaitingTrust,
    AiMemoryLink codexMcp = AiMemoryLink.on,
  }) => AiMemoryWiring(
    claude: AiMemoryAgentWiring(
      agent: AiMemoryAgent.claude,
      hooks: claudeHooks,
      mcp: claudeMcp,
    ),
    codex: AiMemoryAgentWiring(
      agent: AiMemoryAgent.codex,
      hooks: codexHooks,
      mcp: codexMcp,
    ),
    dataDir: '/home/u/.local/share/ai-memory',
    removal: const ['would remove ai-memory from /home/u/.claude.json'],
  );

  Future<List<List<String>>> pump(
    WidgetTester tester, {
    required AiMemoryWiring w,
    bool codexOn = true,
  }) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ran = <List<String>>[];
    var current = w;
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        aiMemoryEnvironmentProvider.overrideWithValue({'HOME': '/home/u'}),
        aiMemoryDetectionProvider.overrideWith((ref) async => connected),
        aiMemoryWiringProvider.overrideWith((ref) async => current),
        aiMemoryCliProvider.overrideWith(
          (ref) async => AiMemoryCli(
            executable: 'ai-memory',
            log: (_) {},
            run: (exe, args, {workingDirectory, required timeout}) async {
              ran.add(args);
              // After Ligar the next read sees it on.
              current = wiring();
              return ProcessResult(0, 0, 'ok ${args.first}\n', '');
            },
          ),
        ),
        providerFlowsProvider.overrideWithValue(
          codexOn
              ? ProviderFlows.defaults
              : ProviderFlows.defaults.turnOff('codex'),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(child: AiMemorySettingsView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ran;
  }

  String pill(WidgetTester tester, String key) {
    final f = find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(Text),
    );
    return tester.widget<Text>(f).data!;
  }

  testWidgets('R3 + R7: Claude with hooks and MCP on; Codex MCP on and hooks '
      'aguardando confiança, saying why the Codex in the app has no memory', (
    tester,
  ) async {
    await pump(tester, w: wiring());
    expect(pill(tester, 'ai-memory-claude-code-hooks'), 'ligado');
    expect(pill(tester, 'ai-memory-claude-code-mcp'), 'ligado');
    expect(pill(tester, 'ai-memory-codex-hooks'), 'aguardando confiança');
    expect(pill(tester, 'ai-memory-codex-mcp'), 'ligado');
    expect(
      find.byKey(const ValueKey('ai-memory-codex-no-memory')),
      findsOneWidget,
    );
    // R6: the three kinds of execution.
    expect(find.text('sem captura · sem passagem'), findsOneWidget);
    expect(find.text('captura · sem passagem no fim'), findsOneWidget);
    expect(find.text('captura · passagem no fim e no começo'), findsOneWidget);
  });

  testWidgets('R3: the Codex block only with the Codex on in the app', (
    tester,
  ) async {
    await pump(tester, w: wiring(), codexOn: false);
    expect(
      find.byKey(const ValueKey('ai-memory-block-claude-code')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ai-memory-block-codex')), findsNothing);
  });

  testWidgets('R4: Ligar shows commands, files and backups first, runs the '
      'installers only after confirming, then shows the output', (
    tester,
  ) async {
    final ran = await pump(
      tester,
      w: wiring(
        codexHooks: AiMemoryLink.missing,
        codexMcp: AiMemoryLink.missing,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ai-memory-link-codex')));
    await tester.pumpAndSettle();
    expect(find.text('Ligar o ai-memory no Codex'), findsOneWidget);
    expect(
      find.text(
        'ai-memory install-hooks --agent codex --apply\n'
        'ai-memory install-mcp --client codex --apply',
      ),
      findsOneWidget,
    );
    expect(find.text('~/.codex/config.toml'), findsOneWidget);
    expect(find.text('~/.local/share/ai-memory/hooks/codex/'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-memory-backup-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-memory-trust-note')), findsOneWidget);
    expect(find.text('O app não escreve nesses arquivos.'), findsOneWidget);
    expect(ran, isEmpty);

    await tester.tap(find.byKey(const ValueKey('ai-memory-link-confirm')));
    await tester.pumpAndSettle();
    expect(ran, [
      ['install-hooks', '--agent', 'codex', '--apply'],
      ['install-mcp', '--client', 'codex', '--apply'],
    ]);
    expect(
      find.text('✓ ai-memory install-hooks --agent codex --apply'),
      findsOneWidget,
    );
    expect(find.text('ok install-mcp'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-memory-link-close')));
    await tester.pumpAndSettle();
    // The block was read again.
    expect(pill(tester, 'ai-memory-codex-mcp'), 'ligado');
  });

  testWidgets('R4: Cancelar runs nothing; "Ligar nos dois" covers both', (
    tester,
  ) async {
    final ran = await pump(
      tester,
      w: wiring(
        claudeHooks: AiMemoryLink.missing,
        codexHooks: AiMemoryLink.missing,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ai-memory-link-both')));
    await tester.pumpAndSettle();
    expect(
      find.text('Ligar o ai-memory no Claude Code e Codex'),
      findsOneWidget,
    );
    expect(find.text('~/.claude/settings.json'), findsOneWidget);
    expect(find.text('~/.codex/config.toml'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-memory-link-cancel')));
    await tester.pumpAndSettle();
    expect(ran, isEmpty);
  });

  testWidgets('R5 + P5: Desligar shows the uninstall commands with "todos os '
      'agentes" and runs nothing', (tester) async {
    final ran = await pump(tester, w: wiring());
    await tester.tap(
      find.byKey(const ValueKey('ai-memory-unlink-claude-code')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Desligar o ai-memory no Claude Code'), findsOneWidget);
    expect(find.textContaining('de todos os agentes'), findsOneWidget);
    expect(find.text(aiMemoryUninstallCommands.join('\n')), findsOneWidget);
    expect(
      find.text('would remove ai-memory from /home/u/.claude.json'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('ai-memory-unlink-close')));
    await tester.pumpAndSettle();
    expect(ran, isEmpty);
  });
}
