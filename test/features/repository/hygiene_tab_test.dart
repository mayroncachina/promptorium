import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/repository/hygiene/hygiene_scan.dart';
import 'package:promptorium/features/repository/hygiene/hygiene_state.dart';
import 'package:promptorium/features/repository/hygiene/hygiene_tab.dart';
import 'package:promptorium/features/repository/releases/releases_state.dart';
import 'package:promptorium/features/repository/repository_info.dart';
import 'package:promptorium/features/repository/repository_screen.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import 'fake_gh.dart';
import 'hygiene_fixture.dart';

class _Settings extends AppSettingsController {
  _Settings(this.initial);

  final Map<String, String> initial;

  @override
  Map<String, String> build() => initial;

  @override
  Future<void> set(String key, String value) async =>
      state = {...state, key: value};
}

class _Summary extends HygieneSummary {
  _Summary(super.path, this.count);

  final int count;

  @override
  Future<int?> build() async => count;
}

Workspace _ws(String path) =>
    Workspace(id: 1, path: path, name: 'repo', createdAt: DateTime(2026));

HygieneContext _context(HygieneFixture f) => HygieneContext(
  liveBranches: {'wt/vivo'},
  liveWorktrees: {f.wt('wt-vivo')},
  sessionByBranch: {'feat/conflito': 'sessao-1'},
  refKeys: {
    'SPEC-001': RefKeyInfo(closed: true, mergedAt: DateTime(2026, 10, 24)),
    'SPEC-002': const RefKeyInfo(closed: false),
  },
);

Future<HygieneReport> _scan(HygieneFixture f) => scanHygiene(
  git: GitService(f.repo),
  repoPath: f.repo,
  defaultBranch: 'main',
  remote: 'origin',
  gh: GhCli((FakeGh()..mergedPrs = f.mergedPrs).call, cwd: f.repo),
  context: _context(f),
);

/// Pumps until [done]: the tab's git runs synchronously in these tests
/// ([_syncGit]), so a few frames are enough.
Future<void> settleGit(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: 'git did not finish');
}

/// Real git, run synchronously: async process I/O doesn't finish under the
/// widget tests' fake clock.
GitService _syncGit(String root) =>
    GitService(root, run: (exe, args) async => Process.runSync(exe, args));

