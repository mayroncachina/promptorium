import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/usage_tracker.dart';
import '../../data/providers.dart';
import 'usage_ledger.dart';

/// The ruler of the plan quota (SPEC-081 R3): how much a window goes up for
/// each dollar of estimated cost of the turns of the app. The quota of the
/// plan is measured by the cost of the calls, so the CLI's estimate works as
/// a weight and never shows as a price.

/// Divisions kept by window (the median of the last ones is the ruler).
const rulerKeep = 20;

/// Below this many divisions there is no ruler yet.
const rulerMinDivisions = 3;

/// One reading of a window: use (0–1) and when it resets.
typedef WindowReading = ({double used, DateTime? resetsAt});

/// Whether two readings are of the same window (the `/usage` text rounds
/// the reset time, the event has seconds: half an hour of tolerance).
bool sameQuotaWindow(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == b;
  return a.difference(b).abs() < const Duration(minutes: 30);
}

/// The median of the last [rulerKeep] divisions; null below
/// [rulerMinDivisions].
double? quotaRulerMedian(List<double> divisions) {
  final valid = [
    for (final d in divisions)
      if (d > 0 && d.isFinite) d,
  ];
  if (valid.length < rulerMinDivisions) return null;
  final last = valid.length > rulerKeep
      ? valid.sublist(valid.length - rulerKeep)
      : valid;
  final sorted = [...last]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// The learning of one window. Pure: [onReading] and [addCost] return a new
/// track.
///
/// The anchor is the last reading where the use went up (or the window
/// renewed); the cost of the turns recorded since then piles up until the
/// next rise, which divided by it is one division. A rise without any cost
/// (the person used Claude outside the app) only moves the anchor.
@immutable
class RulerTrack {
  const RulerTrack({this.anchor, this.cost = 0, this.divisions = const []});

  final WindowReading? anchor;

  /// Cost of the turns recorded since [anchor].
  final double cost;
  final List<double> divisions;

  double? get ruler => quotaRulerMedian(divisions);

  RulerTrack addCost(double usd) => usd <= 0
      ? this
      : RulerTrack(anchor: anchor, cost: cost + usd, divisions: divisions);

  RulerTrack onReading(WindowReading r) {
    final a = anchor;
    if (a == null || !sameQuotaWindow(a.resetsAt, r.resetsAt)) {
      // First reading or a window that renewed: start again.
      return RulerTrack(anchor: r, divisions: divisions);
    }
    final rise = r.used - a.used;
    if (rise < 0) return RulerTrack(anchor: r, divisions: divisions);
    if (rise == 0) return this;
    if (cost <= 0) return RulerTrack(anchor: r, divisions: divisions);
    final next = [...divisions, rise / cost];
    return RulerTrack(
      anchor: r,
      divisions: next.length > rulerKeep
          ? next.sublist(next.length - rulerKeep)
          : next,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RulerTrack &&
      other.anchor == anchor &&
      other.cost == cost &&
      listEquals(other.divisions, divisions);

  @override
  int get hashCode => Object.hash(anchor, cost, Object.hashAll(divisions));
}

/// The two windows of the plan.
@immutable
class QuotaRuler {
  const QuotaRuler({
    this.fiveHour = const RulerTrack(),
    this.sevenDay = const RulerTrack(),
  });

  final RulerTrack fiveHour;
  final RulerTrack sevenDay;

  /// Use of the 5-hour window (0–1) per dollar; null = no ruler yet.
  double? get fiveHourRuler => fiveHour.ruler;

  /// Use of the week (0–1) per dollar; null = no ruler yet.
  double? get sevenDayRuler => sevenDay.ruler;

  bool get ready => fiveHourRuler != null || sevenDayRuler != null;

  /// Weight of [costUsd] in each window by the ruler of now (R4).
  ({double? fiveHour, double? week}) weigh(double costUsd) => (
    fiveHour: fiveHourRuler == null ? null : costUsd * fiveHourRuler!,
    week: sevenDayRuler == null ? null : costUsd * sevenDayRuler!,
  );
}

List<double> _decode(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    return [
      for (final v in jsonDecode(raw) as List)
        if (v is num) v.toDouble(),
    ];
  } catch (_) {
    return const [];
  }
}

/// Fed by every reading of the quota ([rateLimitProvider]: the
/// `rate_limit_event`s and `/usage`) and by the cost of each turn recorded
/// ([UsageLedger]). The divisions go to `app_settings`; when a window gets
/// its first ruler, the entries recorded without weight receive it (R4).
class QuotaRulerController extends Notifier<QuotaRuler> {
  @override
  QuotaRuler build() {
    ref.listen(rateLimitProvider, (_, r) {
      if (r == null) return;
      onReading(
        fiveHour: r.fiveHourUtilization == null
            ? null
            : (used: r.fiveHourUtilization!, resetsAt: r.fiveHourResetsAt),
        sevenDay: r.sevenDayUtilization == null
            ? null
            : (used: r.sevenDayUtilization!, resetsAt: r.sevenDayResetsAt),
      );
    });
    final settings = ref.read(appSettingsProvider);
    return QuotaRuler(
      fiveHour: RulerTrack(
        divisions: _decode(settings[AppSettingKeys.quotaRulerFiveHour]),
      ),
      sevenDay: RulerTrack(
        divisions: _decode(settings[AppSettingKeys.quotaRulerSevenDay]),
      ),
    );
  }

  /// The divisions stored in `app_settings` (the splash loads them after
  /// the provider may already exist). Keeps the anchors.
  void loadStored() {
    final settings = ref.read(appSettingsProvider);
    state = QuotaRuler(
      fiveHour: RulerTrack(
        anchor: state.fiveHour.anchor,
        cost: state.fiveHour.cost,
        divisions: _decode(settings[AppSettingKeys.quotaRulerFiveHour]),
      ),
      sevenDay: RulerTrack(
        anchor: state.sevenDay.anchor,
        cost: state.sevenDay.cost,
        divisions: _decode(settings[AppSettingKeys.quotaRulerSevenDay]),
      ),
    );
    // Entries recorded while there was no ruler (or the history of before)
    // get the weight now (R4).
    if (state.ready) ref.read(usageLedgerProvider).applyPendingWeights();
  }

  void addCost(double usd) {
    if (usd <= 0) return;
    state = QuotaRuler(
      fiveHour: state.fiveHour.addCost(usd),
      sevenDay: state.sevenDay.addCost(usd),
    );
  }

  void onReading({WindowReading? fiveHour, WindowReading? sevenDay}) {
    final before = state;
    final next = QuotaRuler(
      fiveHour: fiveHour == null
          ? before.fiveHour
          : before.fiveHour.onReading(fiveHour),
      sevenDay: sevenDay == null
          ? before.sevenDay
          : before.sevenDay.onReading(sevenDay),
    );
    if (next.fiveHour == before.fiveHour && next.sevenDay == before.sevenDay) {
      return;
    }
    state = next;
    final settings = ref.read(appSettingsProvider.notifier);
    if (!listEquals(next.fiveHour.divisions, before.fiveHour.divisions)) {
      settings.set(
        AppSettingKeys.quotaRulerFiveHour,
        jsonEncode(next.fiveHour.divisions),
      );
    }
    if (!listEquals(next.sevenDay.divisions, before.sevenDay.divisions)) {
      settings.set(
        AppSettingKeys.quotaRulerSevenDay,
        jsonEncode(next.sevenDay.divisions),
      );
    }
    final gotFive = before.fiveHourRuler == null && next.fiveHourRuler != null;
    final gotWeek = before.sevenDayRuler == null && next.sevenDayRuler != null;
    if (gotFive || gotWeek) {
      ref.read(usageLedgerProvider).applyPendingWeights();
    }
  }
}

final quotaRulerProvider = NotifierProvider<QuotaRulerController, QuotaRuler>(
  QuotaRulerController.new,
);
