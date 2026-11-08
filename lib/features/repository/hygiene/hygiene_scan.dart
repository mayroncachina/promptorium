import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/git/gh_cli.dart';
import '../../../core/git/git_service.dart';
import '../../../core/process/process_runner.dart';
import '../../review/merge_options.dart' show ConflictPrediction;
import '../../review/review_service.dart' show predictMergeConflict;

/// Why an item can't be selected (SPEC-047 R6). It stays in the list,
/// dimmed, with [reason].
@immutable
class Protection {
  const Protection(this.reason, {this.worktreePath});

  /// `sessão viva`, `alterações não commitadas`, `worktree em …`.
  final String reason;

  /// Set when the branch is only held by the worktree at this path: selecting
  /// that worktree (removed first) frees the branch.
  final String? worktreePath;

  @override
  bool operator ==(Object other) =>
      other is Protection &&
      other.reason == reason &&
      other.worktreePath == worktreePath;

  @override
  int get hashCode => Object.hash(reason, worktreePath);

  @override
  String toString() => reason;
}

/// A local branch already in the default branch (R2).
@immutable
class MergedBranch {
  const MergedBranch({
    required this.name,
    required this.sha,
    this.date,
    this.spec,
    this.pr,
    this.bySquash = false,
    this.upstream,
    this.remoteRef,
    this.protection,
  });

  final String name;
  final String sha;

  /// Date of the last commit.
  final DateTime? date;

  /// `SPEC-042 T1`, when known.
  final String? spec;

  /// Number of the merged PR, when `gh` knows it.
  final int? pr;

  /// Merged by squash: only the PR says so, git doesn't see it.
  final bool bySquash;

  /// `origin/spec/x`, kept for the undo.
  final String? upstream;

  /// `origin/<name>` when the remote branch exists and is merged too: it
  /// gets the separate "também no remoto" box.
  final String? remoteRef;
  final Protection? protection;

  String get id => 'branch:$name';
}

enum WorktreeKind {
  /// The folder no longer exists.
  orphan,

  /// The branch was merged or deleted.
  closed,

  /// No commit for more than [staleAfter] and no live session.
  stale,
}

/// A worktree that can go (R3).
@immutable
class WorktreeItem {
  const WorktreeItem({
    required this.path,
    required this.kind,
    this.branch,
    this.head,
    this.lastCommit,
    this.sizeBytes,
    this.dirty = false,
    this.protection,
  });

  final String path;
  final WorktreeKind kind;

  /// Null when detached.
  final String? branch;
  final String? head;
  final DateTime? lastCommit;

  /// `du` of the folder (null = not measured or the folder is gone).
  final int? sizeBytes;

  /// Uncommitted changes (tracked or untracked files).
  final bool dirty;
  final Protection? protection;

  String get id => 'wt:$path';

  bool get missing => kind == WorktreeKind.orphan;
}

/// An open branch behind the default branch (R4). Only informs.
@immutable
class BehindBranch {
  const BehindBranch({
    required this.name,
    required this.behind,
    required this.ahead,
    this.conflict,
    this.sessionId,
  });

  final String name;
  final int behind;
  final int ahead;

  /// Null = not checked (light scan).
  final ConflictPrediction? conflict;

  /// Last session of the branch: "Abrir no Review".
  final String? sessionId;
}

/// The `refs/promptorium/<key>/` refs of a closed spec (R5).
@immutable
class RefGroup {
  const RefGroup({
    required this.key,
    required this.refs,
    this.mergedAt,
    this.deleted = false,
  });

  /// `SPEC-020` (or a session id, for refs written before the spec code).
  final String key;
  final List<String> refs;
  final DateTime? mergedAt;

  /// The spec (or session) no longer exists.
  final bool deleted;

  String get prefix => 'refs/promptorium/$key/';
}

/// What the app database knows about one refs key ([HygieneContext]).
@immutable
class RefKeyInfo {
  const RefKeyInfo({required this.closed, this.mergedAt, this.branch});

  /// The spec is done / archived, or the session was merged.
  final bool closed;
  final DateTime? mergedAt;

  /// Branch of the session (a session id key): deleted = closed.
  final String? branch;
}

