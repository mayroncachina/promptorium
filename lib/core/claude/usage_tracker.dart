import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'claude_event.dart';

/// Token usage and cost of one day (sum of `result.usage`).
@immutable
class DailyUsage {
  const DailyUsage({
    required this.day,
    this.usage = const Usage(),
    this.costUsd = 0,
    this.results = 0,
  });

  /// `yyyy-mm-dd` (local time).
  final String day;
  final Usage usage;
  final double costUsd;

  /// Number of `result` events counted.
  final int results;

  int get totalTokens => usage.total;

  DailyUsage add(Result r) => DailyUsage(
    day: day,
    usage: usage + r.usage,
    costUsd: costUsd + r.totalCostUsd,
    results: results + 1,
  );

  String encode() => jsonEncode({
    'input': usage.inputTokens,
    'output': usage.outputTokens,
    'cacheCreation': usage.cacheCreationInputTokens,
    'cacheRead': usage.cacheReadInputTokens,
    'costUsd': costUsd,
    'results': results,
  });

  /// Tolerant: invalid or missing JSON gives an empty day.
  factory DailyUsage.decode(String day, String? raw) {
    if (raw == null || raw.isEmpty) return DailyUsage(day: day);
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      int i(String k) => (j[k] as num?)?.toInt() ?? 0;
      return DailyUsage(
        day: day,
        usage: Usage(
          inputTokens: i('input'),
          outputTokens: i('output'),
          cacheCreationInputTokens: i('cacheCreation'),
          cacheReadInputTokens: i('cacheRead'),
        ),
        costUsd: (j['costUsd'] as num?)?.toDouble() ?? 0,
        results: i('results'),
      );
    } catch (_) {
      return DailyUsage(day: day);
    }
  }
}

/// `yyyy-mm-dd` of [t] in local time.
String usageDay(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

/// Clock used for the day key (overridden in tests).
final usageClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Today's usage, persisted in `app_settings` under `usage.<yyyy-mm-dd>`.
class DailyUsageController extends Notifier<DailyUsage> {
  @override
  DailyUsage build() {
    final day = usageDay(ref.watch(usageClockProvider)());
    final raw = ref.watch(
      appSettingsProvider.select((s) => s[AppSettingKeys.usage(day)]),
    );
    return DailyUsage.decode(day, raw);
  }

  /// Adds one `result` to today's total (starting a new day if needed).
  Future<void> record(Result r) {
    final day = usageDay(ref.read(usageClockProvider)());
    final base = state.day == day
        ? state
        : DailyUsage.decode(
            day,
            ref.read(appSettingsProvider)[AppSettingKeys.usage(day)],
          );
    final next = base.add(r);
    state = next;
    return ref
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.usage(day), next.encode());
  }
}

final dailyUsageProvider = NotifierProvider<DailyUsageController, DailyUsage>(
  DailyUsageController.new,
);

/// Last `rate_limit_event` of any session (in memory only).
class RateLimitController extends Notifier<RateLimit?> {
  @override
  RateLimit? build() => null;

  void record(RateLimit r) => state = r;
}

final rateLimitProvider = NotifierProvider<RateLimitController, RateLimit?>(
  RateLimitController.new,
);

/// Feeds session events into [dailyUsageProvider] / [rateLimitProvider].
/// Fase 5 calls [handle] for every event of every session and binds the
/// footer to those providers.
class UsageTracker {
  UsageTracker(this._ref);

  final Ref _ref;

  Future<void> handle(ClaudeEvent event) async {
    switch (event) {
      case Result():
        await _ref.read(dailyUsageProvider.notifier).record(event);
      case RateLimit():
        _ref.read(rateLimitProvider.notifier).record(event);
      default:
        break;
    }
  }
}

final usageTrackerProvider = Provider(UsageTracker.new);
