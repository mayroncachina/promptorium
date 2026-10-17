import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../process/process_runner.dart';
import 'git_root.dart';

/// A git command that failed (non-zero exit or git missing).
class GitException implements Exception {
  const GitException(
    this.message, {
    this.arguments = const [],
    this.exitCode,
    this.stderr = '',
    this.stdout = '',
  });

  final String message;
  final List<String> arguments;
  final int? exitCode;
  final String stderr;

  /// Some failures (e.g. merge conflicts) are reported on stdout.
  final String stdout;

  @override
  String toString() {
    final cmd = arguments.isEmpty ? '' : ' (git ${arguments.join(' ')})';
    final detail = stderr.trim().isEmpty ? stdout.trim() : stderr.trim();
    final err = detail.isEmpty ? '' : ': $detail';
    return '$message$cmd$err';
  }
}

/// One entry of `git status --porcelain` (v1).
@immutable
class GitStatusEntry {
  const GitStatusEntry({
    required this.path,
    required this.x,
    required this.y,
    this.origPath,
  });

  final String path;

  /// Index status (`M`, `A`, `D`, `R`, `C`, `?`, `!`, ` `).
  final String x;

  /// Work-tree status.
  final String y;

  /// Source path of a rename / copy.
  final String? origPath;

  bool get isUntracked => x == '?' && y == '?';

  @override
  String toString() => '$x$y $path';
}

/// One block of `git worktree list --porcelain`.
@immutable
class GitWorktree {
  const GitWorktree({
    required this.path,
    this.head,
    this.branch,
    this.detached = false,
    this.bare = false,
    this.locked = false,
    this.prunable = false,
  });

  final String path;
  final String? head;

  /// Short branch name (`refs/heads/` removed), null when detached.
  final String? branch;
  final bool detached;
  final bool bare;
  final bool locked;
  final bool prunable;
}

/// Worktree created by [GitService.addWorktree].
@immutable
class CreatedWorktree {
  const CreatedWorktree({required this.path, required this.branch});

  final String path;
  final String branch;
}

@immutable
class GitLogEntry {
  const GitLogEntry({
    required this.sha,
    required this.shortSha,
    required this.author,
    required this.date,
    required this.subject,
  });

  final String sha;
  final String shortSha;
  final String author;
  final DateTime date;
  final String subject;
}

/// Git operations on one repository (`git -C <repoRoot> …`).
class GitService {
  GitService(this.repoRoot, {ProcessRunner? run, String? worktreesBase})
    : _run = run ?? _defaultRun,
      worktreesBase = worktreesBase ?? defaultWorktreesBase();

  final String repoRoot;

  /// Folder for session worktrees (default `~/.promptorium/worktrees`).
  final String worktreesBase;
  final ProcessRunner _run;

  static Future<ProcessResult> _defaultRun(String exe, List<String> args) =>
      Process.run(exe, args);

  static String defaultWorktreesBase({String? home}) =>
      '${home ?? Platform.environment['HOME'] ?? ''}/.promptorium/worktrees';

  String get repoName => folderName(repoRoot);

  /// Valid slug: lowercase letters, digits, `.`, `_`, `-` (no leading `.`/`-`).
  static final slugPattern = RegExp(r'^[a-z0-9_][a-z0-9._-]*$');

  /// Rejects refs / paths that git would parse as options (`-x`, `--y`).
  static String _arg(String value, String what) {
    if (value.isEmpty || value.startsWith('-')) {
      throw GitException('$what inválido: "$value"');
    }
    return value;
  }

  /// Runs `git -C repoRoot <args>` and returns stdout. Throws [GitException].
  Future<String> git(List<String> args) async {
    final full = ['-C', repoRoot, ...args];
    final ProcessResult r;
    try {
      r = await _run('git', full);
    } on ProcessException catch (e) {
      throw GitException(
        'git não encontrado',
        arguments: args,
        stderr: e.message,
      );
    }
    if (r.exitCode != 0) {
      throw GitException(
        'git ${args.isEmpty ? '' : args.first} falhou',
        arguments: args,
        exitCode: r.exitCode,
        stderr: '${r.stderr}',
        stdout: '${r.stdout}',
      );
    }
    return '${r.stdout}';
  }

