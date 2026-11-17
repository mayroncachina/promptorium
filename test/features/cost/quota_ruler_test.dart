import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/cost/quota_ruler.dart';

import '../../helpers/test_db.dart';

// SPEC-081 R3, R4.
void main() {
  final resets = DateTime.utc(2026, 11, 17, 14);
  WindowReading at(double used, [DateTime? r]) =>
      (used: used, resetsAt: r ?? resets);

  group('quotaRulerMedian', () {
    test('below 3 divisions there is no ruler', () {
      expect(quotaRulerMedian(const []), isNull);
      expect(quotaRulerMedian(const [0.1, 0.2]), isNull);
      expect(quotaRulerMedian(const [0.1, 0.2, 0.3]), 0.2);
    });

    test('median of the last 20, even and odd', () {
      expect(quotaRulerMedian(const [0.1, 0.4, 0.2, 0.3]), closeTo(0.25, 1e-9));
      final many = [for (var i = 0; i < 25; i++) i < 5 ? 100.0 : 1.0];
      // The 5 old outliers fall out of the last 20.
      expect(quotaRulerMedian(many), 1.0);
    });

    test('ignores invalid divisions', () {
      expect(quotaRulerMedian(const [0, -1, 0.2, 0.2]), isNull);
      expect(quotaRulerMedian(const [0, 0.1, 0.2, 0.3]), 0.2);
    });
  });

  group('RulerTrack', () {
    test('divides the rise in the same window by the cost between', () {
      var t = const RulerTrack().onReading(at(0.10));
      t = t.addCost(0.5).addCost(0.5);
      t = t.onReading(at(0.12));
      expect(t.divisions.single, closeTo(0.02, 1e-9));
      expect(t.cost, 0);
      expect(t.anchor, at(0.12));
    });

    test('a reading without rise keeps the anchor and the cost piles up', () {
      var t = const RulerTrack().onReading(at(0.10)).addCost(1);
      t = t.onReading(at(0.10)).addCost(1);
      expect(t.anchor, at(0.10));
      expect(t.cost, 2);
      t = t.onReading(at(0.14));
      expect(t.divisions.single, closeTo(0.02, 1e-9));
    });

    test('a window that renews in the middle gives no division', () {
      var t = const RulerTrack().onReading(at(0.80)).addCost(2);
      final next = resets.add(const Duration(hours: 5));
      t = t.onReading(at(0.05, next));
      expect(t.divisions, isEmpty);
      expect(t.cost, 0);
      expect(t.anchor, at(0.05, next));
      // The /usage text rounds the reset: a few minutes is the same window.
      t = t
          .addCost(1)
          .onReading(at(0.07, next.add(const Duration(minutes: 1))));
      expect(t.divisions.single, closeTo(0.02, 1e-9));
    });

    test('a rise without any turn of the app (used outside) only moves the '
        'anchor', () {
      var t = const RulerTrack().onReading(at(0.10));
      t = t.onReading(at(0.20));
      expect(t.divisions, isEmpty);
      expect(t.anchor, at(0.20));
    });

    test('the median leaves out the contaminated intervals', () {
      var t = const RulerTrack().onReading(at(0));
      var used = 0.0;
      // Four clean intervals (0.02 / dollar) and one where the terminal
      // was used at the same time (0.30 / dollar).
      for (final rise in [0.02, 0.02, 0.30, 0.02, 0.02]) {
        used += rise;
        t = t.addCost(1).onReading(at(used));
      }
      expect(t.divisions, hasLength(5));
      expect(t.ruler, closeTo(0.02, 1e-9));
    });
  });

  group('QuotaRulerController', () {
    test('learns from the readings, stores the divisions and weighs the '
        'entries recorded without a ruler', () async {
      final db = memoryDatabase();
      final c = ProviderContainer(overrides: [databaseOverride(db)]);
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await db
          .into(db.workspaces)
          .insert(WorkspacesCompanion.insert(path: '/r', name: 'r'));
      final pending = await c
          .read(usageEntriesRepoProvider)
          .add(
            UsageEntriesCompanion.insert(
              workspaceId: Value(ws),
              source: UsageSource.etapa,
              at: DateTime(2026, 11, 17),
              costUsd: const Value(2),
            ),
          );
      final ruler = c.read(quotaRulerProvider.notifier);
      ruler.onReading(fiveHour: at(0.10), sevenDay: at(0.01));
      for (var i = 1; i <= 3; i++) {
        ruler.addCost(1);
        ruler.onReading(
          fiveHour: at(0.10 + i * 0.03),
          sevenDay: at(0.01 + i * 0.005),
        );
      }
      final state = c.read(quotaRulerProvider);
      expect(state.fiveHourRuler, closeTo(0.03, 1e-9));
      expect(state.sevenDayRuler, closeTo(0.005, 1e-9));
      final stored = c.read(appSettingsProvider);
      expect(
        jsonDecode(stored[AppSettingKeys.quotaRulerFiveHour]!) as List,
        hasLength(3),
      );
      expect(stored[AppSettingKeys.quotaRulerSevenDay], isNotNull);

      // R4: the entry without weight receives it once the ruler exists.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final row = await (db.select(
        db.usageEntries,
      )..where((e) => e.id.equals(pending))).getSingle();
      expect(row.fiveHourPct, closeTo(0.06, 1e-9));
      expect(row.weekPct, closeTo(0.01, 1e-9));

      // A new container reads the divisions back.
      final c2 = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(c2.dispose);
      await c2.read(appSettingsProvider.notifier).load();
      // An entry recorded without a ruler gets it when the stored one loads.
      final later = await c2
          .read(usageEntriesRepoProvider)
          .add(
            UsageEntriesCompanion.insert(
              workspaceId: Value(ws),
              source: UsageSource.vibe,
              at: DateTime(2026, 11, 17),
              costUsd: const Value(1),
            ),
          );
      c2.read(quotaRulerProvider.notifier).loadStored();
      expect(c2.read(quotaRulerProvider).fiveHourRuler, closeTo(0.03, 1e-9));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final weighed = await (db.select(
        db.usageEntries,
      )..where((e) => e.id.equals(later))).getSingle();
      expect(weighed.fiveHourPct, closeTo(0.03, 1e-9));
    });
  });
}
