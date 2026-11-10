import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/features/board/attention_shake.dart';
import 'package:promptorium/ui/theme/motion.dart';

class _Settings extends AppSettingsController {
  _Settings(this.initial);
  final Map<String, String> initial;
  @override
  Map<String, String> build() => initial;
}

/// Offset of the card [id] right now (0 at rest).
double _dx(WidgetTester tester, int id) {
  final finder = find.descendant(
    of: find.byKey(ValueKey('shake-$id')),
    matching: find.byType(Transform),
  );
  if (finder.evaluate().isEmpty) return 0;
  return tester.widget<Transform>(finder.first).transform.getTranslation().x;
}

Widget _board({
  required List<int> queue,
  Map<int, String>? reasons,
  int? selected,
  Map<String, String> settings = const {},
  bool reduced = false,
}) => ProviderScope(
  overrides: [appSettingsProvider.overrideWith(() => _Settings(settings))],
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: AttentionShakeHost(
          queue: queue,
          reasons: reasons ?? {for (final id in queue) id: 'aguardando você'},
          selected: selected,
          child: Column(
            children: [
              for (final id in [1, 2, 3])
                AttentionShake(
                  key: ValueKey('shake-$id'),
                  specId: id,
                  child: SizedBox(width: 200, height: 40, child: Text('$id')),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

/// Pumps through one shake, recording which cards moved.
Future<Set<int>> _shakeWindow(WidgetTester tester) async {
  final moved = <int>{};
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    for (final id in [1, 2, 3]) {
      if (_dx(tester, id).abs() > 0.1) moved.add(id);
    }
  }
  return moved;
}

void main() {
  setUp(() => AppMotion.enabled = true);
  tearDown(() => AppMotion.enabled = false);

  group('AttentionShakeQueue (R2, R3, R4)', () {
    test('turns in queue order, skipping the selected', () {
      final q = AttentionShakeQueue()..update([1, 2], {1: 'a', 2: 'b'});
      expect([q.next(), q.next(), q.next()], [1, 2, 1]);
      // An immediate shake also moves the turn on.
      final r = AttentionShakeQueue()..update([1, 2], {1: 'a', 2: 'b'});
      expect(r.shake(1), isTrue);
      expect(r.next(), 2);
      expect(q.next(skip: {2}), 1);
    });

    test('at most six shakes in a row, then only the halo', () {
      final q = AttentionShakeQueue()..update([1], {1: 'a'});
      final shakes = [for (var i = 0; i < 8; i++) q.next()];
      expect(shakes.whereType<int>(), hasLength(attentionShakeMax));
      expect(q.next(), isNull);
    });

    test('a new reason counts as a new call: it shakes again', () {
      final q = AttentionShakeQueue()..update([1], {1: 'a'});
      for (var i = 0; i < attentionShakeMax; i++) {
        q.next();
      }
      q.seen(1);
      expect(q.update([1], {1: 'b'}), [1]);
      expect(q.next(), 1);
    });

    test('seen takes the card out of the turns', () {
      final q = AttentionShakeQueue()..update([1, 2], {1: 'a', 2: 'b'});
      q.seen(2);
      expect([q.next(), q.next()], [1, 1]);
    });

    test('a card that left the queue starts over when it comes back', () {
      final q = AttentionShakeQueue()..update([1], {1: 'a'});
      q.next();
      q.update([], {});
      expect(q.update([1], {1: 'a'}), [1]);
      expect(q.count(1), 0);
    });
  });

  test('the shake goes to ±3 px and back to rest (R1)', () {
    final xs = [for (var t = 0.0; t <= 1.0; t += 0.01) attentionShakeAt(t).dx];
    expect(xs.reduce((a, b) => a < b ? a : b), closeTo(-3, 0.01));
    expect(xs.reduce((a, b) => a > b ? a : b), closeTo(3, 0.01));
    expect(attentionShakeAt(0).dx, 0);
    expect(attentionShakeAt(1).dx, 0);
  });

  testWidgets('a card that starts to need the person shakes at once, then '
      'the cards take turns every 5 s, one at a time (R1, R2)', (tester) async {
    await tester.pumpWidget(_board(queue: [1, 2]));
    expect(await _shakeWindow(tester), {1});
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pump(attentionShakeInterval);
    expect(await _shakeWindow(tester), {2});
    await tester.pump(attentionShakeInterval);
    expect(await _shakeWindow(tester), {1});
  });

  testWidgets('nothing is drawn between shakes (R8)', (tester) async {
    await tester.pumpWidget(_board(queue: [1]));
    await _shakeWindow(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('hovering a card takes it out of the turns (R4)', (tester) async {
    await tester.pumpWidget(_board(queue: [1, 2]));
    await _shakeWindow(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('2')));
    await tester.pump();
    await mouse.removePointer();
    for (var i = 0; i < 3; i++) {
      await tester.pump(attentionShakeInterval);
      expect(await _shakeWindow(tester), {1});
    }
  });

  testWidgets('the selected card does not shake (R4)', (tester) async {
    await tester.pumpWidget(_board(queue: [1], selected: 1));
    expect(await _shakeWindow(tester), isEmpty);
    await tester.pump(attentionShakeInterval);
    expect(await _shakeWindow(tester), isEmpty);
  });

  testWidgets('no shake while a dialog covers the board (R4)', (tester) async {
    await tester.pumpWidget(_board(queue: [1]));
    await _shakeWindow(tester);
    showDialog<void>(
      context: tester.element(find.text('1')),
      builder: (_) => const Text('diálogo'),
    );
    await tester.pumpAndSettle();
    await tester.pump(attentionShakeInterval);
    expect(await _shakeWindow(tester), isEmpty);
  });

  testWidgets('with reduced motion or the option off nothing shakes '
      '(R6, R7)', (tester) async {
    await tester.pumpWidget(_board(queue: [1], reduced: true));
    expect(await _shakeWindow(tester), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _board(queue: [2], settings: {AppSettingKeys.attentionShake: 'false'}),
    );
    expect(await _shakeWindow(tester), isEmpty);
    await tester.pump(attentionShakeInterval);
    expect(await _shakeWindow(tester), isEmpty);
  });

  testWidgets('no timer is left when the board goes away', (tester) async {
    await tester.pumpWidget(_board(queue: [1, 2]));
    await _shakeWindow(tester);
    await tester.pumpWidget(const SizedBox());
  });
}
