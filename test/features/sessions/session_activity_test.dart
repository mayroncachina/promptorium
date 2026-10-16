import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/session_activity.dart';

void main() {
  test(
    'activityLabel: what the agent is doing from the end of the timeline',
    () {
      expect(activityLabel([]), 'Pensando');
      expect(activityLabel([UserItem('oi')]), 'Pensando');
      expect(
        activityLabel([ToolItem(id: 't', name: 'Bash', input: const {})]),
        'Executando Bash',
      );
      expect(
        activityLabel([ToolItem(id: 't', name: 'Task', input: const {})]),
        'Subagente trabalhando',
      );
      expect(
        activityLabel([
          ToolItem(id: 't', name: 'Bash', input: const {})..result = 'ok',
        ]),
        'Pensando',
      );
      expect(
        activityLabel([AssistantTextItem('abc', live: true)]),
        'Escrevendo a resposta',
      );
    },
  );

  test('formatElapsed', () {
    expect(formatElapsed(const Duration(seconds: 7)), '7s');
    expect(formatElapsed(const Duration(seconds: 65)), '1:05');
    expect(formatElapsed(const Duration(minutes: 75)), '1h 15m');
  });

  testWidgets('shows the activity and warns when nothing new arrives', (
    tester,
  ) async {
    final items = <TimelineItem>[UserItem('oi')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionActivity(
            items: items,
            since: DateTime.now().subtract(const Duration(minutes: 2)),
            quiet: Duration.zero,
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text)).data!;
    expect(text, contains('Pensando…'));
    expect(text, contains('2:0'));
    expect(text, contains('sem novidades'));
  });
}
