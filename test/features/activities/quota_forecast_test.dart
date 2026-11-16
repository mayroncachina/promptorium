import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/activities/quota_forecast.dart';

void main() {
  final resets = DateTime(2026, 11, 15, 14);
  QuotaSample at(int h, int m, double used) =>
      (at: DateTime(2026, 11, 15, h, m), used: used, resetsAt: resets);

  test('the pace of the last readings: it runs out before the reset', () {
    final f = quotaForecast([
      at(10, 0, .50),
      at(10, 30, .62),
    ], now: DateTime(2026, 11, 15, 10, 30));
    // 12% in 30 min → 38% left in ~1 h 35.
    expect(f.used, .62);
    expect(f.text, 'neste ritmo, acaba em 1 h 35');
    expect(f.endsAt, isNotNull);
  });

  test('a slow pace lasts until the reset', () {
    final f = quotaForecast([
      at(10, 0, .20),
      at(10, 30, .21),
    ], now: DateTime(2026, 11, 15, 10, 30));
    expect(f.text, 'dura até renovar às 14:00');
    expect(f.endsAt, isNull);
  });

  test('without two readings, or without a rise, there is no pace', () {
    expect(
      quotaForecast([at(10, 0, .3)], now: DateTime(2026, 11, 15, 10)).text,
      'sem ritmo ainda · renova às 14:00',
    );
    expect(
      quotaForecast([
        at(10, 0, .3),
        at(10, 20, .3),
      ], now: DateTime(2026, 11, 15, 10, 20)).text,
      'sem ritmo ainda · renova às 14:00',
    );
    expect(
      quotaForecast(const [], now: DateTime(2026)).text,
      'sem leitura da cota',
    );
  });

  test('a reading of an earlier window does not count; a window already '
      'reset says so', () {
    final old = (
      at: DateTime(2026, 11, 15, 8),
      used: .9,
      resetsAt: DateTime(2026, 11, 15, 9),
    );
    final f = quotaForecast([
      old,
      at(10, 0, .1),
    ], now: DateTime(2026, 11, 15, 10));
    expect(f.text, startsWith('sem ritmo ainda'));
    expect(
      quotaForecast([old], now: DateTime(2026, 11, 15, 10)).text,
      'janela renovada',
    );
  });

  test('durations, the week and the weight of each session', () {
    expect(quotaDuration(const Duration(minutes: 25)), '25 min');
    expect(quotaDuration(const Duration(minutes: 100)), '1 h 40');
    expect(quotaDuration(const Duration(minutes: 120)), '2 h');
    // 2026-11-16 is a Monday.
    expect(weekResetLabel(DateTime(2026, 11, 16, 9)), 'renova seg. 09:00');
    final w = sessionQuotaWeights({'a': 3, 'b': 1}, .4);
    expect(w['a'], closeTo(.3, 1e-9));
    expect(w['b'], closeTo(.1, 1e-9));
    expect(sessionQuotaWeights({'a': 1}, null), isEmpty);
  });
}
