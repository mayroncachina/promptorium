import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/widgets/staggered_entrance.dart';

/// SPEC-066 R1: the cascade of the right column of Sobre.
void main() {
  test('R1 · delays: 0, 60, 120 ms, then 40 ms apart up to the sixth line', () {
    final ms = [
      for (var i = 0; i < 11; i++) StaggeredEntrance.delayFor(i).inMilliseconds,
    ];
    expect(ms, [0, 60, 120, 160, 200, 240, 280, 320, 360, 360, 360]);
    // The last part ends inside the 640 ms of the cascade.
    expect(
      ms.last + AppMotion.emphasis.inMilliseconds,
      lessThanOrEqualTo(StaggeredEntrance.total.inMilliseconds),
    );
  });

  test(
    'R1 · each part takes 220 ms; the block of lines ends with the sixth',
    () {
      const total = 640.0;
      expect(StaggeredItem.progressAt(1, 59 / total), 0);
      expect(StaggeredItem.progressAt(1, 280 / total), 1);
      expect(StaggeredItem.progressAt(1, 170 / total), inExclusiveRange(0, 1));
      expect(
        StaggeredItem.progressAt(3, 570 / total, reveal: true),
        lessThan(1),
      );
      expect(StaggeredItem.progressAt(3, 580 / total, reveal: true), 1);
    },
  );

  group('StaggeredEntrance', () {
    tearDown(() => AppMotion.enabled = false);

    Widget host({bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const Scaffold(
          body: StaggeredEntrance(
            child: Column(
              children: [
                StaggeredItem(index: 0, child: Text('cabeçalho')),
                StaggeredItem(index: 1, child: Text('cartão')),
                StaggeredItem(index: 3, reveal: true, child: Text('linhas')),
              ],
            ),
          ),
        ),
      ),
    );

    double opacityOf(WidgetTester tester, String text) => tester
        .widget<Opacity>(
          find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
        )
        .opacity;

    testWidgets('R1 · the parts enter one after the other in 640 ms', (
      tester,
    ) async {
      AppMotion.enabled = true;
      await tester.pumpWidget(host());
      expect(opacityOf(tester, 'cabeçalho'), 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf(tester, 'cabeçalho'), greaterThan(0));
      expect(
        opacityOf(tester, 'cartão'),
        lessThan(opacityOf(tester, 'cabeçalho')),
      );
      expect(find.byKey(const ValueKey('staggered-reveal')), findsOneWidget);
      await tester.pump(StaggeredEntrance.total);
      expect(find.byType(Opacity), findsNothing);
      expect(find.byKey(const ValueKey('staggered-reveal')), findsNothing);
    });

    testWidgets('R8 · with animations off everything is in place at once', (
      tester,
    ) async {
      AppMotion.enabled = true;
      await tester.pumpWidget(host(reduced: true));
      expect(find.byType(Opacity), findsNothing);
      expect(find.byKey(const ValueKey('staggered-reveal')), findsNothing);
    });
  });
}
