import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'claude_cli.dart' show claudeExecutableProvider;
import 'claude_event.dart';
import 'usage_tracker.dart';

/// Reads the plan usage without spending tokens: `claude -p "/usage"` is a
/// local command (0 turns, cost 0) whose text has the 5-hour ("Current
/// session") and weekly percentages and their reset times. The footer was
/// only updated by the `rate_limit_event` of runs, so it went stale while
/// nothing was running.

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// `Oct 16, 2:09pm`, `2pm` (today / the next one), local time.
DateTime? parseUsageReset(String text, DateTime now) {
  final m = RegExp(
    r'^(?:([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+)?(\d{1,2})(?::(\d{2}))?\s*([ap]m)$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (m == null) return null;
  var hour = int.parse(m.group(3)!) % 12;
  if (m.group(5)!.toLowerCase() == 'pm') hour += 12;
  final minute = int.tryParse(m.group(4) ?? '0') ?? 0;
  final month = m.group(1) == null
      ? now.month
      : _months[m.group(1)!.toLowerCase()];
  if (month == null) return null;
  final day = m.group(2) == null ? now.day : int.parse(m.group(2)!);
  var at = DateTime(now.year, month, day, hour, minute);
  if (m.group(1) == null) {
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));
  } else if (at.isBefore(now.subtract(const Duration(days: 1)))) {
    at = DateTime(now.year + 1, month, day, hour, minute);
  }
  return at;
}

/// The `/usage` text → a [RateLimit] (null when the percentages are absent).
RateLimit? parseUsageText(String text, DateTime now) {
  ({double used, DateTime? resets})? line(String label) {
    final m = RegExp(
      '$label[^:\\n]*:\\s*(\\d+(?:\\.\\d+)?)%\\s*used(?:\\s*·\\s*resets\\s+([^\\n(]+?))?\\s*(?:\\([^)\\n]*\\))?\\s*\$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    return (
      used: double.parse(m.group(1)!) / 100,
      resets: m.group(2) == null ? null : parseUsageReset(m.group(2)!, now),
    );
  }

  final five = line('Current session');
  final week = line(r'Current week \(all models\)');
  if (five == null && week == null) return null;
  int? epoch(DateTime? d) =>
      d == null ? null : d.millisecondsSinceEpoch ~/ 1000;
  final rejected = (five?.used ?? 0) >= 1 || (week?.used ?? 0) >= 1;
  final json = {
    'type': 'rate_limit_event',
    'rate_limit_info': {
      'status': rejected ? 'rejected' : 'allowed',
      'rateLimitType': (week?.used ?? 0) >= 1 ? 'seven_day' : 'five_hour',
      'resetsAt': epoch((week?.used ?? 0) >= 1 ? week?.resets : five?.resets),
      'isUsingOverage': false,
      'unifiedWindows': {
        if (five != null)
          'five_hour': {
            'utilization': five.used,
            'resetsAt': epoch(five.resets),
          },
        if (week != null)
          'seven_day': {
            'utilization': week.used,
            'resetsAt': epoch(week.resets),
          },
      },
    },
  };
  final e = ClaudeEvent.fromJson(json);
  return e is RateLimit ? e : null;
}

/// Runs `claude -p "/usage"` and returns its text (null on any failure).
typedef UsageRunner = Future<String?> Function();

Future<String?> _runUsage(String executable) async {
  try {
    final r = await Process.run(executable, [
      '-p',
      '/usage',
      '--output-format',
      'json',
      '--no-session-persistence',
    ]).timeout(const Duration(seconds: 40));
    if (r.exitCode != 0) return null;
    final j = jsonDecode('${r.stdout}');
    return j is Map && j['result'] is String ? j['result'] as String : null;
  } catch (e) {
    debugPrint('uso do plano: /usage falhou — $e');
    return null;
  }
}

final usageRunnerProvider = Provider<UsageRunner>((ref) {
  final exe = ref.watch(claudeExecutableProvider);
  return () => _runUsage(exe);
});

class UsagePoller {
  UsagePoller(this._ref);

  final Ref _ref;
  bool _running = false;

  /// Reads `/usage` and updates the footer. Safe to call often.
  Future<void> refresh({DateTime? now}) async {
    if (_running) return;
    _running = true;
    try {
      final text = await _ref.read(usageRunnerProvider)();
      if (text == null) return;
      final r = parseUsageText(text, now ?? DateTime.now());
      if (r == null) {
        debugPrint('uso do plano: formato do /usage não reconhecido');
        return;
      }
      await _ref.read(rateLimitProvider.notifier).record(r);
    } finally {
      _running = false;
    }
  }
}

final usagePollerProvider = Provider(UsagePoller.new);
