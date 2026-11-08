import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/repository/repository_info.dart';
import 'package:promptorium/features/repository/repository_screen.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/git_test_utils.dart';

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
}
