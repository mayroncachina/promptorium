import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_event.dart' show QuotaWindow;
import 'package:promptorium/core/providers/quota_source.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/board/orchestrator/quota_divert.dart';

import 'orchestrator_fixture.dart' show codexCatalog;

final _now = DateTime(2026, 11, 25, 15);
final _at18 = DateTime(2026, 11, 25, 18);
final _at1640 = DateTime(2026, 11, 25, 16, 40);

QuotaSnapshot _reading(
  String provider, {
  double? five,
  double? week,
  DateTime? resetsAt,
  DateTime? weekResetsAt,
  String? reached,
  bool? allowed,
}) => QuotaSnapshot(
  provider: provider,
  ordinaryUsageAllowed: allowed,
  main: QuotaBucket(
    id: provider,
    reached: reached,
    windows: [
      QuotaWindow(
        id: 'primary',
        label: '5h',
        usedPercent: five,
        resetsAt: resetsAt,
        minutes: 300,
      ),
      if (week != null)
        QuotaWindow(
          id: 'secondary',
          label: 'semana',
          usedPercent: week,
          resetsAt: weekResetsAt,
          minutes: 10080,
        ),
    ],
  ),
);

OrchestratorPrefs _prefs({
  bool quota = true,
  int? above,
  Map<String, String> extra = const {},
}) => OrchestratorPrefs({
  ...codexCatalog(),
  AppSettingKeys.orchestratorDivertOnQuota: quota ? '1' : '0',
  if (above != null) ...{
    AppSettingKeys.orchestratorDivertAbove: '1',
    AppSettingKeys.orchestratorDivertAbovePercent: '$above',
  },
  ...extra,
});

