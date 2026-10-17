import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../board/board_rules.dart';
import '../board/spec_runner.dart' show parseSessionSteps;

/// Quality of one spec (F14): what it cost and how much correction it
/// needed.
@immutable
class SpecMetrics {
  const SpecMetrics({
    required this.spec,
    required this.cost,
    required this.sessions,
    required this.stepTime,
    required this.gateResends,
    required this.reviewerRounds,
    required this.humanRounds,
    required this.rejectedHunks,
  });

  final Spec spec;
  final double cost;
  final int sessions;

  /// Time of the sessions of each step (a session doing R1–R3 counts for
  /// each of them).
  final Map<String, Duration> stepTime;

  /// Failures of the gate sent back to the agent.
  final int gateResends;

  /// Rounds of the automatic reviewer / of the user ("Pedir ajustes").
  final int reviewerRounds;
  final int humanRounds;
  final int rejectedHunks;

  Duration get time => stepTime.values.fold(Duration.zero, (a, b) => a + b);
}

/// Metrics of [specs] from their sessions and review rounds. A running
/// session counts until [now].
List<SpecMetrics> computeSpecMetrics({
  required List<Spec> specs,
  required List<Session> sessions,
  required List<ReviewCommentRow> comments,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return [
    for (final spec in specs)
      () {
        final mine = [
          for (final s in sessions)
            if (s.specId == spec.id) s,
        ];
        final stepTime = <String, Duration>{};
        for (final s in mine) {
          final d = (s.endedAt ?? at).difference(s.startedAt);
          for (final step in parseSessionSteps(s.steps)) {
            stepTime[step] = (stepTime[step] ?? Duration.zero) + d;
          }
        }
        Set<int> rounds(String author) => {
          for (final c in comments)
            if (c.specId == spec.id && c.author == author) c.round,
        };
        return SpecMetrics(
          spec: spec,
          cost: mine.fold(0.0, (a, s) => a + s.costUsd),
          sessions: mine.length,
          stepTime: stepTime,
          gateResends: spec.gateResends,
          reviewerRounds: rounds('revisor').length,
          humanRounds: rounds('humano').length,
          rejectedHunks: spec.rejectedHunks,
        );
      }(),
  ];
}

/// Metrics of the specs of a workspace that ran (have sessions).
final specMetricsProvider = FutureProvider.autoDispose
    .family<List<SpecMetrics>, int>((ref, workspaceId) async {
      final specs = await ref.watch(specsProvider(workspaceId).future);
      final sessions = await ref.watch(sessionsProvider(workspaceId).future);
      final comments = <ReviewCommentRow>[];
      for (final s in specs) {
        comments.addAll(
          await ref.read(reviewCommentsRepoProvider).bySpec(s.id),
        );
      }
      final ran = [
        for (final s in specs)
          if (sessions.any((x) => x.specId == s.id) && isOnBoard(s)) s,
      ];
      return computeSpecMetrics(
        specs: ran,
        sessions: sessions,
        comments: comments,
      );
    });
