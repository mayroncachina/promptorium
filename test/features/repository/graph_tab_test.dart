import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:promptorium/features/repository/graph/graph_watcher.dart';
import 'package:promptorium/features/board/board_screen.dart'
    show boardSelectedSpecProvider;
import 'package:promptorium/features/repository/releases/releases_state.dart';
import 'package:promptorium/features/repository/releases/releases_tab.dart';
import 'package:promptorium/features/repository/repository_info.dart';
import 'package:promptorium/features/repository/repository_screen.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/git_test_utils.dart';
import 'commit_log_test.dart' show buildHistory, commitIn;
import 'fake_gh.dart';

class _Settings extends AppSettingsController {
  @override
  Map<String, String> build() => {};

  @override
  Future<void> set(String key, String value) async =>
      state = {...state, key: value};
}

Spec specRow(int id, String code, String title) => Spec(
  hasPlan: false,
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

/// Taps [key] with real time, so the git the tap starts can finish.
Future<void> tapAndLoad(
  WidgetTester tester,
  GraphController c,
  ValueKey<String> key,
) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(key));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (var i = 0; i < 200 && c.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pump();
}

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
            body: GraphTab(repo: info(), controller: c, watchRefs: false),
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

  group('R6 · filters and search', () {
    testWidgets('only the default branch, one commit per merge', (
      tester,
    ) async {
      final c = await loaded(tester);
      await pumpTab(tester, c);
      await tapAndLoad(tester, c, const ValueKey('graph-scope-defaultBranch'));
      expect(c.query.scope, GraphScope.defaultBranch);
      expect(c.rows.map((r) => c.commit(r.sha)!.subject), [
        'Merge pull request #94 from o/spec/042-sprints',
        'fix: na main',
        'inicial',
      ]);
      expect(find.text('Só a main'), findsOneWidget);
      expect(find.text('3 de 3 commits'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('open specs: the default branch and the spec branches not '
        'merged', (tester) async {
      await tester.runAsync(() async {
        await gitIn(repo, ['checkout', '-q', '-b', 'feat/solta']);
        await commitIn(repo, 'feat: fora das specs');
        await gitIn(repo, ['checkout', '-q', 'main']);
      });
      final c = await loaded(tester);
      expect(
        c.rows.any((r) => c.commit(r.sha)!.subject == 'feat: fora das specs'),
        isTrue,
      );
      await tester.runAsync(() => c.setScope(GraphScope.openSpecs));
      await pumpTab(tester, c);
      final subjects = c.rows.map((r) => c.commit(r.sha)!.subject).toList();
      expect(subjects.first, 'docs: SPEC-043, conflito');
      expect(subjects, isNot(contains('feat: fora das specs')));
    });

    testWidgets('remote branches without a local copy only when asked', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await gitIn(repo, ['checkout', '-q', '-b', 'feat/remota']);
        final sha = await commitIn(repo, 'feat: só no remoto');
        await gitIn(repo, ['checkout', '-q', 'main']);
        await gitIn(repo, [
          'update-ref',
          'refs/remotes/origin/feat/remota',
          sha,
        ]);
        await gitIn(repo, ['branch', '-q', '-D', 'feat/remota']);
      });
      final c = await loaded(tester);
      await pumpTab(tester, c);
      expect(find.text('feat: só no remoto'), findsNothing);
      await tapAndLoad(tester, c, const ValueKey('graph-remote-only'));
      expect(c.query.remoteOnly, isTrue);
      expect(find.text('feat: só no remoto'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('graph-branch-origin/feat/remota')),
        findsOneWidget,
      );
    });

    testWidgets('search by SPEC-NNN, SHA and author; Enter goes to the next '
        'result', (tester) async {
      final c = await loaded(tester);
      await pumpTab(tester, c);
      await tester.enterText(
        find.byKey(const ValueKey('graph-search')),
        'SPEC-042',
      );
      await tester.pump();
      // The collapsed spec and the merge of its PR.
      expect(find.text('1 de 2 · Enter'), findsOneWidget);
      final first = c.currentMatchRow!;
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('2 de 2 · Enter'), findsOneWidget);
      expect(c.currentMatchRow, isNot(first));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(c.currentMatchRow, first);
      final sha = c.commit(c.rows.last.sha)!.sha.substring(0, 8);
      await tester.enterText(find.byKey(const ValueKey('graph-search')), sha);
      await tester.pump();
      expect(c.matches, [c.rows.length - 1]);
      await tester.enterText(
        find.byKey(const ValueKey('graph-search')),
        'teste',
      );
      await tester.pump();
      expect(c.matches.length, c.rows.length - 1);
      await tester.enterText(find.byKey(const ValueKey('graph-search')), 'xyz');
      await tester.pump();
      expect(find.text('nenhum'), findsOneWidget);
    });

    testWidgets('a day only (the Atividade of SPEC-046)', (tester) async {
      final c = await loaded(tester);
      await tester.runAsync(() => c.setDay(DateTime.now()));
      expect(c.rows, isNotEmpty);
      expect(c.query.day, isNotNull);
      await tester.runAsync(
        () => c.setDay(DateTime.now().subtract(const Duration(days: 3))),
      );
      await pumpTab(tester, c);
      expect(c.rows, isEmpty);
      expect(find.text('Nenhum commit neste dia.'), findsOneWidget);
      expect(find.byKey(const ValueKey('graph-day')), findsOneWidget);
    });

    testWidgets('openGraph asks the tab for a search and a commit', (
      tester,
    ) async {
      final c = await loaded(tester);
      final target = c.rows.first.sha;
      await tester.runAsync(() => c.loadDetails(target));
      final container = await pumpTab(tester, c);
      container
          .read(graphRequestProvider.notifier)
          .request(GraphRequest(search: 'SPEC-043', select: target));
      await tester.pump();
      await tester.pump();
      expect(container.read(graphRequestProvider), isNull);
      expect(find.text('1 de 1 · Enter'), findsOneWidget);
      expect(c.selected, target);
      expect(find.byKey(const ValueKey('graph-commit-panel')), findsOneWidget);
    });
  });

  group('R5 · the commit panel', () {
    testWidgets('message, parents, what contains it, spec, PR and the files '
        'with +/−', (tester) async {
      final c = await loaded(tester);
      final merge = c.rows.firstWhere(
        (r) => c.commit(r.sha)!.subject.contains('#94'),
      );
      await tester.runAsync(() => c.loadDetails(merge.sha));
      final container = await pumpTab(
        tester,
        c,
        sessions: [sessionOn('s9', 'spec/042-sprints')],
      );
      await tester.tap(
        find.text('Merge pull request #94 from o/spec/042-sprints'),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('graph-commit-panel')), findsOneWidget);
      final commit = c.commit(merge.sha)!;
      expect(find.text(commit.shortSha), findsWidgets);
      final parents = tester
          .widget<Wrap>(find.byKey(const ValueKey('graph-panel-parents')))
          .children;
      expect(parents, hasLength(2));
      final inPanel = tester
          .widget<Text>(find.byKey(const ValueKey('graph-panel-contains')))
          .data!;
      expect(inPanel, contains('main'));
      expect(inPanel, contains('spec/043-conflito'));
      expect(inPanel, contains('v0.1.0'));
      expect(find.text('ARQUIVOS · 2 · +2 −0'), findsOneWidget);
      expect(find.text('SPEC-042 · Sprints no Quadro'), findsOneWidget);
      expect(find.text('#94 · mergeado'), findsOneWidget);
      // The list goes compact: no spec nor author column.
      expect(find.text('AUTOR'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('graph-open-review')));
      await tester.pump();
      expect(container.read(selectedReviewProvider), 's9');
      expect(container.read(navigationProvider), AppSection.review);
      await tester.tap(find.byKey(const ValueKey('graph-open-board')));
      await tester.pump();
      expect(container.read(boardSelectedSpecProvider), 1);
      expect(container.read(navigationProvider), AppSection.tasks);
    });

    testWidgets('"Ver diferença" opens the diff of the file', (tester) async {
      final c = await loaded(tester);
      final row = c.rows.firstWhere(
        (r) => c.commit(r.sha)!.subject == 'docs: SPEC-043, conflito',
      );
      await tester.runAsync(() => c.loadDetails(row.sha));
      await pumpTab(tester, c);
      c.select(row.sha);
      await tester.pump();
      final path = c.details(row.sha)!.files.single.path;
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey('graph-diff-$path')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('graph-diff-dialog')), findsOneWidget);
      expect(find.text('docs: SPEC-043, conflito'), findsWidgets);
    });

    testWidgets('Copiar SHA and closing the panel', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      final c = await loaded(tester);
      final row = c.rows.first;
      await tester.runAsync(() => c.loadDetails(row.sha));
      await pumpTab(tester, c);
      c.select(row.sha);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('graph-copy-sha')));
      await tester.pump();
      expect(copied, row.sha);
      expect(find.text('SHA copiado.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('graph-panel-close')));
      await tester.pump();
      expect(c.selected, isNull);
      expect(find.byKey(const ValueKey('graph-commit-panel')), findsNothing);
    });

    test('numstat with binaries and renames', () {
      expect(
        parseNumstat(
          '3\t1\tlib/a.dart\n-\t-\tlogo.png\n2\t0\tlib/{x => y}/b.dart\n'
          '1\t1\told.txt => new.txt\n',
        ).map((f) => (f.path, f.added, f.removed)),
        [
          ('lib/a.dart', 3, 1),
          ('logo.png', null, null),
          ('lib/y/b.dart', 2, 0),
          ('new.txt', 1, 1),
        ],
      );
    });
  });

  group('R7 · live update', () {
    testWidgets('a new commit appears without losing the selection nor the '
        'rows on screen', (tester) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 40; i++) {
          await commitIn(repo, 'chore: passo $i');
        }
      });
      final c = await loaded(tester);
      await pumpTab(tester, c);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('graph-list')),
          matching: find.byType(Scrollable),
        ),
      );
      scrollable.position.jumpTo(4 + 20 * graphRowHeight);
      await tester.pump();
      final anchor = c.rows[20].sha;
      final selected = c.rows[22].sha;
      await tester.runAsync(() => c.loadDetails(selected));
      c.select(selected);
      await tester.pump();

      await tester.runAsync(() async {
        await gitIn(repo, ['checkout', '-q', 'spec/043-conflito']);
        File('$repo/mais.txt').writeAsStringSync('mais');
        await gitIn(repo, ['add', 'mais.txt']);
        // A minute ahead, so it is the newest commit of the log.
        final r = await Process.run(
          'git',
          ['-C', repo, 'commit', '-q', '-m', 'docs: SPEC-043, mais um'],
          environment: {
            'GIT_COMMITTER_DATE': DateTime.now()
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          },
        );
        expect(r.exitCode, 0);
        await gitIn(repo, ['checkout', '-q', 'main']);
        await tester.state<GraphTabState>(find.byType(GraphTab)).refresh();
      });
      await tester.pump();
      expect(c.commit(c.rows.first.sha)!.subject, 'docs: SPEC-043, mais um');
      expect(c.selected, selected);
      expect(find.byKey(const ValueKey('graph-commit-panel')), findsOneWidget);
      final p = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const ValueKey('graph-list')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final top = ((p.pixels - 4) / graphRowHeight).round();
      expect(c.rows[top].sha, anchor);
    });

    test('the watcher reacts to a new ref, not to the index', () async {
      final gitDir = (await gitIn(repo, [
        'rev-parse',
        '--absolute-git-dir',
      ])).trim();
      final changed = Completer<void>();
      final w = GraphRefsWatcher(
        gitDir,
        debounce: const Duration(milliseconds: 50),
        onChange: () {
          if (!changed.isCompleted) changed.complete();
        },
      );
      addTearDown(w.close);
      expect(w.isRefChange('$gitDir/index'), isFalse);
      expect(w.isRefChange('$gitDir/refs/heads/x.lock'), isFalse);
      expect(w.isRefChange('$gitDir/refs/stash'), isFalse);
      expect(w.isRefChange('$gitDir/refs/promptorium/SPEC-1/a'), isFalse);
      expect(w.isRefChange('$gitDir/HEAD'), isTrue);
      expect(w.isRefChange('$gitDir/refs/heads/spec/050-x'), isTrue);
      expect(w.dirs(), contains('$gitDir/refs/heads/spec'));
      await gitIn(repo, ['branch', 'spec/099-nova']);
      await changed.future.timeout(const Duration(seconds: 5));
    });
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
