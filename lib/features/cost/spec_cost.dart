import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_event.dart' show RateLimit;
import '../../core/claude/usage_tracker.dart';
import '../../core/providers/provider_availability.dart';
import '../../data/providers.dart';
import '../activities/quota_forecast.dart';
import '../sessions/session_manager.dart';
import 'usage_ledger.dart' show entryHasCost;

/// What a spec cost (SPEC-081 R6–R12): the sum of the entries of every
/// origin, in weight of the plan quota (or dollars with an API key).

/// One sum of entries.
@immutable
class CostSlice {
  const CostSlice({
    this.turns = 0,
    this.week,
    this.fiveHour,
    this.tokens = 0,
    this.cacheRead = 0,
    this.costUsd = 0,
    this.units = 0,
    this.unpricedTurns = 0,
    this.unpricedTokens = 0,
    this.reasoning = 0,
  });

  final int turns;

  /// Weight in the week / 5-hour window (0–1, a window can go above 1);
  /// null when no entry has a weight yet.
  final double? week;
  final double? fiveHour;

  /// New input + cache write + output (P3).
  final int tokens;

  /// Cache read, shown apart (P3).
  final int cacheRead;
  final double costUsd;

  /// Sessions, conversations or rounds (the line of each origin).
  final int units;

  /// Turns of a provider without cost in US\$ (the Codex, SPEC-097 R9) and
  /// their tokens (part of [tokens]): "custo indisponível", never 0.
  final int unpricedTurns;
  final int unpricedTokens;

  /// Reasoning tokens (part of [tokens]).
  final int reasoning;

  /// Tokens of the turns with a cost.
  int get pricedTokens => tokens - unpricedTokens;

  bool get hasUnpriced => unpricedTurns > 0;

  /// Every turn is without cost: no US\$ and no weight to show.
  bool get onlyUnpriced => turns > 0 && unpricedTurns == turns;
}

double? _add(double? a, double? b) => b == null ? a : (a ?? 0) + b;

CostSlice _sum(Iterable<UsageEntry> entries, {int Function()? units}) {
  var turns = 0, tokens = 0, cacheRead = 0;
  var unpricedTurns = 0, unpricedTokens = 0, reasoning = 0;
  double? week, five;
  var cost = 0.0;
  for (final e in entries) {
    turns++;
    final t = e.tokensIn + e.tokensCacheWrite + e.tokensOut;
    tokens += t;
    cacheRead += e.tokensCacheRead;
    reasoning += e.tokensReasoning;
    // SPEC-097 R9, R10: no cost and no weight, never a measured 0.
    if (!entryHasCost(e)) {
      unpricedTurns++;
      unpricedTokens += t;
      continue;
    }
    week = _add(week, e.weekPct);
    five = _add(five, e.fiveHourPct);
    cost += e.costUsd;
  }
  return CostSlice(
    turns: turns,
    week: week,
    fiveHour: five,
    tokens: tokens,
    cacheRead: cacheRead,
    costUsd: cost,
    units: units?.call() ?? 0,
    unpricedTurns: unpricedTurns,
    unpricedTokens: unpricedTokens,
    reasoning: reasoning,
  );
}

/// Order of the origins in the detail (R8).
const usageSourceOrder = [
  UsageSource.etapa,
  UsageSource.revisor,
  UsageSource.ci,
  UsageSource.vibe,
  UsageSource.refino,
  UsageSource.orquestrador,
  UsageSource.verificacao,
  UsageSource.outros,
  UsageSource.livre,
];

/// "Etapas", "Corrigir CI"…
String usageSourceLabel(UsageSource s) => switch (s) {
  UsageSource.etapa => 'Etapas',
  UsageSource.revisor => 'Revisor',
  UsageSource.ci => 'Corrigir CI',
  UsageSource.vibe => 'VIBE',
  UsageSource.refino => 'Refinamento',
  UsageSource.orquestrador => 'Orquestrador',
  UsageSource.verificacao => 'Verificação',
  UsageSource.outros => 'Outros',
  UsageSource.livre => 'Sem spec',
};

