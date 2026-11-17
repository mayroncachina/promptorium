import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/replay/replay_state.dart';
import 'package:promptorium/features/sessions/replay/replay_step.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../sessions_screen_test.dart'
    show assistant, pumpFor, pumpScreen, root, toolResult, toolUse;
import 'replay_fixtures.dart';
import 'replay_view_test.dart' show position;

/// 5.000 events: a turn every 50 tool calls, each a call and its result.
List<Map<String, dynamic>> bigSession() {
  final out = <Map<String, dynamic>>[];
  var i = 0;
  while (out.length < 5000) {
    if (i % 50 == 0) {
      out.add(AppEventTypes.userMessage('turno ${i ~/ 50}', DateTime(2026)));
    }
    final id = 't$i';
    final name = switch (i % 4) {
      0 => 'Read',
      1 => 'Edit',
      2 => 'Bash',
      _ => 'Grep',
    };
    out.add(
      assistant([
        toolUse(id, name, {
          'file_path': '$root/lib/f${i % 40}.dart',
          'old_string': 'a$i',
          'new_string': 'b$i\nc$i',
          'command': 'flutter test $i',
          'pattern': 'x$i',
        }),
      ], id: 'm$i'),
    );
    out.add(toolResult(id, 'linha\n' * 20, error: i % 97 == 0));
    i++;
  }
  return out;
}

void main() {
  test('R11: steps and the state of a 5.000-event session are fast', () {
    final b = TimelineBuilder();
    for (final e in bigSession()) {
      b.t.apply(ev(e));
    }
    final sw = Stopwatch()..start();
    final steps = replaySteps(b.items, root: root);
    for (var k = 0; k < 50; k++) {
      replayStateAt(steps, steps.length - 1 - k);
    }
    sw.stop();
    expect(steps.length, greaterThan(2400));
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  testWidgets('R11: the tab of a 5.000-event session opens in under 1 s '
      'and the cursor keeps up', (tester) async {
    await pumpScreen(tester, events: bigSession());
    final sw = Stopwatch()..start();
    await tester.tap(find.byKey(const ValueKey('session-tab-replay')));
    await tester.pump();
    await tester.pump();
    sw.stop();
    expect(find.byKey(const ValueKey('replay-position')), findsOneWidget);
    expect(sw.elapsedMilliseconds, lessThan(1000));

    // 100 key steps (the cursor follows a drag the same way). The median
    // frame, so a busy machine (other test files in parallel) does not fail
    // it; a walk over the whole session per move would still be caught.
    final frames = <int>[];
    for (var k = 0; k < 100; k++) {
      final f = Stopwatch()..start();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      frames.add(f.elapsedMicroseconds);
    }
    frames.sort();
    expect(position(tester), contains('Passo '));
    expect(frames[frames.length ~/ 2] / 1000, lessThan(50));
    await pumpFor(tester, 2);
  });
}
