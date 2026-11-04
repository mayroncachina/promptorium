import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/widgets/app_dialog.dart';

const _scrim = Color(0xCC000000);
const _dialog = ValueKey('dialog');

void motionOn() {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
}

/// The app's screen: "open" shows a dialog through [show].
class _Host extends StatelessWidget {
  const _Host({required this.show, this.reduced = false, this.focusNode});

  final void Function(BuildContext context) show;
  final bool reduced;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const ValueKey('open'),
            focusNode: focusNode,
            onPressed: () => show(context),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
}

Widget _sheet(BuildContext context) => AlertDialog(
  key: _dialog,
  title: const Text('Apagar?'),
  actions: [
    TextButton(
      key: const ValueKey('no'),
      autofocus: true,
      onPressed: () => Navigator.pop(context, 'no'),
      child: const Text('Não'),
    ),
    TextButton(
      key: const ValueKey('yes'),
      onPressed: () => Navigator.pop(context, 'yes'),
      child: const Text('Sim'),
    ),
  ],
);

double opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(_dialog),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

double scale(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .ancestor(of: find.byKey(_dialog), matching: find.byType(Transform))
          .first,
    )
    .transform
    .storage[0];

/// The alpha of the dialog's scrim (the page below has a barrier of its own).
double scrimAlpha(WidgetTester tester) =>
    tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).last.color?.a ??
    0;

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pump();
}

/// Past the frame that starts the transition, so a later pump counts in full.
Future<void> start(WidgetTester tester) =>
    tester.pump(const Duration(microseconds: 1));

