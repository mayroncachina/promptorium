import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';

/// Synthetic `control_request` copied from plano, Fase 0.3.
const permissionRequestLine =
    '{"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool","tool_name":"Bash","display_name":"Bash","input":{"command":"ls -la"},"description":"Lista arquivos","permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"ls:*"}],"behavior":"allow","destination":"localSettings"}],"decision_reason":"sem regra","tool_use_id":"toolu_01"}}';

void main() {
  test('parses the real stream-json fixture', () {
    final lines = File('test/fixtures/stream-json-exemplo.jsonl')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty);
    final events = [for (final l in lines) ...ClaudeEvent.parseLine(l)];

    expect(events.whereType<UnknownEvent>(), isEmpty);
    for (final o in events.whereType<SystemOther>()) {
      expect(o.subtype, startsWith('hook_'));
    }

    // Order: init → stream_event… → assistant → rate_limit_event → result.
    final relevant = events
        .where((e) => e is! SystemOther && e is! SystemStatus)
        .toList();
    expect(relevant.first, isA<SystemInit>());
    expect(relevant[1], anyOf(isA<StreamDelta>(), isA<StreamOther>()));
    final firstAssistant = relevant.indexWhere((e) => e is AssistantMessage);
    final rate = relevant.indexWhere((e) => e is RateLimit);
    expect(firstAssistant, greaterThan(1));
    expect(rate, greaterThan(firstAssistant));
    expect(relevant.last, isA<Result>());
    expect(relevant.indexOf(relevant.last), rate + 1);

    final init = relevant.first as SystemInit;
    expect(init.model, 'claude-haiku-5-5');
    expect(init.tools, contains('Bash'));
    expect(init.mcpServers.map((s) => s.name), contains('youtrack'));
    expect(
      init.mcpServers.firstWhere((s) => s.name == 'context7').status,
      'pending',
    );
    expect(init.agents, contains('Explore'));
    expect(init.permissionMode, 'default');
    expect(init.cwd, '/tmp/claude-1000/cctest');

    final deltas = events.whereType<StreamDelta>().toList();
    expect(
      deltas.where((d) => d.kind == StreamDeltaKind.text).map((d) => d.text),
      ['ok'],
    );
    expect(deltas.where((d) => d.kind == StreamDeltaKind.thinking), isNotEmpty);

    final assistants = events.whereType<AssistantMessage>().toList();
    expect(assistants, hasLength(2));
    expect(assistants.first.blocks.single, isA<ThinkingBlock>());
    expect((assistants.last.blocks.single as TextBlock).text, 'ok');
    expect(assistants.last.parentToolUseId, isNull);

    final rl = events.whereType<RateLimit>().single;
    expect(rl.fiveHourUtilization, inInclusiveRange(0, 1));
    expect(rl.fiveHourUtilization, 0.12);
    expect(rl.sevenDayUtilization, 0.56);
    expect(
      rl.fiveHourResetsAt,
      DateTime.fromMillisecondsSinceEpoch(1792038000 * 1000, isUtc: true),
    );

    final r = events.whereType<Result>().single;
    expect(r.subtype, 'success');
    expect(r.isSuccess, isTrue);
    expect(r.totalCostUsd, greaterThan(0));
    expect(r.usage.inputTokens, 2);
    expect(r.usage.outputTokens, 42);
    expect(r.usage.cacheCreationInputTokens, 14458);
    expect(r.usage.cacheReadInputTokens, 11091);
    expect(r.numTurns, 1);
    expect(r.durationMs, 3958);
    expect(r.result, 'ok');
    expect(r.permissionDenials, isEmpty);
  });

  test('parses a can_use_tool control_request (Fase 0.3)', () {
    final e = ClaudeEvent.parseLine(permissionRequestLine).single;
    expect(e, isA<PermissionRequest>());
    final p = e as PermissionRequest;
    expect(p.requestId, 'req-1');
    expect(p.toolName, 'Bash');
    expect(p.displayName, 'Bash');
    expect(p.input, {'command': 'ls -la'});
    expect(p.description, 'Lista arquivos');
    expect(p.decisionReason, 'sem regra');
    expect(p.toolUseId, 'toolu_01');
    expect(p.permissionSuggestions.single['type'], 'addRules');
    expect(p.permissionSuggestions.single['destination'], 'localSettings');
  });

  test('control_cancel_request, tool_result and subagent messages', () {
    final cancel = ClaudeEvent.fromJson({
      'type': 'control_cancel_request',
      'request_id': 'req-1',
    });
    expect((cancel as ControlCancel).requestId, 'req-1');

    final user = {
      'type': 'user',
      'parent_tool_use_id': 'toolu_parent',
      'message': {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 'toolu_a',
            'content': [
              {'type': 'text', 'text': 'linha 1'},
              {'type': 'text', 'text': 'linha 2'},
            ],
          },
          {
            'type': 'tool_result',
            'tool_use_id': 'toolu_b',
            'content': 'falhou',
            'is_error': true,
          },
        ],
      },
    };
    final results = ClaudeEvent.expand(user).cast<ToolResult>();
    expect(results.map((r) => r.toolUseId), ['toolu_a', 'toolu_b']);
    expect(results.first.content, 'linha 1\nlinha 2');
    expect(results.first.isError, isFalse);
    expect(results.last.isError, isTrue);
    expect(results.first.parentToolUseId, 'toolu_parent');
    expect((ClaudeEvent.fromJson(user) as ToolResult).toolUseId, 'toolu_a');

    final toolUse = ClaudeEvent.fromJson({
      'type': 'assistant',
      'parent_tool_use_id': 'toolu_parent',
      'message': {
        'id': 'msg_1',
        'content': [
          {
            'type': 'tool_use',
            'id': 'toolu_c',
            'name': 'Read',
            'input': {'file_path': '/x'},
          },
          {'type': 'server_tool_use', 'id': 'x'},
        ],
      },
    }) as AssistantMessage;
    expect(toolUse.messageId, 'msg_1');
    final block = toolUse.blocks.first as ToolUseBlock;
    expect(block.name, 'Read');
    expect(block.input['file_path'], '/x');
    expect(toolUse.blocks.last, isA<OtherBlock>());
    expect(toolUse.parentToolUseId, 'toolu_parent');
  });

  test('never throws on unknown or malformed input', () {
    expect(ClaudeEvent.fromJson({'type': 'novidade'}), isA<UnknownEvent>());
    expect(ClaudeEvent.fromJson({}), isA<UnknownEvent>());
    expect(
      ClaudeEvent.fromJson({'type': 'system', 'subtype': 'api_retry'}),
      isA<SystemOther>(),
    );
    expect(ClaudeEvent.fromJson({'type': 'system'}), isA<SystemOther>());
    expect(
      ClaudeEvent.fromJson({
        'type': 'control_request',
        'request_id': 'x',
        'request': {'subtype': 'outro'},
      }),
      isA<UnknownEvent>(),
    );
    // Wrong value types are tolerated.
    final weird = ClaudeEvent.fromJson({
      'type': 'result',
      'total_cost_usd': 'muito',
      'usage': [1, 2],
      'num_turns': 2.0,
    }) as Result;
    expect(weird.totalCostUsd, 0);
    expect(weird.numTurns, 2);
    expect(
      ClaudeEvent.fromJson({'type': 'assistant', 'message': 3}),
      isA<AssistantMessage>(),
    );

    final bad = ClaudeEvent.parseLine('isto não é json').single;
    expect((bad as UnknownEvent).raw, 'isto não é json');
    expect(ClaudeEvent.parseLine('[1,2]').single, isA<UnknownEvent>());
    expect(jsonDecode(permissionRequestLine), isA<Map>());
  });
}
