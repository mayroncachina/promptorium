import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/timeline_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/widgets/motion_enter.dart';

void _motionOn() {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
}

Map<String, dynamic> _tool(String id) => {
  'type': 'assistant',
  'message': {
    'id': 'm-$id',
    'role': 'assistant',
    'content': [
      {
        'type': 'tool_use',
        'id': id,
        'name': 'Read',
        'input': {'file_path': '/w/$id.md'},
      },
    ],
  },
  'parent_tool_use_id': null,
  'session_id': 's',
};

Map<String, dynamic> _result(String id) => {
  'type': 'user',
  'message': {
    'role': 'user',
    'content': [
      {
        'type': 'tool_result',
        'tool_use_id': id,
        'content': 'conteúdo de $id',
        'is_error': false,
      },
    ],
  },
  'parent_tool_use_id': null,
  'session_id': 's',
};

/// A timeline on screen, fed the way the provider does: the same mutable list
/// and a rebuild after each change.
class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final timeline = Timeline();
  final _version = ValueNotifier(0);
  var loading = false;

  void apply(Map<String, dynamic> json) {
    for (final e in ClaudeEvent.expand(json)) {
      timeline.apply(e);
    }
  }

  void addTools(Iterable<String> ids) {
    for (final id in ids) {
      apply(_tool(id));
    }
    _version.value++;
  }

  void finishLoading(Iterable<String> ids) {
    loading = false;
    addTools(ids);
  }

  Future<void> pump({bool reduced = false}) async {
    tester.view.physicalSize = const Size(700, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(700, 400),
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: _version,
              builder: (_, _, _) =>
                  TimelineListView(items: timeline.items, loading: loading),
            ),
          ),
        ),
      ),
    );
  }

  /// [MotionEnter] of the card of tool [id], when it has one.
  Finder enterOf(String id) => find.ancestor(
    of: find.byKey(ValueKey('tool-$id')),
    matching: find.byType(MotionEnter),
  );

  double opacityOf(String id) => tester
      .widget<FadeTransition>(
        find.descendant(of: enterOf(id), matching: find.byType(FadeTransition)),
      )
      .opacity
      .value;

  double dyOf(String id) => tester
      .widget<Transform>(
        find
            .descendant(of: enterOf(id), matching: find.byType(Transform))
            .first,
      )
      .transform
      .getTranslation()
      .y;

  ScrollPosition get scroll =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position;
}

const _frame = Duration(milliseconds: 1);
const _afterBurstWindow = Duration(milliseconds: 301);

