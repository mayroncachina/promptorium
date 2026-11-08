import 'package:flutter/foundation.dart';

import '../../../core/git/git_service.dart';
import 'hygiene_scan.dart';

/// What the person confirmed in "Limpar selecionados" (SPEC-047 R6).
@immutable
class CleanupRequest {
  const CleanupRequest({
    this.worktrees = const [],
    this.branches = const [],
    this.remoteBranches = const [],
    this.refs = const [],
    this.deleteRemote = false,
  });

  final List<WorktreeItem> worktrees;

  /// Local branches (`git branch -d`).
  final List<MergedBranch> branches;

  /// Branches whose "também no remoto" box is checked.
  final List<MergedBranch> remoteBranches;
  final List<RefGroup> refs;

  /// The confirmation's own box: without it nothing leaves the remote.
  final bool deleteRemote;

  bool get isEmpty =>
      worktrees.isEmpty &&
      branches.isEmpty &&
      (remoteBranches.isEmpty || !deleteRemote) &&
      refs.isEmpty;
}

/// A worktree removed by the cleanup, enough to put it back.
@immutable
class RemovedWorktree {
  const RemovedWorktree({
    required this.path,
    this.branch,
    this.head,
    this.sizeBytes,
    this.wasMissing = false,
  });

  final String path;
  final String? branch;
  final String? head;
  final int? sizeBytes;

  /// The folder was already gone: nothing to put back.
  final bool wasMissing;
}

/// A local branch deleted by the cleanup: its commit and upstream.
@immutable
class DeletedBranch {
  const DeletedBranch({required this.name, required this.sha, this.upstream});

  final String name;
  final String sha;
  final String? upstream;
}

/// What the cleanup did, in order, and what git refused (R6, R7).
@immutable
class CleanupOutcome {
  const CleanupOutcome({
    required this.finishedAt,
    this.worktrees = const [],
    this.branches = const [],
    this.remoteBranches = const [],
    this.refs = const [],
    this.errors = const {},
  });

  final DateTime finishedAt;
  final List<RemovedWorktree> worktrees;
  final List<DeletedBranch> branches;

  /// `origin/x` deleted on the remote (they don't come back).
  final List<String> remoteBranches;

  /// Keys whose refs were removed (they don't come back).
  final List<String> refs;

  /// Item id ([WorktreeItem.id], [MergedBranch.id], `remote:<name>`,
  /// `refs:<key>`) → git's message.
  final Map<String, String> errors;

  int get freedBytes => worktrees.fold(0, (a, w) => a + (w.sizeBytes ?? 0));

  bool get undoable =>
      worktrees.any((w) => !w.wasMissing) || branches.isNotEmpty;
}

/// What the undo brought back.
@immutable
class UndoOutcome {
  const UndoOutcome({
    this.branches = const [],
    this.worktrees = const [],
    this.errors = const [],
  });

  final List<String> branches;
  final List<String> worktrees;
  final List<String> errors;
}

class UndoExpiredException implements Exception {
  const UndoExpiredException();

  @override
  String toString() => 'O prazo para desfazer acabou.';
}

