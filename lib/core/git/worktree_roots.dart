import 'dart:io';

import 'package:path/path.dart' as p;

/// What a `git commit` in a linked worktree writes outside it (SPEC-096
/// R10, SPEC-093 R8): its own `worktrees/<wt>` dir and the shared
/// `objects`, `refs` and `logs` of the git common dir. Never the whole
/// `.git`: `hooks/` and `config` would run outside the sandbox later.
///
/// Read from the files git itself keeps (`<wt>/.git` = `gitdir: …`, then
/// `<gitdir>/commondir`), without running git. Empty when [worktree] is not
/// a linked worktree (the project root, a plain folder).
List<String> worktreeWritableRoots(String worktree) {
  final marker = File(p.join(worktree, '.git'));
  if (!marker.existsSync()) return const [];
  final line = marker.readAsStringSync().trim();
  if (!line.startsWith('gitdir:')) return const [];
  var gitDir = line.substring('gitdir:'.length).trim();
  if (!p.isAbsolute(gitDir)) gitDir = p.join(worktree, gitDir);
  gitDir = p.normalize(gitDir);
  final commonFile = File(p.join(gitDir, 'commondir'));
  if (!commonFile.existsSync()) return const [];
  var common = commonFile.readAsStringSync().trim();
  if (!p.isAbsolute(common)) common = p.join(gitDir, common);
  common = p.normalize(common);
  return [
    gitDir,
    for (final d in ['objects', 'refs', 'logs']) p.join(common, d),
  ];
}
