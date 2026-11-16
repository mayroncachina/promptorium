import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../process/process_runner.dart';
import 'git_root.dart';
import 'git_service.dart';

/// Turns a plain folder into a workspace repository: `git init` (with a first
/// commit and, optionally, an `origin` remote) or `git clone` into it.
///
/// Session worktrees start from a commit, so [init] always creates one.
class RepoSetup {
  RepoSetup({ProcessRunner? run}) : _run = run ?? _defaultRun;

  final ProcessRunner _run;

  /// Never waits on a username/password prompt (`git clone` over https from
  /// a terminal-launched app would hang otherwise); the failure is reported.
  static Future<ProcessResult> _defaultRun(String exe, List<String> args) =>
      Process.run(
        exe,
        args,
        environment: const {'GIT_TERMINAL_PROMPT': '0'},
        stdoutEncoding: lenientUtf8,
        stderrEncoding: lenientUtf8,
      );

  /// Whether [folder] has no entries (a clone can go straight into it).
  bool isEmptyFolder(String folder) => Directory(folder).listSync().isEmpty;

  /// `git init`, `origin` = [remoteUrl] (if given) and a first commit: with
  /// the folder's files when [commitFiles], otherwise empty. The repository
  /// starts on [branch] (SPEC-072 R6). Safe to retry after a failure (e.g.
  /// missing git identity).
  Future<void> init(
    String folder, {
    bool commitFiles = true,
    String? remoteUrl,
    String branch = 'main',
  }) async {
    final url = remoteUrl?.trim();
    if (url != null && url.isNotEmpty) _checkUrl(url);
    final git = GitService(folder, run: _run);
    await _initBranch(git, branch.trim().isEmpty ? 'main' : branch.trim());
    if (url != null && url.isNotEmpty) {
      final remotes = (await git.git(['remote'])).split('\n');
      await git.git([
        'remote',
        remotes.contains('origin') ? 'set-url' : 'add',
        'origin',
        url,
      ]);
    }
    if (commitFiles) await git.git(['add', '-A']);
    await git.git(['commit', '-q', '--allow-empty', '-m', 'Commit inicial']);
  }

  /// `git init -b <branch>` (SPEC-071 R25, SPEC-072 R6). A git older than
  /// 2.28 has no `-b`, and a re-init of a folder left by an older failure
  /// ignores it, so an unborn HEAD (no commits yet) is always pointed at
  /// [branch] by hand.
  Future<void> _initBranch(GitService git, String branch) async {
    try {
      await git.git(['init', '-q', '-b', branch]);
    } on GitException catch (e) {
      final err = '${e.stderr}${e.stdout}';
      if (!err.contains('unknown switch') && !err.contains('initial-branch')) {
        rethrow;
      }
      await git.git(['init', '-q']);
    }
    try {
      await git.git(['rev-parse', '--verify', '-q', 'HEAD']);
    } on GitException {
      await git.git(['symbolic-ref', 'HEAD', 'refs/heads/$branch']);
    }
  }

