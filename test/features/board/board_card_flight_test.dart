import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/widgets/board_card_flight.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/motion.dart';

import '../../helpers/test_db.dart';

const _frame = Duration(milliseconds: 16);

void motionOn() {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
}

class Board {
  Board(this.container, this.db, this.ids);

  final ProviderContainer container;
  final AppDatabase db;

  /// Spec ids by card number.
  final List<int> ids;

  Future<void> move(int card, SpecStage stage) =>
      container.read(specsRepoProvider).setStage(ids[card], stage);
}

/// [backlog] cards in the Backlog, numbered from 0, and [running] after them
/// in Em execução.
Future<Board> pumpBoard(
  WidgetTester tester, {
  int backlog = 3,
  int running = 1,
  bool reduced = false,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final ws = await db
      .into(db.workspaces)
      .insertReturning(
        WorkspacesCompanion.insert(path: '/work/repo', name: 'repo'),
      );
  await db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: AppSettingKeys.activeWorkspace,
          value: '${ws.id}',
        ),
      );
  final ids = <int>[];
  for (var i = 0; i < backlog + running; i++) {
    final code = 'SPEC-${i.toString().padLeft(3, '0')}';
    final spec = await db
        .into(db.specs)
        .insertReturning(
          SpecsCompanion.insert(
            workspaceId: ws.id,
            code: code,
            title: 'Card $i',
            path: 'specs/$code.md',
            status: const Value(SpecStatus.approved),
            stage: Value(i < backlog ? SpecStage.backlog : SpecStage.running),
            requirements: const Value([(id: 'R1', text: 'Req')]),
          ),
        );
    ids.add(spec.id);
  }
  final c = ProviderContainer(overrides: [databaseOverride(db)]);
  addTearDown(c.dispose);
  await c.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: const Scaffold(body: BoardScreen()),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return Board(c, db, ids);
}

Finder flight(int id) => find.byKey(ValueKey('board-flight-$id'));

Finder card(int n) => find.byKey(
  ValueKey('board-card-SPEC-${n.toString().padLeft(3, '0')}'),
  skipOffstage: false,
);

/// Includes the rows the list built below the fold.
Finder inColumn(String stage, Finder what) => find.descendant(
  of: find.byKey(ValueKey('board-column-$stage'), skipOffstage: false),
  matching: what,
  skipOffstage: false,
);

