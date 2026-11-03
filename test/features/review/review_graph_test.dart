import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/review_service.dart';

import 'review_screen_stack_test.dart' show pumpStack;

/// SPEC-032 R16: the graph of the merge branches.
Future<ProviderContainer> pumpGraph(WidgetTester tester) async {
  final c = await pumpStack(
    tester,
    extra: [
      pairConflictProvider.overrideWith(
        (ref, key) async => {key.$2, key.$3}.containsAll({'pr/b', 'pr/x'})
            ? const ['lib/features/board/widgets/wave_graph.dart']
            : const <String>[],
      ),
    ],
  );
  await tester.tap(find.byKey(const ValueKey('review-mode-grafo')));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return c;
}

Finder node(String id) => find.byKey(ValueKey('review-graph-node-$id'));

void main() {
  testWidgets('the stack is a branch from the trunk, base at the bottom; '
      '"próximo" on what can go in now; the legend; the mode is kept', (
    tester,
  ) async {
    final c = await pumpGraph(tester);
    expect(find.byKey(const ValueKey('review-graph')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-graph-legend')), findsOneWidget);
    expect(find.text('Aguardando review · 3'), findsNothing);
    // Read from the bottom up: the base (a) is below its child (b).
    expect(
      tester.getTopLeft(node('a')).dy > tester.getTopLeft(node('b')).dy,
      isTrue,
    );
    expect(tester.getTopLeft(node('a')).dx, tester.getTopLeft(node('b')).dx);
    expect(tester.getTopLeft(node('x')).dy, tester.getTopLeft(node('a')).dy);
    expect(find.byKey(const ValueKey('review-graph-next-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-graph-next-x')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-graph-next-b')), findsNothing);
    expect(c.read(appSettingsProvider)[reviewModeKey(1)], 'grafo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dashed line names the file two specs of the queue both '
      'change', (tester) async {
    await pumpGraph(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('review-graph-conflict-b-x')))
          .data,
      'wave_graph.dart',
    );
    expect(
      find.byKey(const ValueKey('review-graph-conflict-a-x')),
      findsNothing,
    );
  });

  testWidgets('arrows and Enter select a node; the bar opens the review or '
      'runs the primary action there', (tester) async {
    final c = await pumpGraph(tester);
    expect(find.byKey(const ValueKey('review-graph-bar')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    // a (first) → up to b.
    expect(find.byKey(const ValueKey('review-graph-bar')), findsOneWidget);
    expect(find.text('Ir para SPEC-029'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-graph-open')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.read(selectedReviewProvider), 'b');
    expect(find.byKey(const ValueKey('review-graph')), findsNothing);

    // Back to the graph: the primary action of a opens the merge dialog.
    await tester.tap(find.byKey(const ValueKey('review-mode-grafo')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(node('a'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review-graph-primary')));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(c.read(selectedReviewProvider), 'a');
    expect(find.byKey(const ValueKey('review-merge-confirm')), findsOneWidget);
  });
}
