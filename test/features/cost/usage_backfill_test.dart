import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/cost/usage_backfill.dart';

import '../../helpers/test_db.dart';

String resultJson(double cost, {int input = 100, int output = 10}) =>
    jsonEncode({
      'type': 'result',
      'subtype': 'success',
      'is_error': false,
      'total_cost_usd': cost,
      'usage': {'input_tokens': input, 'output_tokens': output},
    });

// SPEC-081 R5.
void main() {
  test('backfillTurns: one turn per result, cost by the difference, no '
      'turn without tokens', () {
    final t0 = DateTime(2026, 11, 10, 9);
    final turns = backfillTurns([
      (at: t0, json: resultJson(0.10)),
      (at: t0.add(const Duration(minutes: 5)), json: resultJson(0.25)),
      (
        at: t0.add(const Duration(minutes: 6)),
        json: resultJson(0.25, input: 0, output: 0),
      ),
      (at: t0.add(const Duration(minutes: 9)), json: '{inválido'),
      // A new process that started from zero.
      (at: t0.add(const Duration(minutes: 30)), json: resultJson(0.05)),
    ]);
    expect([for (final t in turns) t.at.minute], [0, 5, 30]);
    expect(turns[0].costUsd, closeTo(0.10, 1e-9));
    expect(turns[1].costUsd, closeTo(0.15, 1e-9));
    expect(turns[2].costUsd, closeTo(0.05, 1e-9));
  });

  test('rebuilds the sessions and conversations of before once, marked as '
      'estimated, and stops at the first live entry', () async {
    final db = memoryDatabase();
    final c = ProviderContainer(overrides: [databaseOverride(db)]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await db
        .into(db.workspaces)
        .insert(WorkspacesCompanion.insert(path: '/r', name: 'r'));
    final spec = await db
        .into(db.specs)
        .insert(
          SpecsCompanion.insert(
            workspaceId: ws,
            code: 'SPEC-071',
            title: 'Correções',
            path: 'x.md',
          ),
        );
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 's1',
            workspaceId: ws,
            worktreePath: '/r',
            branch: 'b',
            model: 'sonnet',
            specId: Value(spec),
            steps: const Value('R1'),
          ),
        );
    final conv = await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            workspaceId: ws,
            title: 'refino',
            model: 'opus',
            refineSpecCode: const Value('SPEC-071'),
          ),
        );
    final t0 = DateTime(2026, 11, 10, 9);
    var seq = 0;
    Future<void> sessionEvent(String type, String json, DateTime at) => db
        .into(db.sessionEvents)
        .insert(
          SessionEventsCompanion.insert(
            sessionId: 's1',
            seq: ++seq,
            type: type,
            json: json,
            createdAt: Value(at),
          ),
        );
    await sessionEvent('system/init', '{"type":"system"}', t0);
    await sessionEvent('result/success', resultJson(0.10), t0);
    await sessionEvent(
      'result/success',
      resultJson(0.30),
      t0.add(const Duration(hours: 1)),
    );
    // After the register started: already recorded live.
    final live = t0.add(const Duration(days: 2));
    await sessionEvent(
      'result/success',
      resultJson(0.50),
      live.add(const Duration(minutes: 1)),
    );
    await db
        .into(db.conversationEvents)
        .insert(
          ConversationEventsCompanion.insert(
            conversationId: conv,
            seq: 1,
            type: 'result/success',
            json: resultJson(0.04),
            createdAt: Value(t0.add(const Duration(hours: 2))),
          ),
        );
    await db
        .into(db.usageEntries)
        .insert(
          UsageEntriesCompanion.insert(
            workspaceId: Value(ws),
            specId: Value(spec),
            source: UsageSource.etapa,
            sessionId: const Value('s1'),
            at: live,
            tokensIn: const Value(1),
          ),
        );

    final written = await c.read(usageBackfillProvider).run();
    expect(written, 3);
    final rebuilt =
        await (db.select(db.usageEntries)
              ..where((e) => e.estimated.equals(true))
              ..orderBy([(e) => OrderingTerm.asc(e.at)]))
            .get();
    expect(
      [for (final e in rebuilt) (e.source, e.specId, e.step, e.at)],
      [
        (UsageSource.etapa, spec, 'R1', t0),
        (UsageSource.etapa, spec, 'R1', t0.add(const Duration(hours: 1))),
        (UsageSource.refino, spec, null, t0.add(const Duration(hours: 2))),
      ],
    );
    expect(rebuilt[1].costUsd, closeTo(0.20, 1e-9));
    expect(rebuilt.every((e) => e.weekPct == null), isTrue);
    expect(c.read(appSettingsProvider)[AppSettingKeys.usageBackfillDone], '1');

    // Once only.
    expect(await c.read(usageBackfillProvider).run(), 0);
    expect(await db.select(db.usageEntries).get(), hasLength(4));
  });
}
