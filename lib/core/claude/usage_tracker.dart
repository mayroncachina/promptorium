import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../providers/quota_source.dart' show QuotaVia;
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

  /// [via]: a reply of a run or `/usage` (the time of the reading goes to
  /// [rateLimitReadProvider], SPEC-097 R6).
  Future<void> record(RateLimit r, {QuotaVia via = QuotaVia.reply}) async {
    state = r;
    final settings = ref.read(appSettingsProvider.notifier);
    await settings.set(AppSettingKeys.lastRateLimit, jsonEncode(r.json));
    await settings.set(
      AppSettingKeys.lastRateLimitRead,
      jsonEncode({
        'at': DateTime.now().toUtc().toIso8601String(),
        'via': via.name,
      }),
    );
  }
}

/// When and how the last Claude reading came (SPEC-097 R6).
final rateLimitReadProvider = Provider<({DateTime at, QuotaVia? via})?>((ref) {
  final raw = ref.watch(
    appSettingsProvider.select((s) => s[AppSettingKeys.lastRateLimitRead]),
  );
  if (raw == null) return null;
  try {
    final j = jsonDecode(raw) as Map;
    final at = DateTime.tryParse('${j['at']}');
    if (at == null) return null;
    return (
      at: at,
      via: QuotaVia.values.where((v) => v.name == j['via']).firstOrNull,
    );
  } catch (_) {
    return null;
  }
});

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
