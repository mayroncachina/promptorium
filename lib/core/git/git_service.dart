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

/// Who made a commit (SPEC-048 R5).
enum CommitOriginKind {
  /// No trailer, after the marking started: the person.
  person,

  /// `Promptorium-Agente: <modelo> · <origem>` from an agent session.
  agent,

  /// `Promptorium-Agente: app · …`: a commit the app made, which may mix
  /// the person's and the agent's edits.
  app,

  /// No trailer, before the first marked commit: unknown.
  unmarked,
}

/// One commit read by [GitService.commitOrigins].
@immutable
class CommitOrigin {
  const CommitOrigin({
    required this.sha,
    required this.kind,
    required this.author,
    required this.date,
    required this.subject,
    this.model,
    this.origin,
    this.trailer,
  });

  final String sha;
  final CommitOriginKind kind;
  final String author;

  /// Committer date.
  final DateTime date;
  final String subject;

  /// `sonnet`, `gpt-5`, `app` (null without trailer).
  final String? model;

  /// `SPEC-042 R2`, `sessão x`, `Prompt` (null without trailer / origin).
  final String? origin;

  /// The exact line: `Promptorium-Agente: sonnet · SPEC-042 R2`.
  final String? trailer;

  bool get isAgent => kind == CommitOriginKind.agent;

  /// `<sha>\x1f<author>\x1f<date>\x1f<subject>\x1f<values>` (values
  /// separated by `\x1d`, the last one wins).
  static CommitOrigin parse(String rec, {DateTime? since}) {
    final f = rec.split('\x1f');
    String at(int i) => f.length > i ? f[i] : '';
    final date = DateTime.tryParse(at(2)) ?? DateTime(1970);
    final values = [
      for (final v in at(4).split('\x1d'))
        if (v.trim().isNotEmpty) v.trim(),
    ];
    final value = values.isEmpty ? null : values.last;
    if (value == null) {
      return CommitOrigin(
        sha: at(0),
        kind: since != null && !date.isBefore(since)
            ? CommitOriginKind.person
            : CommitOriginKind.unmarked,
        author: at(1),
        date: date,
        subject: at(3),
      );
    }
    final cut = value.indexOf(' · ');
    final model = (cut < 0 ? value : value.substring(0, cut)).trim();
    final origin = cut < 0 ? null : value.substring(cut + 3).trim();
    return CommitOrigin(
      sha: at(0),
      kind: model == 'app' ? CommitOriginKind.app : CommitOriginKind.agent,
      author: at(1),
      date: date,
      subject: at(3),
      model: model,
      origin: origin == null || origin.isEmpty ? null : origin,
      trailer: 'Promptorium-Agente: $value',
    );
  }
}

/// Result of [GitService.commitOrigins].
@immutable
class CommitOriginLog {
  const CommitOriginLog({required this.commits, this.since});

  /// Newest first.
  final List<CommitOrigin> commits;

  /// First marked commit of the default branch (null = marking never ran).
  final DateTime? since;

  int count(CommitOriginKind kind) =>
      commits.where((c) => c.kind == kind).length;
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
  Future<String> git(List<String> args) => _git(args);

