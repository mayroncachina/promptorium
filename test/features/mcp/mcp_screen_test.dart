import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/agents/agent_file.dart';
import 'package:promptorium/features/agents/agent_repository.dart';
import 'package:promptorium/features/mcp/mcp_cli.dart';
import 'package:promptorium/features/mcp/mcp_config.dart';
import 'package:promptorium/features/mcp/mcp_screen.dart';
import 'package:promptorium/features/mcp/mcp_state.dart';
import 'package:promptorium/features/mcp/widgets/add_server_dialog.dart';
import 'package:promptorium/ui/shell/footer_stats.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart' show addWorkspace;
import 'mcp_cli_test.dart' show FakeMcpRunner, ok;

const wsPath = '/work/repo';

final listOut = File('test/fixtures/mcp_list_2.1.300.txt').readAsStringSync();
final initOut = File('test/fixtures/mcp_inventory_init_2.1.300.jsonl')
    .readAsStringSync();

McpServerConfig cfg(
  String name,
  McpScope scope, {
  bool active = true,
  List<String> env = const [],
}) => McpServerConfig(
  name: name,
  scope: scope,
  transport: McpTransport.stdio,
  sourcePath: scope == McpScope.project
      ? '$wsPath/.mcp.json'
      : '/home/u/.claude.json',
  command: 'python3',
  args: const ['-I', 'fake_mcp.py'],
  envKeys: env,
  active: active,
);

final snapshot = McpRegistrySnapshot([
  cfg('fake-ok', McpScope.user, env: ['TOKEN_Y']),
  cfg('usr-fake', McpScope.user),
  cfg('web-bad', McpScope.user),
  cfg('eco', McpScope.project),
]);

FakeMcpRunner runner() => FakeMcpRunner((args) {
  if (args.first == '-p') return ok(initOut);
  return switch (args[1]) {
    'list' => ok(listOut),
    'get' => ok(File('test/fixtures/mcp_get_2.1.300.txt').readAsStringSync()),
    'add' => ok('Added stdio MCP server novo'),
    'remove' => ok('Removed MCP server eco from project config'),
    _ => ok('', code: 1),
  };
});

Future<(ProviderContainer, FakeMcpRunner)> pumpMcp(
  WidgetTester tester, {
  Size size = const Size(1044, 628),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  await addWorkspace(db, wsPath);
  final r = runner();
  final container = ProviderContainer(
    overrides: [
      databaseOverride(db),
      agentHomeProvider.overrideWithValue('/home/u'),
      mcpRunnerProvider.overrideWithValue(r.call),
      mcpRegistryProvider.overrideWith((ref, ws) async => snapshot),
      agentEntriesProvider.overrideWith(
        (ref, ws) async => [
          AgentEntry(
            scope: AgentScope.project,
            path: '$wsPath/.claude/agents/implementer.md',
            file: AgentFile.parse(
              '---\nname: implementer\ndescription: d\n'
              'mcpServers:\n  - fake-ok\n---\n',
            ),
          ),
        ],
      ),
    ],
  );
  await container.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: McpScreen()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(Duration.zero);
  });
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return (container, r);
}

void main() {
  for (final size in const [Size(1044, 628), Size(1100, 700), Size(800, 600)]) {
    testWidgets('sem overflow em $size; status e ferramentas', (tester) async {
      final (c, r) = await pumpMcp(tester, size: size);
      expect(tester.takeException(), isNull);
      // list + inventory ran once, in the workspace.
      expect(
        r.calls.map((x) => x.$1.first == '-p' ? 'init' : x.$1[1]).toSet(),
        {'list', 'init'},
      );
      expect(r.calls.every((x) => x.$2 == wsPath), isTrue);
      expect(find.text('fake-ok'), findsWidgets);
      expect(find.byKey(const ValueKey('mcp-row-project:eco')), findsOneWidget);
      // fake-ok (first row) is selected: connected, 2 tools, used by.
      expect(find.byKey(const ValueKey('mcp-rule-echo')), findsOneWidget);
      expect(find.byKey(const ValueKey('mcp-rule-apagar')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mcp-used-by-implementer')),
        findsOneWidget,
      );
      expect(find.text('••••'), findsOneWidget); // TOKEN_Y masked
      expect(c.read(footerStatsProvider).mcpTotal, isNotNull);
    });
  }

  testWidgets('regra cicla Pedir → Bloqueado e é gravada', (tester) async {
    final (c, _) = await pumpMcp(tester);
    expect(find.text('2 de 2 liberadas'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcp-rule-apagar')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final rules = await c.read(mcpToolRulesRepoProvider).getAll();
    expect(rules.single.tool, 'apagar');
    expect(rules.single.server, 'fake-ok');
    expect(rules.single.rule, McpRule.block);
    expect(find.text('1 de 2 liberadas'), findsOneWidget);
    expect(find.text('Bloqueado'), findsOneWidget);
  });

  testWidgets('falhou em vermelho; rodapé conta conectados/falhas', (
    tester,
  ) async {
    final (c, _) = await pumpMcp(tester);
    await tester.tap(find.byKey(const ValueKey('mcp-row-user:usr-fake')));
    await tester.pump();
    final status = tester.widget<Text>(
      find.byKey(const ValueKey('mcp-detail-status')),
    );
    expect(status.data, 'Falhou');
    expect(status.style?.color, mcpStateColor(McpConnState.failed));
    expect(find.textContaining('CONNECTION_CLOSED'), findsWidgets);
    // Inventory init came after the list: 1 connected of 4, 3 failed.
    final f = c.read(footerStatsProvider);
    expect((f.mcpConnected, f.mcpTotal, f.mcpFailed), (1, 4, 3));
  });

  testWidgets('Remover pede confirmação e roda claude mcp remove -s', (
    tester,
  ) async {
    final (_, r) = await pumpMcp(tester);
    await tester.tap(find.byKey(const ValueKey('mcp-row-project:eco')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mcp-remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mcp-remove-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcp-remove-ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      r.calls.any(
        (x) => x.$1.join(' ') == 'mcp remove eco -s project' && x.$2 == wsPath,
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('Testar conexão usa claude mcp get e não mostra o env', (
    tester,
  ) async {
    final (_, r) = await pumpMcp(tester);
    await tester.tap(find.byKey(const ValueKey('mcp-test')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(r.calls.last.$1, ['mcp', 'get', 'fake-ok']);
    expect(find.textContaining('zzz'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('diálogo Adicionar monta claude mcp add', (tester) async {
    final (c, r) = await pumpMcp(tester, size: const Size(1100, 700));
    final ctx = tester.element(find.byType(McpScreen));
    showAddMcpServerDialog(ctx);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byKey(const ValueKey('mcp-add-name')), 'novo');
    await tester.tap(find.byKey(const ValueKey('mcp-add-scope-project')));
    await tester.enterText(
      find.byKey(const ValueKey('mcp-add-target')),
      'npx -y "pkg x"',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mcp-add-pairs')),
      'API_KEY=s3cr3t',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('mcp-add-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mcp-add-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final add = r.calls.firstWhere((x) => x.$1[1] == 'add');
    expect(add.$1, [
      'mcp', 'add', '-s', 'project', '-t', 'stdio', //
      '-e', 'API_KEY=s3cr3t', '--', 'novo', 'npx', '-y', 'pkg x',
    ]);
    expect(add.$2, wsPath);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mcp-add-dialog')), findsNothing);
    expect(c.read(selectedMcpServerProvider), 'project:novo');
  });
}
