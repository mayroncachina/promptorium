import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_rpc.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/agents/agent_repository.dart';
import 'package:promptorium/features/mcp/codex_mcp_cli.dart';
import 'package:promptorium/features/mcp/codex_mcp_state.dart';
import 'package:promptorium/features/mcp/mcp_cli.dart';
import 'package:promptorium/features/mcp/mcp_config.dart';
import 'package:promptorium/features/mcp/mcp_screen.dart';
import 'package:promptorium/features/mcp/widgets/add_server_dialog.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/codex/fake_codex.dart';
import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart' show addWorkspace;
import 'codex_mcp_cli_test.dart' show fixtures, statusFixture, transcript;
import 'mcp_cli_test.dart' show FakeMcpRunner, ok;

const wsPath = '/work/repo';

final claudeSnapshot = McpRegistrySnapshot([
  for (final n in ['a', 'b', 'c', 'd'])
    McpServerConfig(
      name: n,
      scope: McpScope.user,
      transport: McpTransport.stdio,
      sourcePath: '/home/u/.claude.json',
      command: 'x',
    ),
]);

/// Every short App Server connection replays this: the status list and an
/// OAuth login that succeeds.
List<CodexLine> appServerTranscript() => transcript([
  (
    dir: 'send',
    msg: {
      'id': 2,
      'method': 'mcpServerStatus/list',
      'params': <String, dynamic>{},
    },
  ),
  (dir: 'recv', msg: {'id': 2, 'result': statusFixture()}),
  (
    dir: 'send',
    msg: {
      'id': 3,
      'method': 'mcpServer/oauth/login',
      'params': <String, dynamic>{},
    },
  ),
  (
    dir: 'recv',
    msg: {
      'id': 3,
      'result': {'authorizationUrl': 'https://mcp.notion.com/authorize'},
    },
  ),
  (
    dir: 'recv',
    msg: {
      'method': 'mcpServer/oauthLogin/completed',
      'params': {'name': 'notion', 'success': true},
    },
  ),
]);

class Harness {
  Harness(this.container, this.runner, this.fakes, this.opened);

  final ProviderContainer container;
  final FakeMcpRunner runner;
  final List<FakeCodex> fakes;
  final List<String> opened;

  List<Object?> get methods => [
    for (final f in fakes)
      for (final m in f.writtenAll) m['method'],
  ];
}

