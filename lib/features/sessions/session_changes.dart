import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/diff_parser.dart';
import '../../core/git/git_service.dart';
import '../../data/providers.dart';

/// Uncommitted changes of a session's worktree (vs. `HEAD`).
@immutable
class SessionChanges {
  const SessionChanges({
    this.entries = const [],
    this.numstat = const {},
    this.files = const [],
    this.error,
  });

  /// `git status --porcelain` (includes untracked files).
  final List<GitStatusEntry> entries;

  /// `git diff --numstat HEAD`: path → (added, deleted); binary = (-1, -1).
  final Map<String, (int, int)> numstat;

  /// `git diff HEAD` parsed by [DiffParser].
  final List<DiffFile> files;
  final String? error;

  int get count => entries.length;
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

/// Changed files + diff of a session (invalidated by `SessionManager` after
/// each `result`).
final sessionChangesProvider = FutureProvider.family<SessionChanges, String>((
  ref,
  sessionId,
) async {
  final s = await ref.read(sessionsRepoProvider).getById(sessionId);
  if (s == null) return const SessionChanges();
  final git = ref.read(gitServiceFactoryProvider)(s.worktreePath);
  try {
    final entries = await git.status();
    final numstat = parseNumstat(
      await git.git(['diff', '--numstat', '--no-color', 'HEAD']),
    );
    final files = DiffParser.parse(await git.diff(base: 'HEAD'));
    return SessionChanges(entries: entries, numstat: numstat, files: files);
  } on GitException catch (e) {
    return SessionChanges(error: '$e');
  }
});
