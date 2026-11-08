import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_root.dart';
import '../../core/git/git_service.dart';
import '../project/project_config.dart';

/// The main repository of a workspace, as the Repositório screen shows it
/// in its header (SPEC-044 R1): `promptorium · origin · main`.
@immutable
class RepositoryInfo {
  const RepositoryInfo({
    required this.path,
    required this.defaultBranch,
    this.remote,
    this.remoteUrl,
  });

  /// Root of the main repository (never a worktree).
  final String path;

  /// Branch the releases come from (`main`).
  final String defaultBranch;

  /// Remote name (`origin`); null without a remote.
  final String? remote;

  /// URL of [remote] (`git@github.com:o/r.git`).
  final String? remoteUrl;

  String get name => folderName(path);

  /// `owner/repo` when the remote is on GitHub (null otherwise).
  String? get githubSlug => githubSlugOf(remoteUrl);

  /// `promptorium · origin · main`.
  String get headline => [name, ?remote, defaultBranch].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is RepositoryInfo &&
      other.path == path &&
      other.defaultBranch == defaultBranch &&
      other.remote == remote &&
      other.remoteUrl == remoteUrl;

  @override
  int get hashCode => Object.hash(path, defaultBranch, remote, remoteUrl);
}

/// `owner/repo` of a GitHub remote URL (`https://github.com/o/r(.git)`,
/// `git@github.com:o/r.git`, `ssh://git@github.com/o/r`); null otherwise.
String? githubSlugOf(String? url) {
  if (url == null) return null;
  final m = RegExp(r'github\.com[:/]+([^/\s]+)/([^/\s]+?)(?:\.git)?/?$')
      .firstMatch(url.trim());
  return m == null ? null : '${m.group(1)}/${m.group(2)}';
}

/// Reads [RepositoryInfo] of the workspace at [workspacePath]: the main
/// repository behind a worktree, the remote (`origin` first) and the default
/// branch (the remote's HEAD, then `branch-base:` of the config, then
/// `main` / `master`, then the current branch).
Future<RepositoryInfo> readRepositoryInfo(
  String workspacePath,
  GitService Function(String root) gitFor, {
  String? configuredBase,
}) async {
  var root = workspacePath;
  try {
    final common = (await gitFor(
      workspacePath,
    ).git(['rev-parse', '--path-format=absolute', '--git-common-dir'])).trim();
    if (common.endsWith('/.git')) {
      root = common.substring(0, common.length - '/.git'.length);
    }
  } on GitException {
    // Not a repository (or an old git): the workspace itself.
  }
  final git = gitFor(root);
  String? remote;
  try {
    final remotes = [
      for (final l in (await git.git(['remote'])).split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    remote = remotes.contains('origin') ? 'origin' : remotes.firstOrNull;
  } on GitException {
    remote = null;
  }
  String? url;
  String? branch;
  if (remote != null) {
    try {
      url = (await git.git(['remote', 'get-url', remote])).trim();
    } on GitException {
      url = null;
    }
    try {
      final head = (await git.git([
        'symbolic-ref',
        '--short',
        'refs/remotes/$remote/HEAD',
      ])).trim();
      if (head.startsWith('$remote/'))
        branch = head.substring(remote.length + 1);
    } on GitException {
      branch = null;
    }
  }
  if (branch == null && configuredBase != null) branch = configuredBase;
  if (branch == null) {
    for (final b in ['main', 'master']) {
      if (await git.resolveRef('refs/heads/$b') != null) {
        branch = b;
        break;
      }
    }
  }
  try {
    branch ??= await git.currentBranch();
  } on GitException {
    branch = null;
  }
  return RepositoryInfo(
    path: root,
    defaultBranch: branch ?? 'main',
    remote: remote,
    remoteUrl: url,
  );
}

/// [RepositoryInfo] of a workspace (by path). Invalidate to read it again.
final repositoryInfoProvider = FutureProvider.family<RepositoryInfo, String>((
  ref,
  workspacePath,
) async {
  final config = await ref.watch(projectConfigProvider(workspacePath).future);
  return readRepositoryInfo(
    workspacePath,
    ref.watch(gitServiceFactoryProvider),
    configuredBase: config.baseBranch,
  );
});
