import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_event.dart' show Result, Usage;
import '../../data/providers.dart';
import 'quota_ruler.dart';

/// The register of the turns (SPEC-081 R1, R2, R4): every `result` of a
/// session, a conversation or a `claude -p` of the app becomes one row of
/// `usage_entries`, with its spec and its origin.

/// Estimated cost of one turn: the difference between the cumulative
/// `total_cost_usd` of this `result` and the one before it in the same
/// process ([lastSeen]; null = the first `result` of the process). The
/// first `result` of a resumed process may come with the cost of the
/// session restored ([stored], what the app already has) or start from
/// zero again. Pure.
double turnCost(double total, {double? lastSeen, double stored = 0}) {
  if (total <= 0) return 0;
  if (lastSeen != null) return total >= lastSeen ? total - lastSeen : total;
  return stored > 0 && total >= stored ? total - stored : total;
}

/// Model of a `result` (the one that cost the most in `modelUsage`), else
/// [fallback].
String? resultModel(Result e, [String? fallback]) {
  final usage = e.json['modelUsage'];
  if (usage is Map && usage.isNotEmpty) {
    String? best;
    var cost = -1.0;
    for (final MapEntry(:key, :value) in usage.entries) {
      final c = value is Map && value['costUSD'] is num
          ? (value['costUSD'] as num).toDouble()
          : 0.0;
      if (key is String && c > cost) {
        best = key;
        cost = c;
      }
    }
    if (best != null) return best;
  }
  return fallback;
}

/// Code of the spec a text is about: the `id:` of its frontmatter, else the
/// `Spec SPEC-NNN` it starts with (the prompt of a `claude -p` that only
/// carries the text of the spec).
String? specCodeInText(String text) {
  final id = RegExp(
    r'^id:\s*((?:SPEC|VIBE)-\d+)\s*$',
    multiLine: true,
  ).firstMatch(text);
  if (id != null) return id.group(1);
  // "Spec SPEC-081:" at the start (the verification). A code anywhere else
  // may be a dependency, not the spec itself.
  return RegExp(r'^\s*Spec ((?:SPEC|VIBE)-\d+)\b').firstMatch(text)?.group(1);
}

/// Origin and spec of a turn of a session (R2): a session of a step is
/// `etapa` (a `REVn` step too), unless the CI fixer marked the turn; a
/// session without a spec is `livre`.
({int? specId, UsageSource source, String? step}) sessionUsageOrigin(
  Session s, {
  UsageSource? mark,
}) {
  if (s.specId == null) {
    return (specId: null, source: mark ?? UsageSource.livre, step: null);
  }
  return (specId: s.specId, source: mark ?? UsageSource.etapa, step: s.steps);
}

/// Origin of a turn of a conversation (R2): a VIBE (`specId`), a refinement
/// (`refineSpecCode`, the spec by its code: [refineSpecId]) or the free
/// Prompt.
({int? specId, UsageSource source}) conversationUsageOrigin(
  Conversation c, {
  int? refineSpecId,
  UsageSource? mark,
}) {
  if (c.specId != null) {
    return (specId: c.specId, source: mark ?? UsageSource.vibe);
  }
  if (c.refineSpecCode != null && refineSpecId != null) {
    return (specId: refineSpecId, source: mark ?? UsageSource.refino);
  }
  return (specId: null, source: mark ?? UsageSource.livre);
}

/// Records the turns. Never throws: a turn that cannot be recorded must not
/// stop the session.
class UsageLedger {
  UsageLedger(this._ref);

  final Ref _ref;

  /// Origin of the next turn of a session (`s:<id>`) or conversation
  /// (`c:<id>`), set by whoever sends the message (P6: the CI fixer).
  final _marks = <String, UsageSource>{};

  static String _sessionKey(String id) => 's:$id';
  static String _conversationKey(int id) => 'c:$id';

  /// The next turn of [sessionId] / [conversationId] is of [source] (P6).
  void markNextTurn({
    String? sessionId,
    int? conversationId,
    required UsageSource source,
  }) {
    if (sessionId != null) _marks[_sessionKey(sessionId)] = source;
    if (conversationId != null) {
      _marks[_conversationKey(conversationId)] = source;
    }
  }

  /// Moves the mark of a session to a conversation (a VIBE talks through
  /// its conversation).
  void moveMark(String sessionId, int conversationId) {
    final m = _marks.remove(_sessionKey(sessionId));
    if (m != null) _marks[_conversationKey(conversationId)] = m;
  }

