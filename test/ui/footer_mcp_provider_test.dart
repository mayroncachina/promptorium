import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_mcp_overrides.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/mcp/codex_mcp_cli.dart';
import 'package:promptorium/features/mcp/codex_mcp_state.dart';
import 'package:promptorium/features/mcp/mcp_cli.dart';
import 'package:promptorium/features/mcp/mcp_state.dart';
import 'package:promptorium/ui/shell/footer_stats.dart';
import 'package:promptorium/ui/shell/status_footer.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../helpers/test_db.dart';

/// SPEC-105 R11: the footer counts the servers of the provider in focus.
void main() {
  Future<ProviderContainer> pump(WidgetTester tester, String provider) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        providerAvailabilityProvider.overrideWith(
          (ref, id) async =>
              const ProviderAvailability(ProviderStatus.ready, 'Pronto'),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(null), provider);
    // Claude: 4 servers, all connected.
    c.read(mcpStatusBoardProvider.notifier).setFromList([
      for (final n in ['a', 'b', 'c', 'd'])
        McpListEntry(
          name: n,
          target: 'x',
          state: McpConnState.connected,
          statusText: 'Connected',
        ),
    ]);
    // Codex: github ready, postgres-dev failed.
    c.read(codexMcpBoardProvider.notifier).setFromStatus(const [
      CodexMcpStatus(name: 'github', state: McpConnState.connected),
      CodexMcpStatus(name: 'postgres-dev', state: McpConnState.failed),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StatusFooter(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('Codex ativo: MCP 1/2 · 1 falhou, com a dica do Codex', (
    tester,
  ) async {
    final c = await pump(tester, 'codex');
    final f = c.read(footerStatsProvider);
    expect((f.mcpConnected, f.mcpTotal, f.mcpFailed), (1, 2, 1));
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('· 1 falhou'), findsOneWidget);
    final tip = tester.widget<Tooltip>(
      find.byKey(const ValueKey('footer-mcp')),
    );
    expect(
      tip.message,
      'Servidores do Codex: github pronto, postgres-dev falhou',
    );
  });

  testWidgets('Claude ativo: MCP 4/4, a conta do Claude', (tester) async {
    final c = await pump(tester, 'claude');
    final f = c.read(footerStatsProvider);
    expect((f.mcpConnected, f.mcpTotal, f.mcpFailed), (4, 4, 0));
    expect(find.text('4/4'), findsOneWidget);
    expect(f.mcpHint, startsWith('Servidores do Claude Code:'));
  });

  testWidgets(
    'o início de cada servidor numa execução Codex atualiza o quadro',
    (tester) async {
      final c = await pump(tester, 'codex');
      codexMcpStartupUpdates.add({'name': 'postgres-dev', 'status': 'ready'});
      codexMcpStartupUpdates.add({'name': 'promptorium', 'status': 'ready'});
      await tester.pump();
      final f = c.read(footerStatsProvider);
      expect((f.mcpConnected, f.mcpTotal, f.mcpFailed), (2, 2, 0));
    },
  );
}
