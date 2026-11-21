import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/core/providers/agent_provider.dart';

import 'fake_codex.dart';

/// Replays a real 0.170 transcript through a real `CodexRun` (SPEC-095).
/// Real App Server transcripts of SPEC-093.
const codexFixtures = 'test/fixtures/codex/0.170';
const _dir = codexFixtures;

/// `account/read` and `model/list` of the handshake transcript.
Map<String, Map<String, dynamic>> codexHandshake() {
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
  Future<void> Function(CodexRun run)? afterTurns,
}) async {
  var t = readCodexTranscript('$_dir/$fixture.jsonl');
  if (edit != null) t = edit(t);
  final fake = FakeCodex.replay(t, fallback: codexHandshake());
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
  if (afterTurns != null) {
    final before = events.length;
    await afterTurns(run);
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (events.length > before &&
          events
              .skip(before)
              .any(
                (e) =>
                    e is CompactionEvent &&
                    e.phase != CompactionEventPhase.started,
              )) {
        break;
      }
    }
  }
  return events;
}
