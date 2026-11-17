import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_event.dart';
import '../../data/providers.dart';
import 'usage_ledger.dart';

/// The history of before (SPEC-081 R5): the sessions and conversations
/// recorded before the register only have their totals. Their `result`
/// events become entries, with the time of each turn, marked as estimated
/// (weighed by the ruler of today). Runs once, in the background, after the
/// database opens. The `claude -p` of before left nothing and stay out.

/// One `result` event of a session or conversation.
typedef StoredResult = ({DateTime at, String json});

/// One turn rebuilt from the events.
typedef BackfillTurn = ({DateTime at, Usage usage, double costUsd, Result e});

/// The turns of the `result` events of one session or conversation, in
/// order (R5). Pure. The cost of a turn is the difference of the cumulative
/// `total_cost_usd` ([turnCost]); turns without tokens give nothing.
List<BackfillTurn> backfillTurns(List<StoredResult> results) {
  final out = <BackfillTurn>[];
  double? seen;
  for (final r in results) {
    final Object? raw;
    try {
      raw = jsonDecode(r.json);
    } on FormatException {
      continue;
    }
    if (raw is! Map<String, dynamic>) continue;
    final e = ClaudeEvent.fromJson(raw);
    if (e is! Result) continue;
    final cost = turnCost(e.totalCostUsd, lastSeen: seen);
    seen = e.totalCostUsd;
    if (e.usage.total <= 0) continue;
    out.add((at: r.at, usage: e.usage, costUsd: cost, e: e));
  }
  return out;
}

class UsageBackfill {
  UsageBackfill(this._ref);

  final Ref _ref;
  Future<int>? _running;

  /// Rebuilds the history once (the mark is in `app_settings`); returns how
  /// many entries it wrote.
  Future<int> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<int> _run() async {
    final settings = _ref.read(appSettingsProvider.notifier);
    if (settings.get(AppSettingKeys.usageBackfillDone) == '1') return 0;
    final db = _ref.read(appDatabaseProvider);
    final repo = _ref.read(usageEntriesRepoProvider);
    // Turns from the first live entry on are already in the register.
    final cutoff = await repo.firstLiveAt() ?? DateTime.now();
    final entries = <UsageEntriesCompanion>[];

    Expression<bool> isResult(GeneratedColumn<String> type) =>
        type.equals('result') | type.like('result/%');

    for (final s in await db.select(db.sessions).get()) {
      final rows =
          await (db.select(db.sessionEvents)
                ..where(
                  (e) =>
                      e.sessionId.equals(s.id) &
                      isResult(e.type) &
                      e.createdAt.isSmallerThanValue(cutoff),
                )
                ..orderBy([(e) => OrderingTerm.asc(e.seq)]))
              .get();
      if (rows.isEmpty) continue;
      final o = sessionUsageOrigin(s);
      for (final t in backfillTurns([
        for (final r in rows) (at: r.createdAt, json: r.json),
      ])) {
        entries.add(
          _entry(
            t,
            workspaceId: s.workspaceId,
            specId: o.specId,
            source: o.source,
            step: o.step,
            sessionId: s.id,
            model: resultModel(t.e, s.model),
          ),
        );
      }
    }

    final specs = _ref.read(specsRepoProvider);
    for (final c in await db.select(db.conversations).get()) {
      final rows =
          await (db.select(db.conversationEvents)
                ..where(
                  (e) =>
                      e.conversationId.equals(c.id) &
                      isResult(e.type) &
                      e.createdAt.isSmallerThanValue(cutoff),
                )
                ..orderBy([(e) => OrderingTerm.asc(e.seq)]))
              .get();
      if (rows.isEmpty) continue;
      final refine = c.refineSpecCode == null || c.specId != null
          ? null
          : await specs.getByCode(c.workspaceId, c.refineSpecCode!);
      final o = conversationUsageOrigin(c, refineSpecId: refine?.id);
      for (final t in backfillTurns([
        for (final r in rows) (at: r.createdAt, json: r.json),
      ])) {
        entries.add(
          _entry(
            t,
            workspaceId: c.workspaceId,
            specId: o.specId,
            source: o.source,
            conversationId: c.id,
            model: resultModel(t.e, c.model),
          ),
        );
      }
    }

    if (entries.isNotEmpty) await repo.addAll(entries);
    await settings.set(AppSettingKeys.usageBackfillDone, '1');
    await _ref.read(usageLedgerProvider).applyPendingWeights();
    return entries.length;
  }

  UsageEntriesCompanion _entry(
    BackfillTurn t, {
    required int workspaceId,
    required int? specId,
    required UsageSource source,
    String? step,
    String? sessionId,
    int? conversationId,
    String? model,
  }) => UsageEntriesCompanion.insert(
    workspaceId: Value(workspaceId),
    specId: Value(specId),
    source: source,
    step: Value(step),
    sessionId: Value(sessionId),
    conversationId: Value(conversationId),
    model: Value(model),
    at: t.at,
    tokensIn: Value(t.usage.inputTokens),
    tokensCacheWrite: Value(t.usage.cacheCreationInputTokens),
    tokensCacheRead: Value(t.usage.cacheReadInputTokens),
    tokensOut: Value(t.usage.outputTokens),
    costUsd: Value(t.costUsd),
    estimated: const Value(true),
  );
}

final usageBackfillProvider = Provider(UsageBackfill.new);