void main() {
  late Directory tmp;
  late HygieneFixture f;
  late HygieneReport report;
  late RepositoryInfo info;
  late ProviderContainer container;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-aba-higiene-');
    f = await HygieneFixture.create(tmp);
    report = await _scan(f);
    info = RepositoryInfo(
      path: f.repo,
      defaultBranch: 'main',
      remote: 'origin',
      remoteUrl: 'git@github.com:o/r.git',
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pump(WidgetTester tester, {bool expand = true}) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            () => _Settings({'repo.tab': 'higiene'}),
          ),
          activeWorkspaceProvider.overrideWithValue(_ws(f.repo)),
          repositoryInfoProvider.overrideWith((ref, path) async => info),
          cliRunnerProvider.overrideWithValue(FakeGh().call),
          releasesProvider.overrideWith(
            (ref, repo) => Completer<ReleasesData>().future,
          ),
          // The scan ran with real git in setUp (git doesn't run under the
          // fake clock).
          hygieneScannerProvider.overrideWithValue(
            (repo, {light = false}) async => report,
          ),
          hygieneContextProvider.overrideWithValue(() async => _context(f)),
          gitServiceFactoryProvider.overrideWithValue(_syncGit),
          hygieneSummaryProvider.overrideWith2((p) => _Summary(p, 0)),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(body: RepositoryScreen()),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    // Every merged branch on screen (the fixture has 6, the preview 5).
    if (expand) {
      await tester.tap(key('hygiene-merged-more'));
      await tester.pump();
    }
  }

  Checkbox box(WidgetTester tester, String k) => tester.widget<Checkbox>(
    find.descendant(of: key(k), matching: find.byType(Checkbox)).first,
  );

  testWidgets('R1 · the tab after Releases, with the counter of everything '
      'it found', (tester) async {
    await pump(tester);
    expect(repositoryTabs.map((t) => t.id).take(2), ['releases', 'higiene']);
    expect(key('repo-tab-body-higiene'), findsOneWidget);
    expect(
      find.descendant(
        of: key('repo-tab-count-higiene'),
        matching: find.text('${report.total}'),
      ),
      findsOneWidget,
    );
    expect(key('hygiene-merged'), findsOneWidget);
    expect(key('hygiene-worktrees'), findsOneWidget);
    expect(key('hygiene-behind'), findsOneWidget);
    expect(key('hygiene-refs'), findsOneWidget);
    expect(
      tester.widget<Text>(key('hygiene-summary')).data,
      contains('branches mergeadas'),
    );
  });

  testWidgets('R6 · protected items are dimmed with the reason and cannot '
      'be selected', (tester) async {
    await pump(tester, expand: false);
    expect(find.text('Mostrar as outras 1'), findsOneWidget);
    await tester.tap(key('hygiene-merged-more'));
    await tester.pump();
    expect(box(tester, 'hygiene-branch-wt/sujo').onChanged, isNull);
    expect(
      tester.widget<Text>(key('hygiene-branch-meta-wt/sujo')).data,
      startsWith('worktree em'),
    );
    expect(box(tester, 'hygiene-branch-feat/mergeada').onChanged, isNotNull);
    final sujo = 'hygiene-worktree-${f.wt('wt-sujo')}';
    expect(box(tester, sujo).onChanged, isNull);
    expect(
      find.descendant(
        of: key(sujo),
        matching: find.text('alterações não commitadas'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: key(sujo), matching: find.byType(Opacity)),
      findsWidgets,
    );
  });

  testWidgets('selection: a worktree carries the merged branch it holds', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(key('hygiene-branch-box-feat/mergeada'));
    await tester.pump();
    expect(find.text('Limpar selecionados (1)'), findsOneWidget);
    final fechado = 'hygiene-worktree-${f.wt('wt-fechado')}';
    await tester.tap(
      find.descendant(of: key(fechado), matching: find.byType(Checkbox)),
    );
    await tester.pump();
    expect(find.text('Limpar selecionados (3)'), findsOneWidget);
    final s = container.read(hygieneProvider(info));
    expect(
      s.selectedBranches.map((b) => b.name),
      containsAll(['feat/mergeada', 'wt/fechado']),
    );
  });

  testWidgets('R4 · behind and ahead with the conflict, "Abrir no Review" '
      'and nothing to delete', (tester) async {
    await pump(tester);
    expect(key('hygiene-conflict-feat/conflito'), findsOneWidget);
    expect(find.text('Conflito previsto em a.txt'), findsOneWidget);
    expect(
      find.descendant(
        of: key('hygiene-behind'),
        matching: find.byType(Checkbox),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: key('hygiene-behind-feat/aberta'),
        matching: find.text('Sem conflito previsto'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('à frente'), findsNWidgets(2));
    await tester.tap(key('hygiene-review-feat/conflito'));
    await tester.pump();
    expect(container.read(selectedReviewProvider), 'sessao-1');
    expect(container.read(navigationProvider), AppSection.review);
  });

  testWidgets('R6 · R7 · the confirmation lists what goes, the remote only '
      'with its own box, then "Desfazer"', (tester) async {
    await pump(tester);
    await tester.tap(key('hygiene-branch-box-feat/mergeada'));
    await tester.tap(key('hygiene-remote-box-feat/mergeada'));
    await tester.pump();
    await tester.tap(key('hygiene-clean'));
    await tester.pumpAndSettle();
    expect(key('hygiene-confirm'), findsOneWidget);
    expect(find.text('Limpar 1 item?'), findsOneWidget);
    expect(find.text('BRANCHES LOCAIS · 1 · git branch -d'), findsOneWidget);
    expect(find.textContaining('origin/feat/mergeada'), findsOneWidget);
    expect(box(tester, 'hygiene-confirm-remote').value, isFalse);

    // Confirmed without the remote box: real git runs outside the fake clock.
    await tester.tap(key('hygiene-confirm-ok'));
    await settleGit(
      tester,
      () => container.read(hygieneProvider(info)).lastCleanup != null,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      await tester.runAsync(
        () => GitService(f.repo).resolveRef('refs/heads/feat/mergeada'),
      ),
      isNull,
    );
    expect(
      await tester.runAsync(
        () => GitService(f.origin).resolveRef('refs/heads/feat/mergeada'),
      ),
      isNotNull,
      reason: 'the remote stays without the box',
    );
    expect(find.text('1 branch removido'), findsOneWidget);
    expect(key('hygiene-undo'), findsOneWidget);
    expect(find.text('Desfazer · 15 s'), findsOneWidget);

    await tester.tap(key('hygiene-undo'));
    await settleGit(
      tester,
      () => find.byKey(const ValueKey('hygiene-undone')).evaluate().isNotEmpty,
    );
    expect(
      await tester.runAsync(
        () => GitService(f.repo).resolveRef('refs/heads/feat/mergeada'),
      ),
      isNotNull,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('cancelling the confirmation deletes nothing', (tester) async {
    await pump(tester);
    await tester.tap(key('hygiene-branch-box-feat/mergeada'));
    await tester.pump();
    await tester.tap(key('hygiene-clean'));
    await tester.pumpAndSettle();
    await tester.tap(key('hygiene-confirm-cancel'));
    await tester.pumpAndSettle();
    expect(key('hygiene-confirm'), findsNothing);
    expect(container.read(hygieneProvider(info)).lastCleanup, isNull);
  });

  group('R8 · Início card', () {
    final now = DateTime(2026, 11, 7, 12);

    Future<ProviderContainer> pumpCard(
      WidgetTester tester, {
      required int count,
      Map<String, String> settings = const {},
    }) async {
      late ProviderContainer c;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(() => _Settings({...settings})),
            repositoryInfoProvider.overrideWith(
              (ref, path) async =>
                  const RepositoryInfo(path: '/r', defaultBranch: 'main'),
            ),
            hygieneSummaryProvider.overrideWith2((p) => _Summary(p, count)),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              c = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: AppTheme.dark(),
                home: Scaffold(
                  body: HygieneHomeCard(workspacePath: '/r', now: () => now),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return c;
    }

    testWidgets('shows above 20 items and leads to the tab', (tester) async {
      await pumpCard(tester, count: 20);
      expect(key('home-hygiene'), findsNothing);
      final c = await pumpCard(tester, count: 31);
      expect(find.text('Repositório com 31 itens para limpar'), findsOneWidget);
      await tester.tap(key('home-hygiene'));
      await tester.pump();
      expect(c.read(navigationProvider), AppSection.repository);
      expect(c.read(repositoryTabProvider), 'higiene');
    });

    testWidgets('dismissed for 30 days', (tester) async {
      final c = await pumpCard(tester, count: 31);
      await tester.tap(key('home-hygiene-dismiss'));
      await tester.pump();
      expect(key('home-hygiene'), findsNothing);
      final until = DateTime.parse(
        c.read(appSettingsProvider)[hygieneDismissKey('/r')]!,
      );
      expect(until, now.add(const Duration(days: 30)));
      expect(
        hygieneDismissed(
          c.read(appSettingsProvider),
          '/r',
          now.add(const Duration(days: 29)),
        ),
        isTrue,
      );
      expect(
        hygieneDismissed(
          c.read(appSettingsProvider),
          '/r',
          now.add(const Duration(days: 31)),
        ),
        isFalse,
      );
      // After 30 days it comes back.
      await pumpCard(
        tester,
        count: 31,
        settings: {
          hygieneDismissKey('/r'): now
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        },
      );
      expect(key('home-hygiene'), findsOneWidget);
    });
  });
}
