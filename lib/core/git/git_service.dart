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

/// The working tree at a moment (SPEC-084 R2): HEAD, the branch (null =
/// detached) and a commit with every file ([head] when the tree is clean).
@immutable
class TreeState {
  const TreeState({
    required this.head,
    required this.branch,
    required this.sha,
    this.files = 0,
    this.bytes = 0,
    this.large = const [],
  });

  final String head;
  final String? branch;
  final String sha;

  /// Uncommitted files kept in [sha] and their size.
  final int files;
  final int bytes;

  /// Untracked files over the limit, left out.
  final List<String> large;
}

enum TreeChangeKind { modified, created, deleted }

/// One file of [GitService.treeChanges]; null lines = binary.
@immutable
class TreeChange {
  const TreeChange({
    required this.path,
    required this.kind,
    this.added,
    this.removed,
  });

  final String path;
  final TreeChangeKind kind;
  final int? added;
  final int? removed;

  @override
  String toString() => '${kind.name} $path';
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
      Process.run(
        exe,
        args,
        stdoutEncoding: lenientUtf8,
        stderrEncoding: lenientUtf8,
      );

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
  ///
  /// [prefix] `vibe` gives `vibe/<slug>` in `<repoName>-vibe-<slug>` (the
  /// VIBEs, SPEC-069 R1).
  Future<CreatedWorktree> addWorktree(
    String slug, {
    String? baseBranch,
    String prefix = 'pr',
  }) async {
    if (!slugPattern.hasMatch(slug) || !slugPattern.hasMatch(prefix)) {
      throw GitException('slug inválido: "$slug"');
    }
    final path = prefix == 'pr'
        ? '$worktreesBase/$repoName-$slug'
        : '$worktreesBase/$repoName-$prefix-$slug';
    final branch = '$prefix/$slug';
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

  /// Creates the worktree `<worktreesBase>/<repoName>-<slug>` from [ref] (a
  /// ref already fetched, like the head of a PR) on a new branch named
  /// [branch], tracking [upstream] (`origin/feat/x`) when given (SPEC-050
  /// R3).
  Future<CreatedWorktree> addWorktreeAt(
    String slug,
    String ref, {
    required String branch,
    String? upstream,
  }) async {
    if (!slugPattern.hasMatch(slug)) {
      throw GitException('slug inválido: "$slug"');
    }
    _arg(branch, 'branch');
    await git(['check-ref-format', '--branch', branch]);
    final path = '$worktreesBase/$repoName-$slug';
    if (await Directory(path).exists()) {
      throw GitException('o diretório do worktree já existe: $path');
    }
    if (await resolveRef('refs/heads/$branch') != null) {
      throw GitException('a branch $branch já existe no repositório local');
    }
    await Directory(worktreesBase).create(recursive: true);
    await git(['worktree', 'add', '-b', branch, path, _arg(ref, 'ref')]);
    if (upstream != null) {
      await git([
        '-C',
        path,
        'branch',
        '--set-upstream-to=${_arg(upstream, 'upstream')}',
        branch,
      ]);
    }
    return CreatedWorktree(path: path, branch: branch);
  }

  /// Runs before any worktree is removed: the app stops what runs there,
  /// like the development server (SPEC-051 R5). Set once in `main`.
  static Future<void> Function(String path)? beforeRemoveWorktree;

  /// `git worktree remove [--force] <path>` (the branch is kept; see
  /// [deleteBranch]).
  Future<void> removeWorktree(String path, {bool force = false}) async {
    try {
      await beforeRemoveWorktree?.call(path);
    } catch (e) {
      debugPrint('antes de remover o worktree $path — $e');
    }
    await git([
      'worktree',
      'remove',
      if (force) '--force',
      _arg(path, 'caminho'),
    ]);
  }

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

  /// Worktrees whose folder is gone (`git worktree prune --dry-run -v`), as
  /// the paths [listWorktrees] gives. Nothing is removed. The output is
  /// translated, so only `worktrees/<name>` is read from each line and the
  /// path comes from `<common dir>/worktrees/<name>/gitdir`.
  Future<Set<String>> pruneDryRun() async {
    final r = await _run('git', [
      '-C',
      repoRoot,
      'worktree',
      'prune',
      '--dry-run',
      '-v',
    ]);
    if (r.exitCode != 0) {
      throw GitException(
        'git worktree prune falhou',
        arguments: const ['worktree', 'prune', '--dry-run', '-v'],
        exitCode: r.exitCode,
        stderr: '${r.stderr}',
      );
    }
    final names = {
      for (final m in RegExp(
        r'worktrees/([^:\s]+):',
      ).allMatches('${r.stdout}\n${r.stderr}'))
        m.group(1)!,
    };
    if (names.isEmpty) return const {};
    final common = (await git([
      'rev-parse',
      '--path-format=absolute',
      '--git-common-dir',
    ])).trim();
    final paths = <String>{};
    for (final n in names) {
      try {
        var p = File('$common/worktrees/$n/gitdir').readAsStringSync().trim();
        if (p.endsWith('/.git')) p = p.substring(0, p.length - 5);
        paths.add(p);
      } on FileSystemException {
        // No gitdir file at all: git prunes it, but there is no path.
      }
    }
    return paths;
  }

  /// Commits of [base] missing in [branch] and of [branch] missing in
  /// [base] (`git rev-list --left-right --count base...branch`).
  Future<({int behind, int ahead})> aheadBehind(
    String branch,
    String base,
  ) async {
    final out = (await git([
      'rev-list',
      '--left-right',
      '--count',
      '${_arg(base, 'base')}...${_arg(branch, 'branch')}',
    ])).trim().split(RegExp(r'\s+'));
    return (
      behind: int.tryParse(out.first) ?? 0,
      ahead: out.length > 1 ? int.tryParse(out[1]) ?? 0 : 0,
    );
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

  /// Text of [path] (relative to the repository) at [rev]
  /// (`git show <rev>:<path>`); null when the file is not there or [rev]
  /// does not exist (SPEC-082 R7).
  Future<String?> show(String rev, String path) async {
    try {
      return await git([
        'show',
        '${_arg(rev, 'revisão')}:${_arg(path, 'caminho')}',
      ]);
    } on GitException catch (e) {
      if (e.exitCode != null) return null;
      rethrow;
    }
  }

  /// `git merge-base <a> <b>` (null when there is none or a ref is
  /// unknown).
  Future<String?> mergeBase(String a, String b) async {
    try {
      final out = (await git(['merge-base', _arg(a, 'ref'), _arg(b, 'ref')]))
          .trim();
      return out.isEmpty ? null : out;
    } on GitException catch (e) {
      if (e.exitCode != null) return null;
      rethrow;
    }
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

  // --- restore points (SPEC-084) ---------------------------------------------

  /// The working tree as a commit for a restore point (SPEC-084 R2): HEAD,
  /// the branch and a commit with the tracked and untracked files (ignored
  /// ones left out), built in a scratch index like [snapshot], so neither
  /// the tree, the index nor the stash is touched. A clean tree gives HEAD
  /// itself. Untracked files bigger than [maxUntrackedBytes] stay out and
  /// come back in [TreeState.large] (R4, P9). Throws [GitException] in a
  /// repository without commits.
  Future<TreeState> captureState({int? maxUntrackedBytes}) async {
    final head = await headSha();
    if (head == null) {
      throw const GitException('repositório sem commit');
    }
    final branch = await currentBranch();
    final entries = await status();
    if (entries.isEmpty) {
      return TreeState(head: head, branch: branch, sha: head);
    }
    final large = <String>[];
    var bytes = 0;
    var files = 0;
    for (final e in entries) {
      final f = File('$repoRoot/${e.path}');
      final size = f.existsSync() ? f.lengthSync() : 0;
      if (e.isUntracked &&
          maxUntrackedBytes != null &&
          size > maxUntrackedBytes) {
        large.add(e.path);
        continue;
      }
      files++;
      bytes += size;
    }
    if (files == 0) {
      return TreeState(head: head, branch: branch, sha: head, large: large);
    }
    final dir = await Directory.systemTemp.createTemp('promptorium-index');
    try {
      final index = '${dir.path}/index';
      await _git(['read-tree', 'HEAD'], indexFile: index);
      await _git([
        'add',
        '-A',
        '--',
        '.',
        for (final l in large) ':(exclude,literal)$l',
      ], indexFile: index);
      final tree = (await _git(['write-tree'], indexFile: index)).trim();
      final headTree = (await git(['rev-parse', 'HEAD^{tree}'])).trim();
      if (tree == headTree) {
        return TreeState(head: head, branch: branch, sha: head, large: large);
      }
      final sha = (await git([
        '-c',
        'user.name=Promptorium',
        '-c',
        'user.email=promptorium@localhost',
        'commit-tree',
        tree,
        '-p',
        head,
        '-m',
        'promptorium: ponto de restauração',
      ])).trim();
      return TreeState(
        head: head,
        branch: branch,
        sha: sha,
        files: files,
        bytes: bytes,
        large: large,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// What changed from tree-ish [a] to [b], file by file, with the `+`/`−`
  /// lines (`git diff --no-renames --name-status / --numstat`; a rename is a
  /// deletion and a creation).
  Future<List<TreeChange>> treeChanges(String a, String b) async {
    if (a == b) return const [];
    final names = await git([
      'diff',
      '--no-renames',
      '--name-status',
      '-z',
      _arg(a, 'commit'),
      _arg(b, 'commit'),
    ]);
    final nums = await git(['diff', '--no-renames', '--numstat', '-z', a, b]);
    final lines = <String, (int?, int?)>{};
    for (final rec in nums.split('\x00')) {
      final f = rec.split('\t');
      if (f.length < 3) continue;
      lines[f.sublist(2).join('\t')] = (int.tryParse(f[0]), int.tryParse(f[1]));
    }
    final parts = names.split('\x00');
    final out = <TreeChange>[];
    for (var i = 0; i + 1 < parts.length; i += 2) {
      final kind = parts[i].trim();
      final path = parts[i + 1];
      if (kind.isEmpty || path.isEmpty) continue;
      final l = lines[path];
      out.add(
        TreeChange(
          path: path,
          kind: switch (kind[0]) {
            'A' => TreeChangeKind.created,
            'D' => TreeChangeKind.deleted,
            _ => TreeChangeKind.modified,
          },
          added: l?.$1,
          removed: l?.$2,
        ),
      );
    }
    return out;
  }

  /// Puts [paths] back as they are in [sha] (a commit of [captureState]):
  /// a file there is written to the working tree, a file missing there is
  /// deleted; the index of these paths goes back to HEAD. Other files, and
  /// the index of other paths, are not touched (SPEC-084 R8).
  Future<void> restorePaths(String sha, Iterable<String> paths) async {
    final list = paths.toList();
    if (list.isEmpty) return;
    final present = <String>{
      for (final l in (await git([
        '--literal-pathspecs',
        'ls-tree',
        '-r',
        '-z',
        '--name-only',
        _arg(sha, 'commit'),
        '--',
        ...list,
      ])).split('\x00'))
        if (l.isNotEmpty) l,
    };
    const chunk = 200;
    final back = [
      for (final p in list)
        if (present.contains(p)) p,
    ];
    for (var i = 0; i < back.length; i += chunk) {
      await git([
        '--literal-pathspecs',
        'restore',
        '--source=$sha',
        '--worktree',
        '--',
        ...back.sublist(i, (i + chunk).clamp(0, back.length)),
      ]);
    }
    for (final p in list) {
      if (present.contains(p)) continue;
      final f = File('$repoRoot/$p');
      if (f.existsSync() || Link('$repoRoot/$p').existsSync()) f.deleteSync();
      _removeEmptyParents(p);
    }
    await unstage(list);
  }

  /// The index of [paths] back to HEAD (`git reset -q -- …`), the working
  /// tree untouched; paths neither in the index nor in HEAD are skipped
  /// (`git reset` fails on them).
  Future<void> unstage(Iterable<String> paths) async {
    final list = paths.toList();
    if (list.isEmpty) return;
    Future<Set<String>> listed(List<String> args) async => {
      for (final l in (await git([
        '--literal-pathspecs',
        ...args,
        '--',
        ...list,
      ])).split('\x00'))
        if (l.isNotEmpty) l,
    };
    final known = {
      ...await listed(['ls-files', '-z']),
      ...await listed(['ls-tree', '-r', '-z', '--name-only', 'HEAD']),
    };
    final reset = [
      for (final p in list)
        if (known.contains(p)) p,
    ];
    const chunk = 200;
    for (var i = 0; i < reset.length; i += chunk) {
      await git([
        '--literal-pathspecs',
        'reset',
        '-q',
        'HEAD',
        '--',
        ...reset.sublist(i, (i + chunk).clamp(0, reset.length)),
      ]);
    }
  }

  void _removeEmptyParents(String path) {
    var dir = File('$repoRoot/$path').parent;
    final root = Directory(repoRoot).absolute.path;
    while (dir.absolute.path.length > root.length && dir.existsSync()) {
      if (dir.listSync().isNotEmpty) return;
      dir.deleteSync();
      dir = dir.parent;
    }
  }

  /// Points HEAD at [sha] without touching the working tree: on [branch]
  /// (switched to with `symbolic-ref`, then moved with `reset --soft`) or
  /// detached when [branch] is null (SPEC-084 R8). The index keeps its
  /// entries.
  Future<void> moveHead(String sha, {String? branch}) async {
    _arg(sha, 'commit');
    final from = await headSha();
    if (branch == null) {
      await git(['update-ref', '--no-deref', 'HEAD', sha]);
    } else {
      final current = await currentBranch();
      if (current != branch) {
        await git([
          'symbolic-ref',
          'HEAD',
          'refs/heads/${_arg(branch, 'branch')}',
        ]);
      }
      await git(['reset', '-q', '--soft', sha]);
    }
    // What the commits between the two HEADs changed is not left staged
    // (a `reset --mixed` limited to those paths).
    if (from != null && from != sha) {
      await unstage([for (final c in await treeChanges(from, sha)) c.path]);
    }
  }

  /// Commits of `<base>..<head>`, newest first.
  Future<List<GitLogEntry>> commitsBetween(String base, String head) async {
    if (base == head) return const [];
    final out = await git([
      'log',
      '--format=%H%x1f%h%x1f%an%x1f%aI%x1f%s%x1e',
      '${_arg(base, 'commit')}..${_arg(head, 'commit')}',
    ]);
    return [
      for (final rec in out.split('\x1e'))
        if (rec.trim().isNotEmpty) _logEntry(rec.trim()),
    ];
  }

  /// Commits of `<base>..<head>` already in a remote branch, and those
  /// branches (`git branch -r --contains`; SPEC-084 R12).
  Future<({Set<String> commits, List<String> remotes})> pushedCommits(
    String base,
    String head,
  ) async {
    if (base == head) return (commits: <String>{}, remotes: <String>[]);
    final all = (await git([
      'rev-list',
      '${_arg(base, 'commit')}..${_arg(head, 'commit')}',
    ])).split('\n').where((l) => l.trim().isNotEmpty).map((l) => l.trim());
    final local =
        (await git(['rev-list', '$base..$head', '--not', '--remotes']))
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => l.trim())
            .toSet();
    final pushed = {
      for (final c in all)
        if (!local.contains(c)) c,
    };
    if (pushed.isEmpty) return (commits: pushed, remotes: <String>[]);
    final newest = all.firstWhere(pushed.contains);
    final remotes = [
      for (final l in (await git([
        'branch',
        '-r',
        '--contains',
        newest,
      ])).split('\n'))
        if (l.trim().isNotEmpty && !l.contains('->')) l.trim(),
    ];
    return (commits: pushed, remotes: remotes);
  }

  /// Refs under [prefix] with their hashes (`git for-each-ref`).
  Future<Map<String, String>> refsUnder(String prefix) async {
    final out = await git([
      'for-each-ref',
      '--format=%(refname) %(objectname)',
      _arg(prefix, 'prefixo'),
    ]);
    return {
      for (final l in out.split('\n'))
        if (l.contains(' ')) l.split(' ').first: l.split(' ').last,
    };
  }

  /// `git update-ref -d` of each of [refs] (missing ones are fine).
  Future<void> deleteRefList(Iterable<String> refs) async {
    for (final r in refs) {
      try {
        await git(['update-ref', '-d', _arg(r, 'ref')]);
      } on GitException {
        // already gone
      }
    }
  }

  /// Bytes of the objects that only the refs under [prefix] keep alive
  /// (`git rev-list --disk-usage`; SPEC-084 R14). Null when git cannot tell.
  Future<int?> diskUsageOnly(String prefix) async {
    try {
      final out = await git([
        'rev-list',
        '--objects',
        '--disk-usage',
        '--glob=${_arg(prefix, 'prefixo')}*',
        '--not',
        '--branches',
        '--tags',
        '--remotes',
      ]);
      return int.tryParse(out.trim());
    } on GitException {
      return null;
    }
  }

  /// Ignored files and folders (`--directory`) changed after [since]: what a
  /// restore point leaves out (SPEC-084 R6). At most [max].
  Future<List<String>> ignoredChangedSince(
    DateTime since, {
    int max = 5,
  }) async {
    final out = await git([
      'ls-files',
      '--others',
      '--ignored',
      '--exclude-standard',
      '--directory',
      '-z',
    ]);
    final found = <String>[];
    for (final p in out.split('\x00')) {
      if (p.isEmpty) continue;
      final stat = FileStat.statSync('$repoRoot/$p');
      if (stat.type == FileSystemEntityType.notFound) continue;
      if (stat.modified.isAfter(since)) found.add(p);
      if (found.length >= max) break;
    }
    return found;
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