void main() {
  testWidgets('R8 · a new event rises 6 px with a fade in base and stops '
      'asking for frames', (tester) async {
    _motionOn();
    final h = _Harness(tester)..addTools(['a']);
    await h.pump();
    h.addTools(['b']);
    await tester.pump();
    expect(h.opacityOf('b'), 0);
    expect(h.dyOf('b'), 6);
    await tester.pump(AppMotion.base ~/ 2);
    expect(h.opacityOf('b'), inExclusiveRange(0, 1));
    await tester.pump(AppMotion.base);
    expect(h.opacityOf('b'), 1);
    expect(h.dyOf('b'), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R8 · the history does not animate, even when it is short and '
      'lands after the opening', (tester) async {
    _motionOn();
    final h = _Harness(tester)..loading = true;
    await h.pump();
    expect(find.text('Carregando…'), findsOneWidget);
    h.finishLoading(['a', 'b']);
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-b')), findsOneWidget);
    expect(find.byType(MotionEnter), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pump(_afterBurstWindow);
    h.addTools(['c']);
    await tester.pump();
    expect(h.enterOf('c'), findsOneWidget);
    await tester.pump(AppMotion.base * 2);
  });

  testWidgets('R8 · a list opened with its history ready does not animate it', (
    tester,
  ) async {
    _motionOn();
    final h = _Harness(tester)..addTools(['a', 'b']);
    await h.pump();
    expect(find.byKey(const ValueKey('tool-b')), findsOneWidget);
    expect(find.byType(MotionEnter), findsNothing);
  });

  testWidgets('R8 · what changes an item that is on screen is not an arrival', (
    tester,
  ) async {
    _motionOn();
    final h = _Harness(tester)..addTools(['a']);
    await h.pump();
    h
      ..apply(_result('a'))
      ..addTools(const []);
    await tester.pump();
    expect(find.byType(MotionEnter), findsNothing);
  });

  testWidgets('R8 · more than 3 events in one frame enter without animation', (
    tester,
  ) async {
    _motionOn();
    final h = _Harness(tester)..addTools(['a']);
    await h.pump();
    h.addTools(['b', 'c', 'd', 'e']);
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-e')), findsOneWidget);
    expect(find.byType(MotionEnter), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R8 · 3 events in one frame still animate', (tester) async {
    _motionOn();
    final h = _Harness(tester)..addTools(['a']);
    await h.pump();
    h.addTools(['b', 'c', 'd']);
    await tester.pump();
    expect(find.byType(MotionEnter), findsNWidgets(3));
    await tester.pump(AppMotion.base * 2);
  });

  testWidgets('R8 · the fourth event in 300 ms enters at once and stops the '
      'ones still moving; after the window, events animate again', (
    tester,
  ) async {
    _motionOn();
    final h = _Harness(tester)..addTools(['a']);
    await h.pump();
    for (final id in ['b', 'c', 'd']) {
      h.addTools([id]);
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(h.opacityOf('d'), lessThan(1));

    h.addTools(['e']);
    await tester.pump(const Duration(milliseconds: 10));
    expect(h.enterOf('e'), findsNothing);
    expect(h.opacityOf('b'), 1);
    expect(h.opacityOf('d'), 1);
    expect(h.dyOf('d'), 0);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pump(_afterBurstWindow);
    h.addTools(['f']);
    await tester.pump();
    expect(h.opacityOf('f'), 0);
    await tester.pump(AppMotion.base * 2);
  });

  testWidgets('R8 · the animation does not change the scroll position, at the '
      'end or scrolled back', (tester) async {
    _motionOn();
    final ids = [for (var i = 0; i < 40; i++) 't$i'];
    final h = _Harness(tester)..addTools(ids);
    await h.pump();

    h.addTools(['new1']);
    await tester.pump();
    expect(h.scroll.pixels, 0);
    await tester.pump(AppMotion.base ~/ 2);
    expect(h.scroll.pixels, 0);
    await tester.pump(AppMotion.base);

    h.scroll.jumpTo(300);
    await tester.pump();
    await tester.pump(_afterBurstWindow);
    h.addTools(['new2']);
    await tester.pump();
    expect(h.scroll.pixels, 300);
    await tester.pump(AppMotion.base ~/ 2);
    expect(h.scroll.pixels, 300);
    await tester.pump(AppMotion.base);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R8 · an item that left the screen and came back does not '
      'animate again', (tester) async {
    _motionOn();
    final h = _Harness(tester)..addTools([for (var i = 0; i < 40; i++) 't$i']);
    await h.pump();
    h.addTools(['new']);
    await tester.pump();
    await tester.pump(AppMotion.base * 2);
    expect(h.enterOf('new'), findsOneWidget);

    h.scroll.jumpTo(h.scroll.maxScrollExtent);
    await tester.pump();
    await tester.pump(_frame);
    expect(find.byKey(const ValueKey('tool-new')), findsNothing);

    h.scroll.jumpTo(0);
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-new')), findsOneWidget);
    expect(h.enterOf('new'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R8 · an event that arrived off screen does not animate when '
      'the user gets to it', (tester) async {
    _motionOn();
    final h = _Harness(tester)..addTools([for (var i = 0; i < 40; i++) 't$i']);
    await h.pump();
    h.scroll.jumpTo(h.scroll.maxScrollExtent);
    await tester.pump();
    await tester.pump(_afterBurstWindow);

    h.addTools(['new']);
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-new')), findsNothing);
    await tester.pump(_frame);

    h.scroll.jumpTo(0);
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-new')), findsOneWidget);
    expect(h.enterOf('new'), findsNothing);
  });

  testWidgets('an item keeps its state when a new one arrives below it', (
    tester,
  ) async {
    final h = _Harness(tester);
    h
      ..apply(_tool('a'))
      ..apply(_result('a'))
      ..addTools(['b']);
    await h.pump();
    await tester.tap(find.byKey(const ValueKey('tool-toggle-a')));
    await tester.pump();
    expect(find.text('conteúdo de a'), findsOneWidget);

    h.addTools(['c']);
    await tester.pump();
    expect(find.text('conteúdo de a'), findsOneWidget);
  });

  testWidgets('R11 · with reduced motion a new event shows at once', (
    tester,
  ) async {
    _motionOn();
    final h = _Harness(tester)..addTools(['a']);
    await h.pump(reduced: true);
    h.addTools(['b']);
    await tester.pump();
    expect(h.opacityOf('b'), 1);
    expect(h.dyOf('b'), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R12 · a click on an event that is still entering already '
      'counts', (tester) async {
    _motionOn();
    final h = _Harness(tester)..addTools(['a']);
    await h.pump();
    h
      ..apply(_tool('b'))
      ..apply(_result('b'))
      ..addTools(const []);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const ValueKey('tool-toggle-b')));
    await tester.pump();
    expect(find.text('conteúdo de b'), findsOneWidget);
    await tester.pump(AppMotion.base * 2);
  });
}
