import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/update/update_check.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/providers_view.dart';

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
      String? seen;
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          appVersionProvider.overrideWith((ref) async => '1.0.0'),
          releaseFetcherProvider.overrideWithValue((version) async {
            seen = version;
            calls++;
            return {
              'tag_name': 'v9.0.0',
              'html_url': 'https://x/r',
              'body': 'Notas',
              'published_at': '2026-10-01T12:00:00Z',
              'assets': [
                {'name': 'a.deb', 'browser_download_url': 'https://x/a.deb'},
                {'name': 'sem-url'},
                'lixo',
              ],
            };
          }),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final checker = c.read(updateCheckerProvider.notifier);
      final u = await checker.check(now: DateTime(2026, 10, 17, 9));
      expect(seen, '1.0.0');
      expect(u!.version, '9.0.0');
      expect(u.url, 'https://x/r');
      expect(u.notes, 'Notas');
      expect(u.publishedAt, DateTime.utc(2026, 10, 1, 12));
      expect(u.assets.map((a) => (a.name, a.url)), [
        ('a.deb', 'https://x/a.deb'),
      ]);
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

  test('update: campos ausentes da release são tolerados', () async {
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        appVersionProvider.overrideWith((ref) async => '1.0.0'),
        releaseFetcherProvider.overrideWithValue(
          (_) async => {
            'tag_name': 'v2.0.0',
            'body': null,
            'published_at': 'x',
            'assets': 'nope',
          },
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final u = await c.read(updateCheckerProvider.notifier).check(force: true);
    expect(u!.version, '2.0.0');
    expect(u.notes, '');
    expect(u.publishedAt, isNull);
    expect(u.assets, isEmpty);
  });

  group('SPEC-038 R10 · consulta que falha', () {
    const release = {'tag_name': 'v9.0.0', 'html_url': 'https://x/r'};

    /// Answers with the next item of [answers]: a map, null, or a throw.
    Future<ProviderContainer> container(List<Object?> answers) async {
      final queue = [...answers];
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          appVersionProvider.overrideWith((ref) async => '1.0.0'),
          releaseFetcherProvider.overrideWithValue((_) async {
            final a = queue.removeAt(0);
            if (a is Exception) throw a;
            return a as Map<String, dynamic>?;
          }),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      return c;
    }

    Future<AvailableUpdate?> check(ProviderContainer c) =>
        c.read(updateCheckerProvider.notifier).check(force: true);

    final failures = <String, Object?>{
      'rede': const SocketException('sem rede'),
      'tempo esgotado': TimeoutException('lento'),
      'resposta inválida': const ReleaseFetchException('resposta inválida'),
      'sem tag': <String, dynamic>{'html_url': 'https://x/r'},
      'tag sem versão': <String, dynamic>{'tag_name': 'nightly'},
    };
    for (final e in failures.entries) {
      test('${e.key} fica registrado como falha, não como em dia', () async {
        final c = await container([e.value]);
        expect(await check(c), isNull);
        expect(c.read(lastCheckProvider)?.outcome, UpdateCheckOutcome.failed);
      });
    }

    test('sem release e versão igual contam como em dia', () async {
      final c = await container([
        null,
        <String, dynamic>{'tag_name': 'v1.0.0'},
      ]);
      await check(c);
      expect(c.read(lastCheckProvider)?.outcome, UpdateCheckOutcome.upToDate);
      await check(c);
      expect(c.read(lastCheckProvider)?.outcome, UpdateCheckOutcome.upToDate);
    });

    test('a atualização já encontrada continua depois de uma falha', () async {
      final c = await container([release, const SocketException('sem rede')]);
      await check(c);
      expect(c.read(lastCheckProvider)?.outcome, UpdateCheckOutcome.found);
      final u = await check(c);
      expect(u?.version, '9.0.0');
      expect(c.read(updateCheckerProvider)?.version, '9.0.0');
      expect(c.read(lastCheckProvider)?.outcome, UpdateCheckOutcome.failed);
    });

    test('uma consulta boa depois da falha limpa o estado', () async {
      final c = await container([
        release,
        const SocketException('sem rede'),
        <String, dynamic>{'tag_name': 'v1.0.0'},
      ]);
      await check(c);
      await check(c);
      expect(await check(c), isNull);
      expect(c.read(lastCheckProvider)?.outcome, UpdateCheckOutcome.upToDate);
    });

    test('o resultado sobrevive ao reinício e lixo vira null', () {
      final r = UpdateCheckResult(
        UpdateCheckOutcome.failed,
        DateTime(2026, 11, 5, 14, 32),
      );
      final back = UpdateCheckResult.parse(r.encode());
      expect(back?.outcome, UpdateCheckOutcome.failed);
      expect(back?.at, r.at);
      expect(UpdateCheckResult.parse(null), isNull);
      expect(UpdateCheckResult.parse('lixo'), isNull);
      expect(UpdateCheckResult.parse('outro 2026-11-05'), isNull);
    });

    group('fetchLatestRelease', () {
      // The widget binding answers every request with a fake 400.
      final overrides = HttpOverrides.current;
      setUp(() => HttpOverrides.global = null);
      tearDown(() => HttpOverrides.global = overrides);

      /// A local server that answers [status] with [body].
      Future<String> serve(int status, String body) async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((req) {
          req.response
            ..statusCode = status
            ..write(body)
            ..close();
        });
        return 'http://127.0.0.1:${server.port}/latest';
      }

      test('404 é "sem release"', () async {
        final url = await serve(404, '{}');
        expect(await fetchLatestRelease('1.0.0', url: url), isNull);
      });

      test('200 devolve o JSON', () async {
        final url = await serve(200, '{"tag_name": "v2.0.0"}');
        final r = await fetchLatestRelease('1.0.0', url: url);
        expect(r?['tag_name'], 'v2.0.0');
      });

      for (final (status, body) in [
        (500, 'erro'),
        (403, '{"message": "rate limit"}'),
        (200, 'isto não é json'),
        (200, '[1, 2]'),
      ]) {
        test('$status com "$body" é falha', () async {
          final url = await serve(status, body);
          await expectLater(
            fetchLatestRelease('1.0.0', url: url),
            throwsA(anything),
          );
        });
      }

      test('sem rede é falha', () async {
        final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final url = 'http://127.0.0.1:${closed.port}/latest';
        await closed.close(force: true);
        await expectLater(
          fetchLatestRelease('1.0.0', url: url),
          throwsA(isA<SocketException>()),
        );
      });
    });

    group('UpdatesCard', () {
      Future<void> pump(WidgetTester tester, ProviderContainer c) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: const MaterialApp(home: Scaffold(body: UpdatesCard())),
          ),
        );
        await tester.pump();
      }

      String status(WidgetTester tester) => tester
          .widget<Text>(find.byKey(const ValueKey('update-status')))
          .data!;

      Future<void> tapCheck(WidgetTester tester) async {
        await tester.tap(find.byKey(const ValueKey('update-check-now')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        await tester.pump();
      }

      testWidgets('a falha não vira "versão mais recente"', (tester) async {
        final c = (await tester.runAsync(
          () => container([
            const SocketException('sem rede'),
            <String, dynamic>{'tag_name': 'v1.0.0'},
          ]),
        ))!;
        await pump(tester, c);
        expect(status(tester), '');
        await tapCheck(tester);
        expect(status(tester), 'Não foi possível verificar atualizações.');
        await tapCheck(tester);
        expect(status(tester), 'Você está na versão mais recente.');
      });

      testWidgets('depois de uma falha, a versão encontrada continua', (
        tester,
      ) async {
        final c = (await tester.runAsync(
          () => container([release, const SocketException('sem rede')]),
        ))!;
        await pump(tester, c);
        await tapCheck(tester);
        expect(status(tester), 'Versão 9.0.0 disponível.');
        await tapCheck(tester);
        expect(status(tester), 'Versão 9.0.0 disponível.');
      });
    });
  });

  group('PackageInfo falha', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/package_info'),
            (_) async => throw PlatformException(code: 'boom'),
          );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/package_info'),
            null,
          );
    });

    test('appVersionProvider devolve 0.0.0', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(await c.read(appVersionProvider.future), '0.0.0');
    });

    testWidgets('UpdatesCard renderiza sem exceção', (tester) async {
      final c = ProviderContainer(
        overrides: [databaseOverride(memoryDatabase())],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: UpdatesCard())),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('update-check-toggle')), findsOneWidget);
    });
  });
}
