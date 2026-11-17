import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/features/resume/presence.dart';

final t0 = DateTime(2026, 11, 17, 9);

void main() {
  group('opening the app (R2)', () {
    test('the last seen 30 min or more ago is a return', () {
      final seen = DateTime(2026, 11, 16, 19, 42);
      final p = PresenceTracker(now: t0, lastSeenAt: seen);
      final span = p.openedAway(t0)!;
      expect(span.since, seen);
      expect(span.away, t0.difference(seen));
      expect(
        PresenceTracker(
          now: t0,
          lastSeenAt: t0.subtract(const Duration(minutes: 29)),
        ).openedAway(t0),
        isNull,
      );
    });

    test('the first run is not a return; an input does not erase it', () {
      expect(PresenceTracker(now: t0).openedAway(t0), isNull);
      final seen = t0.subtract(const Duration(hours: 13));
      final p = PresenceTracker(now: t0, lastSeenAt: seen)..input(t0);
      expect(p.openedAway(t0)?.since, seen);
    });
  });

  group('with the app open (R2)', () {
    test('a window flickering in and out of focus is still away', () {
      final p = PresenceTracker(now: t0)..input(t0);
      final spans = <AwaySpan?>[];
      for (var m = 5; m < 40; m += 5) {
        p.blur(t0.add(Duration(minutes: m)));
        spans.add(p.focus(t0.add(Duration(minutes: m, seconds: 1))));
      }
      // The focus at 30 min ends the absence that began with the input.
      expect(spans.whereType<AwaySpan>().single.since, t0);
    });

    test('back after 30 min without focus', () {
      final p = PresenceTracker(now: t0)..input(t0);
      final spans = <AwaySpan>[];
      p.returns.listen(spans.add);
      p.blur(t0.add(const Duration(minutes: 1)));
      expect(p.focus(t0.add(const Duration(minutes: 20))), isNull);
      p.blur(t0.add(const Duration(minutes: 21)));
      final span = p.focus(t0.add(const Duration(minutes: 55)));
      // The focus alone is not activity: away since the last input.
      expect(span?.since, t0);
      expect(span?.away, const Duration(minutes: 55));
      // The input right after is the same return, not another.
      expect(p.input(t0.add(const Duration(minutes: 56))), isNull);
    });

    test('stopped in focus: the first input after 47 min is a return', () {
      final p = PresenceTracker(now: t0)..input(t0);
      expect(p.input(t0.add(const Duration(minutes: 10))), isNull);
      final span = p.input(t0.add(const Duration(minutes: 57)));
      expect(span?.away, const Duration(minutes: 47));
      expect(p.input(t0.add(const Duration(minutes: 58))), isNull);
    });

    test('the limit can change; "nunca" never returns', () {
      final p = PresenceTracker(now: t0, limit: const Duration(minutes: 15))
        ..input(t0);
      expect(p.input(t0.add(const Duration(minutes: 16))), isNotNull);
      p.limit = null;
      expect(p.input(t0.add(const Duration(hours: 5))), isNull);
    });

    test('the returns go to the listeners (the compact card)', () async {
      final p = PresenceTracker(now: t0);
      final spans = <AwaySpan>[];
      p.returns.listen(spans.add);
      p.input(t0.add(const Duration(hours: 1)));
      await pumpEventQueue();
      expect(spans.single.away, const Duration(hours: 1));
    });
  });

  group('writing the last seen (R1)', () {
    test('at most once a minute while in use, and on blur', () async {
      final writes = <DateTime>[];
      final p = PresenceTracker(now: t0, write: (at) async => writes.add(at));
      for (var s = 0; s < 90; s += 5) {
        p.input(t0.add(Duration(seconds: s)));
      }
      expect(writes, [t0, t0.add(const Duration(seconds: 60))]);
      p.blur(t0.add(const Duration(seconds: 100)));
      await pumpEventQueue();
      expect(writes.last, t0.add(const Duration(seconds: 85)));
      expect(p.lastSeenAt, t0.add(const Duration(seconds: 85)));
      // Nothing new: closing writes nothing again.
      await p.flush();
      expect(writes, hasLength(3));
    });

    test('the focus alone is not seen', () async {
      final writes = <DateTime>[];
      final p = PresenceTracker(
        now: t0,
        focused: false,
        write: (at) async => writes.add(at),
      )..focus(t0);
      await p.flush();
      expect(writes, isEmpty);
      expect(p.lastSeenAt, isNull);
    });
  });

  test('awayLimitOf: 30 min by default, 0 = never', () {
    expect(awayLimitOf(const {}), const Duration(minutes: 30));
    expect(
      awayLimitOf(const {AppSettingKeys.resumeAwayMinutes: '120'}),
      const Duration(hours: 2),
    );
    expect(awayLimitOf(const {AppSettingKeys.resumeAwayMinutes: '0'}), isNull);
  });
}
