import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/usage_tracker.dart';

/// The plan quota with a forecast at the current pace (SPEC-076 R7).

/// One reading of the 5-hour window.
typedef QuotaSample = ({DateTime at, double used, DateTime? resetsAt});

/// Readings of the 5-hour window, in memory, fed by every
/// `rate_limit_event` and `/usage` ([rateLimitProvider]). Only the last
/// [keep] are kept.
class QuotaSamples extends Notifier<List<QuotaSample>> {
  static const keep = 40;

  @override
  List<QuotaSample> build() {
    ref.listen(rateLimitProvider, (_, r) {
      final used = r?.fiveHourUtilization;
      if (used != null) add(used, r?.fiveHourResetsAt);
    });
    final r = ref.read(rateLimitProvider);
    final used = r?.fiveHourUtilization;
    return used == null
        ? const []
        : [(at: DateTime.now(), used: used, resetsAt: r?.fiveHourResetsAt)];
  }

  void add(double used, DateTime? resetsAt, {DateTime? at}) {
    final next = [
      ...state,
      (at: at ?? DateTime.now(), used: used, resetsAt: resetsAt),
    ];
    state = next.length > keep ? next.sublist(next.length - keep) : next;
  }
}

final quotaSamplesProvider = NotifierProvider<QuotaSamples, List<QuotaSample>>(
  QuotaSamples.new,
);

/// What the quota card says about the 5-hour window.
@immutable
class QuotaForecast {
  const QuotaForecast({required this.used, required this.text, this.endsAt});

  /// 0–1 (null = no reading yet).
  final double? used;

  /// "neste ritmo, acaba em 1 h 40", "dura até renovar às 14:00",
  /// "sem ritmo ainda".
  final String text;

  /// When it runs out at this pace (null = it lasts until the reset).
  final DateTime? endsAt;
}

/// `1 h 40`, `25 min`, `menos de 1 min`.
String quotaDuration(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return 'menos de 1 min';
  if (m < 60) return '$m min';
  final rest = m % 60;
  return rest == 0
      ? '${m ~/ 60} h'
      : '${m ~/ 60} h ${rest.toString().padLeft(2, '0')}';
}

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

const _weekdays = ['seg.', 'ter.', 'qua.', 'qui.', 'sex.', 'sáb.', 'dom.'];

/// `renova seg. 09:00` (the weekly window); empty without a reset time.
String weekResetLabel(DateTime? resetsAt) => resetsAt == null
    ? ''
    : 'renova ${_weekdays[resetsAt.weekday - 1]} ${_hhmm(resetsAt)}';

/// The pace of the readings of the current window (of the last [span]) and
/// what it means (R7). Pure.
QuotaForecast quotaForecast(
  List<QuotaSample> samples, {
  required DateTime now,
  Duration span = const Duration(hours: 1),
}) {
  if (samples.isEmpty) {
    return const QuotaForecast(used: null, text: 'sem leitura da cota');
  }
  final last = samples.last;
  final resets = last.resetsAt;
  if (resets != null && !resets.isAfter(now)) {
    return const QuotaForecast(used: 0, text: 'janela renovada');
  }
  // Only the readings of this window (a reset starts a new pace).
  final window = [
    for (final s in samples)
      if (s.resetsAt == resets && now.difference(s.at) <= span) s,
  ];
  final first = window.isEmpty ? last : window.first;
  final minutes = last.at.difference(first.at).inSeconds / 60;
  final rise = last.used - first.used;
  if (window.length < 2 || minutes < 1 || rise <= 0) {
    return QuotaForecast(
      used: last.used,
      text: resets == null
          ? 'sem ritmo ainda'
          : 'sem ritmo ainda · renova às ${_hhmm(resets)}',
    );
  }
  final perMinute = rise / minutes;
  final left = (1 - last.used).clamp(0, 1) / perMinute;
  final endsAt = now.add(Duration(seconds: (left * 60).round()));
  if (resets != null && !endsAt.isBefore(resets)) {
    return QuotaForecast(
      used: last.used,
      text: 'dura até renovar às ${_hhmm(resets)}',
    );
  }
  return QuotaForecast(
    used: last.used,
    text: 'neste ritmo, acaba em ${quotaDuration(endsAt.difference(now))}',
    endsAt: endsAt,
  );
}

/// The weight of each session in the 5-hour window (R7): its part in the
/// cost of the sessions of the window times the use of the window. [costs]
/// = cost of each session that ran in the window.
Map<String, double> sessionQuotaWeights(
  Map<String, double> costs,
  double? used,
) {
  final total = costs.values.fold(0.0, (a, c) => a + c);
  if (used == null || total <= 0) return const {};
  return {for (final e in costs.entries) e.key: e.value / total * used};
}
