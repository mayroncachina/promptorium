import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/mcp/codex_mcp_cli.dart';
import 'package:promptorium/features/mcp/codex_mcp_state.dart';
import 'package:promptorium/features/mcp/copy_to_codex.dart';
import 'package:promptorium/features/mcp/mcp_config.dart';
import 'package:promptorium/features/mcp/widgets/copy_to_codex_dialog.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart' show addWorkspace;
import 'codex_mcp_cli_test.dart' show fixtures;
import 'mcp_cli_test.dart' show FakeMcpRunner, ok;

const ws = '/work/vitrine';

McpServerConfig stdioCfg({
  String name = 'postgres-dev',
  McpScope scope = McpScope.project,
  String source = '/x/.mcp.json',
}) => McpServerConfig(
  name: name,
  scope: scope,
  transport: McpTransport.stdio,
  sourcePath: source,
  command: 'npx',
  args: maskArgs(['-y', '@mcp/postgres', '--token', 'abc123']),
  envKeys: const ['DATABASE_URL'],
);

const raw = ClaudeMcpRawEntry(
  command: 'npx',
  args: ['-y', '@mcp/postgres', '--token', 'abc123'],
  env: {'DATABASE_URL': 'postgres://u:segredo@localhost/vitrine'},
);

McpServerConfig httpCfg(String name, List<String> headers, {String? type}) =>
    McpServerConfig(
      name: name,
      scope: McpScope.user,
      transport: McpTransport.parse(type ?? 'http', hasCommand: false),
      sourcePath: '/home/u/.claude.json',
      url: 'https://api.githubcopilot.com/mcp/',
      headerKeys: headers,
    );