/// Deletes in the order that keeps git happy — worktrees, local branches,
/// remote branches, refs — never forcing anything, and keeps the commits
/// for [undo] (SPEC-047 R6, R7).
class HygieneCleaner {
  HygieneCleaner(this.git, {this.remote, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final GitService git;

  /// Remote name (`origin`).
  final String? remote;
  final DateTime Function() _clock;

  /// How long "Desfazer" stays available.
  static const undoWindow = Duration(seconds: 15);

  Future<CleanupOutcome> clean(CleanupRequest r) async {
    final errors = <String, String>{};
    final removed = <RemovedWorktree>[];
    final deleted = <DeletedBranch>[];
    final remoteDeleted = <String>[];
    final refs = <String>[];

    // 1. Worktrees: without --force, git refuses a dirty one.
    for (final w in r.worktrees) {
      if (w.protection != null) {
        errors[w.id] = w.protection!.reason;
        continue;
      }
      try {
        await git.removeWorktree(w.path);
        removed.add(
          RemovedWorktree(
            path: w.path,
            branch: w.branch,
            head: w.head,
            sizeBytes: w.sizeBytes,
            wasMissing: w.missing,
          ),
        );
      } on GitException catch (e) {
        errors[w.id] = _message(e);
      }
    }

    // 2. Local branches, only with -d: a refusal stays as the item's error.
    final refused = <String>{};
    for (final b in r.branches) {
      final p = b.protection;
      final freed =
          p?.worktreePath != null &&
          removed.any((w) => samePath(w.path, p!.worktreePath!));
      if (p != null && !freed) {
        errors[b.id] = p.reason;
        refused.add(b.name);
        continue;
      }
      final sha = await git.resolveRef('refs/heads/${b.name}') ?? b.sha;
      try {
        await git.deleteBranch(b.name);
        deleted.add(
          DeletedBranch(name: b.name, sha: sha, upstream: b.upstream),
        );
      } on GitException catch (e) {
        errors[b.id] = _message(e);
        refused.add(b.name);
      }
    }

    // 3. Remote branches, only with the confirmation's box checked, and
    //    never one whose local branch git refused.
    if (r.deleteRemote && remote != null) {
      for (final b in r.remoteBranches) {
        if (b.remoteRef == null || refused.contains(b.name)) continue;
        try {
          await git.git([
            'push',
            '-q',
            remote!,
            '--delete',
            'refs/heads/${b.name}',
          ]);
          remoteDeleted.add('$remote/${b.name}');
        } on GitException catch (e) {
          errors['remote:${b.name}'] = _message(e);
        }
      }
    }

    // 4. Internal refs.
    for (final g in r.refs) {
      try {
        await git.deleteRefs(g.prefix);
        refs.add(g.key);
      } on GitException catch (e) {
        errors['refs:${g.key}'] = _message(e);
      }
    }

    return CleanupOutcome(
      finishedAt: _clock(),
      worktrees: removed,
      branches: deleted,
      remoteBranches: remoteDeleted,
      refs: refs,
      errors: errors,
    );
  }

  /// Within [undoWindow]: the local branches come back at their commits
  /// (with the upstream, when the remote branch is still there), then the
  /// worktrees of branches that exist. Remote branches and refs don't.
  Future<UndoOutcome> undo(CleanupOutcome o) async {
    if (_clock().difference(o.finishedAt) > undoWindow) {
      throw const UndoExpiredException();
    }
    final branches = <String>[];
    final worktrees = <String>[];
    final errors = <String>[];
    for (final b in o.branches) {
      try {
        if (await git.resolveRef('refs/heads/${b.name}') == null) {
          await git.git(['branch', b.name, b.sha]);
        }
        branches.add(b.name);
        final up = b.upstream;
        if (up != null && await git.resolveRef('refs/remotes/$up') != null) {
          await git.git(['branch', '--set-upstream-to=$up', b.name]);
        }
      } on GitException catch (e) {
        errors.add('${b.name}: ${_message(e)}');
      }
    }
    for (final w in o.worktrees) {
      if (w.wasMissing) continue;
      try {
        if (w.branch != null) {
          if (await git.resolveRef('refs/heads/${w.branch}') == null) continue;
          await git.git(['worktree', 'add', '-q', w.path, w.branch!]);
        } else if (w.head != null) {
          await git.git(['worktree', 'add', '-q', '--detach', w.path, w.head!]);
        } else {
          continue;
        }
        worktrees.add(w.path);
      } on GitException catch (e) {
        errors.add('${w.path}: ${_message(e)}');
      }
    }
    return UndoOutcome(
      branches: branches,
      worktrees: worktrees,
      errors: errors,
    );
  }

  static String _message(GitException e) {
    final s = e.stderr.trim().isEmpty ? e.stdout.trim() : e.stderr.trim();
    if (s.isEmpty) return e.message;
    return s
        .split('\n')
        .first
        .replaceFirst(RegExp(r'^(error|fatal|erro): '), '');
  }
}