void main() {
  const plan = StepRule('opus', 'high');
  const reserve = StepRule('gpt-6.2-sol', 'high', provider: 'codex');
  final claudeHit = QuotaHit(
    provider: 'claude',
    at: _now,
    minutes: 300,
    resetsAt: _at18,
  );

  DivertDecision decide(
    OrchestratorPrefs prefs, {
    StepRule? reserveRule = reserve,
    Map<String, QuotaSnapshot?> readings = const {},
    Map<String, QuotaHit?> hits = const {},
    String? blocked,
    DateTime? now,
  }) => divertFor(
    plan: plan,
    reserve: reserveRule,
    prefs: prefs,
    now: now ?? _now,
    readings: readings,
    hits: hits,
    reserveBlocked: blocked,
  );

  test('everything off (the default) is the plan, whatever the quotas say', () {
    final d = decide(
      const OrchestratorPrefs({}),
      readings: {
        'claude': _reading('claude', five: 100, reached: 'five_hour'),
        'codex': _reading('codex', five: 5),
      },
      hits: {'claude': claudeHit},
    );
    expect(d.rule, plan);
    expect(d.diverted, isFalse);
    expect(d.waits, isFalse);
  });

  test('R5: the quota ended → the reserve of the kind, with the why', () {
    final d = decide(_prefs(), hits: {'claude': claudeHit});
    expect(d.rule, reserve);
    expect(d.reason, DivertReason.quota);
    expect(d.until, _at18);
    expect(
      d.why('claude', now: _now),
      'Cota do Claude esgotada (janela de 5 h, renova às 18:00)',
    );
    // By the last reading too (SPEC-097): reached, 100% or blocked.
    for (final r in [
      _reading('claude', five: 92, reached: 'five_hour', resetsAt: _at18),
      _reading('claude', five: 100, resetsAt: _at18),
      _reading('claude', five: 92, allowed: false, resetsAt: _at18),
    ]) {
      expect(
        decide(_prefs(), readings: {'claude': r}).reason,
        DivertReason.quota,
      );
    }
    // A weekly limit holds until the week renews, not the 5 hours.
    final week = decide(
      _prefs(),
      readings: {
        'claude': _reading(
          'claude',
          five: 10,
          resetsAt: _now.subtract(const Duration(minutes: 1)),
          week: 99,
          weekResetsAt: DateTime(2026, 11, 27, 9),
          reached: 'seven_day',
        ),
      },
    );
    expect(
      week.why('claude', now: _now),
      'Cota do Claude esgotada (semana, renova em 27/11 às 09:00)',
    );
  });

  test('R2, R8: without a reserve, or with the other provider unavailable, '
      'the step waits and says why', () {
    final none = decide(
      _prefs(extra: {AppSettingKeys.orchestratorFallback('altoRisco'): 'none'}),
      reserveRule: null,
      hits: {'claude': claudeHit},
    );
    expect(none.waits, isTrue);
    expect(
      SpecQuotaWait(step: 'R4', blocks: none.blocks).detail(now: _now),
      'Claude renova às 18:00 · Codex sem reserva para este tipo de etapa',
    );
    final off = decide(
      _prefs(),
      hits: {'claude': claudeHit},
      blocked: 'login pendente',
    );
    expect(off.waits, isTrue);
    expect(off.blocks.last.text(now: _now), 'Codex login pendente');
    // Preventive: without a reserve it just goes on the plan.
    final prev = decide(
      _prefs(above: 90),
      reserveRule: null,
      readings: {'claude': _reading('claude', five: 93, resetsAt: _at18)},
    );
    expect(prev.rule, plan);
  });

  test('R8: both without quota wait, with the first renewal known', () {
    final d = decide(
      _prefs(),
      hits: {'claude': claudeHit},
      readings: {
        'codex': _reading(
          'codex',
          five: 100,
          reached: 'rate_limit_reached',
          resetsAt: _at1640,
        ),
      },
    );
    expect(d.waits, isTrue);
    expect(d.rule, isNull);
    final wait = SpecQuotaWait(step: 'R5', blocks: d.blocks);
    expect(wait.title, 'Sem cota nos dois provedores');
    expect(
      wait.detail(now: _now),
      'Claude renova às 18:00 · Codex renova às 16:40',
    );
    expect(wait.firstRenewal, _at1640);
    final again = SpecQuotaWait.decode(wait.withResume(_at1640).encode())!;
    expect(again.resumeAt!.toLocal(), _at1640);
    expect(again.detail(now: _now), wait.detail(now: _now));
  });

  test('R6: the preventive diversion needs a reading at or above the limit '
      'and a better provider', () {
    QuotaSnapshot c(double five) =>
        _reading('claude', five: five, resetsAt: _at18);
    final p = _prefs(quota: false, above: 90);
    final d = decide(p, readings: {'claude': c(93)});
    expect(d.rule, reserve);
    expect(d.reason, DivertReason.threshold);
    expect(d.why('claude'), 'Claude · janela de 5 h em 93% ≥ 90%');
    expect(d.until, _at18);
    expect(decide(p, readings: {'claude': c(89)}).rule, plan);
    // No reading = no diversion.
    expect(decide(p).rule, plan);
    expect(decide(p, readings: {'claude': _reading('claude')}).rule, plan);
    // A window that renewed says nothing.
    expect(decide(p, readings: {'claude': c(93)}, now: _at18).rule, plan);
    // The other one is above the limit too, without quota or blocked.
    for (final other in [
      _reading('codex', five: 95, resetsAt: _at1640),
      _reading('codex', five: 100, reached: 'x', resetsAt: _at1640),
    ]) {
      expect(decide(p, readings: {'claude': c(93), 'codex': other}).rule, plan);
    }
    expect(decide(p, readings: {'claude': c(93)}, blocked: 'x').rule, plan);
    // The week counts too.
    expect(
      decide(
        p,
        readings: {
          'claude': _reading('claude', five: 10, week: 96, resetsAt: _at18),
        },
      ).reason,
      DivertReason.threshold,
    );
  });

  test('R7: after the renewal the next step goes back to the plan, even with '
      'the old reading', () {
    final old = _reading(
      'claude',
      five: 100,
      reached: 'five_hour',
      resetsAt: _at18,
    );
    DivertDecision at(DateTime now) => decide(
      _prefs(),
      hits: {'claude': claudeHit},
      readings: {'claude': old},
      now: now,
    );
    expect(at(_at18.subtract(const Duration(minutes: 1))).rule, reserve);
    expect(at(_at18).rule, plan);
    expect(at(_at18.add(const Duration(hours: 1))).rule, plan);
    // Without a renewal time, half an hour.
    final hit = QuotaHit(provider: 'claude', at: _now);
    expect(hit.activeAt(_now.add(const Duration(minutes: 29))), isTrue);
    expect(hit.activeAt(_now.add(const Duration(minutes: 31))), isFalse);
    expect(QuotaHit.decode(hit.encode())!.resetsAt, isNull);
    expect(QuotaHit.decode('x'), isNull);
  });

  test('R14: the card and the screen reader say the step, where and until '
      'when', () {
    final d = SpecDivert(
      step: 'R4',
      from: 'claude',
      to: reserve,
      reason: DivertReason.quota,
      why: 'x',
      until: _at18,
    );
    expect(d.cardText(now: _now), 'desviada: cota do Claude · volta às 18:00');
    expect(
      d.spoken,
      'R4 desviada para o Codex: cota do Claude esgotada, renova às 18 horas',
    );
    final again = SpecDivert.decode(d.encode())!;
    expect(again.to, reserve);
    expect(again.spoken, d.spoken);
    expect(quotaSpokenClock(_at1640), 'às 16 horas e 40 minutos');
  });
}
