import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/prompt/compare/compare_controller.dart';
import 'package:promptorium/features/prompt/compare/compare_run.dart';
import 'package:promptorium/features/prompt/prompt_activity.dart';

void main() {
  test('each running side is one activity, with the conversation robot and '
      'its letter (R9)', () {
    final conv = Conversation(
      id: 7,
      workspaceId: 1,
      title: 'Cupons expirados',
      provider: 'claude',
      model: 'sonnet',
      createdAt: DateTime(2026, 11, 17, 10),
      mode: 'ask',
      tokensIn: 0,
      tokensOut: 0,
      costUsd: 0,
      messageCount: 0,
    );
    final run = CompareRun(
      conversationId: 7,
      prompt: 'por quê?',
      at: DateTime(2026, 11, 17, 10, 6),
      sides: const [
        CompareSide(
          letter: 'A',
          model: 'sonnet',
          mode: PromptMode.ask,
          state: CompareSideState.done,
        ),
        CompareSide(
          letter: 'B',
          model: 'opus',
          mode: PromptMode.ask,
          state: CompareSideState.running,
        ),
      ],
    );
    final list = buildActivities(
      [
        ActivityWorkspace(id: 1, name: 'w', conversations: [conv]),
      ],
      ActivityLive(compares: {7: CompareView(run: run)}),
      now: DateTime(2026, 11, 17, 10, 7),
    );
    final a = list.single;
    expect(a.id, 'conv:7:B');
    expect(a.compareSide, 'B');
    expect(a.seed, 'conv:7');
    expect(a.robotLabel, 'B');
    expect(a.model, 'opus');
    expect(a.conversationId, 7);
    expect(a.action, ActivityAction.stop);
    expect(a.subtitle, 'Prompt · comparando B');
  });

  test('the Prompt badge says it compares', () {
    const p = PromptActivity(
      conversationId: 1,
      title: 'Cupons',
      mode: PromptMode.ask,
      comparing: true,
    );
    expect(p.tooltip, 'Comparando respostas em “Cupons”');
  });
}
