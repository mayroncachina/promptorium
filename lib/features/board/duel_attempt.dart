import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// What one attempt of "Executar em dobro (A/B)" runs with (SPEC-108 R11):
/// [provider], and its model and effort; null = the current configuration
/// of the spec for that provider.
@immutable
class DuelAttempt {
  const DuelAttempt({required this.provider, this.model, this.effort});

  final String provider;
  final String? model;
  final String? effort;

  @override
  bool operator ==(Object other) =>
      other is DuelAttempt &&
      other.provider == provider &&
      other.model == model &&
      other.effort == effort;

  @override
  int get hashCode => Object.hash(provider, model, effort);

  @override
  String toString() => '$provider/$model/$effort';
}

/// The two attempts, A and B.
typedef DuelAttempts = ({DuelAttempt a, DuelAttempt b});

/// What one attempt spent, for the result dialog: time and tokens, never
/// US$ (SPEC-108 R11).
@immutable
class DuelStats {
  const DuelStats({
    required this.provider,
    required this.model,
    this.effort,
    this.durationMs = 0,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.reasoning = 0,
  });

  final String provider;
  final String model;
  final String? effort;

  /// Sum of the turns.
  final int durationMs;

  /// Input with the cache.
  final int tokensIn;

  /// Output with the reasoning.
  final int tokensOut;

  /// Part of [tokensOut].
  final int reasoning;
}

/// [DuelStats] of the session of an attempt (null = no session): the turns
/// recorded in the usage ledger and the time of each `result`.
final duelStatsProvider = FutureProvider.autoDispose.family<DuelStats?, String>(
  (ref, sessionId) async {
    final repo = ref.read(sessionsRepoProvider);
    final s = await repo.getById(sessionId);
    if (s == null) return null;
    var ms = 0;
    for (final e in await repo.events(sessionId)) {
      if (!e.type.startsWith('result')) continue;
      try {
        final j = jsonDecode(e.json);
        if (j is Map && j['duration_ms'] is num) {
          ms += (j['duration_ms'] as num).toInt();
        }
      } catch (_) {}
    }
    final entries = await ref
        .read(usageEntriesRepoProvider)
        .bySession(sessionId)
        .first;
    var input = 0, output = 0, reasoning = 0;
    for (final e in entries) {
      input += e.tokensIn + e.tokensCacheWrite + e.tokensCacheRead;
      output += e.tokensOut;
      reasoning += e.tokensReasoning;
    }
    return DuelStats(
      provider: s.provider,
      model: s.model,
      effort: s.effort,
      durationMs: ms,
      tokensIn: entries.isEmpty ? s.tokensIn : input,
      tokensOut: entries.isEmpty ? s.tokensOut : output,
      reasoning: reasoning,
    );
  },
);