  /// Why [name] cannot be a branch (`git check-ref-format --branch`), or
  /// null when it can (SPEC-072 R5).
  Future<String?> checkBranchName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return 'Informe a branch inicial.';
    if (n.startsWith('-')) return 'O nome não pode começar com "-".';
    final ProcessResult r;
    try {
      r = await _run('git', ['check-ref-format', '--branch', n]);
    } on ProcessException {
      return null; // no git: the Git item says so
    }
    if (r.exitCode == 0) return null;
    return '"$n" não é um nome de branch válido.';
  }

  /// The name and e-mail git commits with, as effective in [folder] (env,
  /// global and system config), read from `git var GIT_AUTHOR_IDENT`.
  /// Throws like [checkIdentity].
  Future<({String name, String email})> identity(String folder) async {
    final git = GitService(folder, run: _run);
    final String author;
    try {
      author = await git.git(['var', 'GIT_AUTHOR_IDENT']);
      await git.git(['var', 'GIT_COMMITTER_IDENT']);
    } on GitException catch (e) {
      if (e.message == 'git não encontrado') {
        throw const InvalidWorkspaceFolder(gitNotFound);
      }
      throw const InvalidWorkspaceFolder(missingGitIdentity);
    }
    final m = RegExp(r'^(.*?)\s*<([^>]*)>').firstMatch(author.trim());
    return (
      name: m?.group(1)?.trim() ?? author.trim(),
      email: m?.group(2)?.trim() ?? '',
    );
  }

  /// `git config --global user.name` and `user.email` ("Gravar no git",
  /// SPEC-072 R3).
  Future<void> setGlobalIdentity(String name, String email) async {
    final n = name.trim();
    final e = email.trim();
    if (n.isEmpty || e.isEmpty) {
      throw const InvalidWorkspaceFolder('Informe o nome e o e-mail.');
    }
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final git = GitService(home, run: _run);
    await git.git(['config', '--global', 'user.name', n]);
    await git.git(['config', '--global', 'user.email', e]);
  }

  /// Fails (with [missingGitIdentity]) when git has no name / e-mail to
  /// commit with, as effective in [folder] (env, global and system config).
  /// `git var` applies the same rule as `git commit`, so this is checked
  /// before anything is created (R21).
  Future<void> checkIdentity(String folder) async {
    await identity(folder);
  }

  /// Whether [folder] holds only what a failed "Novo projeto" left behind: a
  /// `.git` without commits, plus the template files (`CLAUDE.md`,
  /// `.promptorium/config.yml`). Creating again there is safe (R21).
  Future<bool> isCreationLeftover(String folder) async {
    final entries = Directory(folder).listSync();
    var hasGit = false;
    for (final e in entries) {
      final name = e.uri.pathSegments.where((p) => p.isNotEmpty).last;
      switch (name) {
        case '.git' when e is Directory:
          hasGit = true;
        case 'CLAUDE.md' when e is File:
          break;
        case '.promptorium' when e is Directory:
          final inside = e.listSync();
          if (inside.any(
            (f) => f is! File || !f.path.endsWith('/config.yml'),
          )) {
            return false;
          }
        default:
          return false;
      }
    }
    if (!hasGit) return entries.isEmpty;
    try {
      await GitService(
        folder,
        run: _run,
      ).git(['rev-parse', '--verify', '-q', 'HEAD']);
      return false; // it has commits: someone's repository
    } on GitException {
      return true;
    }
  }

  /// `git clone <url>` into [cloneDestination]; returns that folder.
  Future<String> clone(String folder, String url) async {
    final u = url.trim();
    _checkUrl(u);
    final dest = cloneDestination(
      folder,
      u,
      folderEmpty: isEmptyFolder(folder),
    );
    if (dest != folder &&
        await FileSystemEntity.type(dest) != FileSystemEntityType.notFound) {
      throw InvalidWorkspaceFolder('Já existe algo em $dest.');
    }
    await GitService(folder, run: _run).git(['clone', '-q', '--', u, dest]);
    return dest;
  }

  static void _checkUrl(String url) {
    if (url.isEmpty) {
      throw const InvalidWorkspaceFolder('Informe a URL do repositório.');
    }
    if (url.startsWith('-')) {
      throw InvalidWorkspaceFolder('URL inválida: "$url"');
    }
  }

  /// [folder] itself when empty, otherwise `<folder>/<repo name>`.
  static String cloneDestination(
    String folder,
    String url, {
    required bool folderEmpty,
  }) {
    if (folderEmpty) return folder;
    final base = folder.endsWith('/') && folder.length > 1
        ? folder.substring(0, folder.length - 1)
        : folder;
    return '$base/${repoNameFromUrl(url)}';
  }

  /// `git@host:o/app.git`, `https://host/o/app/` and `/srv/app.git` → `app`.
  static String repoNameFromUrl(String url) {
    var name = url.trim();
    while (name.endsWith('/')) {
      name = name.substring(0, name.length - 1);
    }
    name = name.split(RegExp('[/:]')).last;
    if (name.endsWith('.git')) name = name.substring(0, name.length - 4);
    return name.isEmpty || name.startsWith('.') ? 'repo' : name;
  }
}

/// The git executable is not on the PATH.
const gitNotFound = 'O git não foi encontrado. Instale o git e tente de novo.';

/// How to fix a missing git identity (pt-BR, shown in "Novo projeto").
const missingGitIdentity =
    'O git ainda não sabe quem você é, e o primeiro commit precisa disso. '
    'Configure seu nome e e-mail no terminal e tente de novo:\n'
    '  git config --global user.name "Seu Nome"\n'
    '  git config --global user.email "voce@exemplo.com"';

/// User-facing text for a failed init / clone.
String repoSetupError(Object e) {
  if (e is InvalidWorkspaceFolder) return e.message;
  if (e is! GitException) return '$e';
  final err = e.stderr.trim();
  if (err.contains('Please tell me who you are') ||
      err.contains('user.email')) {
    return missingGitIdentity;
  }
  if (err.contains('terminal prompts disabled') ||
      err.contains('could not read Username')) {
    return 'O remoto pediu usuário e senha. Use uma URL SSH ou configure um '
        'credential helper do git.';
  }
  final lines = err.split('\n').where((l) => l.trim().isNotEmpty).toList();
  return lines.isEmpty ? e.message : lines.last.trim();
}

final repoSetupProvider = Provider<RepoSetup>((ref) => RepoSetup());
