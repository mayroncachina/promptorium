import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/update/update_check.dart';
import 'package:promptorium/data/providers.dart';

import '../helpers/test_db.dart';
import 'claude/claude_process_test.dart' show FakeProcess;

Future<void> pump() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('ACP agents: "nome = comando" per line', () {
    final a = parseAcpAgents(
      '# comentário\nGemini CLI = gemini --experimental-acp\n'
      'Outro=meu-agente  --acp\nsem igual\n = vazio\n',
    );
    expect(a.map((x) => '${x.id}|${x.name}|${x.command.join(' ')}'), [
      'acp-gemini-cli|Gemini CLI|gemini --experimental-acp',
      'acp-outro|Outro|meu-agente --acp',
    ]);
  });

  test('ACP run: handshake, text chunks, tool call, permission and the end '
      'of the turn become stream-json events', () async {
    final fake = FakeProcess();
    final provider = AcpProvider(
      id: 'acp-x',
      displayName: 'X',
      command: ['x', '--acp'],
      starter: (exe, args, {workingDirectory, environment}) async => fake,
    );
    void reply(int id, Object result) =>
        fake.emit(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));

    final starting = provider.start(
      const AgentStartOptions(workingDirectory: '/w', mode: PromptMode.edit),
    );
    await pump();
    expect(fake.writtenJson.single['method'], 'initialize');
    reply(1, {'protocolVersion': 1, 'agentCapabilities': {}});
    await pump();
    expect(fake.writtenJson.last['method'], 'session/new');
    expect(fake.writtenJson.last['params']['cwd'], '/w');
    reply(2, {'sessionId': 'sess-9'});
    final run = await starting;
    final events = <ClaudeEvent>[];
    run.events.listen(events.add);
    await pump();
    expect((events.single as SystemInit).sessionId, 'sess-9');

    final sending = run.send('olá');
    await pump();
    final prompt = fake.writtenJson.last;
    expect(prompt['method'], 'session/prompt');
    expect(prompt['params']['prompt'], [
      {'type': 'text', 'text': 'olá'},
    ]);
    void update(Map<String, Object?> u) => fake.emit(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {'sessionId': 'sess-9', 'update': u},
      }),
    );
    update({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'Vou '},
    });
    update({
      'sessionUpdate': 'tool_call',
      'toolCallId': 't1',
      'title': 'Ler a.txt',
      'kind': 'read',
      'rawInput': {'path': 'a.txt'},
    });
    fake.emit(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 77,
        'method': 'session/request_permission',
        'params': {
          'sessionId': 'sess-9',
          'toolCall': {
            'toolCallId': 't2',
            'title': 'Editar a.txt',
            'kind': 'edit',
          },
          'options': [
            {'optionId': 'ok', 'name': 'Permitir', 'kind': 'allow_once'},
            {'optionId': 'sempre', 'name': 'Sempre', 'kind': 'allow_always'},
            {'optionId': 'nao', 'name': 'Negar', 'kind': 'reject_once'},
          ],
        },
      }),
    );
    update({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 't1',
      'status': 'completed',
      'content': [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': 'conteúdo'},
        },
      ],
    });
    update({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'pronto.'},
    });
    await pump();
    final ask = events.whereType<PermissionRequest>().single;
    expect(ask.toolName, 'Editar a.txt');
    await run.approve(ask.requestId);
    expect(fake.writtenJson.last, {
      'jsonrpc': '2.0',
      'id': 77,
      'result': {
        'outcome': {'outcome': 'selected', 'optionId': 'ok'},
      },
    });
    reply(prompt['id'] as int, {'stopReason': 'end_turn'});
    await sending;
    await pump();
    expect(events.whereType<StreamDelta>().map((d) => d.text), [
      'Vou ',
      'pronto.',
    ]);
    final tool = events.whereType<AssistantMessage>().first;
    expect(tool.blocks.whereType<ToolUseBlock>().single.name, 'Ler a.txt');
    expect(events.whereType<ToolResult>().single.toolUseId, 't1');
    final result = events.whereType<Result>().single;
    expect(result.isSuccess, isTrue);
    expect(result.result, 'Vou pronto.');
  });

  test('ACP in Perguntar: edits are refused without asking', () async {
    final fake = FakeProcess();
    final provider = AcpProvider(
      id: 'acp-x',
      displayName: 'X',
      command: ['x'],
      starter: (exe, args, {workingDirectory, environment}) async => fake,
    );
    final starting = provider.start(
      const AgentStartOptions(workingDirectory: '/w', mode: PromptMode.ask),
    );
    await pump();
    fake.emit(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': {}}));
    await pump();
    fake.emit(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'sessionId': 's'},
      }),
    );
    final run = await starting;
    final events = <ClaudeEvent>[];
    run.events.listen(events.add);
    fake.emit(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'session/request_permission',
        'params': {
          'toolCall': {'toolCallId': 't', 'title': 'rm', 'kind': 'execute'},
          'options': [
            {'optionId': 'y', 'kind': 'allow_once'},
            {'optionId': 'n', 'kind': 'reject_once'},
          ],
        },
      }),
    );
    await pump();
    expect(events.whereType<PermissionRequest>(), isEmpty);
    expect(fake.writtenJson.last['result'], {
      'outcome': {'outcome': 'selected', 'optionId': 'n'},
    });
  });

  test('registry lists the configured ACP agents', () async {
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    expect(c.read(agentProvidersProvider).map((p) => p.displayName), [
      'Claude Code',
      'Gemini CLI',
      'Codex',
    ]);
    await c
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.acpAgents, 'Meu = meu-agente --acp');
    expect(c.read(agentProvidersProvider).map((p) => (p.id, p.enabled)), [
      ('claude', true),
      ('acp-meu', true),
      ('codex', false),
    ]);
  });

  test(
    'update: semver compare; once a day; a newer release is offered',
    () async {
      expect(isNewer('v0.2.0', '0.1.0'), isTrue);
      expect(isNewer('0.1.0', '0.1.0'), isFalse);
      expect(isNewer('v0.0.9', '0.1.0'), isFalse);
      expect(isNewer('nightly', '0.1.0'), isFalse);
      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          releaseFetcherProvider.overrideWithValue(() async {
            calls++;
            return {'tag_name': 'v9.0.0', 'html_url': 'https://x/r'};
          }),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final checker = c.read(updateCheckerProvider.notifier);
      final u = await checker.check(now: DateTime(2026, 10, 17, 9));
      expect(u!.version, '9.0.0');
      expect(u.url, 'https://x/r');
      await checker.check(now: DateTime(2026, 10, 17, 20));
      expect(calls, 1);
      await checker.check(now: DateTime(2026, 10, 18, 10));
      expect(calls, 2);
      await c
          .read(appSettingsProvider.notifier)
          .set(UpdateChecker.enabledKey, '0');
      await checker.check(now: DateTime(2026, 10, 20));
      expect(calls, 2);
      expect(Platform.isLinux, isTrue);
    },
  );
}
