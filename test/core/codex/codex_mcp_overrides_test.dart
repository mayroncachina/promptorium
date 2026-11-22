import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_mcp_overrides.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/mcp/app_mcp_config.dart' show mcpConfigJson;
import 'package:promptorium/core/mcp/app_mcp_tools.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/core/providers/capabilities.dart';

import 'fake_codex.dart';

const _token = 'tok-0123456789abcdef0123456789abcdef';

void main() {
  test('codex mcp list --json (0.170) → nomes', () {
    final out = File('test/fixtures/codex/0.170/mcp-list.json')
        .readAsStringSync();
    expect(codexMcpServerNames('WARNING: x\n$out'), [
      'github',
      'notion',
      'postgres-dev',
    ]);
  });

  group('overrides (R7–R9)', () {
    test(
      'leitura: cada servidor desligado e apps fora, sem mcp_servers={}',
      () {
        final a = codexMcpOverrides(
          servers: ['github', 'postgres-dev', 'tem espaço'],
          readOnly: true,
          disallowed: ['mcp__github__delete_branch'],
        );
        expect(a, [
          '-c',
          'mcp_servers.github.enabled=false',
          '-c',
          'mcp_servers.postgres-dev.enabled=false',
          '-c',
          'features.apps=false',
        ]);
        expect(a.join(' '), isNot(contains('mcp_servers={}')));
      },
    );

    test('Bloqueado vira disabled_tools só de servidores que existem', () {
      final a = codexMcpOverrides(
        servers: ['github', 'postgres-dev'],
        readOnly: false,
        disallowed: [
          'mcp__github__delete_branch',
          'mcp__github__close_issue',
          'mcp__postgres-dev__drop',
          'mcp__nada__x',
          'Bash',
        ],
      );
      expect(a, [
        '-c',
        'mcp_servers.github.disabled_tools=["close_issue", "delete_branch"]',
        '-c',
        'mcp_servers.postgres-dev.disabled_tools=["drop"]',
      ]);
    });

    test('servidor do app por URL, token por variável, só leitura', () {
      final a = codexMcpOverrides(
        servers: const [],
        readOnly: false,
        app: (url: 'http://127.0.0.1:4567/mcp', token: _token),
      );
      expect(a, [
        '-c',
        'mcp_servers.promptorium.url="http://127.0.0.1:4567/mcp"',
        '-c',
        'mcp_servers.promptorium.bearer_token_env_var="$codexAppMcpTokenVar"',
        '-c',
        'mcp_servers.promptorium.enabled_tools='
            '${jsonEncode(codexAppMcpTools).replaceAll(',', ', ')}',
      ]);
      expect(a.join(' '), isNot(contains(_token)));
      final writes = [
        for (final t in appMcpCatalog)
          if (t.write) t.name,
      ];
      expect(writes, isNotEmpty);
      for (final w in writes) {
        expect(codexAppMcpTools, isNot(contains(w)));
      }
    });

    test('lê URL e token do arquivo --mcp-config do app', () async {
      final dir = await Directory.systemTemp.createTemp('mcp-cfg-');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/mcp.json')
        ..writeAsStringSync(
          jsonEncode(mcpConfigJson(port: 4567, token: _token)),
        );
      final app = readAppMcpConfig(f.path)!;
      expect(app.url, 'http://127.0.0.1:4567/mcp');
      expect(app.token, _token);
      expect(readAppMcpConfig('${dir.path}/nada.json'), isNull);
    });
  });

  group('adaptador', () {
    late Directory dir;
    late String cfg;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('codex-mcp-');
      cfg = '${dir.path}/mcp.json';
      File(
        cfg,
      ).writeAsStringSync(jsonEncode(mcpConfigJson(port: 4567, token: _token)));
    });
    tearDown(() => dir.delete(recursive: true));

    Future<(List<String>, Map<String, String>?)> start(
      AgentStartOptions o, {
      List<String> servers = const ['github', 'postgres-dev'],
      bool failList = false,
    }) async {
      final fake = FakeCodex();
      late List<String> args;
      Map<String, String>? env;
      final run = await CodexProvider(
        mcpLister: (exe, cwd) async {
          expect(cwd, '/w');
          if (failList) throw const ProcessException('codex', []);
          return servers;
        },
        starter: (exe, a, {workingDirectory, environment}) async {
          args = a;
          env = environment;
          return fake;
        },
      ).start(o);
      run.events.listen((_) {});
      await run.stop(timeout: const Duration(milliseconds: 50));
      return (args, env);
    }

    for (final mode in [PromptMode.ask, PromptMode.plan]) {
      test(
        '$mode: sem terceiros, com o servidor do app só de leitura [R7, R8]',
        () async {
          final (args, env) = await start(
            AgentStartOptions(
              workingDirectory: '/w',
              mode: mode,
              appMcpConfigs: [cfg],
              appAllowedTools: appMcpReadToolIds,
              environment: const {'X': '1'},
            ),
          );
          expect(args.first, 'app-server');
          expect(
            args,
            containsAllInOrder([
              '-c',
              'mcp_servers.github.enabled=false',
              '-c',
              'mcp_servers.postgres-dev.enabled=false',
              '-c',
              'features.apps=false',
              '-c',
              'mcp_servers.promptorium.url="http://127.0.0.1:4567/mcp"',
            ]),
          );
          expect(args.join(' '), contains('promptorium.enabled_tools='));
          expect(args.join(' '), isNot(contains(_token)));
          expect(env, {'X': '1', codexAppMcpTokenVar: _token});
        },
      );
    }

    test(
      'Editar: servidores do Codex como estão; Bloqueado aplicado [R8, R9]',
      () async {
        final (args, env) = await start(
          AgentStartOptions(
            workingDirectory: '/w',
            mode: PromptMode.edit,
            extras: const CodexExtras(
              mcpDisallowedTools: ['mcp__github__delete_branch'],
            ),
          ),
        );
        expect(args, [
          'app-server',
          '-c',
          'mcp_servers.github.disabled_tools=["delete_branch"]',
        ]);
        expect(env, isNull);
      },
    );

    test('Editar sem regras nem app: só app-server, sem listar', () async {
      final (args, _) = await start(
        const AgentStartOptions(workingDirectory: '/w', mode: PromptMode.edit),
        failList: true,
      );
      expect(args, ['app-server']);
    });

    test('leitura sem conseguir listar falha fechado [R8]', () async {
      await expectLater(
        start(
          const AgentStartOptions(workingDirectory: '/w', mode: PromptMode.ask),
          failList: true,
        ),
        throwsA(isA<AgentUnavailable>()),
      );
    });

    test('o MCP do app não é mais recusado no Codex (SPEC-094 R6 → 105)', () {
      expect(
        () => CodexProvider.validateOptions(
          AgentStartOptions(
            workingDirectory: '/w',
            mode: PromptMode.ask,
            appMcpConfigs: [cfg],
          ),
        ),
        returnsNormally,
      );
      expect(
        ProviderCapabilities.codex.supports(ProviderCapability.appMcpServer),
        isTrue,
      );
    });
  });
}