/// What the scan needs from outside git: sessions, specs and `gh`.
@immutable
class HygieneContext {
  const HygieneContext({
    this.liveBranches = const {},
    this.liveWorktrees = const {},
    this.sessionByBranch = const {},
    this.specByBranch = const {},
    this.refKeys = const {},
  });

  /// Branches / worktree paths of sessions with a live process.
  final Set<String> liveBranches;
  final Set<String> liveWorktrees;

  /// Last session of each branch ("Abrir no Review").
  final Map<String, String> sessionByBranch;

  /// Spec code of each branch known to the database.
  final Map<String, String> specByBranch;

  /// Refs keys known to the database (spec codes and session ids).
  final Map<String, RefKeyInfo> refKeys;
}

/// The four groups of the Higiene tab.
@immutable
class HygieneReport {
  const HygieneReport({
    required this.defaultBranch,
    required this.scannedAt,
    this.remote,
    this.merged = const [],
    this.worktrees = const [],
    this.behind = const [],
    this.refs = const [],
    this.ghAvailable = true,
  });

  final String defaultBranch;
  final String? remote;
  final DateTime scannedAt;
  final List<MergedBranch> merged;
  final List<WorktreeItem> worktrees;
  final List<BehindBranch> behind;
  final List<RefGroup> refs;

  /// False = merged PRs unknown: branches merged by squash are missing.
  final bool ghAvailable;

  /// The tab counter (Higiene · 89): every item of the four groups.
  int get total =>
      merged.length + worktrees.length + behind.length + refs.length;

  /// What the Início card counts (R8): merged branches and worktrees of
  /// closed specs.
  int get cleanable =>
      merged.length +
      worktrees.where((w) => w.kind == WorktreeKind.closed).length;

  int get worktreeBytes => worktrees.fold(0, (a, w) => a + (w.sizeBytes ?? 0));
}

/// Days without a commit after which a worktree is "parado".
const staleAfter = Duration(days: 14);

// --- protection rules (R6), pure ---------------------------------------------

/// Why branch [name] can't be deleted, or null. [checkedOut] maps each
/// branch checked out somewhere to that worktree's path.
Protection? branchProtection(
  String name, {
  required String defaultBranch,
  required String mainPath,
  Map<String, String> checkedOut = const {},
  Set<String> liveBranches = const {},
}) {
  if (name == defaultBranch) return const Protection('branch padrão');
  if (liveBranches.contains(name)) return const Protection('sessão viva');
  final wt = checkedOut[name];
  if (wt == null) return null;
  if (samePath(wt, mainPath)) return const Protection('branch atual');
  return Protection('worktree em ${shortWorktree(wt)}', worktreePath: wt);
}

/// Why a worktree can't be removed, or null.
Protection? worktreeProtection({
  bool dirty = false,
  bool live = false,
  bool locked = false,
}) {
  if (live) return const Protection('sessão viva');
  if (dirty) return const Protection('alterações não commitadas');
  if (locked) return const Protection('bloqueado');
  return null;
}

/// The situation of a worktree, or null when it is in use and fine (R3).
WorktreeKind? classifyWorktree({
  required bool missing,
  required String? branch,
  required bool branchExists,
  required bool branchMerged,
  required DateTime? lastCommit,
  required DateTime now,
  bool live = false,
}) {
  if (missing) return WorktreeKind.orphan;
  if (branch != null && (!branchExists || branchMerged)) {
    return WorktreeKind.closed;
  }
  if (!live && lastCommit != null && now.difference(lastCommit) > staleAfter) {
    return WorktreeKind.stale;
  }
  return null;
}

/// Whether the refs under `refs/promptorium/<key>/` belong to a closed spec:
/// done / merged in the database, a session whose branch is gone, or a key
/// the database no longer knows (deleted). Returns null for an open one.
RefGroup? closedRefGroup(
  String key,
  List<String> refs, {
  required Map<String, RefKeyInfo> known,
  required Set<String> localBranches,
}) {
  final info = known[key];
  if (info == null) return RefGroup(key: key, refs: refs, deleted: true);
  if (info.closed) {
    return RefGroup(key: key, refs: refs, mergedAt: info.mergedAt);
  }
  if (info.branch != null && !localBranches.contains(info.branch)) {
    return RefGroup(key: key, refs: refs, deleted: true);
  }
  return null;
}

