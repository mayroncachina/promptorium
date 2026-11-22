import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/claude/usage_tracker.dart';
import 'package:promptorium/core/providers/agent_registry.dart' show ImagePart;
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/core/providers/structured_run.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/cost/usage_ledger.dart';

import '../codex/fake_codex.dart';
import '../../features/sessions/session_test_utils.dart'
    show FakeCli, settle, until;
import '../../helpers/test_db.dart';

const _schema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['titulo'],
  'properties': {
    'titulo': {'type': 'string'},
    'nota': {'type': 'string'},
  },
};

void main() {
  late Directory tmp;
  late FakeCli cli;
  late List<FakeCodex> servers;
  late List<List<String>> codexArgs;
  late ProviderContainer c;
  late List<Map<String, dynamic>> models;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-structured-');
    cli = FakeCli();
    servers = [];
    codexArgs = [];
    models = [
      {
        'id': 'gpt-6.1-terra',
        'supportedReasoningEfforts': [
          {'reasoningEffort': 'low'},
          {'reasoningEffort': 'medium'},
        ],
        'inputModalities': ['text', 'image'],
      },
      {
        'id': 'gpt-6-luna',
        'supportedReasoningEfforts': [
          {'reasoningEffort': 'medium'},
        ],
        'inputModalities': ['text'],
      },
    ];
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        claudeProcessStarterProvider.overrideWithValue(cli.start),
        runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
        codexProcessStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
        }) async {
          final s = FakeCodex(threadId: 'th-${servers.length}', models: models);
          servers.add(s);
          codexArgs.add(args);
          return s;
        }),
      ],
    );
    await c.read(appSettingsProvider.notifier).load();
  });

  tearDown(() async {
    c.dispose();
    for (final s in servers) {
      await s.finish();
    }
    tmp.deleteSync(recursive: true);
  });

  Future<void> set(String key, String value) =>
      c.read(appSettingsProvider.notifier).set(key, value);

  Future<StructuredResult> run(StructuredIntent intent) => c.read(
    Provider(
      (ref) =>
          () => runStructured(ref, intent),
    ),
  )();

  Map<String, dynamic> sent(FakeCodex s, String method) =>
      s.writtenJson.lastWhere((m) => m['method'] == method);

  void claudeResult(Map<String, dynamic> data, {double cost = 0.02}) =>
      cli.last.emit(
        jsonEncode({
          'type': 'result',
          'subtype': 'success',
          'result': jsonEncode(data),
          'structured_output': data,
          'total_cost_usd': cost,
          'usage': {'input_tokens': 10, 'output_tokens': 5},
        }),
      );

  void codexUsage(FakeCodex s) => s.emit(
    jsonEncode({
      'method': 'thread/tokenUsage/updated',
      'params': {
        'threadId': s.threadId,
        'tokenUsage': {
          'total': {
            'inputTokens': 12000,
            'cachedInputTokens': 2000,
            'outputTokens': 200,
            'reasoningOutputTokens': 80,
          },
          'last': {'totalTokens': 12200},
        },
      },
    }),
  );

  group('Claude Code (R1, R2, R4)', () {
    test('the read-only options are built by the adapter, with the extras '
        'and the schema', () async {
      final done = run(
        StructuredIntent(
          cwd: tmp.path,
          prompt: 'Planeje',
          instructions: 'Seja breve.',
          schema: _schema,
          claude: const ClaudeStructuredExtras(maxBudgetUsd: 0.5),
        ),
      );
      await until(() async => cli.args.isNotEmpty);
      final args = cli.args.single;
      String arg(String flag) => args[args.indexOf(flag) + 1];
      expect(arg('--tools'), contains('Read'));
      expect(arg('--tools'), isNot(contains('Edit')));
      expect(args, contains('--strict-mcp-config'));
      expect(arg('--permission-mode'), 'default');
      expect(arg('--max-budget-usd'), '0.5');
      expect(arg('--append-system-prompt'), 'Seja breve.');
      expect(jsonDecode(arg('--json-schema')), _schema);
      expect(args, contains('--disallowedTools'));
      claudeResult({'titulo': 'x'});
      final r = await done;
      expect(r.provider, 'claude');
      expect(r.data, {'titulo': 'x'});
      expect(r.costUsd, 0.02);
    });

    test('the profile "rápido" is Haiku · low on the Claude Code', () async {
      final done = run(
        StructuredIntent(
          cwd: tmp.path,
          prompt: 'x',
          profile: StructuredProfile.fast,
          schema: _schema,
        ),
      );
      await until(() async => cli.args.isNotEmpty);
      final args = cli.args.single;
      expect(args[args.indexOf('--model') + 1], 'haiku');
      expect(args[args.indexOf('--effort') + 1], 'low');
      claudeResult({'titulo': 'x'});
      await done;
    });
  });

  group('Codex (R2–R6)', () {
    setUp(() => set(providerPreferenceKey(null), 'codex'));

    test('read-only thread, never asks, no MCP; schema in outputSchema and '
        'instructions in developerInstructions; no Claude option', () async {
      await set('codex.model.planner', 'gpt-6.1-terra');
      final done = run(
        StructuredIntent(
          cwd: tmp.path,
          prompt: 'Planeje',
          instructions: 'Seja breve.',
          schema: _schema,
          claude: const ClaudeStructuredExtras(
            model: 'haiku',
            maxBudgetUsd: 1,
            maxTurns: 3,
            agent: 'revisor',
          ),
        ),
      );
      await until(
        () async =>
            servers.isNotEmpty &&
            servers.single.writtenJson.any((m) => m['method'] == 'turn/start'),
      );
      final s = servers.single;
      expect(codexArgs.single, containsAllInOrder(['-c', 'mcp_servers={}']));
      expect(codexArgs.single.join(' '), isNot(contains('budget')));
      final thread = sent(s, 'thread/start')['params'] as Map;
      expect(thread['sandbox'], 'read-only');
      expect(thread['approvalPolicy'], 'never');
      expect(thread['developerInstructions'], 'Seja breve.');
      // R4: the alias of the Claude never reaches the Codex.
      expect(thread['model'], 'gpt-6.1-terra');
      expect(jsonEncode(s.writtenJson), isNot(contains('haiku')));
      expect(jsonEncode(s.writtenJson), isNot(contains('revisor')));
      final turn = sent(s, 'turn/start')['params'] as Map;
      expect(turn['sandboxPolicy'], {'type': 'readOnly'});
      expect(turn['approvalPolicy'], 'never');
      // R3: the strict variant (the optional `nota` accepts null).
      expect(turn['outputSchema'], codexCompatibleSchema(_schema));
      expect(
        (turn['outputSchema'] as Map)['required'],
        containsAll(['titulo', 'nota']),
      );
      s.answer('{"titulo":"Cupons","nota":null}');
      codexUsage(s);
      s.completeTurn();
      final r = await done;
      expect(r.provider, 'codex');
      expect(r.model, 'gpt-6.1-terra');
      // R3: the null of the variant is absent for the service.
      expect(r.data, {'titulo': 'Cupons'});
      expect(r.costUsd, isNull);
    });

    test('an answer outside the schema is a clear error with the provider '
        '(R3)', () async {
      final done = run(
        StructuredIntent(cwd: tmp.path, prompt: 'x', schema: _schema),
      );
      await until(
        () async =>
            servers.isNotEmpty &&
            servers.single.writtenJson.any((m) => m['method'] == 'turn/start'),
      );
      servers.single.answer('{"nota":"sem título"}');
      servers.single.completeTurn();
      await expectLater(
        done,
        throwsA(
          isA<PlannerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Codex'), contains('titulo')),
          ),
        ),
      );
    });

    test('text that is not JSON is the same clear error (R3)', () async {
      final done = run(
        StructuredIntent(cwd: tmp.path, prompt: 'x', schema: _schema),
      );
      await until(
        () async =>
            servers.isNotEmpty &&
            servers.single.writtenJson.any((m) => m['method'] == 'turn/start'),
      );
      servers.single.answer('Aqui está o plano: …');
      servers.single.completeTurn();
      await expectLater(
        done,
        throwsA(
          isA<PlannerException>().having(
            (e) => e.message,
            'message',
            contains('não é JSON'),
          ),
        ),
      );
    });

    test(
      'approvals for a command and a file change are declined (R2)',
      () async {
        final done = run(
          StructuredIntent(cwd: tmp.path, prompt: 'x', schema: _schema),
        );
        await until(
          () async =>
              servers.isNotEmpty &&
              servers.single.writtenJson.any(
                (m) => m['method'] == 'turn/start',
              ),
        );
        final s = servers.single;
        for (final (id, method) in [
          (901, 'item/commandExecution/requestApproval'),
          (902, 'item/fileChange/requestApproval'),
        ]) {
          s.emit(
            jsonEncode({
              'id': id,
              'method': method,
              'params': {'threadId': s.threadId, 'itemId': 'i$id'},
            }),
          );
        }
        await until(
          () async =>
              s.writtenAll
                  .where((m) => m['id'] == 901 || m['id'] == 902)
                  .length ==
              2,
        );
        for (final id in [901, 902]) {
          expect(s.writtenAll.singleWhere((m) => m['id'] == id)['result'], {
            'decision': 'decline',
          });
        }
        s.answer('{"titulo":"x"}');
        s.completeTurn();
        expect((await done).data, {'titulo': 'x'});
      },
    );

    test(
      'the time limit interrupts the turn and ends the process (R5)',
      () async {
        final done = run(
          StructuredIntent(
            cwd: tmp.path,
            prompt: 'x',
            schema: _schema,
            timeout: const Duration(milliseconds: 300),
          ),
        );
        await expectLater(
          done,
          throwsA(
            isA<PlannerException>().having(
              (e) => e.message,
              'message',
              contains('não respondeu'),
            ),
          ),
        );
        final s = servers.single;
        final interrupt = sent(s, 'turn/interrupt')['params'] as Map;
        expect(interrupt['turnId'], 'turn-1');
        expect(s.signals, isNotEmpty);
      },
    );

    test('cancelling interrupts the turn and counts as cancelled, not as a '
        'failure (R5)', () async {
      final cancel = Completer<void>();
      final done = run(
        StructuredIntent(
          cwd: tmp.path,
          prompt: 'x',
          schema: _schema,
          cancelled: cancel.future,
        ),
      );
      await until(
        () async =>
            servers.isNotEmpty &&
            servers.single.writtenJson.any((m) => m['method'] == 'turn/start'),
      );
      cancel.complete();
      await expectLater(done, throwsA(isA<StructuredCancelled>()));
      expect(
        servers.single.writtenJson.any((m) => m['method'] == 'turn/interrupt'),
        isTrue,
      );
    });

    test(
      'prints go as image input when the model has the modality (R6)',
      () async {
        await set('codex.model.planner', 'gpt-6.1-terra');
        final done = run(
          StructuredIntent(
            cwd: tmp.path,
            prompt: 'Veja o print',
            schema: _schema,
            images: const [ImagePart(mediaType: 'image/png', base64: 'AAAA')],
          ),
        );
        await until(
          () async =>
              servers.isNotEmpty &&
              servers.single.writtenJson.any(
                (m) => m['method'] == 'turn/start',
              ),
        );
        final input = sent(servers.single, 'turn/start')['params']['input'];
        expect(input, [
          {'type': 'text', 'text': 'Veja o print'},
          {'type': 'image', 'url': 'data:image/png;base64,AAAA'},
        ]);
        servers.single.answer('{"titulo":"x"}');
        servers.single.completeTurn();
        await done;
      },
    );

    test('a model without images refuses the prints instead of dropping '
        'them (R6)', () async {
      await set('codex.model.planner', 'gpt-6-luna');
      await expectLater(
        run(
          StructuredIntent(
            cwd: tmp.path,
            prompt: 'Veja',
            schema: _schema,
            images: const [ImagePart(mediaType: 'image/png', base64: 'AAAA')],
          ),
        ),
        throwsA(
          isA<StructuredImagesUnsupported>()
              .having((e) => e.count, 'count', 1)
              .having(
                (e) => e.message,
                'message',
                'O modelo gpt-6-luna do Codex não lê imagens.',
              ),
        ),
      );
      // Nothing was sent: no turn without the prints.
      expect(
        servers.single.writtenJson.any((m) => m['method'] == 'turn/start'),
        isFalse,
      );
    });

    test(
      'the profile "rápido" is the kind\'s model with effort low (P2)',
      () async {
        await set('codex.model.planner', 'gpt-6.1-terra');
        await set('codex.effort.planner', 'medium');
        final done = run(
          StructuredIntent(
            cwd: tmp.path,
            prompt: 'x',
            schema: _schema,
            profile: StructuredProfile.fast,
          ),
        );
        await until(
          () async =>
              servers.isNotEmpty &&
              servers.single.writtenJson.any(
                (m) => m['method'] == 'turn/start',
              ),
        );
        final s = servers.single;
        expect(sent(s, 'thread/start')['params']['model'], 'gpt-6.1-terra');
        expect(sent(s, 'turn/start')['params']['effort'], 'low');
        s.answer('{"titulo":"x"}');
        s.completeTurn();
        await done;
      },
    );

    test('the ledger keeps the Codex tokens without a cost, and its quota '
        'never reaches the Claude tracker (R12)', () async {
      await set('codex.model.planner', 'gpt-6.1-terra');
      final done = run(
        StructuredIntent(
          cwd: tmp.path,
          prompt: 'x',
          schema: _schema,
          usageSource: UsageSource.verificacao,
        ),
      );
      await until(
        () async =>
            servers.isNotEmpty &&
            servers.single.writtenJson.any((m) => m['method'] == 'turn/start'),
      );
      final s = servers.single;
      s.emit(
        jsonEncode({
          'method': 'account/rateLimits/updated',
          'params': {
            'rateLimits': {
              'limitId': 'codex',
              'primary': {'usedPercent': 41, 'windowDurationMins': 300},
            },
          },
        }),
      );
      s.answer('{"titulo":"x"}');
      codexUsage(s);
      s.completeTurn();
      final r = await done;
      expect(r.usage.total, greaterThan(0));
      final db = c.read(appDatabaseProvider);
      final e = await db.select(db.usageEntries).getSingle();
      expect(e.provider, 'codex');
      expect(e.model, 'gpt-6.1-terra');
      expect(e.tokensReasoning, 80);
      expect(entryHasCost(e), isFalse);
      expect(c.read(rateLimitProvider), isNull);
    });
  });

  group('provider of the run (R7, R9, R11)', () {
    test('a continuation runs on the original provider and thread, even '
        'after the kind changed (R7)', () async {
      await set(ProviderKind.planner.settingKey, 'codex');
      final first = run(
        StructuredIntent(
          cwd: tmp.path,
          prompt: 'Plano',
          schema: _schema,
          sessionId: 'plano-1',
        ),
      );
      await until(
        () async =>
            servers.isNotEmpty &&
            servers.single.writtenJson.any((m) => m['method'] == 'turn/start'),
      );
      servers.single.answer('{"titulo":"v1"}');
      servers.single.completeTurn();
      await first;
      await settle();
      await set(ProviderKind.planner.settingKey, 'claude');
      final second = run(
        StructuredIntent(
          cwd: tmp.path,
          prompt: 'Refine',
          schema: _schema,
          resumeId: 'plano-1',
        ),
      );
      await until(
        () async =>
            servers.length == 2 &&
            servers.last.writtenJson.any((m) => m['method'] == 'turn/start'),
      );
      expect(cli.processes, isEmpty);
      final resume = sent(servers.last, 'thread/resume')['params'] as Map;
      expect(resume['threadId'], 'th-0');
      servers.last.answer('{"titulo":"v2"}');
      servers.last.completeTurn();
      expect((await second).data, {'titulo': 'v2'});
    });

    test('a provider that cannot start says which and why, and offers the '
        'other one; nothing switches by itself (R11)', () async {
      await set(ProviderKind.planner.settingKey, 'claude');
      cli.failStart = true;
      await expectLater(
        run(StructuredIntent(cwd: tmp.path, prompt: 'x', schema: _schema)),
        throwsA(
          isA<StructuredProviderFailure>()
              .having((e) => e.provider, 'provider', 'claude')
              .having((e) => e.alternative, 'alternative', 'codex')
              .having((e) => e.message, 'message', contains('Claude Code')),
        ),
      );
      expect(servers, isEmpty);
    });
  });
}