/// "3 sessões", "2 rodadas", "1 conversa", "4 chamadas".
String usageUnitsLabel(UsageSource s, int n) {
  String plural(String one, String many) => '$n ${n == 1 ? one : many}';
  return switch (s) {
    UsageSource.etapa || UsageSource.livre => plural('sessão', 'sessões'),
    UsageSource.revisor || UsageSource.ci => plural('rodada', 'rodadas'),
    UsageSource.vibe || UsageSource.refino => plural('conversa', 'conversas'),
    _ => plural('chamada', 'chamadas'),
  };
}

/// Order of the steps: `R1`, `R2`… then `REV1`… then anything else.
int compareSteps(String a, String b) {
  (int, int, String) key(String s) {
    final m = RegExp(r'^(REV|R)(\d+)').firstMatch(s);
    if (m == null) return (2, 0, s);
    return (m.group(1) == 'R' ? 0 : 1, int.parse(m.group(2)!), s);
  }

  final ka = key(a), kb = key(b);
  if (ka.$1 != kb.$1) return ka.$1.compareTo(kb.$1);
  if (ka.$2 != kb.$2) return ka.$2.compareTo(kb.$2);
  return ka.$3.compareTo(kb.$3);
}

@immutable
class SpecCost {
  const SpecCost({
    required this.total,
    required this.bySource,
    required this.bySteps,
    required this.entries,
    this.thisWindow,
    this.estimated = false,
  });

  static const empty = SpecCost(
    total: CostSlice(),
    bySource: {},
    bySteps: [],
    entries: [],
  );

  final CostSlice total;

  /// In [usageSourceOrder].
  final Map<UsageSource, CostSlice> bySource;

  /// The steps of the sessions (`R1`, `REV1`), in [compareSteps] order.
  final List<(String, CostSlice)> bySteps;

  /// Newest first.
  final List<UsageEntry> entries;

  /// Weight in the current 5-hour window (R9); null when the spec spent
  /// nothing in it (or there is no ruler).
  final double? thisWindow;

  /// Some entry came from the history of before (R5).
  final bool estimated;

  bool get isEmpty => entries.isEmpty;

  /// Part of an origin in the spec: by weight, else by cost, else by tokens.
  double share(CostSlice s) {
    if (total.week != null && total.week! > 0 && s.week != null) {
      return s.week! / total.week!;
    }
    if (total.costUsd > 0) return s.costUsd / total.costUsd;
    return total.tokens > 0 ? s.tokens / total.tokens : 0;
  }
}

/// The cost of a spec from its entries (R8, R9). Pure. [windowStart] =
/// start of the current 5-hour window.
SpecCost specCostOf(List<UsageEntry> entries, {DateTime? windowStart}) {
  if (entries.isEmpty) return SpecCost.empty;
  final sorted = [...entries]..sort((a, b) => b.at.compareTo(a.at));
  final bySource = <UsageSource, CostSlice>{};
  for (final source in usageSourceOrder) {
    final mine = [
      for (final e in sorted)
        if (e.source == source) e,
    ];
    if (mine.isEmpty) continue;
    bySource[source] = _sum(
      mine,
      units: () => switch (source) {
        UsageSource.etapa || UsageSource.livre => {
          for (final e in mine) e.sessionId ?? 'e${e.id}',
        }.length,
        UsageSource.vibe || UsageSource.refino => {
          for (final e in mine) e.conversationId ?? -e.id,
        }.length,
        UsageSource.revisor => {
          for (final e in mine) e.step ?? 'e${e.id}',
        }.length,
        _ => mine.length,
      },
    );
  }
  final steps = <String, List<UsageEntry>>{};
  for (final e in sorted) {
    if (e.step == null) continue;
    if (e.source != UsageSource.etapa && e.source != UsageSource.ci) continue;
    steps.putIfAbsent(e.step!, () => []).add(e);
  }
  final stepKeys = steps.keys.toList()..sort(compareSteps);
  double? window;
  if (windowStart != null) {
    for (final e in sorted) {
      if (!e.at.isBefore(windowStart)) window = _add(window, e.fiveHourPct);
    }
  }
  return SpecCost(
    total: _sum(sorted),
    bySource: bySource,
    bySteps: [for (final k in stepKeys) (k, _sum(steps[k]!))],
    entries: sorted,
    thisWindow: window != null && window > 0 ? window : null,
    estimated: sorted.any((e) => e.estimated),
  );
}

