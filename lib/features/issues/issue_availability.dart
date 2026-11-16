import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/gh_cli.dart';
import '../../core/git/gh_issues.dart';
import '../../core/git/git_service.dart';
import '../../data/db/app_database.dart' show Workspace;
import '../project/project_config.dart';
import '../review/review_host.dart';

/// Why the issues of a workspace cannot be used (SPEC-074 R2), the same
/// diagnosis the Review gives for a PR.
enum IssueProblem {
  noRemote,
  chooseRemote,
  localRemote,
  invalidRemote,
  gitlab,
  otherHost,
  ghMissing,
  ghLoggedOut,
  network,
  issuesDisabled,
  error,
}

/// Whether "Importar issues", "Criar issue", the `Closes #N` and the
/// progress comment can talk to GitHub.
@immutable
class IssueAvailability {
  const IssueAvailability.ok({
    required this.repo,
    this.remote,
    this.defaultBranch,
    this.account,
  }) : available = true,
       problem = null,
       reason = null,
       installUrl = null;

  const IssueAvailability.unavailable(
    this.problem,
    this.reason, {
    this.repo,
    this.remote,
    this.installUrl,
  }) : available = false,
       defaultBranch = null,
       account = null;

  final bool available;
  final IssueProblem? problem;

  /// The tooltip of the disabled button and the text of the dialog.
  final String? reason;

  /// `owner/name` of the repository on GitHub (null when unknown).
  final String? repo;
  final String? remote;

  /// The branch a merge into closes the issue (R8).
  final String? defaultBranch;

  /// Login of the `gh` account.
  final String? account;

  /// `gh` missing: the link of "Como instalar".
  final String? installUrl;

  /// Short title of the problem, for the dialog (R2).
  String get title => switch (problem) {
    null => 'Issues disponíveis',
    IssueProblem.ghMissing => 'O GitHub CLI (gh) não está instalado',
    IssueProblem.ghLoggedOut => 'O gh não está logado em github.com',
    IssueProblem.gitlab => 'Issues do GitLab ainda não',
    IssueProblem.issuesDisabled =>
      'As issues estão desligadas em ${repo ?? 'este repositório'}',
    IssueProblem.noRemote => 'O repositório não tem remote',
    IssueProblem.network => 'Não deu para falar com o GitHub',
    _ => 'Issues indisponíveis',
  };

  /// Web address of the issue [number] (null without a repository).
  String? issueUrl(int number) =>
      repo == null ? null : 'https://github.com/$repo/issues/$number';
}

/// `owner/name` of a GitHub remote URL (null when it is not one).
String? githubRepoOf(String remoteUrl) {
  final url = reviewRepositoryUrl(remoteUrl);
  if (url == null) return null;
  final uri = Uri.parse(url);
  final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (parts.length < 2) return null;
  return '${parts[0]}/${parts[1]}';
}

/// The remote of the workspace: the upstream of the current branch, else
/// `origin`, else the only one.
Future<String?> _remoteOf(GitService git, List<String> names) async {
  String? upstream;
  try {
    final branch = await git.currentBranch();
    if (branch != null) {
      upstream = (await git.git(['config', '--get', 'branch.$branch.remote']))
          .trim();
    }
  } on GitException {
    /* no upstream */
  }
  return chooseReviewRemote(names, upstream: upstream) ??
      (names.contains('origin') ? 'origin' : null);
}

/// The diagnosis of R2 for the repository at [root]: the remote, its host,
/// the `gh` (installed, logged in) and the issues of the repository. Needs
/// no session or worktree.
Future<IssueAvailability> issueAvailability({
  required String root,
  required GitService git,
  required GhCli gh,
  required ProjectConfig config,
}) async {
  try {
    return await _availability(root: root, git: git, gh: gh, config: config);
  } on Exception catch (e) {
    // A folder that is not there, `git` missing…: the reason, not a crash.
    return IssueAvailability.unavailable(IssueProblem.error, '$e');
  }
}

