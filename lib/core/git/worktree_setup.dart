import 'dart:io';

import 'package:flutter/foundation.dart';

import '../process/shell_runner.dart';
import 'git_service.dart';

/// Result of [WorktreeSetup.run].
@immutable
class WorktreeSetupResult {
  const WorktreeSetupResult({this.copied = const [], this.prepare});

  /// Files of `copiar:` copied from the root.
  final List<String> copied;

  /// `preparar:` (null = none).
  final ShellOutcome? prepare;

  bool get ok => prepare?.ok ?? true;
}

/// Makes a new worktree ready to run (`worktree:` of the config): copies the
/// ignored files the root has (`.env`…) and runs `preparar:` once.
class WorktreeSetup {
  WorktreeSetup({required this.root, required this.shell});

  /// The repository root (where the files come from).
  final GitService root;
  final ShellRunner shell;

  /// Copies each of [files] (relative) from the root to [worktree] when it
  /// exists in the root, is ignored by git (a tracked file is already in
  /// the worktree) and is not in the worktree yet.
  Future<List<String>> copyFiles(String worktree, List<String> files) async {
    final copied = <String>[];
    for (final rel in files) {
      final src = File('${root.repoRoot}/$rel');
      final dst = File('$worktree/$rel');
      if (!await src.exists() || await dst.exists()) continue;
      if (!await root.isIgnored(rel)) continue;
      await dst.parent.create(recursive: true);
      await src.copy(dst.path);
      copied.add(rel);
    }
    return copied;
  }

  Future<WorktreeSetupResult> run(
    String worktree, {
    List<String> copy = const [],
    String? prepare,
    Duration timeout = const Duration(minutes: 10),
    Map<String, String>? environment,
  }) async {
    final copied = await copyFiles(worktree, copy);
    final outcome = prepare == null
        ? null
        : await shell(
            prepare,
            cwd: worktree,
            timeout: timeout,
            environment: environment,
          );
    return WorktreeSetupResult(copied: copied, prepare: outcome);
  }
}

/// Smallest index ≥ 1 not in [used] (indices of the live worktrees).
int nextWorktreeIndex(Iterable<int?> used) {
  final taken = {for (final i in used) ?i};
  var i = 1;
  while (taken.contains(i)) {
    i++;
  }
  return i;
}

/// Variables of the sessions, terminals and commands run in a worktree.
Map<String, String> worktreeEnvironment({
  required String root,
  required String worktree,
  String? specCode,
  int? port,
}) => {
  'PROMPTORIUM_ROOT': root,
  'PROMPTORIUM_WORKTREE': worktree,
  'PROMPTORIUM_SPEC': ?specCode,
  if (port != null) 'PROMPTORIUM_PORT': '$port',
};