/// Start of the current 5-hour window (null without a reading or when it
/// already renewed).
DateTime? currentWindowStart(RateLimit? r, DateTime now) {
  final resets = r?.fiveHourResetsAt;
  if (resets == null || !resets.isAfter(now)) return null;
  return resets.subtract(const Duration(hours: 5));
}

/// Like the other streams of the panel, kept for the spec while the app
/// runs (a drift stream closing at dispose leaves a timer behind).
final specUsageProvider = StreamProvider.family<List<UsageEntry>, int>(
  (ref, specId) => ref.watch(usageEntriesRepoProvider).bySpec(specId),
);

final specCostProvider = Provider.family<SpecCost, int>((ref, specId) {
  final entries = ref.watch(specUsageProvider(specId)).value ?? const [];
  return specCostOf(
    entries,
    windowStart: currentWindowStart(
      ref.watch(rateLimitProvider),
      DateTime.now(),
    ),
  );
});

final sessionUsageProvider = StreamProvider.family<List<UsageEntry>, String>(
  (ref, sessionId) => ref.watch(usageEntriesRepoProvider).bySession(sessionId),
);

/// With an API key there is no quota: the cost is shown in dollars (R12).
/// Unknown while the CLI is checked: quota.
final costInDollarsProvider = Provider.autoDispose<bool>((ref) {
  final a = ref.watch(providerAvailabilityProvider('claude')).value;
  return a != null && a.available && !a.subscription;
});

/// The weight of each live session in the current 5-hour window (R7), the
/// same as the Atividades (SPEC-076 R7).
final liveQuotaWeightsProvider = Provider.autoDispose<Map<String, double>>((
  ref,
) {
  final rate = ref.watch(rateLimitProvider);
  final manager = ref.watch(sessionManagerProvider);
  final workspaces = ref.watch(workspacesProvider).value ?? const [];
  final windowStart = rate?.fiveHourResetsAt?.subtract(
    const Duration(hours: 5),
  );
  final costs = <String, double>{};
  for (final ws in workspaces) {
    costs.addAll(
      windowSessionCosts(
        ref.watch(sessionsProvider(ws.id)).value ?? const [],
        windowStart: windowStart,
        isAlive: manager.isAlive,
      ),
    );
  }
  return sessionQuotaWeights(costs, rate?.fiveHourUtilization);
});

// --- ranking (R10, R11) ------------------------------------------------------

/// Period of the ranking (R10).
enum CostPeriod {
  week('7 dias', Duration(days: 7)),
  month('30 dias', Duration(days: 30)),
  all('Tudo', null);

  const CostPeriod(this.label, this.span);

  final String label;
  final Duration? span;
}

/// One line of the ranking.
@immutable
class SpecCostRank {
  const SpecCostRank({
    required this.spec,
    required this.workspace,
    required this.cost,
  });

  final Spec spec;
  final Workspace workspace;
  final SpecCost cost;

  /// The origin that weighed the most and its part.
  (UsageSource, double)? get top {
    (UsageSource, double)? best;
    for (final MapEntry(:key, :value) in cost.bySource.entries) {
      final part = cost.share(value);
      if (best == null || part > best.$2) best = (key, part);
    }
    return best;
  }
}

/// The weight that orders the ranking: the week, else the cost.
double rankWeight(SpecCost c) => c.total.week ?? c.total.costUsd;

List<SpecCostRank> _specRanks(
  List<UsageEntry> entries,
  Map<int, (Spec, Workspace)> specs,
) {
  final bySpec = <int, List<UsageEntry>>{};
  for (final e in entries) {
    final id = e.specId;
    if (id == null || !specs.containsKey(id)) continue;
    bySpec.putIfAbsent(id, () => []).add(e);
  }
  return [
    for (final MapEntry(:key, :value) in bySpec.entries)
      SpecCostRank(
        spec: specs[key]!.$1,
        workspace: specs[key]!.$2,
        cost: specCostOf(value),
      ),
  ];
}