/// `SPEC-042 T1` read from a branch name (`spec/042-t1-dados`,
/// `pr/spec-020-icone…`, `docs/spec-014-…`); null when there is none.
String? specOfBranchName(String name) {
  final m = RegExp(r'spec[-/_]?(\d{3})(?:-t(\d+)\b)?').firstMatch(name);
  if (m == null) return null;
  final t = m.group(2);
  return 'SPEC-${m.group(1)}${t == null ? '' : ' T$t'}';
}

bool samePath(String a, String b) => _norm(a) == _norm(b);

String _norm(String p) =>
    p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;

/// `promptorium-wt/release`: the last two folders of [path].
String shortWorktree(String path) {
  final parts = _norm(path).split('/').where((p) => p.isNotEmpty).toList();
  return parts.length <= 2
      ? parts.join('/')
      : parts.skip(parts.length - 2).join('/');
}

/// [path] with the home folder as `~`.
String tildePath(String path, {String? home}) {
  final h = home ?? Platform.environment['HOME'];
  if (h == null || h.isEmpty) return path;
  return path == h || path.startsWith('$h/')
      ? '~${path.substring(h.length)}'
      : path;
}

// --- scan ----------------------------------------------------------------------

typedef _Local = ({String sha, DateTime? date, String? upstream});