void main() {
  group('tradução (R6)', () {
    test(
      'stdio com variáveis: sem valores por padrão; com a opção, inclui',
      () {
        final plan = planCodexCopy(stdioCfg(), raw);
        expect(plan.blocker, isNull);
        expect(plan.scopeWarning, isTrue);
        final none = codexCopyRequest(plan, raw);
        expect(buildCodexMcpAddArgs(none), [
          'mcp',
          'add',
          'postgres-dev',
          '--',
          'npx',
          '-y',
          '@mcp/postgres',
          '--token',
          'abc123',
        ]);
        final withValues = codexCopyRequest(plan, raw, envValues: raw.env);
        expect(buildCodexMcpAddArgs(withValues), [
          'mcp',
          'add',
          'postgres-dev',
          '--env',
          'DATABASE_URL=postgres://u:segredo@localhost/vitrine',
          '--',
          'npx',
          '-y',
          '@mcp/postgres',
          '--token',
          'abc123',
        ]);
        expect(
          codexMcpAddPreview(withValues),
          'codex mcp add postgres-dev --env DATABASE_URL=$mcpMask -- npx -y '
          '@mcp/postgres --token $mcpMask',
        );
        // An empty field means "do not copy that value".
        expect(
          codexCopyRequest(plan, raw, envValues: {'DATABASE_URL': ''}).env,
          isEmpty,
        );
      },
    );

    test('Global no Claude não avisa escopo', () {
      expect(
        planCodexCopy(stdioCfg(scope: McpScope.user), raw).scopeWarning,
        isFalse,
      );
    });

    test('sse e ws: sem equivalente, com o motivo', () {
      for (final t in ['sse', 'ws']) {
        final p = planCodexCopy(httpCfg('figma', const [], type: t), null);
        expect(
          p.blocker,
          startsWith('Sem equivalente no Codex: transporte $t'),
        );
      }
    });

    test('http: Authorization Bearer vira --bearer-token-env-var', () {
      const r = ClaudeMcpRawEntry(
        url: 'https://api.githubcopilot.com/mcp/',
        headers: {'Authorization': 'Bearer ghp_segredo'},
      );
      final p = planCodexCopy(httpCfg('github', const ['Authorization']), r);
      expect(p.blocker, isNull);
      expect(p.bearerHeader, isTrue);
      expect(p.defaultTokenVar, 'GITHUB_TOKEN');
      final req = codexCopyRequest(p, r, tokenVar: 'GITHUB_TOKEN');
      expect(buildCodexMcpAddArgs(req), [
        'mcp',
        'add',
        'github',
        '--url',
        'https://api.githubcopilot.com/mcp/',
        '--bearer-token-env-var',
        'GITHUB_TOKEN',
      ]);
      expect(codexMcpAddPreview(req), isNot(contains('ghp_')));
    });

    test('outro cabeçalho não tem equivalente', () {
      const r = ClaudeMcpRawEntry(headers: {'X-Api-Key': 'k'});
      final p = planCodexCopy(httpCfg('x', const ['X-Api-Key']), r);
      expect(p.blocker, contains('cabeçalho X-Api-Key'));
    });

    test('diferença com o servidor que o Codex já tem (P3)', () {
      final current = parseCodexMcpList(
        File('$fixtures/mcp-list.json').readAsStringSync(),
      ).firstWhere((s) => s.name == 'github');
      final diff = codexCopyDiff(
        current,
        const CodexMcpAddRequest(
          name: 'github',
          transport: McpTransport.http,
          url: 'https://api.githubcopilot.com/mcp/',
        ),
      );
      expect(diff, [('Token', 'GITHUB_PAT', 'OAuth')]);
    });

    test('lê a entrada do arquivo do escopo (user, local, project)', () async {
      final dir = await Directory.systemTemp.createTemp('claude-json-');
      addTearDown(() => dir.delete(recursive: true));
      final home = File('${dir.path}/.claude.json')
        ..writeAsStringSync(
          jsonEncode({
            'mcpServers': {
              'g': {
                'command': 'a',
                'env': {'K': 'v1'},
              },
            },
            'projects': {
              ws: {
                'mcpServers': {
                  'l': {
                    'command': 'b',
                    'args': ['x'],
                    'env': {'K': 'v2'},
                  },
                },
              },
            },
          }),
        );
      final proj = File('${dir.path}/.mcp.json')
        ..writeAsStringSync(
          jsonEncode({
            'mcpServers': {
              'p': {
                'type': 'http',
                'url': 'https://p',
                'headers': {'H': 'v3'},
              },
            },
          }),
        );
      McpServerConfig cfg(String n, McpScope s, File f) => McpServerConfig(
        name: n,
        scope: s,
        transport: McpTransport.stdio,
        sourcePath: f.path,
      );
      expect((await readClaudeMcpRaw(cfg('g', McpScope.user, home)))!.env, {
        'K': 'v1',
      });
      final l = await readClaudeMcpRaw(
        cfg('l', McpScope.local, home),
        workspacePath: ws,
      );
      expect(l!.command, 'b');
      expect(l.args, ['x']);
      expect(l.env, {'K': 'v2'});
      expect(
        (await readClaudeMcpRaw(cfg('p', McpScope.project, proj)))!.headers,
        {'H': 'v3'},
      );
      expect(await readClaudeMcpRaw(cfg('nada', McpScope.user, home)), isNull);
    });
  });

  group('diálogo (R6)', () {
    late Directory dir;

    Future<(ProviderContainer, FakeMcpRunner)> pumpDialog(
      WidgetTester tester,
      McpServerConfig Function(String claudeJson) config,
    ) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('copy-codex-'),
      ))!;
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/.mcp.json';
      File(path).writeAsStringSync(
        jsonEncode({
          'mcpServers': {
            'pg': {
              'command': 'npx',
              'args': ['-y', '@mcp/postgres', '--token', 'abc123'],
              'env': {'DATABASE_URL': 'postgres://u:segredo@localhost/vitrine'},
            },
            'figma': {'type': 'sse', 'url': 'https://figma/sse'},
            'github': {
              'type': 'http',
              'url': 'https://api.githubcopilot.com/mcp/',
            },
          },
        }),
      );
      final db = memoryDatabase();
      await addWorkspace(db, ws);
      final list = File('$fixtures/mcp-list.json').readAsStringSync();
      final runner = FakeMcpRunner(
        (args) => switch (args[1]) {
          'list' => ok(list),
          'add' => ok("Added global MCP server '${args[2]}'."),
          'remove' => ok("Removed global MCP server '${args[2]}'."),
          _ => ok('', code: 1),
        },
      );
      final container = ProviderContainer(
        retry: (count, error) => null,
        overrides: [
          databaseOverride(db),
          codexMcpRunnerProvider.overrideWithValue(runner.call),
        ],
      );
      await container.read(appSettingsProvider.notifier).load();
      final cfg = config(path);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => showCopyToCodexDialog(
                    ctx,
                    config: cfg,
                    cwd: ws,
                    workspacePath: ws,
                    workspaceName: 'vitrine',
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      });
      await tester.tap(find.text('abrir'));
      await settle(tester);
      return (container, runner);
    }

    String preview(WidgetTester tester) => tester
        .widget<SelectableText>(find.byKey(const ValueKey('mcp-copy-preview')))
        .data!;

    testWidgets(
      'stdio: sem valores por padrão; marcar copia; abre a aba Codex',
      (tester) async {
        final (c, r) = await pumpDialog(tester, (p) => stdioCfg(name: 'pg', source: p));
        expect(tester.takeException(), isNull);
        expect(find.text('DATABASE_URL = preencher'), findsOneWidget);
        expect(find.text('valor não copiado'), findsOneWidget);
        expect(find.byKey(const ValueKey('mcp-copy-scope')), findsOneWidget);
        expect(find.text('vale em todos os projetos'), findsOneWidget);
        expect(
          preview(tester),
          'codex mcp add pg -- npx -y @mcp/postgres --token $mcpMask',
        );
        await tester.tap(find.byKey(const ValueKey('mcp-copy-values')));
        await tester.pump();
        expect(
          preview(tester),
          'codex mcp add pg --env DATABASE_URL=$mcpMask -- npx -y '
          '@mcp/postgres --token $mcpMask',
        );
        await tester.tap(find.byKey(const ValueKey('mcp-copy-submit')));
        await settle(tester);
        final add = r.calls.firstWhere((x) => x.$1[1] == 'add').$1;
        expect(
          add,
          contains('DATABASE_URL=postgres://u:segredo@localhost/vitrine'),
        );
        expect(add.sublist(add.length - 4), [
          '-y',
          '@mcp/postgres',
          '--token',
          'abc123',
        ]);
        expect(c.read(mcpProviderTabProvider), McpProviderTab.codex);
        expect(c.read(selectedCodexMcpServerProvider), 'codex:pg');
        expect(find.byKey(const ValueKey('mcp-copy-dialog')), findsNothing);
      },
    );

    testWidgets('sse: cópia desabilitada com o motivo', (tester) async {
      final (_, r) = await pumpDialog(
        tester,
        (p) => McpServerConfig(
          name: 'figma',
          scope: McpScope.project,
          transport: McpTransport.sse,
          sourcePath: p,
          url: 'https://figma/sse',
        ),
      );
      expect(
        find.textContaining('Sem equivalente no Codex: transporte sse'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('mcp-copy-submit')));
      await settle(tester);
      expect(r.calls.where((x) => x.$1[1] == 'add'), isEmpty);
    });

    testWidgets(
      'nome repetido: mostra a diferença e só substitui confirmando',
      (tester) async {
        final (_, r) = await pumpDialog(
          tester,
          (p) => McpServerConfig(
            name: 'github',
            scope: McpScope.project,
            transport: McpTransport.http,
            sourcePath: p,
            url: 'https://api.githubcopilot.com/mcp/',
          ),
        );
        expect(find.byKey(const ValueKey('mcp-copy-exists')), findsOneWidget);
        expect(find.byKey(const ValueKey('mcp-copy-diff')), findsOneWidget);
        expect(find.text('GITHUB_PAT'), findsOneWidget);
        expect(find.byKey(const ValueKey('mcp-copy-submit')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('mcp-copy-replace')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('mcp-copy-replace-confirm')),
          findsOneWidget,
        );
        // Cancel: nothing runs.
        await tester.tap(find.text('Cancelar').last);
        await tester.pumpAndSettle();
        expect(r.calls.where((x) => x.$1[1] != 'list'), isEmpty);
        await tester.tap(find.byKey(const ValueKey('mcp-copy-replace')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mcp-copy-replace-ok')));
        await settle(tester);
        expect(
          [
            for (final x in r.calls)
              if (x.$1[1] != 'list') x.$1.take(3).join(' '),
          ],
          ['mcp remove github', 'mcp add github'],
        );
      },
    );
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}