Future<Harness> pumpCodexTab(
  WidgetTester tester, {
  ProviderAvailability availability = const ProviderAvailability(
    ProviderStatus.ready,
    'ok',
    version: '0.170.0',
  ),
  bool selectCodex = true,
  Size size = const Size(1366, 768),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  CodexRpc.live.clear();
  final db = memoryDatabase();
  final wsId = (await addWorkspace(db, wsPath)).id;
  final list = File('$fixtures/mcp-list.json').readAsStringSync();
  final get = File('$fixtures/mcp-get-github.json').readAsStringSync();
  final runner = FakeMcpRunner(
    (args) => switch (args[1]) {
      'list' => ok(list),
      'get' => ok(get),
      'add' => ok("Added global MCP server '${args[2]}'."),
      'remove' => ok("Removed global MCP server '${args[2]}'."),
      'logout' => ok('Logged out.'),
      _ => ok('', code: 1),
    },
  );
  final fakes = <FakeCodex>[];
  final opened = <String>[];
  final container = ProviderContainer(
    // Failed providers (the Claude CLI is absent here) are not retried.
    retry: (count, error) => null,
    overrides: [
      databaseOverride(db),
      agentHomeProvider.overrideWithValue('/home/u'),
      // The Claude tab must never run the Claude CLI here.
      mcpRunnerProvider.overrideWithValue(
        (exe, args, {workingDirectory, timeout}) async => ok('', code: 1),
      ),
      mcpRegistryProvider.overrideWith((ref, ws) async => claudeSnapshot),
      codexMcpRunnerProvider.overrideWithValue(runner.call),
      codexMcpStarterProvider.overrideWithValue((
        exe,
        args, {
        workingDirectory,
        environment,
      }) async {
        expect(args, ['app-server']);
        final f = FakeCodex.replay(appServerTranscript());
        fakes.add(f);
        return f;
      }),
      codexMcpOpenUrlProvider.overrideWithValue((u) async => opened.add(u)),
      providerAvailabilityProvider.overrideWith(
        (ref, id) async => availability,
      ),
      agentEntriesProvider.overrideWith((ref, ws) async => const []),
    ],
  );
  await container.read(appSettingsProvider.notifier).load();
  if (selectCodex) {
    await container
        .read(appSettingsProvider.notifier)
        .set(mcpProviderTabKey(wsId), 'codex');
  }
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
  await settle(tester);
  return Harness(container, runner, fakes, opened);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  for (final size in const [Size(1366, 768), Size(1100, 700)]) {
    testWidgets(
      'aba Codex lista config, status e ferramentas sem turno ($size) [R1–R3]',
      (tester) async {
        final h = await pumpCodexTab(tester, size: size);
        expect(tester.takeException(), isNull);
        expect(find.text('Claude Code · 4'), findsOneWidget);
        expect(find.text('Codex · 3'), findsOneWidget);
        expect(find.text('Globais'), findsOneWidget);
        expect(find.text('~/.codex/config.toml'), findsWidgets);
        expect(find.text('De plugins'), findsOneWidget);
        expect(find.text('Da sessão'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mcp-row-codex:linear')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('mcp-row-codex-app')), findsOneWidget);
        // github (first) selected: connected, OAuth, its tools.
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('mcp-detail-status')))
              .data,
          'Conectado',
        );
        expect(find.text('Codex · Global'), findsOneWidget);
        expect(find.text('OAuth · conectado'), findsOneWidget);
        expect(find.text('search_issues'), findsOneWidget);
        expect(find.text('delete_branch'), findsOneWidget);
        expect(find.byKey(const ValueKey('mcp-codex-logout')), findsOneWidget);
        // postgres-dev failed, with the reason.
        expect(find.textContaining('failed to start'), findsWidgets);
        // Only `codex mcp list --json`, and the App Server without a turn.
        expect(h.runner.calls.map((c) => c.$1.join(' ')).toSet(), {
          'mcp list --json',
        });
        expect(h.runner.calls.every((c) => c.$2 == wsPath), isTrue);
        expect(h.methods, contains('mcpServerStatus/list'));
        expect(h.methods.where((m) => m == 'turn/start'), isEmpty);
        expect(h.methods.where((m) => m == 'thread/start'), isEmpty);
        // env values never reach the screen.
        await tester.tap(
          find.byKey(const ValueKey('mcp-row-codex:postgres-dev')),
        );
        await tester.pump();
        expect(find.textContaining('postgres://'), findsNothing);
        expect(find.text(mcpMask), findsWidgets);
      },
    );
  }

  testWidgets('a escolha da aba fica por workspace; padrão = provedor ativo', (
    tester,
  ) async {
    final h = await pumpCodexTab(tester, selectCodex: false);
    // Footer default is the Claude Code.
    expect(find.byKey(const ValueKey('mcp-codex-checking')), findsNothing);
    expect(find.text('SERVIDORES MCP'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('mcp-tab-codex')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mcp-tab-codex')));
    await settle(tester);
    expect(find.text('Globais'), findsOneWidget);
    final settings = h.container.read(appSettingsProvider);
    expect(settings.entries.where((e) => e.key.startsWith('mcp.provider.')), [
      isA<MapEntry<String, String>>().having((e) => e.value, 'v', 'codex'),
    ]);
    await tester.tap(find.byKey(const ValueKey('mcp-tab-claude')));
    await settle(tester);
    expect(find.text('SERVIDORES MCP'), findsOneWidget);
  });

  testWidgets('Remover mostra e roda codex mcp remove [R4]', (tester) async {
    final h = await pumpCodexTab(tester);
    await tester.tap(find.byKey(const ValueKey('mcp-remove')));
    await tester.pumpAndSettle();
    final cmd = tester.widget<Text>(
      find.byKey(const ValueKey('mcp-codex-remove-command')),
    );
    expect(cmd.data, contains('codex mcp remove github'));
    await tester.tap(find.byKey(const ValueKey('mcp-remove-ok')));
    await settle(tester);
    expect(
      h.runner.calls.map((c) => c.$1.join(' ')),
      contains('mcp remove github'),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('Adicionar no Codex: o comando mostrado é o executado [R4]', (
    tester,
  ) async {
    final h = await pumpCodexTab(tester);
    final ctx = tester.element(find.byType(McpScreen));
    showAddMcpServerDialog(ctx);
    await tester.pumpAndSettle();
    expect(find.text('Adicionar servidor MCP ao Codex'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp-add-codex-scope')), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp-add-type-sse')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('mcp-add-name')), 'pg');
    await tester.enterText(
      find.byKey(const ValueKey('mcp-add-target')),
      'npx -y @mcp/postgres',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mcp-add-pairs')),
      'DATABASE_URL=postgres://x:segredo@h/db',
    );
    await tester.pump();
    final preview = tester
        .widget<SelectableText>(
          find.byKey(const ValueKey('mcp-add-codex-preview')),
        )
        .data!;
    expect(
      preview,
      'codex mcp add pg --env DATABASE_URL=$mcpMask -- npx -y @mcp/postgres',
    );
    expect(find.textContaining('segredo'), findsOneWidget); // only the field
    await tester.ensureVisible(find.byKey(const ValueKey('mcp-add-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mcp-add-submit')));
    await settle(tester);
    expect(find.byKey(const ValueKey('mcp-add-error')), findsNothing);
    final add = h.runner.calls.firstWhere((c) => c.$1[1] == 'add').$1;
    expect(
      'codex ${add.join(' ')}',
      preview.replaceAll(mcpMask, 'postgres://x:segredo@h/db'),
    );
    expect(h.container.read(selectedCodexMcpServerProvider), 'codex:pg');
    await tester.pumpAndSettle();
  });

  testWidgets('Entrar num servidor notLoggedIn faz o login e atualiza [R5]', (
    tester,
  ) async {
    final h = await pumpCodexTab(tester);
    await tester.tap(find.byKey(const ValueKey('mcp-row-codex:notion')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('mcp-detail-status'))).data,
      'Precisa autenticar',
    );
    final before = h.fakes.length;
    await tester.tap(find.byKey(const ValueKey('mcp-codex-login')));
    await settle(tester);
    expect(h.opened, ['https://mcp.notion.com/authorize']);
    expect(h.methods, contains('mcpServer/oauth/login'));
    // The status is read again after the login.
    expect(h.fakes.length, greaterThan(before + 1));
    expect(h.methods.where((m) => m == 'turn/start'), isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'regras: Bloqueado = disabled_tools; o resto Só Claude Code [R9]',
    (tester) async {
      final h = await pumpCodexTab(tester);
      await h.container
          .read(mcpToolRulesRepoProvider)
          .setRule('github', 'delete_branch', McpRule.block);
      await h.container
          .read(mcpToolRulesRepoProvider)
          .setRule('github', 'search_issues', McpRule.allow);
      // Re-read the rules of the selected server.
      await tester.tap(find.byKey(const ValueKey('mcp-row-codex:notion')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mcp-row-codex:github')));
      await settle(tester);
      Text tag(String t) => tester.widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey('mcp-codex-rule-tag-$t')),
          matching: find.byType(Text),
        ),
      );
      expect(tag('delete_branch').data, 'disabled_tools');
      expect(tag('search_issues').data, 'Só Claude Code');
      expect(tag('create_issue').data, 'Só Claude Code');
      expect(find.text('2 de 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('mcp-codex-used-by')), findsOneWidget);
    },
  );

  testWidgets('servidor do Promptorium na aba Codex: só leitura [R7]', (
    tester,
  ) async {
    await pumpCodexTab(tester);
    await tester.tap(find.byKey(const ValueKey('mcp-row-codex-app')));
    await tester.pump();
    expect(find.byKey(const ValueKey('mcp-codex-app-note')), findsOneWidget);
    expect(find.text('Fora no Codex'), findsWidgets);
  });

  testWidgets('Codex incompatível: motivo na aba; a do Claude segue [R12]', (
    tester,
  ) async {
    final h = await pumpCodexTab(
      tester,
      availability: const ProviderAvailability(
        ProviderStatus.incompatible,
        'Versão instalada 0.168.0, mínimo 0.170.',
        version: '0.168.0',
      ),
    );
    expect(find.byKey(const ValueKey('mcp-codex-unavailable')), findsOneWidget);
    expect(find.textContaining('Codex 0.168.0 encontrado'), findsOneWidget);
    expect(find.text('Codex · —'), findsOneWidget);
    // Nothing of the Codex runs.
    expect(h.fakes, isEmpty);
    expect(h.runner.calls.where((c) => c.$1[1] != 'list'), isEmpty);
    await tester.tap(find.byKey(const ValueKey('mcp-tab-claude')));
    await settle(tester);
    expect(find.text('SERVIDORES MCP'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp-codex-unavailable')), findsNothing);
  });

  testWidgets('Codex ausente: "Codex não encontrado" [R12]', (tester) async {
    await pumpCodexTab(
      tester,
      availability: const ProviderAvailability(
        ProviderStatus.missing,
        'Codex CLI não encontrado. Instale o CLI e confira o PATH.',
      ),
    );
    expect(find.textContaining('Codex não encontrado'), findsOneWidget);
    expect(jsonEncode([]), '[]');
  });
}
