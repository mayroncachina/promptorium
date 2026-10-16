import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/claude/usage_tracker.dart';
import 'package:promptorium/data/providers.dart';

import '../../helpers/test_db.dart';

void main() {
  late List<ClaudeEvent> fixture;

  setUpAll(() {
    fixture = [
      for (final l in File(
        'test/fixtures/stream-json-exemplo.jsonl',
      ).readAsLinesSync().where((l) => l.trim().isNotEmpty))
        ...ClaudeEvent.parseLine(l),
    ];
  });

  test('keeps the last rate limit and restores it after a restart', () async {
    final db = memoryDatabase();
    final c = ProviderContainer(overrides: [databaseOverride(db)]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    expect(c.read(rateLimitProvider), isNull);

    // Results no longer feed anything: only rate_limit_event counts.
    for (final e in fixture) {
      await c.read(usageTrackerProvider).handle(e);
    }
    final r = c.read(rateLimitProvider)!;
    expect(r.fiveHourUtilization, 0.12);
    expect(r.sevenDayUtilization, 0.56);
    expect(
      c.read(appSettingsProvider).keys,
      isNot(contains(startsWith('usage.2'))),
    );

    // A new container (app restart) reads the stored event.
    final again = ProviderContainer(overrides: [databaseOverride(db)]);
    addTearDown(again.dispose);
    await again.read(appSettingsProvider.notifier).load();
    final restored = again.read(rateLimitProvider)!;
    expect(restored.fiveHourUtilization, 0.12);
    expect(restored.fiveHourResetsAt, r.fiveHourResetsAt);
  });

  test('decode is tolerant', () {
    expect(decodeRateLimit(null), isNull);
    expect(decodeRateLimit('lixo'), isNull);
    expect(decodeRateLimit('{"type":"result"}'), isNull);
  });

  test('a window expires at its reset time', () {
    final t = DateTime(2026, 10, 16, 18);
    expect(planWindowExpired(null, t), isFalse);
    expect(planWindowExpired(t.add(const Duration(minutes: 1)), t), isFalse);
    expect(planWindowExpired(t, t), isTrue);
    expect(planWindowExpired(t.subtract(const Duration(hours: 1)), t), isTrue);
  });
}
