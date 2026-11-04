import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/prototype/prototype_delete.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/widgets/app_toast.dart';

void motionOn() {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
}

Finder _ofToast(Finder toast, Type type) =>
    find.ancestor(of: toast, matching: find.byType(type)).first;

/// Opacity of [toast]: the [ToastMotion] one, the only one that moves it.
double opacity(WidgetTester tester, Finder toast) {
  final motion = find.ancestor(of: toast, matching: find.byType(ToastMotion));
  return tester
      .widget<FadeTransition>(
        find
            .descendant(of: motion.first, matching: find.byType(FadeTransition))
            .first,
      )
      .opacity
      .value;
}

double travel(WidgetTester tester, Finder toast) =>
    tester.getTopLeft(toast).dy - restingTop;

/// Where the toast rests, measured after it settles.
late double restingTop;

/// Past the frame that starts the transition, so a later pump counts in full.
Future<void> start(WidgetTester tester) =>
    tester.pump(const Duration(microseconds: 1));

void main() {
  group('showAppToast', () {
    final text = find.text('Spec salva');
    late ScaffoldMessengerState messenger;

    Future<void> mount(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.expand())),
      );
      messenger = tester.state(find.byType(ScaffoldMessenger));
    }

    Future<void> measure(WidgetTester tester) async {
      messenger.showAppToast(const SnackBar(content: Text('Spec salva')));
      await tester.pumpAndSettle();
      restingTop = tester.getTopLeft(text).dy;
      messenger.removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }

    testWidgets('R5 · rises 8 px with a fade in base', (tester) async {
      motionOn();
      await mount(tester);
      await measure(tester);

      messenger.showAppToast(const SnackBar(content: Text('Spec salva')));
      await tester.pump();
      expect(opacity(tester, text), 0);
      expect(travel(tester, text), closeTo(8, 1e-6));

      await start(tester);
      await tester.pump(const Duration(milliseconds: 40));
      expect(opacity(tester, text), inExclusiveRange(0, 1));
      expect(travel(tester, text), inExclusiveRange(0, 8));

      await tester.pump(AppMotion.base - const Duration(milliseconds: 40));
      expect(opacity(tester, text), 1);
      expect(travel(tester, text), 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('R5 · leaves the same way in the exit of base', (tester) async {
      motionOn();
      await mount(tester);
      await measure(tester);
      messenger.showAppToast(const SnackBar(content: Text('Spec salva')));
      await tester.pumpAndSettle();

      messenger.hideCurrentSnackBar();
      await tester.pump();
      await start(tester);
      await tester.pump(AppMotion.baseExit - const Duration(milliseconds: 40));
      expect(opacity(tester, text), inExclusiveRange(0, 1));
      expect(travel(tester, text), inExclusiveRange(0, 8));

      await tester.pump(const Duration(milliseconds: 39));
      expect(opacity(tester, text), closeTo(0, .05));
      expect(travel(tester, text), closeTo(8, .4));

      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(text, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('R12, R13 · hiding during the entrance starts from what is on '
        'screen, and the size never changes', (tester) async {
      motionOn();
      await mount(tester);
      await measure(tester);
      final box = find.byType(SnackBar);

      messenger.showAppToast(const SnackBar(content: Text('Spec salva')));
      await tester.pump();
      final size = tester.getSize(box);
      await start(tester);
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.getSize(box), size);
      final o = opacity(tester, text);
      final y = travel(tester, text);

      messenger.hideCurrentSnackBar();
      await tester.pump();
      await start(tester);
      expect(opacity(tester, text), closeTo(o, .01));
      expect(travel(tester, text), closeTo(y, .1));
      expect(tester.getSize(box), size);

      await tester.pumpAndSettle();
      expect(text, findsNothing);
    });

    testWidgets('R11 · with reduced motion it shows at once', (tester) async {
      motionOn();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await mount(tester);
      messenger.showAppToast(const SnackBar(content: Text('Spec salva')));
      await tester.pump();
      expect(opacity(tester, text), 1);
      expect(tester.hasRunningAnimations, isFalse);
      messenger.hideCurrentSnackBar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(text, findsNothing);
    });

    testWidgets('keeps the message, the key, the action and the reason', (
      tester,
    ) async {
      motionOn();
      await mount(tester);
      var undone = 0;
      final closed = messenger
          .showAppToast(
            SnackBar(
              key: const ValueKey('toast'),
              content: const Text('Spec salva'),
              action: SnackBarAction(
                key: const ValueKey('toast-undo'),
                label: 'Desfazer',
                onPressed: () => undone++,
              ),
            ),
          )
          .closed;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('toast')), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(SnackBarAction), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toast-undo')));
      await tester.pumpAndSettle();
      expect(undone, 1);
      expect(text, findsNothing);
      expect(await closed, SnackBarClosedReason.action);
    });

    testWidgets('R12 · the action already counts during the entrance', (
      tester,
    ) async {
      motionOn();
      await mount(tester);
      var undone = 0;
      messenger.showAppToast(
        SnackBar(
          content: const Text('Spec salva'),
          action: SnackBarAction(label: 'Desfazer', onPressed: () => undone++),
        ),
      );
      await tester.pump();
      await start(tester);
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(find.text('Desfazer'), warnIfMissed: false);
      expect(undone, 1);
      await tester.pumpAndSettle();
    });

    for (final animated in [true, false]) {
      testWidgets('the timer closes it and the queue goes on '
          '(${animated ? 'animated' : 'animations off'})', (tester) async {
        if (animated) motionOn();
        await mount(tester);
        final first = messenger
            .showAppToast(
              const SnackBar(
                content: Text('Primeiro'),
                duration: Duration(seconds: 1),
              ),
            )
            .closed;
        messenger.showAppToast(
          const SnackBar(
            content: Text('Segundo'),
            duration: Duration(seconds: 1),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Primeiro'), findsOneWidget);
        expect(find.text('Segundo'), findsNothing);

        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Primeiro'), findsNothing);
        expect(find.text('Segundo'), findsOneWidget);
        expect(await first, SnackBarClosedReason.timeout);

        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Segundo'), findsNothing);
      });
    }
  });

  group('PrototypeUndoToast', () {
    final toast = find.byKey(const ValueKey('proto-undo-toast'));
    final message = find.byKey(const ValueKey('proto-undo-message'));
    late ProviderContainer container;
    late int undone;

    PrototypeUndoController ctrl() =>
        container.read(prototypeUndoProvider.notifier);

    void offer([String text = 'Tela R2, variação A, apagada.']) => ctrl().offer(
      PrototypeUndo(specId: 1, message: text, undo: () async => undone++),
    );

    Future<void> mount(WidgetTester tester, {VoidCallback? onBelow}) async {
      undone = 0;
      container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('below'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onBelow,
                    ),
                  ),
                  const Positioned(
                    left: 20,
                    bottom: 20,
                    child: PrototypeUndoToast(specId: 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Future<void> measure(WidgetTester tester) async {
      offer();
      await tester.pumpAndSettle();
      restingTop = tester.getTopLeft(toast).dy;
      ctrl().dismiss();
      await tester.pumpAndSettle();
      expect(toast, findsNothing);
    }

    testWidgets('R5 · rises 8 px with a fade in base', (tester) async {
      motionOn();
      await mount(tester);
      await measure(tester);

      offer();
      await tester.pump();
      expect(travel(tester, toast), closeTo(8, 1e-6));
      expect(
        tester
            .widget<FadeTransition>(_ofToast(toast, FadeTransition))
            .opacity
            .value,
        0,
      );
      await start(tester);
      await tester.pump(AppMotion.base);
      expect(travel(tester, toast), 0);
      expect(opacity(tester, toast), 1);
      expect(tester.hasRunningAnimations, isFalse);
      ctrl().dismiss();
      await tester.pumpAndSettle();
    });

    testWidgets('R5 · leaves the same way in the exit of base, with the '
        'message still there', (tester) async {
      motionOn();
      await mount(tester);
      await measure(tester);
      offer();
      await tester.pumpAndSettle();

      ctrl().dismiss();
      await tester.pump();
      await start(tester);
      await tester.pump(AppMotion.baseExit - const Duration(milliseconds: 40));
      expect(message, findsOneWidget);
      expect(opacity(tester, toast), inExclusiveRange(0, 1));
      expect(travel(tester, toast), inExclusiveRange(0, 8));

      await tester.pump(const Duration(milliseconds: 41));
      expect(toast, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('R12 · Ctrl+Z\'s undo works during the entrance and does not '
        'wait for the exit', (tester) async {
      motionOn();
      await mount(tester);
      offer();
      await tester.pump();
      await start(tester);
      await tester.pump(const Duration(milliseconds: 30));

      await ctrl().undo();
      expect(undone, 1);
      expect(container.read(prototypeUndoProvider), isNull);

      // A second press while it leaves has nothing left to undo.
      await tester.pump();
      await ctrl().undo();
      expect(undone, 1);
      await tester.pumpAndSettle();
      expect(toast, findsNothing);
    });

    testWidgets('the timer of the offer is not moved by the animations', (
      tester,
    ) async {
      motionOn();
      await mount(tester);
      offer();
      await tester.pumpAndSettle();
      expect(container.read(prototypeUndoProvider), isNotNull);

      const margin = Duration(seconds: 1);
      await tester.pump(prototypeUndoWindow - margin);
      expect(container.read(prototypeUndoProvider), isNotNull);
      await tester.pump(margin);
      expect(container.read(prototypeUndoProvider), isNull);
      expect(toast, findsOneWidget);
      await tester.pumpAndSettle();
      expect(toast, findsNothing);
    });

    testWidgets('R12 · a new deletion while it leaves turns back from where '
        'it is, with the new message', (tester) async {
      motionOn();
      await mount(tester);
      await measure(tester);
      offer();
      await tester.pumpAndSettle();
      ctrl().dismiss();
      await tester.pump();
      await start(tester);
      await tester.pump(const Duration(milliseconds: 70));
      final o = opacity(tester, toast);
      expect(o, inExclusiveRange(0, 1));

      offer('2 telas apagadas.');
      await tester.pump();
      await start(tester);
      expect(opacity(tester, toast), closeTo(o, .02));
      expect(find.text('2 telas apagadas.'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(opacity(tester, toast), 1);
      expect(travel(tester, toast), 0);
      ctrl().dismiss();
      await tester.pumpAndSettle();
    });

    testWidgets('R12 · a click on a toast on its way out reaches what is '
        'under it', (tester) async {
      motionOn();
      var below = 0;
      await mount(tester, onBelow: () => below++);
      offer();
      await tester.pumpAndSettle();
      final spot = tester.getCenter(message);
      ctrl().dismiss();
      await tester.pump();
      await start(tester);
      await tester.tapAt(spot);
      expect(below, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('R11 · with animations off it comes and goes at once', (
      tester,
    ) async {
      await mount(tester);
      offer();
      await tester.pump();
      expect(opacity(tester, toast), 1);
      ctrl().dismiss();
      await tester.pump();
      expect(toast, findsNothing);
    });
  });
}
