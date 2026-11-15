import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_provider.dart';

import 'fake_codex.dart';

/// SPEC-071 R14: the scrub acts on JSON values, so the event stays intact.
void main() {
  test(
    'texto com Bearer, \\" e task-runner chega íntegro e redigido',
    () async {
      final fake = FakeCodex();
      final run =
          await CodexProvider(
            starter: (exe, args, {workingDirectory, environment}) async => fake,
          ).start(
            const AgentStartOptions(
              workingDirectory: '/w',
              mode: PromptMode.edit,
            ),
          );
      addTearDown(run.stop);
      final events = <ClaudeEvent>[];
      run.events.listen(events.add);

      for (final text in [
        'use Bearer abc.def',
        r'echo \"oi\"',
        'npm run task-runner',
      ]) {
        fake.emit(
          jsonEncode({
            'method': 'item/agentMessage/delta',
            'params': {
              'threadId': fake.threadId,
              'itemId': 'i1',
              'delta': text,
            },
          }),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final texts = [
        for (final e in events.where((e) => e.json['type'] == 'stream_event'))
          e.json['event']['delta']['text'],
      ];
      expect(texts, [
        'use Bearer [redigido]',
        r'echo \"oi\"',
        'npm run task-runner',
      ]);
      expect(events.every((e) => e.json['provider'] == 'codex'), isTrue);
    },
  );
}