Future<IssueAvailability> _availability({
  required String root,
  required GitService git,
  required GhCli gh,
  required ProjectConfig config,
}) async {
  final List<String> names;
  try {
    names = (await git.git(['remote']))
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  } on GitException catch (e) {
    return IssueAvailability.unavailable(IssueProblem.error, '$e');
  }
  if (names.isEmpty) {
    return const IssueAvailability.unavailable(
      IssueProblem.noRemote,
      'O repositório não tem remote (git remote add origin …). As issues '
      'vêm do GitHub.',
    );
  }
  final remote = await _remoteOf(git, names);
  if (remote == null) {
    return const IssueAvailability.unavailable(
      IssueProblem.chooseRemote,
      'O repositório tem vários remotes e nenhum se chama origin: escolha o '
      'remote no Review.',
    );
  }
  final String url;
  try {
    url = (await git.git(['remote', 'get-url', remote])).trim();
  } on GitException catch (e) {
    return IssueAvailability.unavailable(IssueProblem.error, '$e');
  }
  final hostname = remoteHost(url);
  final host = detectReviewHost(url, config);
  if (host != 'github') {
    return IssueAvailability.unavailable(
      switch (remoteKind(url)) {
        RemoteKind.local => IssueProblem.localRemote,
        RemoteKind.invalid => IssueProblem.invalidRemote,
        RemoteKind.hosted when host == 'gitlab' => IssueProblem.gitlab,
        RemoteKind.hosted => IssueProblem.otherHost,
      },
      switch (remoteKind(url)) {
        RemoteKind.local =>
          'O remote $remote aponta para um caminho local ($url); as issues '
              'exigem um repositório no GitHub.',
        RemoteKind.invalid =>
          'O remote $remote tem URL inválida ($url). Corrija com git remote '
              'set-url $remote <url>.',
        RemoteKind.hosted when host == 'gitlab' =>
          'O remote $remote está em $hostname. Importar e criar issues vale '
              'só para GitHub, como o Review hoje.',
        RemoteKind.hosted =>
          'O remote $remote está em $hostname: importar e criar issues vale '
              'só para GitHub.',
      },
      remote: remote,
    );
  }
  final repo = githubRepoOf(url);
  final a = await GithubHost(gh.runner).availability(root, hostname!);
  if (!a.available) {
    return IssueAvailability.unavailable(
      switch (a.problem) {
        HostProblem.missing => IssueProblem.ghMissing,
        HostProblem.authentication => IssueProblem.ghLoggedOut,
        HostProblem.network => IssueProblem.network,
        _ => IssueProblem.error,
      },
      switch (a.problem) {
        HostProblem.missing =>
          'O GitHub CLI (gh) não está instalado. O app usa o gh para ler e '
              'criar issues, como já faz com os PRs.',
        HostProblem.authentication =>
          'O gh não está logado em github.com. Rode gh auth login no '
              'terminal e confira de novo.',
        _ => a.reason ?? 'Não deu para verificar o gh.',
      },
      repo: repo,
      remote: remote,
      installUrl: a.installUrl,
    );
  }
  if (repo == null) {
    return IssueAvailability.unavailable(
      IssueProblem.invalidRemote,
      'Não deu para ler o repositório do remote $remote ($url).',
      remote: remote,
    );
  }
  try {
    final info = await GhIssues(gh, repo: repo).info();
    if (!info.hasIssuesEnabled) {
      return IssueAvailability.unavailable(
        IssueProblem.issuesDisabled,
        'As issues estão desligadas em ${info.nameWithOwner}. Ligue em '
        'Settings › Features do repositório e confira de novo.',
        repo: info.nameWithOwner,
        remote: remote,
      );
    }
    final auth = await gh.ghAuthStatus();
    return IssueAvailability.ok(
      repo: info.nameWithOwner,
      remote: remote,
      defaultBranch: info.defaultBranch,
      account: auth.account,
    );
  } on GhException catch (e) {
    return IssueAvailability.unavailable(
      IssueProblem.network,
      'Não deu para ler o repositório $repo no GitHub: $e',
      repo: repo,
      remote: remote,
    );
  }
}

/// The diagnosis of a workspace (by its root path); "Conferir de novo"
/// invalidates it.
final issueAvailabilityProvider =
    FutureProvider.family<IssueAvailability, String>((ref, root) async {
      final config = await ref.watch(projectConfigProvider(root).future);
      return issueAvailability(
        root: root,
        git: ref.read(gitServiceFactoryProvider)(root),
        gh: ref.read(ghCliFactoryProvider)(root),
        config: config,
      );
    });

/// The issues client of [ws] with its diagnosis; the client is null without
/// GitHub (R2).
Future<(GhIssues?, IssueAvailability)> githubIssuesOf(
  Ref ref,
  Workspace ws,
) async {
  final a = await ref.read(issueAvailabilityProvider(ws.path).future);
  if (!a.available || a.repo == null) return (null, a);
  return (GhIssues(ref.read(ghCliFactoryProvider)(ws.path), repo: a.repo!), a);
}
