import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/project/spec_metrics.dart';

void main() {
  test('cost, time per step, gate fixes, review rounds and hunks', () {
    final spec = Spec(
      id: 1,
      workspaceId: 1,
      code: 'SPEC-001',
      title: 'A',
      status: SpecStatus.approved,
      path: 'specs/a.md',
      stage: SpecStage.review,
      requirements: const [],
      dependsOn: const [],
      autoAdvance: true,
      reviewRounds: 1,
      gateResends: 2,
      rejectedHunks: 3,
    );
    Session s(String id, String steps, int minutes, double cost) => Session(
      provider: 'claude',
      id: id,
      workspaceId: 1,
      worktreePath: '/w',
      branch: 'pr/x',
      status: SessionStatus.completed,
      model: 'sonnet',
      specId: 1,
      steps: steps,
      costUsd: cost,
      tokensIn: 0,
      tokensOut: 0,
      startedAt: DateTime(2026, 10, 17, 10),
      endedAt: DateTime(2026, 10, 17, 10, minutes),
    );
    ReviewCommentRow c(int round, String author) => ReviewCommentRow(
      id: round * 10 + author.length,
      specId: 1,
      round: round,
      author: author,
      body: 'x',
      resolved: false,
      createdAt: DateTime(2026),
    );
    final m = computeSpecMetrics(
      specs: [spec],
      sessions: [
        s('a', 'R1', 10, 0.10),
        s('b', 'R2,R3', 20, 0.25),
        s('c', 'R2', 5, 0.05),
      ],
      comments: [c(1, 'revisor'), c(1, 'revisor'), c(2, 'humano')],
    ).single;
    expect(m.cost, closeTo(0.40, 1e-9));
    expect(m.sessions, 3);
    expect(m.stepTime, {
      'R1': const Duration(minutes: 10),
      'R2': const Duration(minutes: 25),
      'R3': const Duration(minutes: 20),
    });
    expect(m.gateResends, 2);
    expect(m.reviewerRounds, 1);
    expect(m.humanRounds, 1);
    expect(m.rejectedHunks, 3);
  });
}
