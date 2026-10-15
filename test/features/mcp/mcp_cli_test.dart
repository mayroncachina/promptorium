import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/mcp/mcp_cli.dart';
import 'package:promptorium/features/mcp/mcp_config.dart';
import 'package:promptorium/features/mcp/mcp_state.dart';

/// Records `claude mcp …` calls and answers with canned results.
class FakeMcpRunner {
  FakeMcpRunner(this.answer);

  final ProcessResult Function(List<String> args) answer;
  final calls = <(List<String>, String?)>[];

  Future<ProcessResult> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
    Duration? timeout,
  }) async {
    calls.add((args, workingDirectory));
    return answer(args);
  }
}

ProcessResult ok(String out, {int code = 0, String err = ''}) =>
    ProcessResult(1, code, out, err);

void main() {
  group('parseMcpList (saída real do CLI 2.1.300)', () {
    test('conectado, falhou (stdio e http) e aguardando aprovação', () {
      final out = File('test/fixtures/mcp_list_2.1.300.txt').readAsStringSync();
      final e = parseMcpList(out);
      expect(e.map((x) => x.name), ['usr-fake', 'fake-ok', 'web-bad', 'eco']);
      expect(e.map((x) => x.state), [
        McpConnState.failed,
        McpConnState.connected,
        McpConnState.failed,
        McpConnState.pending,
      ]);
      expect(e[0].target, '/bin/false');
      expect(e[0].statusText, 'Failed to connect');
      expect(e[0].detail, 'CONNECTION_CLOSED: Connection closed');
      expect(e[1].target, 'python3 -I /tmp/sonda/bin/fake_mcp.py');
      expect(e[1].detail, isNull);
      expect(e[2].target, 'http://127.0.0.1:9/mcp');
      expect(e[2].isHttp, isTrue);
      expect(e[2].detail, startsWith('ECONNREFUSED'));
      expect(e[3].statusText, startsWith('Pending approval'));
    });

    test('para no bloco de diagnósticos', () {
      final out = File('test/fixtures/mcp_list_diagnostics_2.1.300.txt')
          .readAsStringSync();
      final e = parseMcpList(out);
      expect(e.map((x) => x.name), ['pr-stdio', 'lo-srv']);
    });

    test('sem servidores / lixo não quebra', () {
      expect(parseMcpList(''), isEmpty);
      expect(
        parseMcpList('No MCP servers configured. Use `claude mcp add`.'),
        isEmpty,
      );
    });
  });

  test('parseMcpGet lê só Status/Issue/Scope (nunca o env)', () {
    final out = File('test/fixtures/mcp_get_2.1.300.txt').readAsStringSync();
    expect(out, contains('TOKEN_Y=zzz')); // the CLI prints the value…
    final s = parseMcpGet(out);
    expect(s.state, McpConnState.connected);
    expect(s.statusText, 'Connected');
    expect(s.scope, startsWith('User config'));
    // …but nothing of it is kept.
    expect('${s.statusText}${s.issue}${s.scope}', isNot(contains('zzz')));
    final failed = parseMcpGet(
      'x:\n  Status: ✘ Failed to connect\n  Issue: ECONNREFUSED: boom\n',
    );
    expect(failed.state, McpConnState.failed);
    expect(failed.issue, 'ECONNREFUSED: boom');
  });

  group('buildMcpAddArgs (flags de claude mcp add --help)', () {
    test('stdio com env: operandos depois de --', () {
      expect(
        buildMcpAddArgs(
          const McpAddRequest(
            name: 'gh',
            scope: McpScope.project,
            transport: McpTransport.stdio,
            command: 'npx',
            args: ['-y', 'server-github'],
            env: {'GITHUB_TOKEN': 'abc', 'B': '2'},
          ),
        ),
        [
          'mcp', 'add', '-s', 'project', '-t', 'stdio', //
          '-e', 'GITHUB_TOKEN=abc', '-e', 'B=2', //
          '--', 'gh', 'npx', '-y', 'server-github',
        ],
      );
    });

    test('http com headers', () {
      expect(
        buildMcpAddArgs(
          const McpAddRequest(
            name: 'web',
            scope: McpScope.user,
            transport: McpTransport.http,
            url: 'https://x.dev/mcp',
            headers: {'Authorization': 'Bearer t'},
          ),
        ),
        [
          'mcp', 'add', '-s', 'user', '-t', 'http', //
          '-H', 'Authorization: Bearer t', '--', 'web', 'https://x.dev/mcp',
        ],
      );
    });

    test('validações', () {
      McpAddRequest r({
        String name = 'ok',
        McpTransport t = McpTransport.stdio,
        String? command = 'x',
        String? url,
        Map<String, String> env = const {},
        Map<String, String> headers = const {},
      }) => McpAddRequest(
        name: name,
        scope: McpScope.local,
        transport: t,
        command: command,
        url: url,
        env: env,
        headers: headers,
      );
      for (final bad in [
        r(name: 'bad name'),
        r(name: ''),
        r(command: ' '),
        r(t: McpTransport.http, url: 'ftp://x'),
        r(t: McpTransport.http, url: null),
        r(env: {'1X': 'a'}),
        r(headers: {'A': 'b'}),
        r(t: McpTransport.http, url: 'http://x', env: {'A': 'b'}),
        r(t: McpTransport.ws, url: 'http://x'),
      ]) {
        expect(() => buildMcpAddArgs(bad), throwsA(isA<McpException>()));
      }
    });

    test('remove', () {
      expect(buildMcpRemoveArgs('gh', McpScope.local), [
        'mcp',
        'remove',
        'gh',
        '-s',
        'local',
      ]);
    });
  });

  test('parseKeyValues e splitCommandLine', () {
    expect(parseKeyValues('A=1\n\n# c\nB = x=y\n'), {'A': '1', 'B': 'x=y'});
    expect(parseKeyValues('Authorization: Bearer a=b\nX-Y=1', header: true), {
      'Authorization': 'Bearer a=b',
      'X-Y': '1',
    });
    expect(() => parseKeyValues('semvalor'), throwsA(isA<McpException>()));
    expect(splitCommandLine('npx -y "my pkg" \'a b\' c\\ d'), [
      'npx',
      '-y',
      'my pkg',
      'a b',
      'c d',
    ]);
    expect(() => splitCommandLine('"aberto'), throwsA(isA<McpException>()));
  });

  test('McpCli: cwd = workspace, mensagens sem segredos', () async {
    final runner = FakeMcpRunner((args) {
      if (args[1] == 'add') {
        // An echo of the value must be redacted.
        return ok('Added stdio MCP server gh with env SEGREDO123');
      }
      if (args[1] == 'remove') {
        return ok('', code: 1, err: 'No MCP server named "gh" in .mcp.json');
      }
      return ok(File('test/fixtures/mcp_list_2.1.300.txt').readAsStringSync());
    });
    final cli = McpCli(executable: 'claude', run: runner.call);
    final msg = await cli.add(
      const McpAddRequest(
        name: 'gh',
        scope: McpScope.project,
        transport: McpTransport.stdio,
        command: 'npx',
        env: {'TOKEN': 'SEGREDO123'},
      ),
      '/ws',
    );
    expect(msg, isNot(contains('SEGREDO123')));
    expect(msg, contains(mcpMask));
    expect(runner.calls.last.$2, '/ws');
    await expectLater(
      cli.remove('gh', McpScope.project, '/ws'),
      throwsA(
        isA<McpException>().having((e) => e.message, 'm', contains('No MCP')),
      ),
    );
    expect(runner.calls.last.$1, ['mcp', 'remove', 'gh', '-s', 'project']);
    expect((await cli.list('/ws')).length, 4);
    expect(runner.calls.last.$1, ['mcp', 'list']);
    // Project / local scope need a workspace.
    await expectLater(
      cli.add(
        const McpAddRequest(
          name: 'x',
          scope: McpScope.local,
          transport: McpTransport.stdio,
          command: 'x',
        ),
        null,
      ),
      throwsA(isA<McpException>()),
    );
  });

  test('McpCli.get com erro não repassa a saída (pode ter valores)', () async {
    Duration? seen;
    final cli = McpCli(
      executable: 'claude',
      run: (exe, args, {workingDirectory, timeout}) async {
        seen = timeout;
        return ok(
          'gh:\n  Scope: Project\n  Environment:\n    TOKEN=SEGREDO123\n',
          code: 1,
        );
      },
    );
    await expectLater(
      cli.get('gh', '/ws'),
      throwsA(
        isA<McpException>().having(
          (e) => e.message,
          'm',
          allOf(isNot(contains('SEGREDO123')), contains('código 1')),
        ),
      ),
    );
    // The runner receives the timeout (it kills the process on expiry).
    expect(seen, McpCli.commandTimeout);
  });

  test('runner padrão recusa rodar o CLI real sob flutter test', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await expectLater(
      c.read(mcpRunnerProvider)('claude', const ['mcp', 'list']),
      throwsA(isA<ProcessException>()),
    );
  });

  test('inventário: system/init real lista mcp__srv__tool e status', () {
    final out = File('test/fixtures/mcp_inventory_init_2.1.300.jsonl')
        .readAsStringSync();
    final init = firstInit(out)!;
    final inv = McpInventory.fromInit(init);
    expect(inv.toolsByServer, {
      'fake-ok': ['apagar', 'echo'],
    });
    expect(
      {for (final s in inv.servers) s.name: s.status},
      {
        'usr-fake': 'failed',
        'fake-ok': 'connected',
        'web-bad': 'failed',
        'eco': 'failed',
      },
    );
    expect(
      mcpInventoryArgs,
      containsAllInOrder(['--model', '--no-session-persistence']),
    );
    expect(mcpInventoryArgs, isNot(contains('--dangerously-skip-permissions')));
  });
}
