import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/core/providers/context_events.dart';

import 'codex_replay.dart';
import 'fake_codex.dart';

/// SPEC-107 T1: the Codex adapter feeds the context contract of SPEC-087
/// from the real 0.170 transcripts of SPEC-093.

/// A recorded notification line (`recv`).
CodexLine _note(String method, Map<String, dynamic> params) =>
    (dir: 'recv', msg: {'method': method, 'params': params});

const _thread = '01a1fbbd-1684-7a72-997b-808791830b3b';

/// [extra] inserted right before the first `turn/completed`.
List<CodexLine> Function(List<CodexLine>) _beforeFirstTurnEnd(
  List<CodexLine> extra,
) => (t) {
  final i = t.indexWhere((l) => l.msg['method'] == 'turn/completed');
  return [...t.take(i), ...extra, ...t.skip(i)];
};

/// Starts a run over [fake] and collects its events.
Future<(CodexRun, List<AgentEvent>)> _start(
  FakeCodex fake, {
  CodexExtras? extras,
}) async {
  final run =
      await CodexProvider(
            starter: (exe, args, {workingDirectory, environment}) async => fake,
          ).start(
            AgentStartOptions(
              workingDirectory: '/w',
              mode: PromptMode.ask,
              extras: extras,
            ),
          )
          as CodexRun;
  final events = <AgentEvent>[];
  run.events.listen(events.add);
  addTearDown(() async {
    await run.stop(timeout: const Duration(milliseconds: 50));
    await fake.finish();
  });
  return (run, events);
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('R1, R3, R4 · readings from `last`', () {
    test('one reading per call with output, turn id and window', () async {
      final events = await replayCodex('contexto', turns: 2);
      final readings = events.whereType<ContextUsageEvent>().toList();
      expect(readings.map((r) => r.tokens), [12403, 14052]);
      final first = readings.first;
      // last.totalTokens = inputTokens (with the cache) + outputTokens.
      expect(first.input, 12393 - 10112);
      expect(first.cacheRead, 10112);
      expect(first.output, 10);
      expect(first.input + first.cacheRead + first.output, first.tokens);
      expect(first.window, 258400);
      expect(first.turnId, isNotEmpty);
      expect(readings[1].turnId, isNot(first.turnId));
      expect(first.provider, 'codex');
      // The turn total (26 455) never becomes a reading.
      expect(readings.map((r) => r.tokens), isNot(contains(26455)));
    });

    test('tokenUsage of another thread (a subagent) is dropped', () async {
      final events = await replayCodex(
        'contexto',
        edit: _beforeFirstTurnEnd([
          _note('thread/tokenUsage/updated', {
            'threadId': 'subagente-7f2e',
            'turnId': 't-sub',
            'tokenUsage': {
              'last': {'totalTokens': 99000, 'inputTokens': 99000},
              'modelContextWindow': 100000,
            },
          }),
        ]),
      );
      expect(events.whereType<ContextUsageEvent>().map((r) => r.tokens), [
        12403,
      ]);
    });
  });

  group('R7 · compaction items', () {
    test('a repeated item and a duplicated thread/compacted mark once', () {
      return replayCodex(
        'contexto',
        edit: (t) {
          final turn =
              (t
                      .firstWhere((l) => l.msg['method'] == 'turn/started')
                      .msg['params']
                  as Map)['turn']['id'];
          final item = {'id': 'cc-1', 'type': 'contextCompaction'};
          return _beforeFirstTurnEnd([
            for (final m in ['item/started', 'item/started'])
              _note(m, {'threadId': _thread, 'item': item}),
            for (final m in ['item/completed', 'item/completed'])
              _note(m, {'threadId': _thread, 'item': item}),
            for (var i = 0; i < 2; i++)
              _note('thread/compacted', {'threadId': _thread, 'turnId': turn}),
          ])(t);
        },
      ).then((events) {
        final c = events.whereType<CompactionEvent>().toList();
        expect(c.map((e) => e.phase), [
          CompactionEventPhase.started,
          CompactionEventPhase.completed,
        ]);
        expect(c.every((e) => e.trigger == 'auto'), isTrue);
      });
    });

    test('thread/compacted alone is the fallback, once per turn', () async {
      final events = await replayCodex(
        'contexto',
        edit: _beforeFirstTurnEnd([
          _note('thread/compacted', {'threadId': _thread, 'turnId': 't9'}),
          _note('thread/compacted', {'threadId': _thread, 'turnId': 't9'}),
        ]),
      );
      final c = events.whereType<CompactionEvent>().toList();
      expect(c, hasLength(1));
      expect(c.single.phase, CompactionEventPhase.completed);
      expect(c.single.key, 'compacted:t9');
    });

    test('a turn error during the compaction becomes "falhou"', () async {
      final events = await replayCodex(
        'contexto',
        edit: (t) {
          final i = t.indexWhere((l) => l.msg['method'] == 'turn/completed');
          final done = t[i].msg['params'] as Map<String, dynamic>;
          return [
            ...t.take(i),
            _note('item/started', {
              'threadId': _thread,
              'item': {'id': 'cc-2', 'type': 'contextCompaction'},
            }),
            _note('turn/completed', {
              ...done,
              'turn': {
                ...(done['turn'] as Map),
                'status': 'failed',
                'error': {'message': 'falhou ao resumir'},
              },
            }),
            ...t.skip(i + 1),
          ];
        },
      );
      final c = events.whereType<CompactionEvent>().toList();
      expect(c.last.phase, CompactionEventPhase.failed);
      expect(c.last.error, 'falhou ao resumir');
    });
  });

  group('R8, R9 · Compactar agora', () {
    test(
      'thread/compact/start once, manual, ends without a work turn',
      () async {
        final t = readCodexTranscript('$codexFixtures/contexto.jsonl');
        final fake = FakeCodex.replay(t, fallback: codexHandshake());
        final (run, events) = await _start(fake);
        for (var n = 0; n < 2; n++) {
          final before = events.whereType<Result>().length;
          await run.send('turno ${n + 1}');
          await _until(() => events.whereType<Result>().length > before);
        }
        final before = events.whereType<Result>().length;
        await run.compactNow();
        // R8: one request at a time; a second one while it runs is refused.
        await expectLater(run.compactNow(), throwsA(isA<AgentUnavailable>()));
        await _until(() => events.whereType<Result>().length > before);
        final sent = [
          for (final m in fake.writtenAll)
            if (m['method'] == 'thread/compact/start') m,
        ];
        expect(sent, hasLength(1));
        // R9: no focus, no "resuma" prompt.
        expect(sent.single['params'], {'threadId': _thread});
        expect(
          fake.writtenAll.where((m) => m['method'] == 'turn/start'),
          hasLength(2),
        );
        final compactions = events.whereType<CompactionEvent>().toList();
        expect(compactions.map((e) => e.trigger).toSet(), {'manual'});
        expect(compactions.last.phase, CompactionEventPhase.completed);
        expect(compactions.last.postTokens, 15663);
        final result = events.whereType<Result>().last;
        expect(result.json['num_turns'], 0);
        // The thread is idle again: a new compaction may go.
        expect(run.steering, isFalse);
      },
    );
  });

  group('R6 · threshold sent and effective', () {
    test('the sent limit goes in thread/start; config/read only adds the '
        'scope', () async {
      final fake = FakeCodex.replay(
        readCodexTranscript('$codexFixtures/contexto.jsonl'),
        fallback: {
          ...codexHandshake(),
          'config/read': {
            'config': {
              'model_auto_compact_token_limit': 180000,
              'model_auto_compact_token_limit_scope': 'total',
            },
          },
        },
      );
      final (_, events) = await _start(
        fake,
        extras: const CodexExtras(compactLimit: '300k'),
      );
      await _until(() => events.whereType<UnknownEvent>().isNotEmpty);
      final start = fake.writtenAll.firstWhere(
        (m) => m['method'] == 'thread/start',
      );
      expect(start['params']['config'], {
        'model_auto_compact_token_limit': 300000,
      });
      final config = events
          .whereType<UnknownEvent>()
          .firstWhere((e) => e.json['type'] == ContextAppEvents.agentConfig)
          .json;
      // The thread override wins over the config layers.
      expect(config['autocompact_limit'], isNull);
      expect(config['autocompact_scope'], 'total');
    });

    test('nothing sent: the effective limit of config/read', () async {
      final fake = FakeCodex.replay(
        readCodexTranscript('$codexFixtures/contexto.jsonl'),
        fallback: {
          ...codexHandshake(),
          'config/read': {
            'config': {'model_auto_compact_token_limit': 180000},
          },
        },
      );
      final (_, events) = await _start(
        fake,
        extras: const CodexExtras(compactLimit: 'auto'),
      );
      await _until(() => events.whereType<UnknownEvent>().isNotEmpty);
      final start = fake.writtenAll.firstWhere(
        (m) => m['method'] == 'thread/start',
      );
      expect(start['params'].containsKey('config'), isFalse);
      final config = events
          .whereType<UnknownEvent>()
          .firstWhere((e) => e.json['type'] == ContextAppEvents.agentConfig)
          .json;
      expect(config['autocompact_limit'], 180000);
      expect(config['source'], 'config/read');
    });
  });

  group('R10, R11 · sources', () {
    test('instructionSources become a stored event', () async {
      final events = await replayCodex('contexto');
      final e = events.whereType<UnknownEvent>().firstWhere(
        (e) => e.json['type'] == ContextAppEvents.instructions,
      );
      expect(e.json['sources'], ['<sonda>/repos/contexto/repo/CLAUDE.md']);
      expect(isStoredEvent(e), isTrue);
    });

    test('commandActions of known types; unknown is not a read', () async {
      final events = await replayCodex(
        'comando',
        permissionMode: ClaudePermissionMode.defaultMode,
      );
      final actions = [
        for (final c in events.whereType<CommandEvent>())
          for (final a in c.actions) a.type,
      ];
      expect(actions, containsAll(['read', 'listFiles']));
      final unknown = codexCommandActions([
        {'type': 'unknown', 'command': 'rm apagar.txt'},
        {'type': 'search', 'command': 'rg x', 'query': 'x', 'path': 'lib'},
        {'type': 'read', 'command': 'cat', 'name': 'a'},
      ]);
      expect(unknown.map((a) => (a.type, a.path, a.query)), [
        ('search', 'lib', 'x'),
      ]);
    });
  });

  group('R12 · model changes', () {
    test('model/rerouted and a settings change mark; readings follow the '
        'new model', () async {
      final events = await replayCodex(
        'contexto',
        turns: 2,
        edit: (t) {
          final i = t.indexWhere((l) => l.msg['method'] == 'turn/started');
          final j = t.indexWhere(
            (l) => l.msg['method'] == 'turn/started',
            i + 1,
          );
          return [
            ...t.take(i + 1),
            _note('model/rerouted', {
              'threadId': _thread,
              'turnId': 't1',
              'fromModel': 'gpt-5.6-luna',
              'toModel': 'gpt-5.6-terra',
              'reason': 'highRiskCyberActivity',
            }),
            ...t.sublist(i + 1, j + 1),
            _note('thread/settings/updated', {
              'threadId': _thread,
              'threadSettings': {'model': 'gpt-5.6-sol'},
            }),
            _note('thread/settings/updated', {
              'threadId': _thread,
              'threadSettings': {'model': 'gpt-5.6-sol'},
            }),
            ...t.skip(j + 1),
          ];
        },
      );
      final changes = [
        for (final e in events.whereType<UnknownEvent>())
          if (e.json['type'] == ContextAppEvents.modelChange) e.json,
      ];
      expect(changes.map((c) => (c['from'], c['to'], c['reason'])), [
        ('gpt-5.6-luna', 'gpt-5.6-terra', 'rerouted'),
        ('gpt-5.6-terra', 'gpt-5.6-sol', 'settings'),
      ]);
      expect(events.whereType<ContextUsageEvent>().map((r) => r.model), [
        'gpt-5.6-terra',
        'gpt-5.6-sol',
      ]);
    });
  });
}

/// The known actions of a `commandActions` list.
List<CommandAction> codexCommandActions(List<Map<String, dynamic>> raw) => [
  for (final a in raw) ?CommandAction.fromJson(a),
];
