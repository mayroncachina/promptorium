import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/usage_poller.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/data/providers.dart';

import '../../../core/codex/fake_codex.dart';
import '../prompt_screen_test.dart' show pumpPrompt;
import '../prompt_test_utils.dart';

/// Claude with the models of the comparison.
class CompareFakeProvider extends FakeAgentProvider {
  @override
  List<String> get models => const ['inherit', 'opus', 'sonnet', 'haiku'];
}

String usageText(int five, int week) =>
    'Current session: $five% used · resets 2pm\n'
    'Current week (all models): $week% used · resets ${weekReset()}\n';

/// A week reset three days ahead: a fixed date turns stale once it passes
/// and the reading drops the week.
String weekReset([DateTime? now]) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = (now ?? DateTime.now()).add(const Duration(days: 3));
  return '${months[d.month - 1]} ${d.day}, 9am';
}

/// The Prompt with the conversation "Parser stream-json em Dart" (Sonnet,
/// session `conv-sid`) open; the agent is [provider] and `/usage` answers
/// [usages] in order.
Future<(AppDatabase, ProviderContainer)> pumpCompare(
  WidgetTester tester, {
  required CompareFakeProvider provider,
  List<String> usages = const [],
  Size size = const Size(1900, 1000),
}) async {
  final queue = [...usages];
  final (db, _, c) = await pumpPrompt(
    tester,
    size: size,
    overrides: [
      agentProvidersProvider.overrideWithValue([provider]),
      usageRunnerProvider.overrideWithValue(
        () async => queue.isEmpty ? null : queue.removeAt(0),
      ),
    ],
  );
  return (db, c);
}

Finder key(String k) => find.byKey(ValueKey(k));

/// A Codex on the App Server fake (no paid turn): each start is one of
/// [servers], with the models of the mock.
CodexProvider fakeCodexProvider(
  List<FakeCodex> servers, {
  String thread = 'thread-codex',
}) => CodexProvider(
  executable: 'codex',
  mcpLister: (_, _) async => const [],
  starter: (exe, args, {workingDirectory, environment}) async {
    final f = FakeCodex(
      threadId: servers.isEmpty ? thread : '$thread-${servers.length + 1}',
      models: codexTestModels,
    );
    servers.add(f);
    return f;
  },
);

const codexTestModels = [
  {
    'id': 'gpt-6.2-sol',
    'supportedReasoningEfforts': [
      {'reasoningEffort': 'low'},
      {'reasoningEffort': 'medium'},
      {'reasoningEffort': 'high'},
    ],
    'inputModalities': ['text'],
  },
  {
    'id': 'gpt-6.2-mini',
    'supportedReasoningEfforts': [
      {'reasoningEffort': 'low'},
    ],
    'inputModalities': ['text'],
  },
];

/// The answer of `account/rateLimits/read`, as the App Server sends it.
Map<String, dynamic> codexLimits(int five, int week) => {
  'rateLimits': {
    'limitId': 'codex',
    'primary': {
      'usedPercent': five,
      'windowDurationMins': 300,
      'resetsAt': 1900000000,
    },
    'secondary': {
      'usedPercent': week,
      'windowDurationMins': 10080,
      'resetsAt': 1900500000,
    },
  },
};

/// A command of the Codex with its classified actions, already done.
void codexCommandItem(
  FakeCodex f,
  String id,
  String command,
  List<Map<String, dynamic>> actions,
) {
  for (final (method, status) in [
    ('item/started', 'inProgress'),
    ('item/completed', 'completed'),
  ]) {
    f.emit(
      jsonEncode({
        'method': method,
        'params': {
          'threadId': f.threadId,
          'turnId': 'turn-1',
          'item': {
            'type': 'commandExecution',
            'id': id,
            'command': "/usr/bin/zsh -lc '$command'",
            'cwd': '/work/repo',
            'status': status,
            'commandActions': actions,
            if (status == 'completed') ...{
              'aggregatedOutput': 'ok',
              'exitCode': 0,
            },
          },
        },
      }),
    );
  }
}

/// Usage, answer and end of the turn.
void codexFinish(
  FakeCodex f,
  String answer, {
  int input = 18400,
  int output = 3700,
  int reasoning = 2100,
  int ms = 68000,
}) {
  f.emit(
    jsonEncode({
      'method': 'thread/tokenUsage/updated',
      'params': {
        'threadId': f.threadId,
        'turnId': 'turn-1',
        'tokenUsage': {
          for (final k in ['total', 'last'])
            k: {
              'totalTokens': input + output,
              'inputTokens': input,
              'cachedInputTokens': 400,
              'outputTokens': output,
              'reasoningOutputTokens': reasoning,
            },
          'modelContextWindow': 258400,
        },
      },
    }),
  );
  f.answer(answer);
  f.emit(
    jsonEncode({
      'method': 'turn/completed',
      'params': {
        'threadId': f.threadId,
        'turn': {'id': 'turn-1', 'status': 'completed', 'durationMs': ms},
      },
    }),
  );
}

/// The params of the last request [method] the app sent to [f].
Map<String, dynamic>? codexParams(FakeCodex f, String method) =>
    f.writtenJson.where((m) => m['method'] == method).lastOrNull?['params']
        as Map<String, dynamic>?;
