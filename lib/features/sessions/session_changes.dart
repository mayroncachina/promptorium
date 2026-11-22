import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/diff_parser.dart';
import '../../core/git/git_service.dart';
import '../../data/providers.dart';

/// What a session changed in its worktree.
///
/// SPEC-111 R1, R2: in a worktree with `baseBranch`, measured from the
/// `merge-base` of `baseBranch` and `HEAD` (the session's commits plus what
/// is still loose, untracked files included); without a base branch or a
/// merge-base, from `HEAD` (only what is not committed yet).
@immutable
class SessionChanges {
  const SessionChanges({
    this.entries = const [],
    this.numstat = const {},
    this.files = const [],
    this.base,
    this.baseBranch,
    this.error,
  });

  /// Changed files: tracked ones (vs. the base) first, then the untracked.
  /// From the `HEAD`, the entries of `git status --porcelain`.
  final List<GitStatusEntry> entries;

  /// `git diff --numstat <base>`: path → (added, deleted); binary = (-1, -1).
  final Map<String, (int, int)> numstat;

  /// `git diff <base>` parsed by [DiffParser].
  final List<DiffFile> files;

  /// The merge-base the changes are measured from (null: `HEAD`).
  final String? base;

  /// The branch whose merge-base is [base] (null: `HEAD`).
  final String? baseBranch;
  final String? error;

  int get count => entries.length;

  /// How the Diff tab names the measure.
  String get baseLabel => base == null || baseBranch == null
      ? 'git diff HEAD'
      : 'desde $baseBranch';
}

/// Parses `git diff --numstat` output.
Map<String, (int, int)> parseNumstat(String out) {
  final result = <String, (int, int)>{};
  for (final line in out.split('\n')) {
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    result[parts.sublist(2).join('\t')] = (
      int.tryParse(parts[0]) ?? -1,
      int.tryParse(parts[1]) ?? -1,
    );
  }
  return result;
}

/// Parses `git diff --name-status -z --no-renames` output into entries
/// (status letter in [GitStatusEntry.x]).
List<GitStatusEntry> parseNameStatusZ(String out) {
  final parts = out.split('\x00');
  final result = <GitStatusEntry>[];
  for (var i = 0; i + 1 < parts.length; i += 2) {
    final code = parts[i];
    final path = parts[i + 1];
    if (code.isEmpty || path.isEmpty) continue;
    result.add(GitStatusEntry(path: path, x: code.substring(0, 1), y: ' '));
  }
  return result;
}

/// Loads the changes of the worktree of [git] (SPEC-111 T1). One
/// `merge-base` per load and no git call per file (R6).
Future<SessionChanges> loadSessionChanges(
  GitService git, {
  String? baseBranch,
}) async {
  try {
    final status = await git.status();
    final base = baseBranch == null
        ? null
        : await git.mergeBase(baseBranch, 'HEAD');
    if (base == null) {
      // R2: from the HEAD, as before.
      final numstat = parseNumstat(
        await git.git(['diff', '--numstat', '--no-color', 'HEAD']),
      );
      final files = DiffParser.parse(await git.diff(base: 'HEAD'));
      return SessionChanges(entries: status, numstat: numstat, files: files);
    }
    // R1: commits + loose changes (the work tree against the merge-base);
    // `git status` only for the untracked files.
    final tracked = parseNameStatusZ(
      await git.git(['diff', '--name-status', '-z', '--no-renames', base]),
    );
    final numstat = parseNumstat(
      await git.git(['diff', '--numstat', '--no-color', '--no-renames', base]),
    );
    final files = DiffParser.parse(
      await git.git([
        'diff',
        '--no-color',
        '--no-ext-diff',
        '--unified=3',
        '--no-renames',
        base,
      ]),
    );
    return SessionChanges(
      entries: [...tracked, ...status.where((e) => e.isUntracked)],
      numstat: numstat,
      files: files,
      base: base,
      baseBranch: baseBranch,
    );
  } on GitException catch (e) {
    return SessionChanges(error: '$e');
  }
}

/// Changed files + diff of a session (invalidated by `SessionManager` after
/// each `result` and after the app's commit of a Codex turn).
final sessionChangesProvider = FutureProvider.family<SessionChanges, String>((
  ref,
  sessionId,
) async {
  final s = await ref.read(sessionsRepoProvider).getById(sessionId);
  if (s == null) return const SessionChanges();
  final git = ref.read(gitServiceFactoryProvider)(s.worktreePath);
  return loadSessionChanges(git, baseBranch: s.baseBranch);
});
