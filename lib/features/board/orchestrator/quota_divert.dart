import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/claude/usage_tracker.dart' show planWindowExpired;
import '../../../core/providers/agent_event.dart' show QuotaWindow;
import '../../../core/providers/quota_source.dart';
import 'orchestrator_rules.dart';

/// Desvio por cota (SPEC-109 R5–R8): what the next step does when the plan
/// quota of its provider ended or passed the limit of the person. Pure: the
/// readings are the ones of the SPEC-097 ([QuotaSnapshot]).

/// `18:00`; on another day, `27/11 às 09:00`.
String quotaClock(DateTime at, {DateTime? now}) {
  final t = at.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final hour = '${two(t.hour)}:${two(t.minute)}';
  if (t.year == n.year && t.month == n.month && t.day == n.day) return hour;
  return '${two(t.day)}/${two(t.month)} às $hour';
}

/// `às 18:00`, or `em 27/11 às 09:00`.
String quotaClockWords(DateTime at, {DateTime? now}) {
  final c = quotaClock(at, now: now);
  return c.contains('/') ? 'em $c' : 'às $c';
}

/// `às 18 horas`, `às 18 horas e 30 minutos` (screen reader, R14).
String quotaSpokenClock(DateTime at) {
  final t = at.toLocal();
  final hours = t.hour == 1 ? '1 hora' : '${t.hour} horas';
  return 'às $hours${t.minute == 0 ? '' : ' e ${t.minute} minutos'}';
}

/// `janela de 5 h`, `semana`.
String quotaWindowName(int? minutes) => switch (minutes) {
  null => 'janela do plano',
  10080 => 'semana',
  final m when m % 60 == 0 => 'janela de ${m ~/ 60} h',
  final m => 'janela de $m min',
};

/// A limit a provider reached during a step (R5): the rejected
/// `rate_limit_event` of the Claude Code, or the limit of the Codex.
@immutable
class QuotaHit {
  const QuotaHit({
    required this.provider,
    required this.at,
    this.minutes,
    this.resetsAt,
  });

  final String provider;
  final DateTime at;

  /// Length of the window that ended (300 = 5 h).
  final int? minutes;
  final DateTime? resetsAt;

  /// How long a limit without a renewal time holds.
  static const unknownHold = Duration(minutes: 30);

  /// R7: the limit holds until its window renews.
  bool activeAt(DateTime now) => (resetsAt ?? at.add(unknownHold)).isAfter(now);

  String encode() => jsonEncode({
    'provider': provider,
    'at': at.toUtc().toIso8601String(),
    'minutes': ?minutes,
    'resets_at': ?resetsAt?.toUtc().toIso8601String(),
  });

  static QuotaHit? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return QuotaHit(
        provider: '${j['provider']}',
        at: DateTime.parse('${j['at']}'),
        minutes: j['minutes'] as int?,
        resetsAt: DateTime.tryParse('${j['resets_at']}'),
      );
    } catch (_) {
      return null;
    }
  }
}

/// The quota of a provider that ended: which window and when it renews.
@immutable
class QuotaOut {
  const QuotaOut(this.provider, {this.minutes, this.resetsAt});

  final String provider;
  final int? minutes;
  final DateTime? resetsAt;

  /// `Cota do Claude esgotada (janela de 5 h, renova às 18:00)`.
  String text({DateTime? now}) =>
      'Cota do ${planProviderLabel(provider)} esgotada '
      '(${quotaWindowName(minutes)}'
      '${resetsAt == null ? '' : ', renova ${quotaClockWords(resetsAt!, now: now)}'})';

  @override
  bool operator ==(Object other) =>
      other is QuotaOut &&
      other.provider == provider &&
      other.minutes == minutes &&
      other.resetsAt == resetsAt;

  @override
  int get hashCode => Object.hash(provider, minutes, resetsAt);

  @override
  String toString() => 'QuotaOut($provider, $minutes, $resetsAt)';
}

