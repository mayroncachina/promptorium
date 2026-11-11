import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/sessions_screen.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/tool_expanded.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/widgets/numbered_text_view.dart';

import 'sessions_screen_test.dart'
    show
        assistant,
        pumpFor,
        pumpScreen,
        root,
        storedEvents,
        toolResult,
        toolUse;

ToolItem _tool(String id) => ToolItem(id: id, name: 'Bash', input: const {});

final _view = find.byKey(const ValueKey('tool-expanded'));

Finder _card(String id) => find.byKey(ValueKey('tool-$id'));

Finder _toggle(String id) => find.byKey(ValueKey('tool-toggle-$id'));

/// Name and target in the header of the expanded view.
String _header(WidgetTester tester) {
  final name = tester.widget<Text>(
    find.byKey(const ValueKey('tool-expanded-name')),
  );
  final target = tester.widget<Text>(
    find.byKey(const ValueKey('tool-expanded-target')),
  );
  return '${name.data} ${target.data}';
}

ScrollPosition _timelineScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('timeline-s1')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

bool _focusInside(Finder f) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  final target = f.evaluate().single;
  var inside = false;
  ctx.visitAncestorElements((e) {
    if (e == target) inside = true;
    return !inside;
  });
  return inside || ctx == target;
}

/// A long Bash output (more than the old 40-line cut), then a few more
/// calls, so the timeline scrolls.
List<Map<String, dynamic>> _longSession() => [
  ...storedEvents.take(storedEvents.length - 1),
  assistant([
    toolUse('t_long', 'Bash', {'command': 'flutter test'}),
  ], id: 'msg_long'),
  toolResult('t_long', [for (var i = 1; i <= 120; i++) 'linha $i'].join('\n')),
  for (var i = 0; i < 12; i++) ...[
    assistant([
      toolUse('t_more$i', 'Read', {'file_path': '$root/lib/m$i.dart'}),
    ], id: 'msg_more$i'),
    toolResult('t_more$i', 'conteúdo $i'),
  ],
];

