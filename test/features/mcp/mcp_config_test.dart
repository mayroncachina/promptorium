import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/mcp/mcp_config.dart';

const secrets = [
  'SEGREDO-USER',
  'SEGREDO-LOCAL',
  'SEGREDO-PROJ',
  'HDR-SECRET',
  'QS-SECRET',
  'PASS-SECRET',
  'ARG-SECRET',
];

void main() {
  late Directory tmp;
  late String claudeJson, ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-mcp-');
    ws = '${tmp.path}/repo';
    Directory(ws).createSync();
    claudeJson = '${tmp.path}/.claude.json';
    File(claudeJson).writeAsStringSync(
      jsonEncode({
        'mcpServers': {
          'youtrack': {
            'type': 'stdio',
            'command': 'npx',
            'args': ['-y', 'youtrack-mcp', '--api-key', 'ARG-SECRET'],
            'env': {'YOUTRACK_TOKEN': 'SEGREDO-USER', 'YOUTRACK_URL': 'x'},
          },
          'shared': {'command': '/bin/user'}, // no "type" = stdio
          'web': {
            'type': 'http',
            'url': 'https://u:PASS-SECRET@h.dev/mcp?key=QS-SECRET&v=1',
            'headers': {'Authorization': 'Bearer HDR-SECRET'},
          },
        },
        'projects': {
          ws: {
            'mcpServers': {
              'shared': {
                'type': 'stdio',
                'command': '/bin/local',
                'env': {'L': 'SEGREDO-LOCAL'},
              },
            },
          },
          '/outro': {
            'mcpServers': {
              'naoaparece': {'command': 'x'},
            },
          },
        },
      }),
    );
    File('$ws/.mcp.json').writeAsStringSync(
      jsonEncode({
        'mcpServers': {
          'shared': {
            'type': 'stdio',
            'command': '/bin/proj',
            'env': {'P': 'SEGREDO-PROJ'},
          },
          'docs': {'type': 'sse', 'url': 'https://d.dev/sse'},
        },
      }),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('três escopos, precedência local > projeto > usuário', () async {
    final snap = await McpRegistry(
      claudeJsonPath: claudeJson,
      workspacePath: ws,
    ).read();
    expect(snap.errors, isEmpty);
    expect(snap.servers.map((s) => '${s.scope.name}:${s.name}:${s.active}'), [
      'local:shared:true',
      'project:docs:true',
      'project:shared:false',
      'user:shared:false',
      'user:web:true',
      'user:youtrack:true',
    ]);
    expect(snap.effective('shared')!.command, '/bin/local');
    final user = snap.ofScope(McpScope.user);
    expect(
      user.firstWhere((s) => s.name == 'shared').transport,
      McpTransport.stdio,
    );
    final docs = snap.servers.firstWhere((s) => s.name == 'docs');
    expect(docs.transport, McpTransport.sse);
    expect(docs.sourcePath, '$ws/.mcp.json');
  });

  test('nenhum valor de env/header/token chega ao modelo exposto', () async {
    final snap = await McpRegistry(
      claudeJsonPath: claudeJson,
      workspacePath: ws,
    ).read();
    final yt = snap.servers.firstWhere((s) => s.name == 'youtrack');
    expect(yt.envKeys, ['YOUTRACK_TOKEN', 'YOUTRACK_URL']);
    expect(yt.args, ['-y', 'youtrack-mcp', '--api-key', mcpMask]);
    final web = snap.servers.firstWhere((s) => s.name == 'web');
    expect(web.headerKeys, ['Authorization']);
    expect(web.url, 'https://u:$mcpMask@h.dev/mcp?key=$mcpMask&v=$mcpMask');

    // Everything the UI can read from the snapshot.
    final exposed = [
      for (final s in snap.servers) ...[
        s.name,
        s.target,
        s.command ?? '',
        s.url ?? '',
        ...s.args,
        ...s.envKeys,
        ...s.headerKeys,
        s.maskedJson(),
        s.sourcePath,
      ],
    ].join('\n');
    for (final v in secrets) {
      expect(exposed, isNot(contains(v)), reason: v);
    }
    expect(yt.maskedJson(), contains('"YOUTRACK_TOKEN": "$mcpMask"'));
  });

  test('sem workspace: só usuário; arquivo inválido vira erro', () async {
    File(claudeJson).writeAsStringSync('{ruim');
    final snap = await McpRegistry(claudeJsonPath: claudeJson).read();
    expect(snap.servers, isEmpty);
    expect(snap.errors.single, contains('JSON inválido'));
    final none = await McpRegistry(
      claudeJsonPath: '${tmp.path}/nao-existe.json',
      workspacePath: ws,
    ).read();
    expect(none.servers.map((s) => s.name), ['docs', 'shared']);
  });

  test('maskArgs', () {
    expect(maskArgs(['--token=abc', '-k', 'v', '--password', 'p', 'x']), [
      '--token=$mcpMask',
      '-k',
      'v',
      '--password',
      mcpMask,
      'x',
    ]);
  });
}
