import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_neutral.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../codex/fake_codex.dart';

/// SPEC-095: the neutral events, from Claude and from Codex (the real 0.170
/// transcripts of SPEC-093 replayed by the fake App Server).
const _dir = 'test/fixtures/codex/0.170';

Map<String, Map<String, dynamic>> _handshake() {
  final t = readCodexTranscript('$_dir/handshake.jsonl');
  Map<String, dynamic> resultOf(String method) {
    final id = t
        .firstWhere((l) => l.dir == 'send' && l.msg['method'] == method)
        .msg['id'];
    return t
            .firstWhere(
              (l) =>
                  l.dir == 'recv' &&
                  l.msg['method'] == null &&
                  l.msg['id'] == id,
            )
            .msg['result']
        as Map<String, dynamic>;
  }

  return {
    'account/read': resultOf('account/read'),
    'model/list': resultOf('model/list'),
  };
}

/// Replays [fixture] through a real `CodexRun`; returns its events.
Future<List<AgentEvent>> replayCodex(
  String fixture, {
  ClaudePermissionMode? permissionMode,
  PromptMode? mode,
  List<CodexLine> Function(List<CodexLine>)? edit,
  int turns = 1,
}) async {
  var t = readCodexTranscript('$_dir/$fixture.jsonl');
  if (edit != null) t = edit(t);
  final fake = FakeCodex.replay(t, fallback: _handshake());
  final run =
      await CodexProvider(
            starter: (exe, args, {workingDirectory, environment}) async => fake,
          ).start(
            AgentStartOptions(
              workingDirectory: '/w',
              mode:
                  mode ??
                  (fixture == 'contexto' ? PromptMode.ask : PromptMode.edit),
              model: 'gpt-5.6-luna',
              permissionMode: permissionMode,
            ),
          )
          as CodexRun;
  final events = <AgentEvent>[];
  run.events.listen((e) {
    events.add(e);
    if (e is PermissionRequest) {
      // The replay may resolve it first.
      unawaited(run.approve(e.requestId).catchError((Object _) {}));
    }
  });
  addTearDown(() async {
    await run.stop(timeout: const Duration(milliseconds: 50));
    await fake.finish();
  });
  for (var n = 0; n < turns; n++) {
    final before = events.whereType<Result>().length;
    await run.send('turno ${n + 1}');
    for (
      var i = 0;
      i < 400 && events.whereType<Result>().length == before;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
  return events;
}

List<ToolUseBlock> _toolUses(List<AgentEvent> events) => [
  for (final m in events.whereType<AssistantMessage>())
    ...m.blocks.whereType<ToolUseBlock>(),
];

AssistantMessage _claudeTool(String name, Map<String, dynamic> input) =>
    AgentEvent.fromJson({
      'type': 'assistant',
      'message': {
        'id': 'msg_1',
        'content': [
          {'type': 'tool_use', 'id': 'toolu_1', 'name': name, 'input': input},
        ],
      },
    }) as AssistantMessage;

void main() {
  group('R1, R8 · FileChangeEvent', () {
    test('the real fileChange of edicao (two adds) after approval', () async {
      final events = await replayCodex('edicao');
      final applied = events
          .whereType<FileChangeEvent>()
          .where((f) => f.status == FileChangeStatus.applied)
          .toList();
      expect(applied.map((f) => f.path.split('/').last), [
        'base.txt',
        'nota.txt',
      ]);
      expect(applied.every((f) => f.kind == FileChangeKind.add), isTrue);
      expect(applied.first.unifiedDiff, '@@ -0,0 +1,1 @@\n+linha dois\n');
      expect(_toolUses(events).where((b) => b.name == 'Edit'), isEmpty);
      // The approval keeps the current vocabulary (R7).
      expect(events.whereType<PermissionRequest>().single.toolName, 'Edit');
    });

    test('update with move_path is a move with fromPath', () {
      final f = codexFileChange(
        {
          'path': '/r/a.dart',
          'kind': {'type': 'update', 'move_path': '/r/b.dart'},
          'diff': '@@ -1 +1 @@\n-a\n+b\n',
        },
        toolUseId: 'i1',
        index: 0,
        status: 'completed',
      );
      final e = AgentEvent.fromJson(f.json) as FileChangeEvent;
      expect(e.kind, FileChangeKind.move);
      expect(e.path, '/r/b.dart');
      expect(e.fromPath, '/r/a.dart');
      expect(e.status, FileChangeStatus.applied);
    });

    test('the update of edicao-turno converts with kind and hunk', () {
      final t = readCodexTranscript('$_dir/edicao-turno.jsonl');
      final item = t
          .where((l) => l.msg['method'] == 'item/completed')
          .map((l) => l.msg['params']['item'] as Map<String, dynamic>)
          .firstWhere((i) => i['type'] == 'fileChange');
      final changes = item['changes'] as List;
      final f = codexFileChange(
        changes.first as Map<String, dynamic>,
        toolUseId: '${item['id']}',
        index: 0,
        status: item['status'],
      );
      final e = AgentEvent.fromJson(f.json) as FileChangeEvent;
      expect(e.kind, FileChangeKind.update);
      expect(e.path, endsWith('/base.txt'));
      expect(e.unifiedDiff, '@@ -1 +1 @@\n-base\n+linha dois\n');
      expect(e.stats, (1, 1));
    });

    test('a failed fileChange (worktree, never) is failed', () async {
      final events = await replayCodex(
        'worktree-com_roots_never',
        permissionMode: ClaudePermissionMode.dontAsk,
      );
      final last = events.whereType<FileChangeEvent>().last;
      expect(last.status, FileChangeStatus.failed);
      expect(events.whereType<ToolResult>(), isEmpty);
    });

    test('Claude Edit, Write, MultiEdit and NotebookEdit', () {
      final edit =
          _claudeTool('Edit', {
                'file_path': '/r/a.dart',
                'old_string': 'a',
                'new_string': 'b',
              }).blocks.single
              as ToolUseBlock;
      final f = edit.fileChanges.single;
      expect(f.path, '/r/a.dart');
      expect(f.kind, FileChangeKind.update);
      expect(f.before, 'a');
      expect(f.after, 'b');
      expect(f.provider, 'claude');
      expect(f.toolUseId, 'toolu_1');

      final write =
          _claudeTool('Write', {
                'file_path': '/r/n.dart',
                'content': 'x\n',
              }).blocks.single
              as ToolUseBlock;
      expect(write.fileChanges.single.kind, FileChangeKind.add);
      expect(write.fileChanges.single.after, 'x\n');

      final multi =
          _claudeTool('MultiEdit', {
                'file_path': '/r/m.dart',
                'edits': [
                  {'old_string': '1', 'new_string': '2'},
                  {'old_string': '3', 'new_string': '4', 'replace_all': true},
                ],
              }).blocks.single
              as ToolUseBlock;
      expect(multi.fileChanges.single.edits, [
        {'old': '1', 'new': '2', 'all': false},
        {'old': '3', 'new': '4', 'all': true},
      ]);

      final nb =
          _claudeTool('NotebookEdit', {
                'notebook_path': '/r/n.ipynb',
                'new_source': 'print(1)',
              }).blocks.single
              as ToolUseBlock;
      expect(nb.fileChanges.single.path, '/r/n.ipynb');

      final read =
          _claudeTool('Read', {'file_path': '/r/a.dart'}).blocks.single
              as ToolUseBlock;
      expect(read.fileChanges, isEmpty);
      expect(read.command, isNull);
    });
  });

  group('R2, R8 · CommandEvent', () {
    test('commandExecution with output and exitCode', () async {
      final events = await replayCodex(
        'comando',
        permissionMode: ClaudePermissionMode.defaultMode,
      );
      final done = events
          .whereType<CommandEvent>()
          .where((c) => c.done)
          .toList();
      expect(done.map((c) => c.exitCode), [0, 1, 0]);
      expect(done.map((c) => c.failed), [false, true, false]);
      expect(done.first.output, 'base.txt\n');
      expect(done.first.displayCommand, 'ls');
      expect(done[1].displayCommand, 'cat nao-existe.txt');
      expect(done[1].reads.single, endsWith('/nao-existe.txt'));
      expect(done.last.output, contains('agente=codex'));
      expect(done.first.durationMs, 0);
      expect(done.first.cwd, isNotNull);
      // Started events come first, running.
      expect(
        events.whereType<CommandEvent>().where((c) => !c.done),
        hasLength(3),
      );
      expect(_toolUses(events).where((b) => b.name == 'Bash'), isEmpty);
      expect(events.whereType<ToolResult>(), isEmpty);
    });

    test('Claude Bash + its tool_result', () {
      final b =
          _claudeTool('Bash', {'command': 'flutter test'}).blocks.single
              as ToolUseBlock;
      final start = b.command!;
      expect(start.command, 'flutter test');
      expect(start.status, CommandStatus.running);
      expect(start.provider, 'claude');
      final ok = start.completedWith(output: 'All passed', isError: false);
      expect(ok.exitCode, 0);
      expect(ok.status, CommandStatus.completed);
      final bad = start.completedWith(
        output: 'Error: Exit code 2\nboom',
        isError: true,
      );
      expect(bad.exitCode, 2);
      expect(bad.failed, isTrue);
    });
  });

  group('R3 · ContextUsageEvent from Claude', () {
    test('usage of a top-level call', () {
      final m = AgentEvent.fromJson({
        'type': 'assistant',
        'message': {
          'id': 'msg_9',
          'model': 'claude-opus',
          'usage': {
            'input_tokens': 10,
            'cache_creation_input_tokens': 20,
            'cache_read_input_tokens': 30,
            'output_tokens': 99,
          },
          'content': const [],
        },
      }) as AssistantMessage;
      final u = m.contextUsage!;
      expect(u.tokens, 60);
      expect(u.input, 10);
      expect(u.cacheWrite, 20);
      expect(u.cacheRead, 30);
      expect(u.source, ContextUsageEvent.claudeUsage);
      expect(u.messageId, 'msg_9');
    });
  });

  group('R5 · QuotaEvent', () {
    test('rate_limit_event of Claude', () {
      final r = AgentEvent.fromJson({
        'type': 'rate_limit_event',
        'rate_limit_info': {
          'status': 'rejected',
          'rateLimitType': 'five_hour',
          'unifiedWindows': {
            'five_hour': {'utilization': 0.42, 'resetsAt': 1795242735},
            'seven_day': {'utilization': 0.15, 'resetsAt': 1795806604},
          },
        },
      }) as RateLimit;
      final q = r.quota;
      expect(q.provider, 'claude');
      expect(q.windows.map((w) => w.label), ['5 h', 'semana']);
      expect(q.windows.first.usedPercent, closeTo(42, 0.001));
      expect(q.windows.last.minutes, 10080);
      expect(q.reached, 'five_hour');
    });

    test('account/rateLimits/updated of Codex (real payload)', () async {
      final events = await replayCodex('contexto');
      final q = events.whereType<QuotaEvent>().first;
      expect(q.provider, 'codex');
      expect(q.plan, 'plus');
      expect(q.windows.map((w) => (w.id, w.label, w.usedPercent)), [
        ('primary', '5 h', 0.0),
        ('secondary', 'semana', 15.0),
      ]);
      expect(
        q.windows.first.resetsAt,
        DateTime.fromMillisecondsSinceEpoch(1795242735000, isUtc: true),
      );
      expect(q.reached, isNull);
      // P5: never stored.
      expect(isStoredEvent(q), isFalse);
    });
  });

  group('R6 · OtherItemEvent', () {
    test('an item without translation is kept with its type', () async {
      final events = await replayCodex(
        'contexto',
        edit: (t) {
          final i = t.indexWhere(
            (l) =>
                l.msg['method'] == 'item/completed' &&
                (l.msg['params']['item'] as Map)['type'] == 'agentMessage',
          );
          final thread = t[i].msg['params']['threadId'];
          return [
            ...t.take(i),
            (
              dir: 'recv',
              msg: {
                'method': 'item/completed',
                'params': {
                  'threadId': thread,
                  'item': {
                    'type': 'plan',
                    'id': 'plan-1',
                    'text': '1. rótulo\n2. testes',
                  },
                },
              },
            ),
            ...t.skip(i),
          ];
        },
      );
      final o = events.whereType<OtherItemEvent>().single;
      expect(o.itemType, 'plan');
      expect(o.summary, '1. rótulo 2. testes');
      expect(o.toolUseId, 'plan-1');
    });
  });

  group('R11, R12 · stored shape', () {
    test('a stored Codex event has type, v, provider and no secret', () async {
      final events = await replayCodex(
        'comando',
        permissionMode: ClaudePermissionMode.defaultMode,
        edit: (t) => [
          for (final l in t)
            if (l.msg['method'] == 'item/completed' &&
                (l.msg['params']['item'] as Map)['type'] == 'commandExecution')
              (
                dir: l.dir,
                msg: {
                  ...l.msg,
                  'params': {
                    ...l.msg['params'] as Map<String, dynamic>,
                    'item': {
                      ...l.msg['params']['item'] as Map<String, dynamic>,
                      'aggregatedOutput': 'token sk-abc123SECRET\n',
                    },
                  },
                },
              )
            else
              l,
        ],
      );
      final c = events.whereType<CommandEvent>().last;
      final stored = jsonDecode(eventJson(c)) as Map<String, dynamic>;
      expect(stored['type'], 'promptorium_command');
      expect(stored['v'], 1);
      expect(stored['provider'], 'codex');
      expect(stored['session_id'], isNotNull);
      expect(eventJson(c), isNot(contains('sk-abc123SECRET')));
      expect(eventTypeKey(c), 'promptorium_command');
      // Reopened: the stored row parses back to the same type.
      final back = AgentEvent.fromJson(stored);
      expect(back, isA<CommandEvent>());
      expect((back as CommandEvent).exitCode, c.exitCode);
    });

    test('a diff over the limit is stored cut with the mark', () async {
      final big = List.generate(2500, (i) => 'linha $i').join('\n');
      final events = await replayCodex(
        'edicao',
        edit: (t) => [
          for (final l in t)
            if (l.msg['method'] == 'item/completed' &&
                (l.msg['params']['item'] as Map)['type'] == 'fileChange')
              (
                dir: l.dir,
                msg: {
                  ...l.msg,
                  'params': {
                    ...l.msg['params'] as Map<String, dynamic>,
                    'item': {
                      ...l.msg['params']['item'] as Map<String, dynamic>,
                      'changes': [
                        {
                          'path': '/w/grande.txt',
                          'kind': {'type': 'add'},
                          'diff': '$big\n',
                        },
                      ],
                    },
                  },
                },
              )
            else
              l,
        ],
      );
      final live = events
          .whereType<FileChangeEvent>()
          .where((f) => f.path == '/w/grande.txt')
          .single;
      // Live: the whole diff (2500 lines + the header).
      expect(
        live.unifiedDiff!.split('\n').where((l) => l.startsWith('+')),
        hasLength(2500),
      );
      expect(live.isCut, isFalse);
      // Stored: 2000 lines and the mark.
      final stored = jsonDecode(eventJson(live)) as Map<String, dynamic>;
      expect('${stored['diff']}'.trimRight().split('\n'), hasLength(2000));
      expect(stored['diff_cut'], 501);
      final reopened = AgentEvent.fromJson(stored) as FileChangeEvent;
      expect(reopened.isCut, isTrue);
      expect(reopened.cutLabel, 'diff cortado: 501 linhas');
    });

    test('the byte limit cuts before the line limit', () {
      final line = 'x' * 1000;
      final text = List.filled(400, line).join('\n');
      final c = NeutralLimits.cut(text);
      expect(c.cut, greaterThan(0));
      expect(c.text.length, lessThanOrEqualTo(NeutralLimits.maxBytes));
    });

    test('old fake Codex events still open the current way', () {
      final old = AgentEvent.fromJson({
        'type': 'assistant',
        'provider': 'codex',
        'message': {
          'id': 'exec-1',
          'content': [
            {
              'type': 'tool_use',
              'id': 'exec-1',
              'name': 'Edit',
              'input': {
                'changes': [
                  {'path': '/w/a.txt', 'kind': 'add', 'diff': 'a\n'},
                ],
              },
            },
          ],
        },
      });
      expect(old, isA<AssistantMessage>());
      final t = Timeline()..apply(old);
      expect(t.items.whereType<ToolItem>().single.name, 'Edit');
    });
  });
}
