import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/codex/codex_neutral.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/codex/codex_thread_ops.dart';
import 'package:promptorium/core/providers/agent_provider.dart';

import 'fake_codex.dart';

/// SPEC-110: what the adapter adds for the Replay and the restore points.
void main() {
  test('R1: ações desconhecidas contam; só leitura exige todas conhecidas', () {
    CommandEvent of(List<Map<String, dynamic>> actions) => ClaudeEvent.fromJson(
      codexCommand({
        'id': 'c',
        'command': 'x',
        'status': 'completed',
        'commandActions': actions,
      }),
    ) as CommandEvent;
    const read = {'type': 'read', 'path': '/w/a', 'command': 'cat a'};
    const unknown = {'type': 'unknown', 'command': 'dart test'};
    expect(of([read]).onlyReads, isTrue);
    expect(of([read]).actions.single.command, 'cat a');
    expect(of([read, unknown]).onlyReads, isFalse);
    expect(of([read, unknown]).unknownActions, 1);
    expect(of([unknown]).onlyReads, isFalse);
    expect(of(const []).onlyReads, isFalse);
  });

  test('R1: o raciocínio só vira evento quando traz texto', () {
    expect(codexReasoningText({'summary': [], 'content': []}), isNull);
    expect(
      codexReasoningText({
        'summary': ['um', 'dois'],
      }),
      'um\n\ndois',
    );
    expect(
      codexReasoningText({
        'summary': [],
        'content': ['x'],
      }),
      'x',
    );
  });

  test('o turno, o plano, o raciocínio e a cópia no App Server', () async {
    final f = FakeCodex();
    final provider = CodexProvider(
      executable: 'codex',
      starter: (_, _, {workingDirectory, environment}) async => f,
    );
    final run = await provider.start(
      AgentStartOptions.forAccess(AgentAccess.edit, workingDirectory: '/tmp'),
    ) as CodexRun;
    final events = <ClaudeEvent>[];
    run.events.listen(events.add);
    void emit(String method, Map<String, dynamic> params) =>
        f.emit(jsonEncode({'method': method, 'params': params}));
    await run.send('oi');
    emit('turn/started', {
      'threadId': f.threadId,
      'turn': {'id': 'turn-1'},
    });
    emit('turn/plan/updated', {
      'threadId': f.threadId,
      'turnId': 'turn-1',
      'explanation': 'porque',
      'plan': [
        {'step': 'ler', 'status': 'inProgress'},
      ],
    });
    emit('item/completed', {
      'threadId': f.threadId,
      'item': {
        'id': 'r1',
        'type': 'reasoning',
        'summary': ['pensei'],
        'content': [],
      },
    });
    // A cópia feita nesta conexão não é desta execução.
    emit('thread/started', {
      'thread': {'id': 'copia-1'},
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final started = events
        .where((e) => e.json['subtype'] == codexTurnStartedSubtype)
        .single;
    expect(started.json['turn_id'], 'turn-1');
    final plan = events.whereType<OtherItemEvent>().single;
    expect(plan.isPlan, isTrue);
    expect(plan.text, 'porque\n\n▸ ler');
    final thought = events.whereType<AssistantMessage>().single;
    expect((thought.blocks.single as ThinkingBlock).thinking, 'pensei');
    expect(events.where((e) => e.json['method'] == 'thread/started'), isEmpty);
    await run.stop(timeout: const Duration(milliseconds: 100));
  });

  test('o motivo da falha em palavras', () {
    String of(String m) => codexThreadFailure(
      AgentUnavailable('Codex: {code: -32600, message: $m}'),
    );
    expect(
      of('thread x already has an active writer'),
      'outro processo do Codex está com esta conversa aberta',
    );
    expect(of('turn not found: t3'), contains('não está mais na conversa'));
    expect(of('no rollout found for thread id x'), contains('não achou'));
    expect(of('algo novo'), 'algo novo');
    expect(
      codexThreadFailure(
        const AgentUnavailable('o App Server não respondeu em 10 s (x)'),
      ),
      'o App Server não respondeu em 10 s (x)',
    );
  });
}
