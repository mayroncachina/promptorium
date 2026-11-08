import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/features/repository/releases/release_timeline.dart';
import 'package:promptorium/features/repository/releases/releases_state.dart';
import 'package:promptorium/features/repository/releases/releases_tab.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';
import 'package:promptorium/features/repository/repository_info.dart';
import 'package:promptorium/features/repository/repository_screen.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/git_test_utils.dart';
import 'fake_gh.dart';
import 'release_timeline_test.dart' show commit;

class _Settings extends AppSettingsController {
  _Settings(this.initial);

  final Map<String, String> initial;

  @override
  Map<String, String> build() => initial;

  @override
  Future<void> set(String key, String value) async =>
      state = {...state, key: value};
}

Workspace workspaceAt(String path) =>
    Workspace(id: 1, path: path, name: 'repo', createdAt: DateTime(2026));

void main() {
  late Directory tmp;
  late String repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-repo-');
    repo = await createRepo(tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('R1 · Repositório in the sidebar', () {
    test('comes after Review, Ctrl+0 is the tenth item and the layout '
        'version went up (the shell shows the notice once)', () {
      final items = AppSection.navItems;
      expect(
        items.indexOf(AppSection.repository),
        items.indexOf(AppSection.review) + 1,
      );
      expect(AppSection.repository.label, 'Repositório');
      expect(AppSection.repository.shortcutLabel, 'Ctrl 7');
      expect(items.length, 10);
      expect(items.last.shortcutLabel, 'Ctrl 0');
      expect(AppSection.shortcutsVersion, 4);
    });

    test('the main repository, never a worktree, with the remote and the '
        'default branch', () async {
      final origin = await createRepo(tmp, name: 'origin');
      await gitIn(repo, ['remote', 'add', 'origin', origin]);
      await gitIn(repo, ['fetch', '-q', 'origin']);
      await gitIn(repo, [
        'symbolic-ref',
        'refs/remotes/origin/HEAD',
        'refs/remotes/origin/main',
      ]);
      await gitIn(repo, ['worktree', 'add', '-q', '-b', 'feat', '../wt']);
      final info = await readRepositoryInfo(
        '${tmp.path}/wt',
        (root) => GitService(root),
      );
      expect(info.path, repo);
      expect(info.remote, 'origin');
      expect(info.defaultBranch, 'main');
      expect(info.headline, 'repo · origin · main');
    });

    test('without a remote: the configured base, then main', () async {
      GitService git(String root) => GitService(root);
      expect((await readRepositoryInfo(repo, git)).headline, 'repo · main');
      expect(
        (await readRepositoryInfo(
          repo,
          git,
          configuredBase: 'trunk',
        )).defaultBranch,
        'trunk',
      );
    });

    test('GitHub slug of the remote URL', () {
      expect(githubSlugOf('git@github.com:o/r.git'), 'o/r');
      expect(githubSlugOf('https://github.com/o/r'), 'o/r');
      expect(githubSlugOf('ssh://git@github.com/o/r.git'), 'o/r');
      expect(githubSlugOf('git@gitlab.com:o/r.git'), isNull);
      expect(githubSlugOf(null), isNull);
    });

    testWidgets('the screen shows the header and the Releases tab', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final info = RepositoryInfo(
        path: repo,
        defaultBranch: 'main',
        remote: 'origin',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(() => _Settings({})),
            activeWorkspaceProvider.overrideWithValue(workspaceAt(repo)),
            repositoryInfoProvider.overrideWith((ref, path) async => info),
            cliRunnerProvider.overrideWithValue(FakeGh().call),
            // Real git doesn't run under the fake clock: the tab loads.
            releasesProvider.overrideWith(
              (ref, repo) => Completer<ReleasesData>().future,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: RepositoryScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Repositório'), findsOneWidget);
      expect(find.text('repo · origin · main'), findsOneWidget);
      expect(find.byKey(const ValueKey('repo-tab-releases')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('repo-tab-body-releases')),
        findsOneWidget,
      );
    });
  });

  group('R3 · R9 · the tab', () {
    const github = RepositoryInfo(
      path: '/r',
      defaultBranch: 'main',
      remote: 'origin',
      remoteUrl: 'git@github.com:o/r.git',
    );

    Future<ReleasesData> load(FakeGh fake, {String? remoteUrl}) async {
      await gitIn(repo, ['tag', 'v0.11.0']);
      await gitIn(repo, ['checkout', '-q', '-b', 'spec/044-t1-casca']);
      await commit(repo, 'b.txt', 'feat(repo): releases');
      await gitIn(repo, ['checkout', '-q', 'main']);
      await commit(repo, 'c.txt', 'fix(repo): data');
      await gitIn(repo, [
        'merge',
        '--no-ff',
        '-q',
        '-m',
        'Merge pull request #9 from o/spec/044-t1-casca',
        'spec/044-t1-casca',
      ]);
      final info = RepositoryInfo(
        path: repo,
        defaultBranch: 'main',
        remote: 'origin',
        remoteUrl: remoteUrl ?? 'git@github.com:o/r.git',
      );
      return loadReleases(
        info,
        git: GitService(repo),
        gh: GhCli(fake.call, cwd: repo),
        cliff: fake.call,
        today: DateTime(2026, 11, 8),
      );
    }

    Future<void> pumpView(WidgetTester tester, ReleasesData data) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(() => _Settings({})),
            activeWorkspaceProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: ReleasesView(data: data, onCreate: () {}),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    test('the blocker: no remote, not GitHub, no gh, no login', () {
      expect(ghBlockerOf(github, const GhAuth.loggedIn('x')), isNull);
      expect(
        ghBlockerOf(
          const RepositoryInfo(path: '/r', defaultBranch: 'main'),
          const GhAuth.loggedIn('x'),
        )!.reason,
        contains('não tem remoto'),
      );
      expect(
        ghBlockerOf(
          const RepositoryInfo(
            path: '/r',
            defaultBranch: 'main',
            remote: 'origin',
            remoteUrl: 'git@gitlab.com:o/r.git',
          ),
          const GhAuth.loggedIn('x'),
        )!.reason,
        contains('não está no GitHub'),
      );
      expect(
        ghBlockerOf(github, const GhAuth.missing())!.fix,
        'https://cli.github.com',
      );
      expect(
        ghBlockerOf(github, const GhAuth.loggedOut())!.fix,
        'gh auth login',
      );
    });

    testWidgets('card Não lançado: commits, suggested version, specs and '
        'groups; the timeline and the open version', (tester) async {
      final fake = FakeGh()
        ..releases = [
          releaseRow(
            'v0.11.0',
            body:
                '## [0.11.0] - 2026-11-07\n\n### Funcionalidades\n'
                '- **voz:** Ditado por voz (abc1234)\n',
            assets: [('promptorium_0.11.0_amd64.deb', 13533822)],
          ),
        ];
      final data = (await tester.runAsync(() => load(fake)))!;
      expect(data.readOnly, isFalse);
      expect(data.auth.account, 'mayroncachina');
      await pumpView(tester, data);
      expect(find.text('3 commits na main desde v0.11.0'), findsOneWidget);
      expect(
        find.textContaining(
          'Versão sugerida pelos commits: ',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('v0.11.1', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('SPEC-044'), findsOneWidget);
      expect(find.text('Funcionalidades'), findsWidgets);
      expect(find.text('Correções'), findsOneWidget);
      expect(find.byKey(const ValueKey('version-v0.11.0')), findsOneWidget);
      expect(find.text('Publicada · mais recente'), findsOneWidget);
      expect(find.text('Ditado por voz'), findsOneWidget);
      expect(find.text('12,9 MB'), findsOneWidget);
      expect(find.text('1 pacote'), findsOneWidget);
      final create = tester.widget<AmberButton>(
        find.byKey(const ValueKey('releases-create')),
      );
      expect(create.onTap, isNotNull);
      expect(find.byKey(const ValueKey('releases-blocker')), findsNothing);

      // R4: the preview, read-only, with Copiar.
      await tester.tap(find.byKey(const ValueKey('releases-changelog')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('changelog-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('changelog-copy')), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('changelog-text')),
            )
            .data,
        startsWith('## [0.11.1] - 2026-11-08'),
      );
    });

    testWidgets('R9: without login the tab is read-only, says why and the '
        'command that solves it', (tester) async {
      final fake = FakeGh(authed: false);
      final data = (await tester.runAsync(() => load(fake)))!;
      expect(data.readOnly, isTrue);
      // No release list without gh: only the local tags.
      expect(fake.calls.where((c) => c.$2.firstOrNull == 'api'), isEmpty);
      expect(data.timeline.single.state, ReleaseState.tagOnly);
      await pumpView(tester, data);
      final create = tester.widget<AmberButton>(
        find.byKey(const ValueKey('releases-create')),
      );
      expect(create.onTap, isNull);
      expect(find.byKey(const ValueKey('releases-blocker')), findsOneWidget);
      expect(find.textContaining('O gh não tem login'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('releases-blocker-fix')),
            )
            .data,
        'gh auth login',
      );
      // The card and the preview still work.
      expect(find.text('3 commits na main desde v0.11.0'), findsOneWidget);
      expect(
        tester
            .widget<SmallButton>(
              find.byKey(const ValueKey('releases-changelog')),
            )
            .onTap,
        isNotNull,
      );
    });

    testWidgets('R9: without gh, the same', (tester) async {
      final data = (await tester.runAsync(() => load(FakeGh(hasGh: false))))!;
      expect(data.auth.installed, isFalse);
      await pumpView(tester, data);
      expect(find.textContaining('não está instalado'), findsOneWidget);
    });

    testWidgets('nothing new: "Nada novo desde" and the button off', (
      tester,
    ) async {
      final data = (await tester.runAsync(() async {
        await gitIn(repo, ['tag', 'v1.0.0']);
        return loadReleases(
          RepositoryInfo(
            path: repo,
            defaultBranch: 'main',
            remote: 'origin',
            remoteUrl: 'git@github.com:o/r.git',
          ),
          git: GitService(repo),
          gh: GhCli(FakeGh().call, cwd: repo),
          cliff: FakeGh().call,
        );
      }))!;
      await pumpView(tester, data);
      expect(find.text('Nada novo desde v1.0.0'), findsOneWidget);
      expect(
        tester
            .widget<AmberButton>(find.byKey(const ValueKey('releases-create')))
            .onTap,
        isNull,
      );
    });
  });
}