void main() {
  void showIt(BuildContext context) => showAppDialog<String>(
    context: context,
    barrierColor: _scrim,
    builder: _sheet,
  );

  group('R4 · motion', () {
    testWidgets('opens from 0.96 and no opacity; the scrim is done in base and '
        'the dialog in emphasis', (tester) async {
      motionOn();
      await tester.pumpWidget(_Host(show: showIt));
      await open(tester);
      expect(opacity(tester), 0);
      expect(scale(tester), closeTo(.96, 1e-6));
      expect(scrimAlpha(tester), 0);

      await start(tester);
      await tester.pump(AppMotion.base);
      expect(scrimAlpha(tester), closeTo(_scrim.a, 1e-6));
      expect(opacity(tester), lessThan(1));
      expect(scale(tester), lessThan(1));

      await tester.pump(AppMotion.emphasis - AppMotion.base);
      expect(opacity(tester), 1);
      expect(scale(tester), 1);
    });

    testWidgets('closes to 0.98 and no opacity in the exit of emphasis, and '
        'the scrim leaves first, in the exit of base', (tester) async {
      motionOn();
      await tester.pumpWidget(_Host(show: showIt));
      await open(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('yes')));
      await tester.pump();
      await start(tester);
      await tester.pump(AppMotion.baseExit);
      expect(scrimAlpha(tester), closeTo(0, 1e-6));
      expect(opacity(tester), greaterThan(0));
      expect(scale(tester), inExclusiveRange(.98, 1));

      await tester.pump(
        AppMotion.emphasisExit -
            AppMotion.baseExit -
            const Duration(milliseconds: 2),
      );
      expect(opacity(tester), closeTo(0, .05));
      expect(scale(tester), closeTo(.98, .002));

      await tester.pump(const Duration(milliseconds: 3));
      expect(find.byKey(_dialog), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('R11 · with reduced motion it opens and closes at once', (
      tester,
    ) async {
      motionOn();
      await tester.pumpWidget(_Host(show: showIt, reduced: true));
      await open(tester);
      expect(opacity(tester), 1);
      expect(scale(tester), 1);
      expect(scrimAlpha(tester), closeTo(_scrim.a, 1e-6));

      await tester.tap(find.byKey(const ValueKey('yes')));
      await tester.pump();
      expect(find.byKey(_dialog), findsNothing);
    });

    testWidgets('R12 · closing during the entrance starts from what is on '
        'screen, and Esc already counts', (tester) async {
      motionOn();
      await tester.pumpWidget(_Host(show: showIt));
      await open(tester);
      await start(tester);
      await tester.pump(const Duration(milliseconds: 40));
      final o = opacity(tester);
      final s = scale(tester);
      final a = scrimAlpha(tester);
      expect(o, inExclusiveRange(0, 1));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await start(tester);
      expect(opacity(tester), closeTo(o, .01));
      expect(scale(tester), closeTo(s, .001));
      expect(scrimAlpha(tester), closeTo(a, .01));

      await tester.pump(AppMotion.emphasisExit);
      expect(find.byKey(_dialog), findsNothing);
    });
  });

  group('R4 · what showDialog does', () {
    Future<void> settled(WidgetTester tester, Widget host) async {
      await tester.pumpWidget(host);
      await open(tester);
      await tester.pumpAndSettle();
    }

    for (final animated in [true, false]) {
      final name = animated ? 'animated' : 'animations off';

      testWidgets('the value is returned ($name)', (tester) async {
        if (animated) motionOn();
        final values = <String?>[];
        await settled(
          tester,
          _Host(
            show: (c) async => values.add(
              await showAppDialog<String>(context: c, builder: _sheet),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('yes')));
        await tester.pumpAndSettle();
        expect(values, ['yes']);
      });

      testWidgets('Esc closes with no value ($name)', (tester) async {
        if (animated) motionOn();
        final values = <String?>['untouched'];
        await settled(
          tester,
          _Host(
            show: (c) async {
              values[0] = await showAppDialog<String>(
                context: c,
                builder: _sheet,
              );
            },
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(_dialog), findsNothing);
        expect(values, [null]);
      });

      testWidgets('a click on the scrim closes ($name)', (tester) async {
        if (animated) motionOn();
        await settled(tester, _Host(show: showIt));
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(find.byKey(_dialog), findsNothing);
      });
    }

    testWidgets('barrierDismissible false keeps it open on a click, and the '
        'scrim is labelled like showDialog', (tester) async {
      motionOn();
      await settled(
        tester,
        _Host(
          show: (c) => showAppDialog<void>(
            context: c,
            barrierDismissible: false,
            builder: _sheet,
          ),
        ),
      );
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsOneWidget);
      final route = ModalRoute.of(tester.element(find.byKey(_dialog)))!;
      expect(route.barrierDismissible, isFalse);
      expect(route.barrierLabel, isNotEmpty);
      expect(route.barrierColor, Colors.black54);
    });

    testWidgets('focus goes in, stays trapped and returns to the opener', (
      tester,
    ) async {
      motionOn();
      final opener = FocusNode();
      addTearDown(opener.dispose);
      await tester.pumpWidget(_Host(show: showIt, focusNode: opener));
      opener.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // In from the first frames: not after the animation.
      await start(tester);
      bool focusIn(Key key) {
        var inside = false;
        FocusManager.instance.primaryFocus!.context!.visitAncestorElements((e) {
          inside = e.widget.key == key;
          return !inside;
        });
        return inside;
      }

      expect(opener.hasFocus, isFalse);
      expect(focusIn(const ValueKey('no')), isTrue);
      await tester.pumpAndSettle();

      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          focusIn(const ValueKey('no')) || focusIn(const ValueKey('yes')),
          isTrue,
        );
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
      expect(opener.hasPrimaryFocus, isTrue);
    });

    testWidgets('themes above the caller and the safe area reach the dialog', (
      tester,
    ) async {
      const padding = EdgeInsets.only(top: 40);
      late BuildContext inside;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: padding),
            child: Scaffold(
              body: IconTheme(
                data: const IconThemeData(size: 77),
                child: Builder(
                  builder: (context) => TextButton(
                    key: const ValueKey('open'),
                    onPressed: () => showAppDialog<void>(
                      context: context,
                      builder: (c) {
                        inside = c;
                        return const SizedBox();
                      },
                    ),
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await open(tester);
      expect(IconTheme.of(inside).size, 77);
      expect(
        find.ancestor(
          of: find.byWidgetPredicate((w) => w is Builder),
          matching: find.byType(SafeArea),
        ),
        findsWidgets,
      );
    });

    testWidgets('useRootNavigator false pushes on the nearest navigator', (
      tester,
    ) async {
      final nested = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            key: nested,
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              builder: (context) => TextButton(
                key: const ValueKey('open'),
                onPressed: () => showAppDialog<void>(
                  context: context,
                  useRootNavigator: false,
                  builder: _sheet,
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await open(tester);
      expect(
        Navigator.of(tester.element(find.byKey(_dialog))),
        nested.currentState,
      );
    });

    testWidgets('with animations off it opens at once', (tester) async {
      await tester.pumpWidget(_Host(show: showIt));
      await open(tester);
      expect(opacity(tester), 1);
      expect(scale(tester), 1);
    });
  });
}