/// The quota of [provider] that ended at [now], or null: the [hit] of a step
/// that has not renewed (R7), else the limit of the last reading whose
/// window has not renewed. Without a reading it did not end.
QuotaOut? quotaOut(
  String provider,
  QuotaSnapshot? reading,
  DateTime now, {
  QuotaHit? hit,
}) {
  if (hit != null && hit.provider == provider && hit.activeAt(now)) {
    return QuotaOut(provider, minutes: hit.minutes, resetsAt: hit.resetsAt);
  }
  final limit = reading?.limit(now);
  if (limit == null) return null;
  // A weekly limit is not renewed by the 5-hour window.
  final w = (limit.kind ?? '').startsWith('seven_day')
      ? reading!.window(10080) ?? limit.window
      : limit.window;
  // R7: a limit said before its window renewed does not hold after it.
  if (planWindowExpired(w?.resetsAt, now)) return null;
  // The same limit of a hit that already renewed.
  if (hit != null &&
      hit.provider == provider &&
      hit.resetsAt != null &&
      w?.resetsAt != null &&
      !w!.resetsAt!.isAfter(hit.resetsAt!)) {
    return null;
  }
  return QuotaOut(provider, minutes: w?.minutes, resetsAt: w?.resetsAt);
}

/// The most used window of a reading, among the ones that did not renew
/// (R6); null = no reading of any use.
QuotaWindow? mostUsedWindow(QuotaSnapshot? reading, DateTime now) {
  QuotaWindow? best;
  for (final w in reading?.main.windows ?? const <QuotaWindow>[]) {
    if (w.usedPercent == null || planWindowExpired(w.resetsAt, now)) continue;
    if (best == null || w.usedPercent! > best.usedPercent!) best = w;
  }
  return best;
}

/// Why a step is not on the provider of its plan (`step_runs.diverted`).
enum DivertReason {
  quota('quota'),
  threshold('threshold'),
  secondOpinion('second_opinion');

  const DivertReason(this.stored);

  final String stored;

  static DivertReason? parse(String? v) =>
      values.where((r) => r.stored == v).firstOrNull;
}

/// Why a provider cannot take the step (R8).
@immutable
class QuotaBlock {
  const QuotaBlock(this.provider, {this.out, this.why});

  final String provider;

  /// Without quota; null = [why].
  final QuotaOut? out;

  /// `sem login`, `sem reserva`… when it is not the quota.
  final String? why;

  DateTime? get resetsAt => out?.resetsAt;

  /// `Claude renova às 18:00` / `Codex sem login`.
  String text({DateTime? now}) {
    final name = planProviderLabel(provider);
    if (out == null) return '$name ${why ?? 'indisponível'}';
    return resetsAt == null
        ? '$name sem cota, sem horário de renovação'
        : '$name renova ${quotaClockWords(resetsAt!, now: now)}';
  }

  /// [text] without the name of the provider (the badge says it).
  String detail({DateTime? now}) =>
      text(now: now).substring(planProviderLabel(provider).length + 1);

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'out': out != null,
    'minutes': ?out?.minutes,
    'resets_at': ?resetsAt?.toUtc().toIso8601String(),
    'why': ?why,
  };

  static QuotaBlock? fromJson(Object? j) {
    if (j is! Map) return null;
    final provider = '${j['provider']}';
    return QuotaBlock(
      provider,
      out: j['out'] == true
          ? QuotaOut(
              provider,
              minutes: j['minutes'] as int?,
              resetsAt: DateTime.tryParse('${j['resets_at']}'),
            )
          : null,
      why: j['why'] as String?,
    );
  }
}

/// What a step does now: run with [rule] (the plan, or the reserve and
/// [reason]), or wait for the person with [blocks] (R8).
@immutable
class DivertDecision {
  const DivertDecision.plan(StepRule this.rule)
    : reason = null,
      out = null,
      window = null,
      threshold = null,
      blocks = const [];