  /// [git] with `GIT_INDEX_FILE=<indexFile>` (a scratch index).
  Future<String> _git(List<String> args, {String? indexFile}) async {
    final full = ['-C', repoRoot, ...args];
    final ProcessResult r;
    try {
      r = indexFile == null
          ? await _run('git', full)
          : await _run('env', ['GIT_INDEX_FILE=$indexFile', 'git', ...full]);
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
  /// returns false). [trailer] (`Promptorium-Agente: app · SPEC-042 R2`)
  /// goes in with `--trailer` (SPEC-048 R4).
  Future<bool> commitAll(String message, {String? trailer}) async {
    await git(['add', '-A']);
    if ((await git(['diff', '--cached', '--name-only'])).trim().isEmpty) {
      return false;
    }
    await git([
      'commit',
      '-q',
      '-m',
      message,
      if (trailer != null) ...['--trailer', trailer],
    ]);
    return true;
  }

  /// Who made [sha] (SPEC-048 R5). [since] = [agentMarkSince] of the
  /// default branch: an unmarked commit before it counts as
  /// [CommitOriginKind.unmarked]; null = read it from [defaultBranch] (or
  /// HEAD).
  Future<CommitOrigin> commitOrigin(
    String sha, {
    DateTime? since,
    String? defaultBranch,
  }) async {
    final log = await commitOrigins(
      _arg(sha, 'commit'),
      since: since,
      defaultBranch: defaultBranch,
      limit: 1,
    );
    if (log.commits.isEmpty) throw GitException('commit não encontrado: $sha');
    return log.commits.first;
  }

  /// [CommitOrigin] of every commit of [range] (`main`, `a..b`), newest
  /// first, read in one `git log` with the `Promptorium-Agente` trailer.
  Future<CommitOriginLog> commitOrigins(
    String range, {
    DateTime? since,
    String? defaultBranch,
    int? limit,
  }) async {
    final from = since ?? await agentMarkSince(defaultBranch ?? 'HEAD');
    final out = await git([
      'log',
      if (limit != null) ...['-n', '$limit'],
      '--format=%H%x1f%an%x1f%cI%x1f%s%x1f'
          '%(trailers:key=$_trailerKey,valueonly,separator=%x1d)%x1e',
      _arg(range, 'intervalo'),
      '--',
    ]);
    return CommitOriginLog(
      since: from,
      commits: [
        for (final rec in out.split('\x1e'))
          if (rec.trim().isNotEmpty)
            CommitOrigin.parse(rec.trim(), since: from),
      ],
    );
  }

  /// [CommitOrigin] of each of [shas] (in that order), read in one `git
  /// log --no-walk` — the Grafo's page of rows (SPEC-045 R9). [since] as in
  /// [commitOrigins]; null = the unmarked ones stay
  /// [CommitOriginKind.unmarked] (no extra read).
  Future<List<CommitOrigin>> commitOriginsOf(
    Iterable<String> shas, {
    DateTime? since,
  }) async {
    final list = [for (final s in shas) _arg(s, 'commit')];
    if (list.isEmpty) return const [];
    final out = await git([
      'log',
      '--no-walk=unsorted',
      '--format=%H%x1f%an%x1f%cI%x1f%s%x1f'
          '%(trailers:key=$_trailerKey,valueonly,separator=%x1d)%x1e',
      ...list,
      '--',
    ]);
    return [
      for (final rec in out.split('\x1e'))
        if (rec.trim().isNotEmpty) CommitOrigin.parse(rec.trim(), since: since),
    ];
  }

  /// Date of the first marked commit of [branch] (when the marking started
  /// there); null = none yet.
  Future<DateTime?> agentMarkSince(String branch) async {
    try {
      final out = await git([
        'log',
        '--format=%cI',
        '--grep=^$_trailerKey: ',
        _arg(branch, 'branch'),
        '--',
      ]);
      final lines = out.trim().split('\n').where((l) => l.trim().isNotEmpty);
      return lines.isEmpty ? null : DateTime.tryParse(lines.last.trim());
    } on GitException {
      return null;
    }
  }

  /// Marked commits of [branch] (status line of the option).
  Future<int> agentMarkCount(String branch) async {
    try {
      return int.tryParse(
            (await git([
              'rev-list',
              '--count',
              '--grep=^$_trailerKey: ',
              _arg(branch, 'branch'),
              '--',
            ])).trim(),
          ) ??
          0;
    } on GitException {
      return 0;
    }
  }

  static const _trailerKey = 'Promptorium-Agente';

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

  /// The working tree (tracked and untracked files; ignored ones left out)
  /// as a commit on top of HEAD, built in a scratch index so neither the
  /// tree nor the index is touched; null when the tree is clean.
  Future<String?> snapshot() async {
    if ((await git(['status', '--porcelain'])).trim().isEmpty) return null;
    final dir = await Directory.systemTemp.createTemp('promptorium-index');
    try {
      final index = '${dir.path}/index';
      await _git(['read-tree', 'HEAD'], indexFile: index);
      await _git(['add', '-A'], indexFile: index);
      final tree = (await _git(['write-tree'], indexFile: index)).trim();
      return (await git([
        '-c',
        'user.name=Promptorium',
        '-c',
        'user.email=promptorium@localhost',
        'commit-tree',
        tree,
        '-p',
        'HEAD',
        '-m',
        'promptorium: estado do worktree',
      ])).trim();
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Puts the files of [sha] (a [snapshot] or a `git stash create` commit)
  /// in the working tree, leaving the index at HEAD.
  Future<void> restoreSnapshot(String sha) async {
    await git(['read-tree', '-u', '--reset', '${_arg(sha, 'commit')}^{tree}']);
    await git(['reset', '-q']);
  }

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