  /// Records one turn (R1): nothing for a turn without tokens. The weight
  /// comes from the ruler of now and never changes after (R4).
  ///
  /// Without [specId], [specCode] finds the spec in the workspace.
  Future<void> record({
    required int? workspaceId,
    int? specId,
    String? specCode,
    required UsageSource source,
    String? step,
    String? sessionId,
    int? conversationId,
    String? model,
    required Usage usage,
    required double costUsd,
    DateTime? at,
  }) async {
    if (usage.total <= 0) return;
    try {
      if (specId == null && specCode != null) {
        if (workspaceId != null) {
          specId =
              (await _ref
                      .read(specsRepoProvider)
                      .getByCode(workspaceId, specCode))
                  ?.id;
        }
        // A spec that does not exist (yet): a free turn (R2).
        if (specId == null) source = UsageSource.livre;
      }
      final ruler = _ref.read(quotaRulerProvider);
      final w = ruler.weigh(costUsd);
      _ref.read(quotaRulerProvider.notifier).addCost(costUsd);
      await _ref
          .read(usageEntriesRepoProvider)
          .add(
            UsageEntriesCompanion.insert(
              workspaceId: Value(workspaceId),
              specId: Value(specId),
              source: source,
              step: Value(step),
              sessionId: Value(sessionId),
              conversationId: Value(conversationId),
              model: Value(model),
              at: at ?? DateTime.now(),
              tokensIn: Value(usage.inputTokens),
              tokensCacheWrite: Value(usage.cacheCreationInputTokens),
              tokensCacheRead: Value(usage.cacheReadInputTokens),
              tokensOut: Value(usage.outputTokens),
              costUsd: Value(costUsd),
              fiveHourPct: Value(w.fiveHour),
              weekPct: Value(w.week),
            ),
          );
    } catch (e) {
      debugPrint('custo por spec: turno não gravado — $e');
    }
  }

  /// A turn of the session [sessionId] (the `result` [e], [costUsd] by
  /// [turnCost]).
  Future<void> recordSessionTurn(
    String sessionId,
    Result e, {
    required double costUsd,
  }) async {
    final mark = _marks.remove(_sessionKey(sessionId));
    if (e.usage.total <= 0) return;
    try {
      final s = await _ref.read(sessionsRepoProvider).getById(sessionId);
      if (s == null) return;
      final o = sessionUsageOrigin(s, mark: mark);
      await record(
        workspaceId: s.workspaceId,
        specId: o.specId,
        source: o.source,
        step: o.step,
        sessionId: s.id,
        model: resultModel(e, s.model),
        usage: e.usage,
        costUsd: costUsd,
      );
    } catch (err) {
      debugPrint('custo por spec: turno da sessão não gravado — $err');
    }
  }

  /// A turn of the conversation [conversationId].
  Future<void> recordConversationTurn(
    int conversationId,
    Result e, {
    required double costUsd,
    String? model,
  }) async {
    final mark = _marks.remove(_conversationKey(conversationId));
    if (e.usage.total <= 0) return;
    try {
      final c = await _ref
          .read(conversationsRepoProvider)
          .getById(conversationId);
      if (c == null) return;
      final refine = c.refineSpecCode == null || c.specId != null
          ? null
          : await _ref
                .read(specsRepoProvider)
                .getByCode(c.workspaceId, c.refineSpecCode!);
      final o = conversationUsageOrigin(
        c,
        refineSpecId: refine?.id,
        mark: mark,
      );
      await record(
        workspaceId: c.workspaceId,
        specId: o.specId,
        source: o.source,
        conversationId: c.id,
        model: resultModel(e, model ?? c.model),
        usage: e.usage,
        costUsd: costUsd,
      );
    } catch (err) {
      debugPrint('custo por spec: turno da conversa não gravado — $err');
    }
  }

  /// The entries recorded without the weight of a window receive it now
  /// that the window has a ruler (R4; the history of before, R5, too).
  Future<void> applyPendingWeights() async {
    try {
      final ruler = _ref.read(quotaRulerProvider);
      if (!ruler.ready) return;
      final repo = _ref.read(usageEntriesRepoProvider);
      for (final e in await repo.pendingWeights()) {
        final w = ruler.weigh(e.costUsd);
        if (w.fiveHour == null && w.week == null) continue;
        await repo.setWeights(e.id, fiveHour: w.fiveHour, week: w.week);
      }
    } catch (e) {
      debugPrint('custo por spec: pesos pendentes não gravados — $e');
    }
  }
}

final usageLedgerProvider = Provider(UsageLedger.new);