/// Pumps until the change written to the database reaches the screen.
Future<void> pumpChange(WidgetTester tester, bool Function() arrived) async {
  for (var i = 0; i < 20 && !arrived(); i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(arrived(), isTrue, reason: 'the change never reached the screen');
}

double listBottom(WidgetTester tester) => tester
    .getBottomLeft(
      inColumn('backlog', find.byType(ListView, skipOffstage: false)).first,
    )
    .dy;

/// The first frame only starts the clock, and it stops past its duration.
Future<void> land(WidgetTester tester) async {
  await tester.pump(_frame);
  await tester.pump(AppMotion.emphasis);
  await tester.pump(_frame);
}

void main() {
  testWidgets('R7 · the agent moves a card: it slides from the old column to '
      'the new one in emphasis, and only the copy shows on the way', (
    tester,
  ) async {
    motionOn();
    final b = await pumpBoard(tester);
    final id = b.ids[0];
    final origin = tester.getTopLeft(card(0));
    await b.move(0, SpecStage.running);
    await pumpChange(tester, () => flight(id).evaluate().isNotEmpty);

    expect(tester.getTopLeft(flight(id)), origin);
    final goal = tester.getTopLeft(card(0));
    expect(goal.dx, greaterThan(origin.dx));
    expect(inColumn('running', card(0)), findsOneWidget);

    await tester.pump(_frame);
    await tester.pump(const Duration(milliseconds: 60));
    final midway = tester.getTopLeft(flight(id));
    expect(midway.dx, greaterThan(origin.dx));
    expect(midway.dx, lessThan(goal.dx));
    // The real card is already in its place, and is the one a pointer finds.
    expect(tester.getTopLeft(card(0)), goal);

    await tester.pump(AppMotion.emphasis - const Duration(milliseconds: 60));
    await tester.pump(_frame);
    expect(flight(id), findsNothing);
    expect(tester.getTopLeft(card(0)), goal);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R7 · a dragged card leaves from the point where it was dropped '
      'and does not go back to the old column', (tester) async {
    motionOn();
    final b = await pumpBoard(tester);
    final id = b.ids[0];
    final start = tester.getTopLeft(card(0));
    final grab = tester.getCenter(card(0));
    final gesture = await tester.startGesture(grab);
    await tester.pump(_frame);
    const way = Offset(380, 200);
    await gesture.moveBy(way);
    await tester.pump(_frame);
    await gesture.up();
    await tester.pump();

    expect(tester.getTopLeft(flight(id)), start + way);
    await pumpChange(
      tester,
      () => inColumn('running', card(0)).evaluate().isNotEmpty,
    );
    await tester.pump(_frame);
    final goal = tester.getTopLeft(card(0));
    expect(tester.getTopLeft(flight(id)).dy, closeTo(start.dy + way.dy, 40));

    await land(tester);
    expect(flight(id), findsNothing);
    expect(tester.getTopLeft(card(0)), goal);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R12 · a drop the database does not confirm ends by itself', (
    tester,
  ) async {
    motionOn();
    final b = await pumpBoard(tester);
    final id = b.ids[0];
    tester
        .state<BoardFlightsState>(find.byType(BoardFlights))
        .drop(id, const Offset(500, 300), 200);
    await tester.pump();
    expect(flight(id), findsOneWidget);
    await land(tester);
    expect(flight(id), findsNothing);
    expect(inColumn('backlog', card(0)), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R7 · the neighbours close the gap in emphasis, from the first '
      'frame, though the list remounts their rows', (tester) async {
    motionOn();
    final b = await pumpBoard(tester);
    final before = tester.getTopLeft(card(1));
    final slot = tester.getTopLeft(card(0));
    await b.move(0, SpecStage.review);
    await pumpChange(tester, () => flight(b.ids[0]).evaluate().isNotEmpty);

    expect(tester.getTopLeft(card(1)), before);
    await tester.pump(_frame);
    await tester.pump(const Duration(milliseconds: 40));
    final midway = tester.getTopLeft(card(1)).dy;
    expect(midway, lessThan(before.dy));
    expect(midway, greaterThan(slot.dy));

    await land(tester);
    expect(tester.getTopLeft(card(1)), slot);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R7 · the counts of both columns fade in base', (tester) async {
    motionOn();
    final b = await pumpBoard(tester);
    await b.move(0, SpecStage.running);
    const count = ValueKey('board-column-count-backlog');
    await pumpChange(tester, () => find.byKey(count).evaluate().length == 2);
    expect(find.text('3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('board-column-count-running')),
      findsNWidgets(2),
    );

    final fading = find.ancestor(
      of: find.text('2').first,
      matching: find.byType(FadeTransition),
    );
    await tester.pump(_frame);
    await tester.pump(const Duration(milliseconds: 30));
    final opacity = tester.widget<FadeTransition>(fading.first).opacity.value;
    expect(opacity, greaterThan(0));
    expect(opacity, lessThan(1));

    await tester.pump(AppMotion.base);
    expect(find.byKey(count), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(count)).data, '2');
    await land(tester);
  });

  testWidgets('R7 · no more than 3 cards fly at a time: the others go '
      'straight there', (tester) async {
    motionOn();
    final b = await pumpBoard(tester, backlog: 4, running: 0);
    await (b.db.update(b.db.specs)..where((s) => s.id.isIn(b.ids))).write(
      const SpecsCompanion(stage: Value(SpecStage.review)),
    );
    await pumpChange(tester, () => flight(b.ids[0]).evaluate().isNotEmpty);
    await tester.pump(_frame);
    await tester.pump(_frame);

    expect(b.ids.where((id) => flight(id).evaluate().isNotEmpty), hasLength(3));
    for (var i = 0; i < 4; i++) {
      expect(inColumn('review', card(i)), findsOneWidget);
    }
    await land(tester);
    expect(b.ids.where((id) => flight(id).evaluate().isNotEmpty), isEmpty);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R7 · the cap also counts the cards still in the air', (
    tester,
  ) async {
    motionOn();
    final b = await pumpBoard(tester, backlog: 5, running: 0);
    for (var i = 0; i < 4; i++) {
      await b.move(i, SpecStage.running);
      await pumpChange(
        tester,
        () => inColumn('running', card(i)).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 2));
    }
    expect(
      b.ids.where((id) => flight(id).evaluate().isNotEmpty).length,
      lessThanOrEqualTo(3),
    );
    expect(flight(b.ids[3]), findsNothing);
    await land(tester);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R7 · a card built by the list but below the fold goes straight '
      'there', (tester) async {
    motionOn();
    final b = await pumpBoard(tester, backlog: 14, running: 1);
    final built = inColumn(
      'backlog',
      find.byType(SpecCard, skipOffstage: false),
    ).evaluate().length;
    expect(built, lessThan(14));
    final last = built - 1;
    expect(tester.getTopLeft(card(last)).dy, greaterThan(listBottom(tester)));

    await b.move(last, SpecStage.done);
    await pumpChange(
      tester,
      () => inColumn('done', card(last)).evaluate().isNotEmpty,
    );
    await tester.pump(_frame);
    expect(flight(b.ids[last]), findsNothing);
    await land(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R7 · a card that lands below the fold goes straight there', (
    tester,
  ) async {
    motionOn();
    final b = await pumpBoard(tester, backlog: 14, running: 1);
    // The last by code: it takes the end of a column that does not fit.
    await b.move(14, SpecStage.backlog);
    final id = b.ids[14];
    await pumpChange(tester, () => flight(id).evaluate().isNotEmpty);
    await tester.pump(_frame);
    expect(flight(id), findsNothing);
    expect(
      tester.hasRunningAnimations,
      isTrue,
      reason: 'the count still fades',
    );
    await land(tester);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R11 · with reduced motion nothing flies and the card is in its '
      'place at once', (tester) async {
    motionOn();
    final b = await pumpBoard(tester, reduced: true);
    await b.move(0, SpecStage.running);
    await pumpChange(
      tester,
      () => inColumn('running', card(0)).evaluate().isNotEmpty,
    );
    expect(flight(b.ids[0]), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(_frame);
    expect(
      find.byKey(const ValueKey('board-column-count-running')),
      findsOneWidget,
    );
  });

  testWidgets('R12 · a click on the card in flight already counts', (
    tester,
  ) async {
    motionOn();
    final b = await pumpBoard(tester);
    await b.move(0, SpecStage.running);
    await pumpChange(tester, () => flight(b.ids[0]).evaluate().isNotEmpty);
    await tester.pump(_frame);
    await tester.tapAt(tester.getCenter(card(0)));
    expect(b.container.read(boardSelectedSpecProvider), b.ids[0]);
    await tester.pump();
    await land(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R12 · a new change starts from where the card is', (
    tester,
  ) async {
    motionOn();
    final b = await pumpBoard(tester);
    final id = b.ids[0];
    await b.move(0, SpecStage.done);
    await pumpChange(tester, () => flight(id).evaluate().isNotEmpty);
    await tester.pump(_frame);
    await tester.pump(const Duration(milliseconds: 50));
    final there = tester.getTopLeft(flight(id));

    await b.move(0, SpecStage.running);
    await pumpChange(
      tester,
      () => inColumn('running', card(0)).evaluate().isNotEmpty,
    );
    final turn = tester.getTopLeft(flight(id));
    // Only the frames the database took: nowhere near the column it left.
    expect((turn - there).distance, lessThan(120));
    final goal = tester.getTopLeft(card(0));
    await land(tester);
    expect(flight(id), findsNothing);
    expect(tester.getTopLeft(card(0)), goal);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('R12 · the final state does not depend on the end of the '
      'animation: leaving the board in the air breaks nothing', (tester) async {
    motionOn();
    final b = await pumpBoard(tester);
    await b.move(0, SpecStage.running);
    await pumpChange(tester, () => flight(b.ids[0]).evaluate().isNotEmpty);
    await tester.pump(_frame);
    b.container.read(boardGraphViewProvider.notifier).set(true);
    await tester.pump();
    expect(find.byType(BoardFlights), findsNothing);
    b.container.read(boardGraphViewProvider.notifier).set(false);
    await tester.pump();
    expect(flight(b.ids[0]), findsNothing);
    expect(inColumn('running', card(0)), findsOneWidget);
    await land(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with animations off the board has no flight at all', (
    tester,
  ) async {
    final b = await pumpBoard(tester);
    await b.move(0, SpecStage.running);
    await pumpChange(
      tester,
      () => inColumn('running', card(0)).evaluate().isNotEmpty,
    );
    expect(flight(b.ids[0]), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