/// Builds the four groups of [repoPath] (the main repository) from git, the
/// merged PRs of `gh` and [context]. [light] skips what is slow (disk size,
/// uncommitted changes, conflicts): enough for the Início card.
Future<HygieneReport> scanHygiene({
  required GitService git,
  required String repoPath,
  required String defaultBranch,
  String? remote,
  GhCli? gh,
  HygieneContext context = const HygieneContext(),
  ProcessRunner? run,
  DateTime? now,
  bool light = false,
}) async {
  final at = now ?? DateTime.now();
  final runner = run ?? Process.run;

  // Local branches.
  final locals = <String, _Local>{};
  for (final line in (await git.git([
    'for-each-ref',
    '--format=%(refname:short)%09%(objectname)%09%(committerdate:iso-strict)%09%(upstream:short)',
    'refs/heads/',
  ])).split('\n')) {
    final f = line.split('\t');
    if (f.length < 2 || f[0].isEmpty) continue;
    locals[f[0]] = (
      sha: f[1],
      date: f.length > 2 ? DateTime.tryParse(f[2]) : null,
      upstream: f.length > 3 && f[3].isNotEmpty ? f[3] : null,
    );
  }

  // Remote branches.
  final remotes = <String, String>{};
  if (remote != null) {
    for (final line in (await git.git([
      'for-each-ref',
      '--format=%(refname:short)%09%(objectname)',
      'refs/remotes/$remote/',
    ])).split('\n')) {
      final f = line.split('\t');
      if (f.length < 2 || !f[0].startsWith('$remote/')) continue;
      final name = f[0].substring(remote.length + 1);
      if (name != 'HEAD' && name.isNotEmpty) remotes[name] = f[1];
    }
  }

  // The bases: the local default branch and the remote one.
  final bases = [
    if (locals.containsKey(defaultBranch)) 'refs/heads/$defaultBranch',
    if (remotes.containsKey(defaultBranch))
      'refs/remotes/$remote/$defaultBranch',
  ];
  final base = bases.isEmpty ? null : bases.first;
  final mergedLocal = <String>{};
  final mergedRemote = <String>{};
  for (final b in bases) {
    mergedLocal.addAll(await _names(git, ['branch', '--merged', b]));
    if (remote != null) {
      for (final r in await _names(git, ['branch', '-r', '--merged', b])) {
        if (r.startsWith('$remote/')) {
          mergedRemote.add(r.substring(remote.length + 1));
        }
      }
    }
  }

  // Merged PRs (squash).
  var ghOk = gh != null;
  final prs = <String, GhPullRequest>{};
  if (gh != null) {
    try {
      for (final p in await gh.prListMerged()) {
        prs.putIfAbsent(p.headRefName, () => p);
      }
    } catch (e) {
      debugPrint('higiene: gh pr list falhou — $e');
      ghOk = false;
    }
  }

  Future<bool> inPr(String sha, GhPullRequest pr) async {
    if (pr.headRefOid.isEmpty) return false;
    if (pr.headRefOid == sha) return true;
    try {
      await git.git(['merge-base', '--is-ancestor', sha, pr.headRefOid]);
      return true;
    } on GitException {
      return false;
    }
  }

  // Worktrees.
  final allWorktrees = await git.listWorktrees();
  final prunable = await git.pruneDryRun().catchError((Object e) {
    debugPrint('higiene: prune --dry-run falhou — $e');
    return <String>{};
  });
  final checkedOut = <String, String>{
    for (final w in allWorktrees)
      if (w.branch != null && !w.bare) w.branch!: w.path,
  };

  // Group 1: merged branches.
  final merged = <MergedBranch>[];
  final squash = <String>{};
  for (final MapEntry(key: name, value: b) in locals.entries) {
    if (name == defaultBranch) continue;
    final pr = prs[name];
    final byAncestry = mergedLocal.contains(name);
    final bySquash = !byAncestry && pr != null && await inPr(b.sha, pr);
    if (!byAncestry && !bySquash) continue;
    if (bySquash) squash.add(name);
    final rsha = remotes[name];
    final remoteMerged =
        rsha != null &&
        (mergedRemote.contains(name) ||
            rsha == b.sha ||
            (pr != null && await inPr(rsha, pr)));
    merged.add(
      MergedBranch(
        name: name,
        sha: b.sha,
        date: b.date,
        spec: context.specByBranch[name] ?? specOfBranchName(name),
        pr: pr?.number,
        bySquash: bySquash,
        upstream: b.upstream,
        remoteRef: remoteMerged ? '$remote/$name' : null,
        protection: branchProtection(
          name,
          defaultBranch: defaultBranch,
          mainPath: repoPath,
          checkedOut: checkedOut,
          liveBranches: context.liveBranches,
        ),
      ),
    );
  }
  // What can go first, then the protected ones; newest first; same date =
  // by name, so the list doesn't shuffle.
  merged.sort((a, b) {
    final p = (a.protection == null ? 0 : 1) - (b.protection == null ? 0 : 1);
    if (p != 0) return p;
    final d = (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970));
    return d != 0 ? d : a.name.compareTo(b.name);
  });
  final mergedNames = {for (final m in merged) m.name};

  // Group 2: worktrees.
  final worktreeJobs = <Future<WorktreeItem?> Function()>[];
  for (final w in allWorktrees) {
    if (w.bare || samePath(w.path, repoPath)) continue;
    worktreeJobs.add(() async {
      final missing =
          w.prunable ||
          prunable.any((p) => samePath(p, w.path)) ||
          !Directory(w.path).existsSync();
      final live =
          context.liveWorktrees.any((p) => samePath(p, w.path)) ||
          (w.branch != null && context.liveBranches.contains(w.branch));
      DateTime? last;
      if (w.head != null) {
        try {
          last = DateTime.tryParse(
            (await git.git(['log', '-1', '--format=%cI', w.head!])).trim(),
          );
        } on GitException {
          last = null;
        }
      }
      final kind = classifyWorktree(
        missing: missing,
        branch: w.branch,
        branchExists: w.branch != null && locals.containsKey(w.branch),
        branchMerged: mergedNames.contains(w.branch),
        lastCommit: last,
        now: at,
        live: live,
      );
      if (kind == null) return null;
      var dirty = false;
      int? size;
      if (!light && !missing) {
        dirty = await _dirty(runner, w.path);
        size = await _diskUsage(runner, w.path);
      }
      return WorktreeItem(
        path: w.path,
        kind: kind,
        branch: w.branch,
        head: w.head,
        lastCommit: last,
        sizeBytes: size,
        dirty: dirty,
        protection: worktreeProtection(
          dirty: dirty,
          live: live,
          locked: w.locked,
        ),
      );
    });
  }
  final worktrees = [for (final w in await _pooled(worktreeJobs)) ?w]
    ..sort(_worktreeOrder);

  // Group 3: open branches behind the base.
  final behind = <BehindBranch>[];
  if (base != null) {
    final open = [
      for (final name in locals.keys)
        if (name != defaultBranch && !mergedNames.contains(name)) name,
    ];
    final rows = await _pooled([
      for (final name in open)
        () async {
          try {
            final ab = await git.aheadBehind('refs/heads/$name', base);
            if (ab.behind == 0) return null;
            return BehindBranch(
              name: name,
              behind: ab.behind,
              ahead: ab.ahead,
              conflict: light
                  ? null
                  : await predictMergeConflict(git, base, 'refs/heads/$name'),
              sessionId: context.sessionByBranch[name],
            );
          } on GitException catch (e) {
            debugPrint('higiene: $name — $e');
            return null;
          }
        },
    ]);
    behind
      ..addAll(rows.nonNulls)
      ..sort((a, b) => b.behind.compareTo(a.behind));
  }

  // Group 4: internal refs of closed specs.
  final byKey = <String, List<String>>{};
  for (final r in (await git.git([
    'for-each-ref',
    '--format=%(refname)',
    'refs/promptorium/',
  ])).split('\n')) {
    final parts = r.trim().split('/');
    if (parts.length < 4) continue;
    (byKey[parts[2]] ??= []).add(r.trim());
  }
  final refs = [
    for (final MapEntry(:key, :value) in byKey.entries)
      ?closedRefGroup(
        key,
        value,
        known: context.refKeys,
        localBranches: locals.keys.toSet(),
      ),
  ]..sort((a, b) => a.key.compareTo(b.key));

  return HygieneReport(
    defaultBranch: defaultBranch,
    remote: remote,
    scannedAt: at,
    merged: merged,
    worktrees: worktrees,
    behind: behind,
    refs: refs,
    ghAvailable: ghOk,
  );
}