  const DivertDecision.quota(StepRule this.rule, QuotaOut this.out)
    : reason = DivertReason.quota,
      window = null,
      threshold = null,
      blocks = const [];

  const DivertDecision.threshold(
    StepRule this.rule,
    QuotaWindow this.window,
    int this.threshold,
  ) : reason = DivertReason.threshold,
      out = null,
      blocks = const [];

  const DivertDecision.wait(this.blocks)
    : rule = null,
      reason = null,
      out = null,
      window = null,
      threshold = null;

  /// Null = wait.
  final StepRule? rule;

  /// Null = the provider of the plan.
  final DivertReason? reason;

  /// The quota that ended ([DivertReason.quota]).
  final QuotaOut? out;

  /// The window above [threshold] ([DivertReason.threshold]).
  final QuotaWindow? window;
  final int? threshold;

  final List<QuotaBlock> blocks;

  bool get waits => rule == null;
  bool get diverted => rule != null && reason != null;

  /// When the diversion ends (R7): the renewal of the window.
  DateTime? get until => out?.resetsAt ?? window?.resetsAt;

  /// Why, for the timeline: `Cota do Claude esgotada (janela de 5 h, renova
  /// às 18:00)` or `Claude · janela de 5 h em 93% ≥ 90%`.
  String why(String from, {DateTime? now}) => switch (reason) {
    DivertReason.quota => out!.text(now: now),
    DivertReason.threshold =>
      '${planProviderLabel(from)} · ${quotaWindowName(window!.minutes)} em '
          '${window!.usedPercent!.round()}% ≥ $threshold%',
    _ => '',
  };
}

/// What the step planned with [plan] does at its boundary (R5–R8), or after
/// a limit in the middle of it ([hits] has it). [reserve] is the rule of its
/// kind on the other provider; [reserveBlocked], why that provider cannot
/// run. Everything off (the default) = the plan, always.
DivertDecision divertFor({
  required StepRule plan,
  required StepRule? reserve,
  required OrchestratorPrefs prefs,
  required DateTime now,
  Map<String, QuotaSnapshot?> readings = const {},
  Map<String, QuotaHit?> hits = const {},
  String? reserveBlocked,
}) {
  QuotaOut? ended(String p) => quotaOut(p, readings[p], now, hit: hits[p]);
  if (prefs.divertOnQuota) {
    if (ended(plan.provider) case final out?) {
      final own = QuotaBlock(plan.provider, out: out);
      final other = otherPlanProvider(plan.provider);
      if (reserve == null) {
        return DivertDecision.wait([
          own,
          QuotaBlock(other, why: 'sem reserva para este tipo de etapa'),
        ]);
      }
      if (reserveBlocked != null) {
        return DivertDecision.wait([
          own,
          QuotaBlock(reserve.provider, why: reserveBlocked),
        ]);
      }
      if (ended(reserve.provider) case final second?) {
        return DivertDecision.wait([
          own,
          QuotaBlock(reserve.provider, out: second),
        ]);
      }
      return DivertDecision.quota(reserve, out);
    }
  }
  if (prefs.divertAbovePercent case final limit?) {
    final w = mostUsedWindow(readings[plan.provider], now);
    if (w != null &&
        w.usedPercent! >= limit &&
        reserve != null &&
        reserveBlocked == null &&
        ended(reserve.provider) == null) {
      final other = mostUsedWindow(readings[reserve.provider], now);
      // Nothing to gain on a provider that is above the limit too.
      if (other == null || other.usedPercent! < limit) {
        return DivertDecision.threshold(reserve, w, limit);
      }
    }
  }
  return DivertDecision.plan(plan);
}

/// Where the current step of a spec was diverted to (R5, R7, R14), kept in
/// `app_settings` while it holds: the card and the steps show it.
@immutable
class SpecDivert {
  const SpecDivert({
    required this.step,
    required this.from,
    required this.to,
    required this.reason,
    required this.why,
    this.until,
  });

  final String step;

