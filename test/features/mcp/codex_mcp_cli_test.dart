import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_rpc.dart';
import 'package:promptorium/features/mcp/codex_mcp_cli.dart';
import 'package:promptorium/features/mcp/mcp_cli.dart';
import 'package:promptorium/features/mcp/mcp_config.dart';

import '../../core/codex/fake_codex.dart';
import 'mcp_cli_test.dart' show FakeMcpRunner, ok;

const fixtures = 'test/fixtures/codex/0.170';

/// A transcript for [FakeCodex.replay]: the handshake, then [rest].
List<CodexLine> transcript(List<CodexLine> rest) => [
  (
    dir: 'send',
    msg: {'id': 1, 'method': 'initialize', 'params': <String, dynamic>{}},
  ),
  (
    dir: 'recv',
    msg: {
      'id': 1,
      'result': {'userAgent': 'codex/0.170.0'},
    },
  ),
  ...rest,
];

Map<String, dynamic> statusFixture() =>
    jsonDecode(File('$fixtures/mcp-status.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  setUp(CodexRpc.live.clear);

  group('codex mcp list --json (saída real do 0.170)', () {
    test('lê transporte, autenticação e só os nomes das variáveis', () {
      final raw = File('$fixtures/mcp-list.json').readAsStringSync();
      // The CLI prints the env value in clear text…
      expect(raw, contains('postgres://u:p@h/db'));
      final list = parseCodexMcpList(raw);
      expect(list.map((s) => s.name), ['github', 'notion', 'postgres-dev']);
      final gh = list[0];
      expect(gh.transport, McpTransport.http);
      expect(gh.url, 'https://api.githubcopilot.com/mcp/');
      expect(gh.bearerTokenEnvVar, 'GITHUB_PAT');
      expect(gh.auth, CodexMcpAuth.bearerToken);
      expect(list[1].auth, CodexMcpAuth.notLoggedIn);
      final pg = list[2];
      expect(pg.transport, McpTransport.stdio);
      expect(pg.target, 'npx -y @mcp/postgres --verbose');
      expect(pg.envKeys, ['DATABASE_URL']);
      expect(pg.auth, CodexMcpAuth.unsupported);
      // …but nothing of it survives the parse.
      expect(pg.maskedToml(), isNot(contains('postgres://')));
      expect(pg.maskedToml(), contains('DATABASE_URL = "$mcpMask"'));
    });

    test('o get traz enabled_tools / disabled_tools', () {
      final raw = File('$fixtures/mcp-get-github.json').readAsStringSync();
      final s = CodexMcpServer.fromJson(jsonDecode(raw))!;
      expect(s.enabledTools, isNull);
      expect(s.disabledTools, isNull);
      expect(s.maskedToml(), startsWith('[mcp_servers.github]'));
    });

    test('aviso do PATH antes do JSON e lixo', () {
      expect(
        parseCodexMcpList('WARNING: proceeding, even though…\n[]'),
        isEmpty,
      );
      expect(() => parseCodexMcpList('erro'), throwsA(isA<McpException>()));
    });
  });

  group('mcpServerStatus/list', () {
    test('estado, autenticação, ferramentas, erro e plugin', () {
      final list = parseCodexMcpStatus(statusFixture());
      final by = {for (final s in list) s.name: s};
      expect(by['github']!.state, McpConnState.connected);
      expect(by['github']!.auth, CodexMcpAuth.oAuth);
      expect(by['github']!.tools.map((t) => t.name), [
        'create_issue',
        'delete_branch',
        'search_issues',
      ]);
      expect(by['postgres-dev']!.state, McpConnState.failed);
      expect(by['postgres-dev']!.toolsError, contains('failed to start'));
      expect(by['notion']!.state, McpConnState.needsAuth);
      expect(by['notion']!.auth, CodexMcpAuth.notLoggedIn);
      expect(by['linear']!.pluginId, 'linear-tools');
    });

    test('uma conexão curta lê o status sem thread e sem turno (R2)', () async {
      final fake = FakeCodex.replay(
        transcript([
          (
            dir: 'send',
            msg: {
              'id': 2,
              'method': 'mcpServerStatus/list',
              'params': <String, dynamic>{},
            },
          ),
          (dir: 'recv', msg: {'id': 2, 'result': statusFixture()}),
        ]),
      );
      final list = await readCodexMcpStatus(
        executable: 'codex',
        starter: (exe, args, {workingDirectory, environment}) async {
          expect(args, ['app-server']);
          return fake;
        },
      );
      expect(list, hasLength(4));
      final methods = [for (final m in fake.writtenAll) m['method']];
      expect(methods, ['initialize', 'initialized', 'mcpServerStatus/list']);
      expect(methods.where((m) => m == 'turn/start'), isEmpty);
      expect(methods.where((m) => m == 'thread/start'), isEmpty);
      expect(fake.writtenAll[2]['params'], {'detail': 'toolsAndAuthOnly'});
    });

    test('um servidor só, com detail full', () async {
      final fake = FakeCodex.replay(transcript(const []));
      await readCodexMcpStatus(
        executable: 'codex',
        serverName: 'github',
        full: true,
        starter: (exe, args, {workingDirectory, environment}) async => fake,
      );
      expect(fake.writtenAll[2]['params'], {
        'detail': 'full',
        'serverName': 'github',
      });
    });
  });

  group('login OAuth (R5)', () {
    test(
      'Entrar pede a URL, abre o navegador e espera o oauthLogin/completed',
      () async {
        final fake = FakeCodex.replay(
          transcript([
            (
              dir: 'send',
              msg: {
                'id': 2,
                'method': 'mcpServer/oauth/login',
                'params': <String, dynamic>{},
              },
            ),
            (
              dir: 'recv',
              msg: {
                'id': 2,
                'result': {
                  'authorizationUrl': 'https://mcp.notion.com/authorize?x=1',
                  'loginId': 'l1',
                },
              },
            ),
            (
              dir: 'recv',
              msg: {
                'method': 'mcpServer/oauthLogin/completed',
                'params': {'name': 'outro', 'success': false},
              },
            ),
            (
              dir: 'recv',
              msg: {
                'method': 'mcpServer/oauthLogin/completed',
                'params': {'name': 'notion', 'success': true, 'loginId': 'l1'},
              },
            ),
          ]),
        );
        final opened = <String>[];
        final r = await codexMcpOauthLogin(
          executable: 'codex',
          name: 'notion',
          openUrl: (u) async => opened.add(u),
          starter: (exe, args, {workingDirectory, environment}) async => fake,
        );
        expect(r.success, isTrue);
        expect(opened, ['https://mcp.notion.com/authorize?x=1']);
        expect(fake.writtenAll[2]['params']['name'], 'notion');
        expect(
          fake.writtenAll.where((m) => m['method'] == 'turn/start'),
          isEmpty,
        );
      },
    );

    test('falha do login volta com o motivo', () async {
      final fake = FakeCodex.replay(
        transcript([
          (
            dir: 'send',
            msg: {
              'id': 2,
              'method': 'mcpServer/oauth/login',
              'params': <String, dynamic>{},
            },
          ),
          (
            dir: 'recv',
            msg: {
              'id': 2,
              'result': {'authorizationUrl': 'https://x/auth'},
            },
          ),
          (
            dir: 'recv',
            msg: {
              'method': 'mcpServer/oauthLogin/completed',
              'params': {
                'name': 'notion',
                'success': false,
                'error': 'access_denied',
              },
            },
          ),
        ]),
      );
      final r = await codexMcpOauthLogin(
        executable: 'codex',
        name: 'notion',
        openUrl: (_) async {},
        starter: (exe, args, {workingDirectory, environment}) async => fake,
      );
      expect(r.success, isFalse);
      expect(r.error, 'access_denied');
    });
  });

  group('codex mcp add / remove (R4)', () {
    const stdio = CodexMcpAddRequest(
      name: 'postgres-dev',
      transport: McpTransport.stdio,
      command: 'npx',
      args: ['-y', '@mcp/postgres'],
      env: {'DATABASE_URL': 'postgres://u:segredo@h/db'},
    );
    const http = CodexMcpAddRequest(
      name: 'github',
      transport: McpTransport.http,
      url: 'https://api.githubcopilot.com/mcp/',
      bearerTokenEnvVar: 'GITHUB_PAT',
    );

    test('argumentos e prévia mascarada', () {
      expect(buildCodexMcpAddArgs(stdio), [
        'mcp',
        'add',
        'postgres-dev',
        '--env',
        'DATABASE_URL=postgres://u:segredo@h/db',
        '--',
        'npx',
        '-y',
        '@mcp/postgres',
      ]);
      expect(
        codexMcpAddPreview(stdio),
        'codex mcp add postgres-dev --env DATABASE_URL=$mcpMask -- npx -y '
        '@mcp/postgres',
      );
      expect(buildCodexMcpAddArgs(http), [
        'mcp',
        'add',
        'github',
        '--url',
        'https://api.githubcopilot.com/mcp/',
        '--bearer-token-env-var',
        'GITHUB_PAT',
      ]);
      expect(
        codexMcpAddPreview(http),
        'codex mcp add github --url https://api.githubcopilot.com/mcp/ '
        '--bearer-token-env-var GITHUB_PAT',
      );
      expect(buildCodexMcpRemoveArgs('github'), ['mcp', 'remove', 'github']);
    });

    test('sse e ws não têm equivalente; nomes e variáveis validados', () {
      for (final t in [McpTransport.sse, McpTransport.ws]) {
        expect(
          () => buildCodexMcpAddArgs(
            CodexMcpAddRequest(name: 'x', transport: t, url: 'https://x'),
          ),
          throwsA(
            isA<McpException>().having(
              (e) => e.message,
              'message',
              contains('Sem equivalente no Codex: transporte'),
            ),
          ),
        );
      }
      expect(
        () => buildCodexMcpAddArgs(
          const CodexMcpAddRequest(
            name: 'a b',
            transport: McpTransport.stdio,
            command: 'x',
          ),
        ),
        throwsA(isA<McpException>()),
      );
      expect(
        () => buildCodexMcpAddArgs(
          const CodexMcpAddRequest(
            name: 'a',
            transport: McpTransport.http,
            url: 'https://x',
            bearerTokenEnvVar: 'tem espaço',
          ),
        ),
        throwsA(isA<McpException>()),
      );
    });

    test('adicionar e remover rodam o comando mostrado e nada mais', () async {
      final home = await Directory.systemTemp.createTemp('codex-home-');
      addTearDown(() => home.delete(recursive: true));
      final runner = FakeMcpRunner(
        (args) => ok(
          "WARNING: proceeding, even though…\nAdded global MCP server "
          "'postgres-dev'. postgres://u:segredo@h/db",
        ),
      );
      final cli = CodexMcpCli(executable: 'codex', run: runner.call);
      final r = await cli.add(stdio, home.path);
      expect(runner.calls.single.$1, buildCodexMcpAddArgs(stdio));
      expect(runner.calls.single.$2, home.path);
      // What the dialog shows is the same command, masked.
      expect(
        codexMcpAddPreview(stdio)
            .replaceAll(mcpMask, 'postgres://u:segredo@h/db'),
        'codex ${runner.calls.single.$1.join(' ')}',
      );
      expect(r.message, isNot(contains('segredo')));
      expect(r.message, isNot(contains('WARNING')));
      expect(r.needsLogin, isFalse);
      await cli.remove('postgres-dev', home.path);
      expect(runner.calls.last.$1, ['mcp', 'remove', 'postgres-dev']);
      // The app never writes the config itself.
      expect(home.listSync(recursive: true), isEmpty);
    });

    test('http sem token: o OAuth do add não trava; o get confirma', () async {
      final calls = <List<String>>[];
      final cli = CodexMcpCli(
        executable: 'codex',
        run: (exe, args, {workingDirectory, timeout}) async {
          calls.add(args);
          if (args[1] == 'add') {
            expect(timeout, CodexMcpCli.oauthGrace);
            throw TimeoutException('oauth');
          }
          return ok(File('$fixtures/mcp-get-github.json').readAsStringSync());
        },
      );
      final r = await cli.add(
        const CodexMcpAddRequest(
          name: 'github',
          transport: McpTransport.http,
          url: 'https://api.githubcopilot.com/mcp/',
        ),
        null,
      );
      expect(r.needsLogin, isTrue);
      expect(calls.last, ['mcp', 'get', 'github', '--json']);
    });

    test('falha do list não ecoa o stdout (pode ter valores)', () async {
      final cli = CodexMcpCli(
        executable: 'codex',
        run: (exe, args, {workingDirectory, timeout}) async =>
            ok('{"env":{"K":"segredo"}}', code: 1, err: 'Error: boom'),
      );
      await expectLater(
        cli.list(null),
        throwsA(
          isA<McpException>().having((e) => e.message, 'm', 'Error: boom'),
        ),
      );
    });

    test('get de um servidor que não existe = null', () async {
      final cli = CodexMcpCli(
        executable: 'codex',
        run: (exe, args, {workingDirectory, timeout}) async =>
            ok('', code: 1, err: "Error: No MCP server named 'x' found."),
      );
      expect(await cli.get('x', null), isNull);
    });
  });
}
