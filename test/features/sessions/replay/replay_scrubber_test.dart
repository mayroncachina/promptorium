import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/replay/replay_step.dart';
import 'package:promptorium/features/sessions/replay/widgets/replay_scrubber.dart';

import '../sessions_screen_test.dart' show pumpFor, pumpScreen;
import 'replay_fixtures.dart';
import 'replay_view_test.dart' show openReplay, position, replayEvents, total;

/// Center of step [i] on the scrubber.
Offset stepAt(WidgetTester tester, int i) {
  final box = tester.getRect(find.byKey(const ValueKey('replay-scrubber')));
  final w = box.width - ReplayScrubber.labelWidth;
  return Offset(
    box.left + ReplayScrubber.labelWidth + (i + .5) / total * w,
    box.top + ReplayScrubber.topRow + ReplayScrubber.laneHeight * 1.5,
  );
}

Future<void> key(
  WidgetTester tester,
  LogicalKeyboardKey k, {
  bool shift = false,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(k);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await pumpFor(tester, 3);
}

void main() {
  group('SPEC-082 · scrubber (R3, R4, R13)', () {
    testWidgets('a click takes the cursor to the nearest step; dragging '
        'follows the mouse', (tester) async {
      await pumpScreen(tester, events: replayEvents);
      await openReplay(tester);
      await tester.tapAt(stepAt(tester, 1));
      await pumpFor(tester, 3);
      expect(position(tester), startsWith('Passo 2 de $total'));

      final g = await tester.startGesture(stepAt(tester, 2));
      await g.moveBy(const Offset(30, 0));
      await g.moveTo(stepAt(tester, 6));
      await pumpFor(tester, 3);
      expect(position(tester), startsWith('Passo 7 de $total'));
      await g.up();
      await pumpFor(tester, 3);
    });

    testWidgets('the hover tip names the step', (tester) async {
      await pumpScreen(tester, events: replayEvents);
      await openReplay(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(stepAt(tester, 3));
      await pumpFor(tester, 3);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('replay-scrubber-tip')),
          matching: find.textContaining('4 · Edit lib/a.dart +2 −1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('← → Shift Home End', (tester) async {
      await pumpScreen(tester, events: replayEvents);
      await openReplay(tester);
      await key(tester, LogicalKeyboardKey.home);
      expect(position(tester), startsWith('Passo 1 de $total'));
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(position(tester), startsWith('Passo 2 de $total'));
      // ↑ / ↓ move too (R13).
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(position(tester), startsWith('Passo 3 de $total'));
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(position(tester), startsWith('Passo 2 de $total'));
      // Shift+→: the next turn (T2 opens at step 7).
      await key(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(position(tester), startsWith('Passo 7 de $total'));
      await key(tester, LogicalKeyboardKey.arrowLeft, shift: true);
      expect(position(tester), startsWith('Passo 1 de $total'));
      await key(tester, LogicalKeyboardKey.end);
      expect(position(tester), startsWith('Passo $total de $total'));
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(position(tester), startsWith('Passo ${total - 1} de $total'));
    });

    testWidgets('Espaço plays one step a second and stops at an error (P6)', (
      tester,
    ) async {
      await pumpScreen(tester, events: replayEvents);
      await openReplay(tester);
      await key(tester, LogicalKeyboardKey.home);
      await key(tester, LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(position(tester), startsWith('Passo 2 de $total'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 1000));
      }
      // Step 5 is the failing flutter test: it stops there.
      expect(position(tester), startsWith('Passo 5 de $total'));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      // 4×: four steps a second.
      await tester.tap(find.byKey(const ValueKey('replay-speed-4')));
      await key(tester, LogicalKeyboardKey.home);
      await tester.tap(find.byKey(const ValueKey('replay-play')));
      await tester.pump(const Duration(milliseconds: 260));
      expect(position(tester), startsWith('Passo 2 de $total'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(position(tester), startsWith('Passo 3 de $total'));
      await key(tester, LogicalKeyboardKey.space);
      await tester.pump(const Duration(seconds: 2));
      expect(position(tester), startsWith('Passo 3 de $total'));
    });

    testWidgets('"próximo erro" and "erro anterior"', (tester) async {
      await pumpScreen(tester, events: replayEvents);
      await openReplay(tester);
      await key(tester, LogicalKeyboardKey.home);
      await tester.tap(find.byKey(const ValueKey('replay-next-error')));
      await pumpFor(tester, 3);
      expect(position(tester), startsWith('Passo 5 de $total'));
      await tester.tap(find.byKey(const ValueKey('replay-next-error')));
      await pumpFor(tester, 3);
      expect(position(tester), startsWith('Passo 6 de $total'));
      await tester.tap(find.byKey(const ValueKey('replay-prev-error')));
      await pumpFor(tester, 3);
      expect(position(tester), startsWith('Passo 5 de $total'));
    });

    testWidgets('the screen reader hears a slider', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, events: replayEvents);
      await openReplay(tester);
      await key(tester, LogicalKeyboardKey.home);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.arrowRight);
      final node = tester.getSemantics(
        find.bySemanticsLabel('Linha do tempo da sessão'),
      );
      expect(
        node.value,
        matches(
          RegExp(r'^Passo 4 de 9, Editar a.dart, mais 2 menos 1, \d\d:\d\d$'),
        ),
      );
      expect(node.increasedValue, startsWith('Passo 5 de $total, Rodar'));
      semantics.dispose();
    });
  });

  group('ReplayAxis', () {
    test('a long pause is a cut; the nearest step skips filtered ones', () {
      final b = TimelineBuilder();
      b.read('/w/a');
      b.read('/w/b');
      b.pause(const Duration(hours: 2));
      b.read('/w/c');
      final axis = ReplayAxis(replaySteps(b.items));
      expect(axis.pos, [0, 1, 2 + ReplayAxis.pauseUnits]);
      expect(axis.nearest(0.4), 0);
      expect(axis.nearest(3.9), 2);
      expect(axis.nearest(0.4, allowed: (i) => i != 0), 1);
      expect(axis.nearest(0.4, allowed: (i) => i == 2), 2);
    });
  });
}
