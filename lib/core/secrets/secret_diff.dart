import 'dart:io';

import '../git/git_service.dart';
import 'secret_rules.dart';
import 'secret_scanner.dart';

/// The diffs the Vigia de segredos reads (SPEC-085 R1, R5), built the same
/// way as the hook's `commit_diff` / `push_diff`.

const _emptyTree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';
const _diffArgs = [
  '-c',
  'core.quotePath=false',
  'diff',
  '--no-color',
  '--no-ext-diff',
  '--no-renames',
  '-U0',
];

/// Everything a commit may take: index and working tree against `HEAD`,
/// plus the untracked files that are not ignored.
Future<String> commitDiff(GitService git) async {
  String base;
  try {
    await git.git(['rev-parse', '-q', '--verify', 'HEAD']);
    base = 'HEAD';
  } on GitException {
    base = _emptyTree;
  }
  final parts = [
    await git.git([..._diffArgs, base]),
  ];
  final names = await git.git([
    'ls-files',
    '--others',
    '--exclude-standard',
    '-z',
  ]);
  for (final name in names.split('\u0000')) {
    if (name.isEmpty) continue;
    final f = File('${git.repoRoot}/$name');
    try {
      if (FileSystemEntity.isLinkSync(f.path) || !f.existsSync()) continue;
      final raf = f.openSync();
      try {
        parts.add(untrackedDiff(name, raf.readSync(secretDiffLimit + 1)));
      } finally {
        raf.closeSync();
      }
    } on FileSystemException {
      continue;
    }
  }
  return parts.join('\n');
}

/// Only what is staged (the manual commit with a partial index).
Future<String> stagedDiff(GitService git) async {
  try {
    await git.git(['rev-parse', '-q', '--verify', 'HEAD']);
    return await git.git([..._diffArgs, '--cached', 'HEAD']);
  } on GitException {
    return git.git([..._diffArgs, '--cached', _emptyTree]);
  }
}

/// Added lines of the commits not on any remote yet (`HEAD --not
/// --remotes`, at most 500 commits).
Future<String> pushDiff(GitService git) => git.git([
  '-c',
  'core.quotePath=false',
  'log',
  '-p',
  '--format=',
  '--no-color',
  '--no-ext-diff',
  '--no-renames',
  '-U0',
  '--max-count=500',
  'HEAD',
  '--not',
  '--remotes',
]);

/// Paths of the files a diff adds or changes (not deleted, not binary).
List<String> changedPaths(String diff) {
  final out = <String>[];
  for (final l in diff.split('\n')) {
    if (l.startsWith('+++ b/')) {
      final p = l.substring(6);
      if (!out.contains(p)) out.add(p);
    }
  }
  return out;
}
