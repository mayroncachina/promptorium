import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/repository/graph/commit_log.dart';
import 'package:promptorium/features/repository/graph/graph_controller.dart';
import 'package:promptorium/features/repository/graph/graph_painter.dart';
import 'package:promptorium/features/repository/graph/graph_sources.dart';
import 'package:promptorium/features/repository/graph/graph_tab.dart';
import 'package:promptorium/features/repository/releases/releases_state.dart';
import 'package:promptorium/features/repository/releases/releases_tab.dart';
import 'package:promptorium/features/repository/repository_info.dart';
import 'package:promptorium/features/repository/repository_screen.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/git_test_utils.dart';
import 'commit_log_test.dart' show buildHistory;
import 'fake_gh.dart';

class _Settings extends AppSettingsController {
  @override
  Map<String, String> build() => {};

  @override
  Future<void> set(String key, String value) async =>
      state = {...state, key: value};
}

Spec specRow(int id, String code, String title) => Spec(
  id: id,
  workspaceId: 1,
  code: code,
  title: title,
  status: SpecStatus.approved,
  path: 'docs/specs/$code.md',
  stage: SpecStage.done,
  requirements: const [],
  dependsOn: const [],
  autoAdvance: true,
  reviewRounds: 0,
  gateResends: 0,
  rejectedHunks: 0,
);

Session sessionOn(String id, String branch) => Session(
  provider: 'claude',
  id: id,
  workspaceId: 1,
  title: 'SPEC-043',
  worktreePath: '/wt/$id',
  branch: branch,
  status: SessionStatus.completed,
  model: 'sonnet',
  costUsd: 0,
  tokensIn: 0,
  tokensOut: 0,
  startedAt: DateTime(2026, 11, 7),
);

