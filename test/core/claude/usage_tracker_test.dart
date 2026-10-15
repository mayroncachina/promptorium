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

  test(
    'sums result usage per day, persists it and keeps the last rate limit',
    () async {
      final db = memoryDatabase();
      var now = DateTime(2026, 10, 15, 23, 50);
      final c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          usageClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final tracker = c.read(usageTrackerProvider);

      for (final e in fixture) {
        await tracker.handle(e);
      }
      for (final e in fixture.whereType<Result>()) {
        await tracker.handle(e);
      }

      final today = c.read(dailyUsageProvider);
      expect(today.day, '2026-10-15');
      expect(today.results, 2);
      expect(today.usage.inputTokens, 4);
      expect(today.usage.outputTokens, 84);
      expect(today.usage.cacheReadInputTokens, 22182);
      expect(today.costUsd, closeTo(0.00604742, 1e-9));
      expect(c.read(rateLimitProvider)!.fiveHourUtilization, 0.12);

      final stored = await c
          .read(appSettingsRepoProvider)
          .get('usage.2026-10-15');
      expect(DailyUsage.decode('2026-10-15', stored).usage.outputTokens, 84);

      // Next day starts from zero; the previous day stays stored.
      now = DateTime(2026, 10, 16, 0, 5);
      await tracker.handle(fixture.whereType<Result>().single);
      final next = c.read(dailyUsageProvider);
      expect(next.day, '2026-10-16');
      expect(next.results, 1);
      expect(c.read(appSettingsProvider)['usage.2026-10-15'], isNotNull);
    },
  );

  test('decode is tolerant', () {
    expect(DailyUsage.decode('d', 'lixo').results, 0);
    expect(DailyUsage.decode('d', null).costUsd, 0);
  });
}
