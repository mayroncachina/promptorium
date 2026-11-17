import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/usage_poller.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/data/providers.dart';

import '../prompt_screen_test.dart' show pumpPrompt;
import '../prompt_test_utils.dart';

/// Claude with the models of the comparison.
class CompareFakeProvider extends FakeAgentProvider {
  @override
  List<String> get models => const ['inherit', 'opus', 'sonnet', 'haiku'];
}

String usageText(int five, int week) =>
    'Current session: $five% used · resets 2pm\n'
    'Current week (all models): $week% used · resets Nov 20, 9am\n';

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
