import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'claude_event.dart';

/// Last `rate_limit_event` of any session, conversation or planner run: the
/// plan usage of the 5-hour and weekly windows shown in the footer.
///
/// Persisted in `app_settings` ([AppSettingKeys.lastRateLimit]) so the footer
/// still shows it after a restart; [planWindowExpired] tells when a stored
/// window has already reset.
class RateLimitController extends Notifier<RateLimit?> {
  @override
  RateLimit? build() => decodeRateLimit(
    ref.watch(
      appSettingsProvider.select((s) => s[AppSettingKeys.lastRateLimit]),
    ),
  );

  Future<void> record(RateLimit r) {
    state = r;
    return ref
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.lastRateLimit, jsonEncode(r.json));
  }
}

/// Stored event → [RateLimit] (null when absent or invalid).
RateLimit? decodeRateLimit(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final e = ClaudeEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return e is RateLimit ? e : null;
  } catch (_) {
    return null;
  }
}

/// Whether a window that resets at [resetsAt] has already reset (its stored
/// utilization no longer applies).
bool planWindowExpired(DateTime? resetsAt, DateTime now) =>
    resetsAt != null && !resetsAt.isAfter(now);

final rateLimitProvider = NotifierProvider<RateLimitController, RateLimit?>(
  RateLimitController.new,
);

/// Feeds the `rate_limit_event`s of every run into [rateLimitProvider].
class UsageTracker {
  UsageTracker(this._ref);

  final Ref _ref;

  Future<void> handle(ClaudeEvent event) async {
    if (event is RateLimit) {
      await _ref.read(rateLimitProvider.notifier).record(event);
    }
  }
}

final usageTrackerProvider = Provider(UsageTracker.new);