/// Closed specs, stale, orphans, then the protected ones; biggest first.
int _worktreeOrder(WorktreeItem a, WorktreeItem b) {
  int rank(WorktreeItem w) => w.protection != null
      ? 3
      : switch (w.kind) {
          WorktreeKind.closed => 0,
          WorktreeKind.stale => 1,
          WorktreeKind.orphan => 2,
        };
  final r = rank(a).compareTo(rank(b));
  if (r != 0) return r;
  final s = (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
  return s != 0 ? s : a.path.compareTo(b.path);
}

Future<List<String>> _names(GitService git, List<String> args) async => [
  for (final l in (await git.git([
    ...args,
    '--format=%(refname:short)',
  ])).split('\n'))
    if (l.trim().isNotEmpty) l.trim(),
];

/// Runs [jobs] [width] at a time (a repository with dozens of branches must
/// not start dozens of git processes at once), keeping their order.
Future<List<T>> _pooled<T>(
  List<Future<T> Function()> jobs, {
  int width = 6,
}) async {
  final results = List<T?>.filled(jobs.length, null);
  var next = 0;
  Future<void> lane() async {
    while (next < jobs.length) {
      final i = next++;
      results[i] = await jobs[i]();
    }
  }

  await Future.wait([for (var i = 0; i < width; i++) lane()]);
  return results.cast<T>();
}

Future<bool> _dirty(ProcessRunner run, String path) async {
  try {
    final r = await run('git', ['-C', path, 'status', '--porcelain']);
    // Unreadable = treated as dirty: nothing is removed without knowing.
    return r.exitCode != 0 || '${r.stdout}'.trim().isNotEmpty;
  } catch (_) {
    return true;
  }
}

Future<int?> _diskUsage(ProcessRunner run, String path) async {
  try {
    final r = await run('du', ['-sk', '--', path]);
    if (r.exitCode != 0 && '${r.stdout}'.trim().isEmpty) return null;
    final kb = int.tryParse('${r.stdout}'.trim().split(RegExp(r'\s+')).first);
    return kb == null ? null : kb * 1024;
  } catch (_) {
    return null;
  }
}