  /// Current branch, or null when HEAD is detached.
  Future<String?> currentBranch() async {
    final full = ['-C', repoRoot, 'symbolic-ref', '--short', '-q', 'HEAD'];
    final ProcessResult r;
    try {
      r = await _run('git', full);
    } on ProcessException catch (e) {
      throw GitException('git não encontrado', stderr: e.message);
    }
    if (r.exitCode == 0) return '${r.stdout}'.trim();
    if (r.exitCode == 1) return null; // detached HEAD
    throw GitException(
      'não foi possível ler a branch atual',
      arguments: full.sublist(2),
      exitCode: r.exitCode,
      stderr: '${r.stderr}',
    );
  }

  /// `git status --porcelain=v1 -z --untracked-files=all`.
  Future<List<GitStatusEntry>> status() async =>
      parseStatusZ(await git(['status', '--porcelain=v1', '-z', '-uall']));

  /// Parses NUL-separated porcelain v1 output.
  static List<GitStatusEntry> parseStatusZ(String out) {
    final parts = out.split('\x00');
    final entries = <GitStatusEntry>[];
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      if (p.length < 4) continue;
      final x = p[0], y = p[1];
      final path = p.substring(3);
      String? orig;
      if (x == 'R' || x == 'C' || y == 'R' || y == 'C') {
        if (i + 1 < parts.length) orig = parts[++i];
      }
      entries.add(GitStatusEntry(path: path, x: x, y: y, origPath: orig));
    }
    return entries;
  }

  /// Creates branch `pr/<slug>` in `<worktreesBase>/<repoName>-<slug>`,
  /// starting at [baseBranch] (default: HEAD).
  Future<CreatedWorktree> addWorktree(String slug, {String? baseBranch}) async {
    if (!slugPattern.hasMatch(slug)) {
      throw GitException('slug inválido: "$slug"');
    }
    final path = '$worktreesBase/$repoName-$slug';
    final branch = 'pr/$slug';
    if (await Directory(path).exists()) {
      throw GitException('o diretório do worktree já existe: $path');
    }
    await Directory(worktreesBase).create(recursive: true);
    await git([
      'worktree',
      'add',
      '-b',
      branch,
      path,
      if (baseBranch != null) _arg(baseBranch, 'branch base'),
    ]);
    return CreatedWorktree(path: path, branch: branch);
  }

  /// `git worktree remove [--force] <path>` (the branch is kept; see
  /// [deleteBranch]).
  Future<void> removeWorktree(String path, {bool force = false}) =>
      git(['worktree', 'remove', if (force) '--force', _arg(path, 'caminho')]);

  /// `git branch -d|-D <branch>`.
  Future<void> deleteBranch(String branch, {bool force = false}) =>
      git(['branch', force ? '-D' : '-d', _arg(branch, 'branch')]);

  Future<List<GitWorktree>> listWorktrees() async =>
      parseWorktreeList(await git(['worktree', 'list', '--porcelain']));

  static List<GitWorktree> parseWorktreeList(String out) {
    final result = <GitWorktree>[];
    String? path, head, branch;
    var detached = false, bare = false, locked = false, prunable = false;
    void flush() {
      if (path != null) {
        result.add(
          GitWorktree(
            path: path!,
            head: head,
            branch: branch,
            detached: detached,
            bare: bare,
            locked: locked,
            prunable: prunable,
          ),
        );
      }
      path = head = branch = null;
      detached = bare = locked = prunable = false;
    }

    for (final line in out.split('\n')) {
      if (line.isEmpty) {
        flush();
      } else if (line.startsWith('worktree ')) {
        flush();
        path = line.substring(9);
      } else if (line.startsWith('HEAD ')) {
        head = line.substring(5);
      } else if (line.startsWith('branch ')) {
        final ref = line.substring(7);
        branch = ref.startsWith('refs/heads/') ? ref.substring(11) : ref;
      } else if (line == 'detached') {
        detached = true;
      } else if (line == 'bare') {
        bare = true;
      } else if (line == 'locked' || line.startsWith('locked ')) {
        locked = true;
      } else if (line == 'prunable' || line.startsWith('prunable ')) {
        prunable = true;
      }
    }
    flush();
    return result;
  }

  /// `git diff --unified` of the work tree against [base] (default: index),
  /// optionally limited to [path]. Parse with `DiffParser`.
  Future<String> diff({String? base, String? path, int context = 3}) => git([
    'diff',
    '--no-color',
    '--no-ext-diff',
    '--unified=$context',
    if (base != null) _arg(base, 'base'),
    if (path != null) ...['--', path],
  ]);

  /// `git merge --no-edit <branch>` into the current branch.
  Future<String> merge(String branch) =>
      git(['merge', '--no-edit', _arg(branch, 'branch')]);

  /// `git merge --abort` (after a conflicting [merge]).
  Future<void> mergeAbort() => git(['merge', '--abort']);

  /// Whether [path] (relative) is ignored by git (`git check-ignore -q`).
  Future<bool> isIgnored(String path) async {
    final r = await _run('git', [
      '-C',
      repoRoot,
      'check-ignore',
      '-q',
      '--',
      _arg(path, 'caminho'),
    ]);
    return r.exitCode == 0;
  }

  /// Full hash of HEAD (null in a repository without commits).
  Future<String?> headSha() async {
    try {
      return (await git(['rev-parse', 'HEAD'])).trim();
    } on GitException catch (e) {
      if (e.exitCode != null) return null;
      rethrow;
    }
  }

  /// Subjects of the commits in `<sha>..HEAD`, newest first.
  Future<List<String>> subjectsSince(String sha) async {
    final out = await git([
      'log',
      '--format=%s',
      '${_arg(sha, 'commit')}..HEAD',
    ]);
    return [
      for (final l in out.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
  }

  /// `git add -A && git commit -m <message>` (nothing staged = no commit,
  /// returns false).
  Future<bool> commitAll(String message) async {
    await git(['add', '-A']);
    if ((await git(['diff', '--cached', '--name-only'])).trim().isEmpty) {
      return false;
    }
    await git(['commit', '-q', '-m', message]);
    return true;
  }

  /// `git update-ref <ref> <sha>` (refs under `refs/promptorium/`).
  Future<void> updateRef(String ref, String sha) =>
      git(['update-ref', _arg(ref, 'ref'), _arg(sha, 'commit')]);

  /// Hash [ref] points to, or null.
  Future<String?> resolveRef(String ref) async {
    try {
      return (await git([
        'rev-parse',
        '--verify',
        '-q',
        '${_arg(ref, 'ref')}^{commit}',
      ])).trim();
    } on GitException {
      return null;
    }
  }

  /// Removes every ref under [prefix] (`refs/promptorium/SPEC-003/`).
  Future<void> deleteRefs(String prefix) async {
    final out = await git([
      'for-each-ref',
      '--format=%(refname)',
      _arg(prefix, 'prefixo'),
    ]);
    for (final r in out.split('\n')) {
      if (r.trim().isNotEmpty) await git(['update-ref', '-d', r.trim()]);
    }
  }

  /// `git stash create`: a commit with the uncommitted changes (tracked files)
  /// without touching the tree; null when the tree is clean.
  Future<String?> stashCreate() async {
    final sha = (await git(['stash', 'create'])).trim();
    return sha.isEmpty ? null : sha;
  }

  /// `git stash apply <sha>`.
  Future<void> stashApply(String sha) =>
      git(['stash', 'apply', _arg(sha, 'stash')]);

  /// `git reset --hard <sha>` + `git clean -fd` (untracked files removed;
  /// ignored ones kept).
  Future<void> resetHard(String sha) async {
    await git(['reset', '-q', '--hard', _arg(sha, 'commit')]);
    await git(['clean', '-q', '-fd']);
  }

  /// Last [n] commits of HEAD.
  Future<List<GitLogEntry>> log(int n) async {
    final out = await git([
      'log',
      '-n',
      '$n',
      '--format=%H%x1f%h%x1f%an%x1f%aI%x1f%s%x1e',
    ]);
    return [
      for (final rec in out.split('\x1e'))
        if (rec.trim().isNotEmpty) _logEntry(rec.trim()),
    ];
  }

  static GitLogEntry _logEntry(String rec) {
    final f = rec.split('\x1f');
    return GitLogEntry(
      sha: f[0],
      shortSha: f.length > 1 ? f[1] : '',
      author: f.length > 2 ? f[2] : '',
      date: DateTime.tryParse(f.length > 3 ? f[3] : '') ?? DateTime(1970),
      subject: f.length > 4 ? f[4] : '',
    );
  }
}

/// Builds a [GitService] for a repository root (overridden in tests).
final gitServiceFactoryProvider = Provider<GitService Function(String)>(
  (ref) =>
      (root) => GitService(root, run: ref.read(processRunnerProvider)),
);

/// Current branch of a repository (title bar). Invalidate to refresh.
final currentBranchProvider = FutureProvider.family<String?, String>(
  (ref, root) => ref.watch(gitServiceFactoryProvider)(root).currentBranch(),
);