void main() {
  late Directory tmp;
  late String repo;
  late FakeGh gh;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-graph-tab-');
    repo = await createRepo(tmp);
    await buildHistory(repo);
    // Merged and deleted, as after a PR.
    await gitIn(repo, ['branch', '-q', '-D', 'spec/042-sprints']);
    gh = FakeGh();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  RepositoryInfo info() =>
      RepositoryInfo(path: repo, defaultBranch: 'main', remote: 'origin');

  Future<GraphController> loaded(WidgetTester tester) async {
    final c = GraphController(
      CommitLog(GitService(repo), defaultBranch: 'main', remote: 'origin'),
    );
    await tester.runAsync(c.load);
    return c;
  }

  Future<ProviderContainer> pumpTab(
    WidgetTester tester,
    GraphController c, {
    List<Session> sessions = const [],
    Set<String> busy = const {},
    CommitAuthorBadge? badge,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ws = Workspace(
      id: 1,
      path: repo,
      name: 'repo',
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(_Settings.new),
          activeWorkspaceProvider.overrideWithValue(ws),
          cliRunnerProvider.overrideWithValue(gh.call),
          specsProvider.overrideWith(
            (ref, id) => Stream.value([
              specRow(1, 'SPEC-042', 'Sprints no Quadro'),
              specRow(2, 'SPEC-043', 'Conflito resolvido'),
            ]),
          ),
          sessionsProvider.overrideWith((ref, id) => Stream.value(sessions)),
          graphBusyBranchesProvider.overrideWithValue(busy),
          if (badge != null) graphAuthorBadgeProvider.overrideWithValue(badge),
          releasesProvider.overrideWith(
            (ref, repo) => Completer<ReleasesData>().future,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: GraphTab(repo: info(), controller: c),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(GraphTab)));
  }

  testWidgets('R1 · a row per commit with the spec, author, date and SHA; '
      'the tab comes after Releases', (tester) async {
    expect(repositoryTabs.map((t) => t.id).take(2), ['releases', 'grafo']);
    final c = await loaded(tester);
    await pumpTab(tester, c);
    expect(find.text('docs: SPEC-043, conflito'), findsOneWidget);
    final row = c.rows.firstWhere(
      (r) => c.commit(r.sha)!.subject == 'docs: SPEC-043, conflito',
    );
    expect(
      tester.widget<Text>(find.byKey(ValueKey('graph-spec-${row.sha}'))).data,
      'SPEC-043',
    );
    expect(find.text(c.commit(row.sha)!.shortSha), findsOneWidget);
    expect(find.text('Teste'), findsWidgets);
    expect(find.text('agora'), findsWidgets);
    expect(find.byKey(const ValueKey('graph-count')), findsOneWidget);
    expect(find.text('7 de 7 commits'), findsOneWidget);
  });

  testWidgets('R3 · a merged spec starts collapsed and expands', (
    tester,
  ) async {
    final c = await loaded(tester);
    await pumpTab(tester, c);
    expect(
      find.text(
        'SPEC-042 · Sprints no Quadro: 1 tarefa, 1 mergeada, 3 commits',
      ),
      findsOneWidget,
    );
    expect(find.text('feat(sprints): dados'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('graph-group-42')));
    await tester.pump();
    expect(find.text('feat(sprints): dados'), findsOneWidget);
    expect(find.textContaining('1 tarefa, 1 mergeada'), findsNothing);
    // The first row of the expanded spec carries SPEC-042, which collapses.
    expect(find.widgetWithText(GraphChip, 'SPEC-042'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('graph-group-42')));
    await tester.pump();
    expect(find.text('feat(sprints): dados'), findsNothing);
  });

  testWidgets('R2 · an open spec is expanded, with the colour of the spec', (
    tester,
  ) async {
    final c = await loaded(tester);
    await pumpTab(tester, c);
    final row = c.rows.first;
    expect(row.track, 'spec/043-conflito');
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(ValueKey('graph-lanes-${row.sha}')),
                )
                .painter!
            as GraphRowPainter;
    expect(painter.row, row);
    expect(
      tester
          .widget<GraphChip>(
            find.byKey(const ValueKey('graph-branch-spec/043-conflito')),
          )
          .color,
      trackColor('spec/043-conflito', 'main'),
    );
  });

  testWidgets('R4 · a tag opens its version in Releases', (tester) async {
    final c = await loaded(tester);
    final container = await pumpTab(tester, c);
    await tester.tap(find.byKey(const ValueKey('graph-tag-v0.1.0')));
    await tester.pump();
    expect(container.read(selectedReleaseProvider), 'v0.1.0');
    expect(container.read(repositoryTabProvider), 'releases');
  });

  testWidgets('R4 · the open PR with its CI; without a session it opens in '
      'the browser', (tester) async {
    gh.prs = [
      {
        'number': 101,
        'url': 'https://github.com/o/r/pull/101',
        'headRefName': 'spec/043-conflito',
        'statusCheckRollup': [
          {'status': 'COMPLETED', 'conclusion': 'SUCCESS'},
          {'status': 'IN_PROGRESS', 'conclusion': ''},
        ],
      },
    ];
    final c = await loaded(tester);
    await pumpTab(tester, c);
    expect(find.text('#101 · CI rodando'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('graph-pr-101')));
    await tester.pump();
    expect(gh.calls.where((x) => x.$1 == 'xdg-open').single.$2, [
      'https://github.com/o/r/pull/101',
    ]);
  });

  testWidgets('R4 · the PR of a session opens its card in the Review', (
    tester,
  ) async {
    gh.prs = [
      {
        'number': 100,
        'url': 'https://github.com/o/r/pull/100',
        'headRefName': 'spec/043-conflito',
        'statusCheckRollup': [
          {'state': 'SUCCESS'},
        ],
      },
    ];
    final c = await loaded(tester);
    final container = await pumpTab(
      tester,
      c,
      sessions: [sessionOn('s1', 'spec/043-conflito')],
    );
    expect(find.text('#100 · CI passou'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('graph-pr-100')));
    await tester.pump();
    expect(container.read(selectedReviewProvider), 's1');
    expect(container.read(navigationProvider), AppSection.review);
  });

  testWidgets('R4 · a branch with an agent running shows "agente '
      'trabalhando" on its tip', (tester) async {
    final c = await loaded(tester);
    await pumpTab(tester, c, busy: {'spec/043-conflito'});
    expect(find.text('agente trabalhando'), findsOneWidget);
  });

  testWidgets('R8 · over a lane: it stands out and the balloon tells the '
      'branch', (tester) async {
    final c = await loaded(tester);
    await pumpTab(tester, c);
    final row = c.rows.first;
    final lanes = find.byKey(ValueKey('graph-lanes-${row.sha}'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getTopLeft(lanes) + Offset(laneX(row.column), graphRowHeight / 2),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('graph-balloon')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('graph-balloon')),
        matching: find.text('spec/043-conflito'),
      ),
      findsOneWidget,
    );
    expect(find.text('1 commit a mais que a main'), findsOneWidget);
    final painter =
        tester.widget<CustomPaint>(lanes).painter! as GraphRowPainter;
    expect(painter.highlight, 43);
    await mouse.moveTo(const Offset(1400, 10));
    await tester.pump();
    expect(find.byKey(const ValueKey('graph-balloon')), findsNothing);
  });

  testWidgets('R8 · a merged spec: when and where it went', (tester) async {
    final c = await loaded(tester);
    c.toggleGroup(42);
    final b = laneBalloon('spec/042-sprints', c);
    expect(b.detail, '1 filha · 3 commits a mais que a main');
    expect(b.merged, startsWith('Mergeada na main em '));
    expect(b.merged, endsWith('(PR #94)'));
    final t = laneBalloon('spec/042-t1-dados', c);
    expect(t.detail, 'SPEC-042 T1 · 1 commit a mais que a main');
    expect(t.merged, contains('em spec/042-sprints'));
  });

  testWidgets('R9 extension point: a badge beside the author', (tester) async {
    final c = await loaded(tester);
    await pumpTab(
      tester,
      c,
      badge: (context, commit) => commit.subject.startsWith('docs: SPEC-043')
          ? const Text('sonnet', key: ValueKey('badge'))
          : null,
    );
    expect(find.byKey(const ValueKey('badge')), findsOneWidget);
  });

  test('CI of the checks: a failure wins, then one running', () {
    expect(ciStateOf([]), CiState.none);
    expect(ciStateOf(['SUCCESS', 'SKIPPED']), CiState.passed);
    expect(ciStateOf(['SUCCESS', 'PENDING']), CiState.running);
    expect(ciStateOf(['PENDING', 'FAILURE']), CiState.failed);
    expect(rollupState({'status': 'QUEUED'}), 'PENDING');
    expect(rollupState({'state': 'ERROR'}), 'ERROR');
  });

  test('the babysitter wins over gh pr list for the PRs it follows', () {
    final s = sessionOn(
      's1',
      'spec/043-x',
    ).copyWith(prUrl: const Value('https://github.com/o/r/pull/7'));
    final prs = mergePrSources(
      const [
        GhOpenPr(
          number: 7,
          url: 'u',
          headRefName: 'spec/043-x',
          ci: CiState.running,
        ),
        GhOpenPr(
          number: 8,
          url: 'v',
          headRefName: 'feat/y',
          ci: CiState.passed,
        ),
      ],
      [s],
      {
        's1': const PrWatch(
          status: PrStatus(state: 'OPEN', checks: [('build', 'FAILURE')]),
        ),
      },
    );
    expect(prs['spec/043-x']!.ci, CiState.failed);
    expect(prs['spec/043-x']!.sessionId, 's1');
    expect(prs['feat/y']!.label, '#8 · CI passou');
    expect(prs['feat/y']!.sessionId, isNull);
  });

  test('relative dates', () {
    final now = DateTime(2026, 11, 7, 12);
    expect(graphDate(now.subtract(const Duration(seconds: 20)), now), 'agora');
    expect(
      graphDate(now.subtract(const Duration(minutes: 5)), now),
      'há 5 min',
    );
    expect(graphDate(now.subtract(const Duration(hours: 2)), now), 'há 2 h');
    expect(graphDate(DateTime(2026, 11, 5, 9), now), '5 nov');
    expect(graphDate(DateTime(2025, 3, 1), now), '1 mar 2025');
    expect(formatThousands(1284), '1.284');
    expect(shortRef('spec/043-conflito-resolvido'), 'spec/043-conflito-r…');
  });
}