/// The specs of [entries] with the most weight, at most [limit]. Pure.
/// Only what has a cost is ranked (SPEC-097 R9): a spec with only tokens
/// (the Codex) is never "the cheapest"; [rankTokenOnlySpecs] lists them.
List<SpecCostRank> rankSpecCosts(
  List<UsageEntry> entries, {
  required Map<int, (Spec, Workspace)> specs,
  int limit = 10,
}) {
  final out = [
    for (final r in _specRanks(entries, specs))
      if (!r.cost.total.onlyUnpriced) r,
  ]..sort((a, b) => rankWeight(b.cost).compareTo(rankWeight(a.cost)));
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// The specs whose turns have no cost (SPEC-097 R9), most tokens first, at
/// most [limit]. Pure.
List<SpecCostRank> rankTokenOnlySpecs(
  List<UsageEntry> entries, {
  required Map<int, (Spec, Workspace)> specs,
  int limit = 10,
}) {
  final out = [
    for (final r in _specRanks(entries, specs))
      if (r.cost.total.onlyUnpriced) r,
  ]..sort((a, b) => b.cost.total.tokens.compareTo(a.cost.total.tokens));
  return out.length > limit ? out.sublist(0, limit) : out;
}

typedef CostRankingQuery = ({int workspaceId, bool all, CostPeriod period});

/// Key: the workspace ids joined by commas (a set has no value equality)
/// and since when.
final _rankingEntriesProvider = StreamProvider.autoDispose
    .family<List<UsageEntry>, (String, DateTime?)>(
      (ref, q) => ref.watch(usageEntriesRepoProvider).byWorkspace([
        for (final id in q.$1.split(',')) ?int.tryParse(id),
      ], since: q.$2),
    );

String _ids(Iterable<int> ids) => (ids.toList()..sort()).join(',');

/// The specs of the period with only tokens (SPEC-097 R9), apart from the
/// ranking by cost.
final specTokenOnlyRankingProvider = Provider.autoDispose
    .family<List<SpecCostRank>?, CostRankingQuery>((ref, q) {
      final d = ref.watch(_rankingDataProvider(q));
      return d == null ? null : rankTokenOnlySpecs(d.$1, specs: d.$2);
    });

/// The ranking of the workspace (or of every open workspace) in the period.
final specCostRankingProvider = Provider.autoDispose
    .family<List<SpecCostRank>?, CostRankingQuery>((ref, q) {
      final d = ref.watch(_rankingDataProvider(q));
      return d == null ? null : rankSpecCosts(d.$1, specs: d.$2);
    });

/// The entries of the period and the specs they may belong to.
final _rankingDataProvider = Provider.autoDispose
    .family<(List<UsageEntry>, Map<int, (Spec, Workspace)>)?, CostRankingQuery>(
      (ref, q) {
        final workspaces = ref.watch(workspacesProvider).value ?? const [];
        final chosen = [
          for (final w in workspaces)
            if (q.all || w.id == q.workspaceId) w,
        ];
        final span = q.period.span;
        // A day as the unit keeps the key stable while the screen is open.
        final now = DateTime.now();
        final since = span == null
            ? null
            : DateTime(now.year, now.month, now.day).subtract(span);
        final entries = ref.watch(
          _rankingEntriesProvider((
            _ids([for (final w in chosen) w.id]),
            since,
          )),
        );
        if (!entries.hasValue) return null;
        final specs = <int, (Spec, Workspace)>{};
        for (final w in chosen) {
          for (final s
              in ref.watch(specsProvider(w.id)).value ?? const <Spec>[]) {
            specs[s.id] = (s, w);
          }
        }
        return (entries.value!, specs);
      },
    );

/// The cost of every spec of a workspace, all time (the "Cota (semana)" of
/// Projeto → Métricas, R11).
final workspaceSpecCostsProvider = Provider.autoDispose
    .family<Map<int, SpecCost>, int>((ref, workspaceId) {
      final entries =
          ref.watch(_rankingEntriesProvider(('$workspaceId', null))).value ??
          const [];
      final bySpec = <int, List<UsageEntry>>{};
      for (final e in entries) {
        if (e.specId != null) bySpec.putIfAbsent(e.specId!, () => []).add(e);
      }
      return {
        for (final MapEntry(:key, :value) in bySpec.entries)
          key: specCostOf(value),
      };
    });
