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
      Process.run(exe, args, environment: const {'GIT_TERMINAL_PROMPT': '0'});

  /// Whether [folder] has no entries (a clone can go straight into it).
  bool isEmptyFolder(String folder) => Directory(folder).listSync().isEmpty;

  /// `git init`, `origin` = [remoteUrl] (if given) and a first commit: with
  /// the folder's files when [commitFiles], otherwise empty. Safe to retry
  /// after a failure (e.g. missing git identity).
  Future<void> init(
    String folder, {
    bool commitFiles = true,
    String? remoteUrl,
  }) async {
    final url = remoteUrl?.trim();
    if (url != null && url.isNotEmpty) _checkUrl(url);
    final git = GitService(folder, run: _run);
    await git.git(['init', '-q']);
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

/// User-facing text for a failed init / clone.
String repoSetupError(Object e) {
  if (e is InvalidWorkspaceFolder) return e.message;
  if (e is! GitException) return '$e';
  final err = e.stderr.trim();
  if (err.contains('Please tell me who you are') ||
      err.contains('user.email')) {
    return 'Configure seu nome e e-mail no git (git config --global '
        'user.name / user.email) e tente de novo.';
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
