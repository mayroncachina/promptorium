import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// When the person is "away" (SPEC-080 R1, R2, P1): the window without
/// focus, or in focus without any key, click or scroll, for the limit
/// (30 min by default). Pure: the shell feeds it the window's focus and
/// the input, with the time.

/// The default limit (R2).
const defaultAwayLimit = Duration(minutes: 30);

/// The visto por último is written at most once a minute while in use (R1).
const presenceWriteEvery = Duration(minutes: 1);

/// A return after being away: since when, and for how long.
typedef AwaySpan = ({DateTime since, Duration away});

class PresenceTracker {
  PresenceTracker({
    required DateTime now,
    DateTime? lastSeenAt,
    this.write,
    this.limit = defaultAwayLimit,
    this.focused = true,
  }) : _activeAt = now,
       previousSeenAt = lastSeenAt,
       lastSeenAt = lastSeenAt;

  /// Writes the visto por último (`app_settings`, R1).
  final Future<void> Function(DateTime at)? write;

  /// The limit of a return; null = never (only the opening counts).
  Duration? limit;

  /// The last time seen in the previous run (what the opening compares).
  final DateTime? previousSeenAt;

  /// The last time seen (the previous run's until the first input).
  DateTime? lastSeenAt;
  DateTime? _writtenAt;

  /// The last time in focus with input, or when the focus came back.
  DateTime _activeAt;

  /// The window has the focus.
  bool focused;

  /// [returned] listeners: the shell shows the compact card (R11).
  final _returns = StreamController<AwaySpan>.broadcast();
  Stream<AwaySpan> get returns => _returns.stream;

  /// Opening the app: away when the last seen is [openLimit] old or more
  /// (R2). The first run (nothing stored) is not a return.
  AwaySpan? openedAway(DateTime now, {Duration openLimit = defaultAwayLimit}) {
    final seen = previousSeenAt;
    if (seen == null) return null;
    final away = now.difference(seen);
    return away >= openLimit ? (since: seen, away: away) : null;
  }

  AwaySpan? _check(DateTime now) {
    final l = limit;
    if (l == null) return null;
    final away = now.difference(_activeAt);
    if (away < l) return null;
    final span = (since: _activeAt, away: away);
    _returns.add(span);
    return span;
  }

  /// A key, a click or a scroll in the window (R1). Returns the span when
  /// it ends an absence (in focus without input, or the focus that came
  /// back unnoticed).
  AwaySpan? input(DateTime now) {
    final span = _check(now);
    focused = true;
    _activeAt = now;
    lastSeenAt = now;
    final w = _writtenAt;
    if (w == null || now.difference(w) >= presenceWriteEvery) {
      _persist(now);
    }
    return span;
  }

  /// The window got the focus (R2): a return after the limit without it.
  AwaySpan? focus(DateTime now) {
    if (focused) return null;
    focused = true;
    final span = _check(now);
    // The focus alone does not mean seen: the next input writes.
    _activeAt = now;
    return span;
  }

  /// The window lost the focus: the last seen is written now (R1).
  void blur(DateTime now) {
    if (!focused) return;
    focused = false;
    flush();
  }

  /// Writes the last seen when it was not written yet (blur, closing).
  Future<void> flush() async {
    final seen = lastSeenAt;
    if (seen == null || seen == _writtenAt) return;
    await _persist(seen);
  }

  Future<void> _persist(DateTime at) async {
    _writtenAt = at;
    try {
      await write?.call(at);
    } catch (e) {
      debugPrint('visto por último não gravado — $e');
    }
  }

  void dispose() => _returns.close();
}

/// The limit of a return in [settings] (R14): `0` = never.
Duration? awayLimitOf(Map<String, String> settings) {
  final m = int.tryParse(settings[AppSettingKeys.resumeAwayMinutes] ?? '');
  if (m == null) return defaultAwayLimit;
  return m <= 0 ? null : Duration(minutes: m);
}

/// The tracker of the app: the visto por último read once when the shell
/// starts it ([PresenceTracker.lastSeenAt] stays the previous run's until
/// the first input).
final presenceProvider = Provider<PresenceTracker>((ref) {
  final repo = ref.read(appSettingsRepoProvider);
  final settings = ref.read(appSettingsProvider);
  final t = PresenceTracker(
    now: DateTime.now(),
    lastSeenAt: DateTime.tryParse(
      settings[AppSettingKeys.resumeLastSeen] ?? '',
    ),
    limit: awayLimitOf(settings),
    write: (at) =>
        repo.set(AppSettingKeys.resumeLastSeen, at.toIso8601String()),
  );
  ref.onDispose(t.dispose);
  return t;
});