  /// Provider of the plan.
  final String from;
  final StepRule to;
  final DivertReason reason;

  /// [DivertDecision.why].
  final String why;
  final DateTime? until;

  /// `desviada: cota do Claude · volta às 18:00`.
  String cardText({DateTime? now}) {
    final name = planProviderLabel(from);
    final what = switch (reason) {
      DivertReason.quota => 'cota do $name',
      DivertReason.threshold => '$name perto do limite',
      DivertReason.secondOpinion => 'segunda opinião',
    };
    return 'desviada: $what'
        '${until == null ? '' : ' · volta ${quotaClockWords(until!, now: now)}'}';
  }

  /// `R4 desviada para o Codex: cota do Claude esgotada, renova às 18
  /// horas` (R14).
  String get spoken {
    final name = planProviderLabel(from);
    final what = switch (reason) {
      DivertReason.quota => 'cota do $name esgotada',
      DivertReason.threshold => 'cota do $name perto do limite',
      DivertReason.secondOpinion => 'segunda opinião no topo da escada',
    };
    return '$step desviada para o ${planProviderLabel(to.provider)}: $what'
        '${until == null ? '' : ', renova ${quotaSpokenClock(until!)}'}';
  }

  String encode() => jsonEncode({
    'step': step,
    'from': from,
    'to': to.encode(),
    'reason': reason.stored,
    'why': why,
    'until': ?until?.toUtc().toIso8601String(),
  });

  static SpecDivert? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final to = StepRule.decode('${j['to']}');
      final reason = DivertReason.parse('${j['reason']}');
      if (to == null || reason == null) return null;
      return SpecDivert(
        step: '${j['step']}',
        from: '${j['from']}',
        to: to,
        reason: reason,
        why: '${j['why']}',
        until: DateTime.tryParse('${j['until']}'),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A step that waits for quota (R8), kept in `app_settings`: the renewals,
/// and [resumeAt] once "Retomar quando renovar" was chosen (P5).
@immutable
class SpecQuotaWait {
  const SpecQuotaWait({
    required this.step,
    required this.blocks,
    this.resumeAt,
    this.sessionId,
  });

  final String step;
  final List<QuotaBlock> blocks;

  /// The session the quota cut (its attempt is undone before the step goes
  /// on); null = the step had not started.
  final String? sessionId;
  final DateTime? resumeAt;

  /// Both providers ran out of quota (else one is unavailable).
  bool get bothOut => blocks.length > 1 && blocks.every((b) => b.out != null);

  /// `Sem cota nos dois provedores`, or `Cota do Claude esgotada`.
  String get title => bothOut
      ? 'Sem cota nos dois provedores'
      : 'Cota do ${planProviderLabel(blocks.first.provider)} esgotada';

  /// `Claude renova às 18:00 · Codex renova às 16:40`.
  String detail({DateTime? now}) =>
      blocks.map((b) => b.text(now: now)).join(' · ');

  /// P5: the first renewal known.
  DateTime? get firstRenewal {
    DateTime? best;
    for (final b in blocks) {
      final at = b.resetsAt;
      if (at != null && (best == null || at.isBefore(best))) best = at;
    }
    return best;
  }

  SpecQuotaWait withResume(DateTime? at) => SpecQuotaWait(
    step: step,
    blocks: blocks,
    resumeAt: at,
    sessionId: sessionId,
  );

  String encode() => jsonEncode({
    'step': step,
    'blocks': [for (final b in blocks) b.toJson()],
    'resume_at': ?resumeAt?.toUtc().toIso8601String(),
    'session': ?sessionId,
  });

  static SpecQuotaWait? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final blocks = [
        for (final b in j['blocks'] as List) ?QuotaBlock.fromJson(b),
      ];
      if (blocks.isEmpty) return null;
      return SpecQuotaWait(
        step: '${j['step']}',
        blocks: blocks,
        resumeAt: DateTime.tryParse('${j['resume_at']}'),
        sessionId: j['session'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
