import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart';
import '../../../core/git/git_service.dart';
import '../repository_info.dart';
import 'release_timeline.dart';
import 'unreleased.dart';

/// Why Criar release is off, and the command that solves it (SPEC-044 R9).
@immutable
class GhBlocker {
  const GhBlocker(this.reason, {this.fix});

  final String reason;

  /// `gh auth login` (null = nothing to type).
  final String? fix;
}

/// The blocker of [repo] with [auth] (null = the dispatch can run).
GhBlocker? ghBlockerOf(RepositoryInfo repo, GhAuth auth) {
  if (repo.remote == null) {
    return const GhBlocker(
      'O repositório não tem remoto no GitHub.',
      fix: 'git remote add origin git@github.com:dono/repo.git',
    );
  }
  if (repo.githubSlug == null) {
    return GhBlocker(
      'O remoto ${repo.remote} não está no GitHub: a release só é '
      'disparada no GitHub.',
    );
  }
  if (!auth.installed) {
    return const GhBlocker(
      'O gh (GitHub CLI) não está instalado.',
      fix: 'https://cli.github.com',
    );
  }
  if (!auth.loggedIn) {
    return const GhBlocker(
      'O gh não tem login no GitHub.',
      fix: 'gh auth login',
    );
  }
  return null;
}

/// Everything the Releases tab shows.
@immutable
class ReleasesData {
  const ReleasesData({
    required this.repo,
    required this.auth,
    required this.timeline,
    required this.unreleased,
    this.blocker,
    this.releasesError,
  });

  final RepositoryInfo repo;
  final GhAuth auth;

  /// Null = Criar release can run.
  final GhBlocker? blocker;
  final List<ReleaseEntry> timeline;
  final Unreleased unreleased;

  /// `gh` failed to list the releases (the local tags are still shown).
  final String? releasesError;

  bool get readOnly => blocker != null;

  /// Every tag known here or on GitHub (R5: a version must be new).
  Set<String> get existingTags => {for (final e in timeline) e.tag};
}

/// The ref of the default branch: the remote's copy when there is one.
Future<String> branchRefOf(GitService git, RepositoryInfo repo) async {
  final remote = repo.remote;
  if (remote != null &&
      await git.resolveRef('refs/remotes/$remote/${repo.defaultBranch}') !=
          null) {
    return 'refs/remotes/$remote/${repo.defaultBranch}';
  }
  if (await git.resolveRef('refs/heads/${repo.defaultBranch}') != null) {
    return 'refs/heads/${repo.defaultBranch}';
  }
  return 'HEAD';
}

/// Reads tags, releases and the unreleased commits of [repo] (no cache of
/// its own: they are few, and reading on open avoids stale data).
Future<ReleasesData> loadReleases(
  RepositoryInfo repo, {
  required GitService git,
  required GhCli gh,
  required CliRunner cliff,
  DateTime? today,
}) async {
  final auth = await gh.ghAuthStatus();
  final blocker = ghBlockerOf(repo, auth);
  final tags = await readLocalTags(git);
  var releases = const <GhRelease>[];
  String? error;
  if (blocker == null) {
    try {
      releases = await gh.releaseList();
    } on GhException catch (e) {
      error = '$e';
    }
  }
  final timeline = await loadTimeline(git, tags: tags, releases: releases);
  final local = [
    for (final e in timeline)
      if (e.hasLocalTag) e,
  ];
  final unreleased = await loadUnreleased(
    root: repo.path,
    git: git,
    branch: repo.defaultBranch,
    branchRef: await branchRefOf(git, repo),
    lastTag: local.firstOrNull?.tag,
    cliff: cliff,
    today: today,
  );
  return ReleasesData(
    repo: repo,
    auth: auth,
    blocker: blocker,
    timeline: timeline,
    unreleased: unreleased,
    releasesError: error,
  );
}

/// [ReleasesData] of a repository. Invalidate to read again.
final releasesProvider = FutureProvider.autoDispose
    .family<ReleasesData, RepositoryInfo>(
      (ref, repo) => loadReleases(
        repo,
        git: ref.watch(gitServiceFactoryProvider)(repo.path),
        gh: ref.watch(ghCliFactoryProvider)(repo.path),
        cliff: ref.watch(cliRunnerProvider),
      ),
    );
