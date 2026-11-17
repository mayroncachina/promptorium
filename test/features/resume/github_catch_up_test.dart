import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart' show CiState;
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/activity_events_repo.dart';
import 'package:promptorium/features/resume/activity_journal.dart';
import 'package:promptorium/features/resume/github_catch_up.dart';

import '../../helpers/test_db.dart';
import '../activities/activity_test.dart' show session, spec;

final since = DateTime.utc(2026, 11, 16, 22, 42).toLocal();

CatchUpPr pr(int n, {Spec? spec}) => (
  workspaceId: 1,
  repoPath: '/r',
  number: n,
  sessionId: 's$n',
  spec: spec,
  title: 'Sessão $n',
);

String view({
  String state = 'OPEN',
  String? mergedAt,
  String? closedAt,
  String? by,
  List<Map<String, Object?>> checks = const [],
}) => jsonEncode({
  'state': state,
  'mergedAt': mergedAt ?? '0001-01-01T00:00:00Z',
  'closedAt': closedAt,
  'mergedBy': by == null ? null : {'login': by},
  'statusCheckRollup': checks,
});

void main() {
  test('parses a merged PR and the CI of check runs and statuses', () {
    final merged = parseCatchUpView(
      view(state: 'MERGED', mergedAt: '2026-11-17T02:14:00Z', by: 'mayron'),
    )!;
    expect(merged.state, 'MERGED');
    expect(merged.mergedAt, DateTime.utc(2026, 11, 17, 2, 14).toLocal());
    expect(merged.mergedBy, 'mayron');

    final red = parseCatchUpView(
      view(
        checks: [
          {
            'name': 'test',
            'status': 'COMPLETED',
            'conclusion': 'FAILURE',
            'completedAt': '2026-11-17T01:00:00Z',
          },
          {
            'context': 'lint',
            'state': 'SUCCESS',
            'startedAt': '2026-11-17T00:50:00Z',
          },
        ],
      ),
    )!;
    expect(red.ci, CiState.failed);
    expect(red.failed, ['test']);
    expect(red.ciDoneAt, DateTime.utc(2026, 11, 17, 1).toLocal());

    final running = parseCatchUpView(
      view(
        checks: [
          {'name': 'test', 'status': 'IN_PROGRESS'},
        ],
      ),
    )!;
    expect(running.ci, CiState.running);
    expect(running.ciDoneAt, isNull);
    expect(parseCatchUpView('nope'), isNull);
  });

  test('a merge after the last seen enters with GitHub\'s time (R7)', () {
    final s = spec(7, 'SPEC-077');
    final at = DateTime.utc(2026, 11, 17, 2, 14).toLocal();
    final out = catchUpEntries(
      pr(267, spec: s),
      parseCatchUpView(
        view(state: 'MERGED', mergedAt: '2026-11-17T02:14:00Z', by: 'mayron'),
      )!,
      since,
    );
    expect(out.single.at, at);
    expect(out.single.detail, 'PR #267 mergeado por mayron');
    expect(out.single.groupKey, 'spec:7');
    // Before the last seen: already known.
    expect(
      catchUpEntries(
        pr(267, spec: s),
        parseCatchUpView(
          view(state: 'MERGED', mergedAt: '2026-11-16T20:00:00Z'),
        )!,
        since,
      ),
      isEmpty,
    );
  });

  test('closed and CI finished after the last seen', () {
    final closed = catchUpEntries(
      pr(5),
      parseCatchUpView(
        view(state: 'CLOSED', closedAt: '2026-11-17T03:00:00Z'),
      )!,
      since,
    );
    expect(closed.single.detail, 'PR #5 fechado sem merge');
    expect(closed.single.title, 'PR #5');
    final ci = catchUpEntries(
      pr(270),
      parseCatchUpView(
        view(
          checks: [
            {
              'name': 'test',
              'conclusion': 'FAILURE',
              'completedAt': '2026-11-17T04:00:00Z',
            },
          ],
        ),
      )!,
      since,
    );
    expect(ci.single.kind, JournalKind.ci);
    expect(ci.single.detail, 'CI do PR #270 falhou em `test`');
  });

  test('catchUpPrs: sessions with an open PR, not merged nor done', () {
    final ws = Workspace(id: 1, path: '/r', name: 'r', createdAt: since);
    final prs = catchUpPrs(
      workspaces: [ws],
      sessions: {
        1: [
          session('a', specId: 7, prUrl: 'https://github.com/o/r/pull/1'),
          session(
            'b',
            status: SessionStatus.merged,
            prUrl: 'https://github.com/o/r/pull/2',
          ),
          session('c', specId: 8, prUrl: 'https://github.com/o/r/pull/3'),
          session('d'),
        ],
      },
      specs: {
        1: [spec(7, 'SPEC-077'), spec(8, 'SPEC-078', stage: SpecStage.done)],
      },
      since: since,
    );
    expect(prs.map((p) => p.number), [1]);
    expect(prs.single.spec?.code, 'SPEC-077');
  });

  group('catchUpGithub', () {
    late AppDatabase db;
    late ActivityEventsRepo repo;
    setUp(() async {
      db = memoryDatabase();
      repo = ActivityEventsRepo(db);
      await db.customStatement(
        "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
      );
    });
    tearDown(() => db.close());

    test('writes the merge once, even when checked again', () async {
      Future<String> gh(String repo, int n, String fields) async {
        expect(fields, catchUpFields);
        return view(state: 'MERGED', mergedAt: '2026-11-17T02:14:00Z');
      }

      expect(
        await catchUpGithub(prs: [pr(267)], since: since, view: gh, repo: repo),
        isTrue,
      );
      await catchUpGithub(prs: [pr(267)], since: since, view: gh, repo: repo);
      final rows = await repo.since(since);
      expect(rows, hasLength(1));
      expect(rows.single.at, DateTime.utc(2026, 11, 17, 2, 14).toLocal());
    });

    test('without gh: false (the card offers "Tentar de novo")', () async {
      Future<String> gh(String repo, int n, String fields) async =>
          throw Exception('gh não encontrado');
      expect(
        await catchUpGithub(
          prs: [pr(1), pr(2)],
          since: since,
          view: gh,
          repo: repo,
        ),
        isFalse,
      );
      expect(await repo.since(since), isEmpty);
    });
  });
}