void main() {
  group('ToolExpandedController', () {
    late ProviderContainer c;
    setUp(() {
      c = ProviderContainer(
        overrides: [
          sessionToolsProvider.overrideWith(
            (ref, id) => [_tool('a'), _tool('b'), _tool('c')],
          ),
        ],
      );
    });
    tearDown(() => c.dispose());

    test('open, next and previous stop at the ends, close keeps the last '
        'tool for the way back (R3, R8)', () {
      final ctrl = c.read(toolExpandedProvider.notifier);
      expect(ctrl.isOpen, isFalse);
      ctrl.open('s1', 'b', origin: const Rect.fromLTWH(1, 2, 3, 4));
      expect(c.read(toolExpandedProvider)!.toolId, 'b');
      expect(c.read(toolExpandedProvider)!.origin, isNotNull);
      expect(ctrl.hasPrevious && ctrl.hasNext, isTrue);

      ctrl.next();
      expect(c.read(toolExpandedProvider)!.toolId, 'c');
      expect(ctrl.hasNext, isFalse);
      ctrl.next();
      expect(c.read(toolExpandedProvider)!.toolId, 'c');

      ctrl
        ..previous()
        ..previous();
      expect(c.read(toolExpandedProvider)!.toolId, 'a');
      expect(ctrl.hasPrevious, isFalse);
      ctrl.previous();
      expect(c.read(toolExpandedProvider)!.toolId, 'a');

      ctrl.close();
      final closed = c.read(toolExpandedProvider)!;
      expect(closed.open, isFalse);
      expect(closed.toolId, 'a');
      expect(ctrl.revealFor('s1')!.toolId, 'a');
      expect(identical(ctrl.revealFor('s1'), ctrl.revealFor('s1')), isTrue);
      expect(ctrl.revealFor('s2'), isNull);
      expect(ctrl.hasNext, isFalse);

      ctrl.open('s1', 'a');
      ctrl.close();
      expect(c.read(toolExpandedProvider)!.seq, greaterThan(closed.seq));
    });

    test('flattenTools puts subagent calls after their Task', () {
      final task = ToolItem(id: 'task', name: 'Task', input: const {});
      task.children.add(_tool('sub'));
      expect(flattenTools([_tool('a'), task, _tool('z')]).map((t) => t.id), [
        'a',
        'task',
        'sub',
        'z',
      ]);
    });
  });

  testWidgets('R1, R2, R11 · a click on a Bash card covers the list, the '
      'session and the panel with its whole output; a dialog labeled '
      '"Bash ampliado"', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester, events: _longSession());
    await tester.tap(_toggle('t_long'));
    await tester.pump();

    expect(_view, findsOneWidget);
    expect(tester.getRect(_view), tester.getRect(find.byType(SessionsScreen)));
    expect(_header(tester), 'Bash flutter test');
    expect(find.text('120 linhas'), findsOneWidget);
    // No 40-line cut.
    final text = tester.widget<NumberedTextView>(find.byType(NumberedTextView));
    expect(text.lines, hasLength(120));
    expect(text.lines.last, 'linha 120');
    expect(find.textContaining('(+80 linhas)'), findsNothing);
    expect(find.bySemanticsLabel('Bash ampliado'), findsOneWidget);
    expect(find.bySemanticsLabel('Anterior (↑ ou K)'), findsOneWidget);
    expect(find.bySemanticsLabel('Próxima (↓ ou J)'), findsOneWidget);
    expect(find.bySemanticsLabel('Fechar (Esc)'), findsOneWidget);
    // Focus is on the text, inside the view.
    expect(_focusInside(_view), isTrue);
    handle.dispose();
  });

  testWidgets('R1 · in sessions side by side the view covers both panes', (
    tester,
  ) async {
    await pumpScreen(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionsScreen)),
    );
    container.read(splitSessionProvider.notifier).set('s1-none');
    await pumpFor(tester, 2);
    await tester.tap(_toggle('t_bash'));
    await tester.pump();
    expect(tester.getRect(_view), tester.getRect(find.byType(SessionsScreen)));
  });

  testWidgets('R2, R3 · ↓/J and ↑/K walk the tools of the session without '
      'closing; the buttons are off at the ends', (tester) async {
    await pumpScreen(tester);
    await tester.tap(_toggle('t_bash'));
    await tester.pump();
    expect(_header(tester), 'Bash flutter analyze');
    expect(find.textContaining('erro grave'), findsOneWidget);
    expect(find.text('erro'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_header(tester), 'Task Revisar testes');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(_header(tester), 'Grep TODO');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(_header(tester), 'Task Revisar testes');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_header(tester), 'Read lib/a.dart');
    InkWell button(String k) =>
        tester.widget<InkWell>(find.byKey(ValueKey('tool-expanded-$k')));
    expect(button('previous').onTap, isNull);
    expect(button('next').onTap, isNotNull);

    // Próxima by click, up to the running Bash at the end (R1: it opens too).
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('tool-expanded-next')));
      await tester.pump();
    }
    expect(_header(tester), 'Bash flutter test');
    expect(
      find.descendant(of: _view, matching: find.text('executando')),
      findsOneWidget,
    );
    expect(button('next').onTap, isNull);
    expect(_view, findsOneWidget);
  });

  testWidgets('R8 · Esc goes back to the same scroll, the card gets the focus '
      'and an amber highlight that fades in 1.2 s', (tester) async {
    await pumpScreen(tester, events: _longSession());
    final scroll = _timelineScroll(tester);
    scroll.jumpTo(120);
    await tester.pump();
    await tester.tap(_toggle('t_more2'));
    await tester.pump();
    expect(_view, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(_view, findsNothing);
    expect(_timelineScroll(tester).pixels, 120);
    expect(find.byKey(const ValueKey('session-tile-s1')), findsOneWidget);
    expect(_focusInside(_card('t_more2')), isTrue);
    Color border() =>
        ((tester.widget<Container>(_card('t_more2')).decoration!
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .color;
    expect(border(), isNot(const Color(0xFF252B35)));
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump();
    expect(border(), const Color(0xFF252B35));
  });

  testWidgets('R8 · after Anterior / Próxima the card of the last tool shown '
      'comes back into view, focused', (tester) async {
    await pumpScreen(tester, events: _longSession());
    await tester.tap(_toggle('t_more11'));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    await tester.pump();
    expect(_header(tester), 'Bash flutter test');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(_card('t_long'), findsOneWidget);
    final box = tester.getRect(_card('t_long'));
    final list = tester.getRect(find.byKey(const ValueKey('timeline-s1')));
    expect(list.overlaps(box), isTrue);
    expect(_focusInside(_card('t_long')), isTrue);
  });

  testWidgets('R11 · Tab stays inside the view', (tester) async {
    await pumpScreen(tester);
    await tester.tap(_toggle('t_bash'));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusInside(_view), isTrue, reason: 'tab $i');
    }
  });

  testWidgets('R2 · Copiar copies the whole output', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpScreen(tester);
    await tester.tap(_toggle('t_bash'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tool-expanded-copy')));
    await tester.pump();
    expect(copied, 'Exit code 1\nerro grave');
    await tester.tap(find.byKey(const ValueKey('tool-expanded-close')));
    await tester.pump();
    expect(_view, findsNothing);
  });

  group('R9 · motion', () {
    setUp(() => AppMotion.enabled = true);
    tearDown(() => AppMotion.enabled = false);

    testWidgets('the view grows from the card in 220 ms and shrinks back in '
        '160 ms', (tester) async {
      await pumpScreen(tester);
      final card = tester.getRect(_card('t_bash'));
      await tester.tap(_toggle('t_bash'));
      await tester.pump();
      final motion = find.byKey(const ValueKey('tool-expanded-motion'));
      expect(motion, findsOneWidget);
      final start = tester.getRect(motion);
      expect((start.top - card.top).abs(), lessThan(8));
      expect(start.width, lessThan(card.width + 40));

      await tester.pump(const Duration(milliseconds: 110));
      final mid = tester.getRect(motion);
      expect(mid.width, greaterThan(start.width));
      await tester.pump(const Duration(milliseconds: 120));
      expect(motion, findsNothing);
      expect(_view, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(motion, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(_view, findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('with reduced motion it opens and closes at once', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpScreen(tester);
      await tester.tap(_toggle('t_bash'));
      await tester.pump();
      expect(_view, findsOneWidget);
      expect(find.byKey(const ValueKey('tool-expanded-motion')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_view, findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
