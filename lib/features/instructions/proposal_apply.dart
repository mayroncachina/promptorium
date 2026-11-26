import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/git/git_service.dart';
import '../../core/providers/instructions_files.dart';
import '../../core/providers/workspace_assets.dart';
import '../project/project_config.dart';
import 'interview_data.dart';

/// Applying the proposal of the interview (SPEC-113 R19–R21): the accepted
/// trechos go into the root `AGENTS.md` / `CLAUDE.md` through the safe write
/// of T1 (R5); a trecho whose old text is no longer in the file comes back
/// as a conflict and is not written (R19). The cited paths are checked
/// against the project (R20) and, when asked, only the instruction files
/// are committed on the current branch, without push (R21).

/// The files a trecho may change (R19, R21).
const instructionRootFiles = [agentsMdName, claudeMdName];

/// The commit message of "Commitar ao aplicar" (R21).
const instructionsCommitMessage = 'docs: instruções dos agentes';

/// The section of the `CLAUDE.md` that is everything but the import (R9):
/// a trecho there goes to the end of the file, never under a new heading.
const claudeOnlySection = 'Só para o Claude Code';

/// `AGENTS.md` / `CLAUDE.md` for the root files the trecho names
/// (`./AGENTS.md` too); null = any other file (never written).
String? instructionFileOf(String file) {
  final f = file.trim().replaceFirst(RegExp(r'^\./'), '');
  return instructionRootFiles.contains(f) ? f : null;
}

// --- Seções ----------------------------------------------------------------------

final _heading = RegExp(r'^ {0,3}(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$');
final _fenceLine = RegExp(r'^ {0,3}(`{3,}|~{3,})');

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The heading lines of [lines] outside code blocks: (index, level, title).
List<(int, int, String)> _headings(List<String> lines) {
  final out = <(int, int, String)>[];
  String? fence;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final f = _fenceLine.firstMatch(line)?.group(1);
    if (fence != null) {
      if (f != null && f[0] == fence[0] && f.length >= fence.length) {
        fence = null;
      }
      continue;
    }
    if (f != null) {
      fence = f;
      continue;
    }
    final m = _heading.firstMatch(line);
    if (m != null) out.add((i, m.group(1)!.length, m.group(2)!));
  }
  return out;
}

/// The lines `[start, end)` of [section] in [lines] (the heading is
/// `start - 1`); null = no such heading.
(int, int)? _sectionRange(List<String> lines, String section) {
  if (section.trim().isEmpty) return null;
  final hs = _headings(lines);
  for (var i = 0; i < hs.length; i++) {
    final (index, level, title) = hs[i];
    if (_norm(title) != _norm(section)) continue;
    var end = lines.length;
    for (final (j, l, _) in hs.skip(i + 1)) {
      if (l <= level) {
        end = j;
        break;
      }
    }
    return (index + 1, end);
  }
  return null;
}

bool _isClaudeOnly(String file, String section) =>
    file == claudeMdName && _norm(section) == _norm(claudeOnlySection);

/// Whether [hunk] creates its section (the "seção nova" tag): an insertion
/// into a section [text] does not have.
bool isNewSection(String? text, InstructionProposalHunk hunk) {
  if (!hunk.isInsertion || hunk.section.trim().isEmpty) return false;
  final file = instructionFileOf(hunk.file);
  if (file == null || _isClaudeOnly(file, hunk.section)) return false;
  if (text == null) return true;
  return _sectionRange(text.split('\n'), hunk.section) == null;
}

// --- Aplicar um trecho -----------------------------------------------------------

/// [text] with [hunk] applied (R19); null = conflict: the old text is not in
/// [text] any more (or the file does not exist). [text] null = no file.
///
/// A replacement swaps the old text for the new one, preferring the
/// occurrence inside its section. An insertion (`oldText` empty) goes to
/// the end of its section, before the blank lines that close it; without
/// the section, to the end of the file under a new `## <seção>` heading
/// (unless the new text brings its own heading).
String? applyHunkText(String? text, InstructionProposalHunk hunk) {
  final file = instructionFileOf(hunk.file) ?? hunk.file;
  if (!hunk.isInsertion) {
    if (text == null) return null;
    var old = hunk.oldText;
    var at = _find(text, old, hunk.section);
    if (at < 0) {
      // The AI often drops (or adds) the line break at the end.
      final trimmed = old.trimRight();
      if (trimmed.isNotEmpty && trimmed != old) {
        old = trimmed;
        at = _find(text, old, hunk.section);
      }
    }
    if (at < 0) return null;
    var replacement = hunk.newText;
    if (old.endsWith('\n') && replacement.isNotEmpty) {
      if (!replacement.endsWith('\n')) replacement = '$replacement\n';
    } else if (!old.endsWith('\n') && replacement.endsWith('\n')) {
      replacement = replacement.substring(0, replacement.length - 1);
    }
    var end = at + old.length;
    // Removing whole lines removes their line break too.
    if (replacement.isEmpty &&
        (at == 0 || text[at - 1] == '\n') &&
        end < text.length &&
        text[end] == '\n') {
      end++;
    }
    return text.replaceRange(at, end, replacement);
  }
  final add = hunk.newText.replaceAll(RegExp(r'\n+$'), '');
  if (add.trim().isEmpty) return text;
  final source = text ?? '';
  final lines = source.split('\n');
  final range = _isClaudeOnly(file, hunk.section)
      ? (0, lines.length)
      : _sectionRange(lines, hunk.section);
  if (range != null) {
    final (start, end) = range;
    var k = end - 1;
    while (k >= start && lines[k].trim().isEmpty) {
      k--;
    }
    final insertAt = k + 1;
    lines.insertAll(insertAt, add.split('\n'));
    var out = lines.join('\n');
    if (!out.endsWith('\n')) out = '$out\n';
    return out;
  }
  // A new section at the end of the file.
  final section = hunk.section.trim();
  final ownHeading = _heading.hasMatch(add.split('\n').first);
  final block = section.isEmpty || ownHeading ? add : '## $section\n$add';
  final body = source.replaceAll(RegExp(r'\s+$'), '');
  return body.isEmpty ? '$block\n' : '$body\n\n$block\n';
}

int _find(String text, String old, String section) {
  if (old.isEmpty) return -1;
  final lines = text.split('\n');
  final range = _sectionRange(lines, section);
  if (range != null) {
    final (start, end) = range;
    var from = 0;
    for (var i = 0; i < start; i++) {
      from += lines[i].length + 1;
    }
    var to = from;
    for (var i = start; i < end; i++) {
      to += lines[i].length + 1;
    }
    final at = text.indexOf(old, from);
    if (at >= 0 && at + old.length <= to) return at;
  }
  return text.indexOf(old);
}

/// Why a trecho was not applied.
enum ProposalConflictKind {
  /// The old text is no longer in the file (R19).
  notFound,

  /// The trecho names a file other than the root `AGENTS.md` / `CLAUDE.md`.
  otherFile,
}

/// The files after the accepted trechos, and the ones that did not apply.
@immutable
class ProposalPlan {
  const ProposalPlan({
    required this.before,
    required this.after,
    required this.conflicts,
  });

  /// `AGENTS.md` / `CLAUDE.md` → text (null = no file).
  final Map<String, String?> before;
  final Map<String, String?> after;

  /// Index of the trecho (in the list given) → why it did not apply.
  final Map<int, ProposalConflictKind> conflicts;

  /// The files whose text changes.
  List<String> get changed => [
    for (final f in instructionRootFiles)
      if (before[f] != after[f]) f,
  ];
}

/// Applies [hunks] in order to [texts] (R19). The `CLAUDE.md` keeps its
/// `@AGENTS.md` line: the trechos go to the "Só para o Claude Code" part
/// ([splitClaudeMd]) and the file is composed back ([composeClaudeMd]).
ProposalPlan planProposal(
  Map<String, String?> texts,
  List<InstructionProposalHunk> hunks,
) {
  final before = {for (final f in instructionRootFiles) f: texts[f]};
  final after = Map<String, String?>.of(before);
  final conflicts = <int, ProposalConflictKind>{};
  // The CLAUDE.md with the import on top is edited without it.
  final claude = before[claudeMdName];
  final split = claude != null && agentsImportLineIndex(claude) == 0
      ? splitClaudeMd(claude)
      : null;
  if (split != null) after[claudeMdName] = split.claudeOnly;
  for (var i = 0; i < hunks.length; i++) {
    final file = instructionFileOf(hunks[i].file);
    if (file == null) {
      conflicts[i] = ProposalConflictKind.otherFile;
      continue;
    }
    final next = applyHunkText(after[file], hunks[i]);
    if (next == null) {
      conflicts[i] = ProposalConflictKind.notFound;
    } else {
      after[file] = next;
    }
  }
  if (split != null) {
    final rest = after[claudeMdName]!;
    after[claudeMdName] = rest == split.claudeOnly
        ? claude
        : composeClaudeMd(rest, importLine: split.importLine!);
  } else if (claude != null &&
      hasAgentsImport(claude) &&
      !hasAgentsImport(after[claudeMdName] ?? '')) {
    // A trecho took the import away: it goes back (R9).
    after[claudeMdName] = restoreAgentsImport(after[claudeMdName] ?? '');
  }
  return ProposalPlan(before: before, after: after, conflicts: conflicts);
}

// --- Depois de aplicar ----------------------------------------------------------

/// Lines added and removed from [a] to [b] (the "+2 −1 linhas" of the
/// panel "Depois de aplicar").
({int added, int removed}) lineDelta(String? a, String? b) {
  List<String> split(String? s) {
    if (s == null || s.isEmpty) return const [];
    final l = s.split('\n');
    if (l.last.isEmpty) l.removeLast();
    return l;
  }

  var x = split(a);
  var y = split(b);
  var p = 0;
  while (p < x.length && p < y.length && x[p] == y[p]) {
    p++;
  }
  var s = 0;
  while (s < x.length - p &&
      s < y.length - p &&
      x[x.length - 1 - s] == y[y.length - 1 - s]) {
    s++;
  }
  x = x.sublist(p, x.length - s);
  y = y.sublist(p, y.length - s);
  if (x.isEmpty || y.isEmpty) return (added: y.length, removed: x.length);
  if (x.length * y.length > 4000000) {
    final count = <String, int>{};
    for (final l in x) {
      count[l] = (count[l] ?? 0) + 1;
    }
    var common = 0;
    for (final l in y) {
      final c = count[l] ?? 0;
      if (c > 0) {
        count[l] = c - 1;
        common++;
      }
    }
    return (added: y.length - common, removed: x.length - common);
  }
  // Longest common subsequence, two rows.
  var prev = List<int>.filled(y.length + 1, 0);
  var cur = List<int>.filled(y.length + 1, 0);
  for (var i = 1; i <= x.length; i++) {
    for (var j = 1; j <= y.length; j++) {
      cur[j] = x[i - 1] == y[j - 1]
          ? prev[j - 1] + 1
          : (prev[j] > cur[j - 1] ? prev[j] : cur[j - 1]);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  final lcs = prev[y.length];
  return (added: y.length - lcs, removed: x.length - lcs);
}

// --- Conferência (R20) -----------------------------------------------------------

final _inlineCode = RegExp(r'`([^`\n]+)`');
final _pathChars = RegExp(r'^[\w./*?@+-]+$');
final _extension = RegExp(r'\.[A-Za-z][A-Za-z0-9]{0,6}$');

/// The paths cited in [texts] (R20): inline code with a `/` or a file
/// extension (`lib/core/log.dart`, `ci.yml`, `packages/legado`), never a
/// command (spaces), a placeholder (`<area>`) or a URL.
List<String> citedPaths(Iterable<String> texts) {
  final out = <String>[];
  for (final t in texts) {
    for (final m in _inlineCode.allMatches(t)) {
      var p = m.group(1)!.trim();
      if (!_pathChars.hasMatch(p) || p.contains('//')) continue;
      if (!p.contains('/') && !_extension.hasMatch(p)) continue;
      if (p.startsWith('-') || p == '/' || p == '.') continue;
      p = p.replaceFirst(RegExp(r'^\./'), '');
      if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
      if (!out.contains(p)) out.add(p);
    }
  }
  return out;
}

/// One cited path and whether it exists in the project (R20).
@immutable
class CitedPath {
  const CitedPath(this.path, {required this.exists});

  final String path;
  final bool exists;
}

const _skipDirs = {
  '.git',
  'node_modules',
  'build',
  'dist',
  'target',
  'vendor',
  'Pods',
  '.dart_tool',
};

RegExp _glob(String pattern) {
  final b = StringBuffer('^');
  for (final ch in pattern.split('')) {
    b.write(switch (ch) {
      '*' => '[^/]*',
      '?' => '[^/]',
      _ => RegExp.escape(ch),
    });
  }
  b.write(r'$');
  return RegExp(b.toString());
}

/// Whether [path] exists under [root]: a file or folder; a glob
/// (`lib/data/db/*.g.dart`) when something matches; a bare file name
/// (`ci.yml`) anywhere in the project.
Future<bool> citedPathExists(String root, String path) async {
  if (path.startsWith('/')) {
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }
  final glob = path.contains('*') || path.contains('?');
  if (!glob) {
    if (await FileSystemEntity.type('$root/$path') !=
        FileSystemEntityType.notFound) {
      return true;
    }
    if (path.contains('/')) return false;
  }
  var seen = 0;
  Future<bool> walk(
    Directory d,
    int depth,
    bool Function(String rel) hit, {
    String rel = '',
    int maxDepth = 8,
  }) async {
    if (depth > maxDepth || seen > 20000) return false;
    List<FileSystemEntity> children;
    try {
      children = await d.list(followLinks: false).toList();
    } catch (_) {
      return false;
    }
    for (final e in children) {
      seen++;
      final name = e.path.split('/').last;
      final r = rel.isEmpty ? name : '$rel/$name';
      if (hit(r)) return true;
      if (e is Directory && !_skipDirs.contains(name)) {
        if (await walk(e, depth + 1, hit, rel: r, maxDepth: maxDepth)) {
          return true;
        }
      }
    }
    return false;
  }

  if (!path.contains('/')) {
    // A bare name (`ci.yml`, `*.g.dart`) anywhere in the project.
    final re = _glob(path);
    return walk(Directory(root), 0, (r) => re.hasMatch(r.split('/').last));
  }
  // A glob with folders: walk from its fixed prefix, as deep as it goes.
  final parts = path.split('/');
  final fixed = parts.takeWhile((p) => !p.contains('*') && !p.contains('?'));
  final prefix = fixed.join('/');
  final dir = Directory(prefix.isEmpty ? root : '$root/$prefix');
  if (!await dir.exists()) return false;
  final re = _glob(parts.skip(fixed.length).join('/'));
  return walk(dir, 0, re.hasMatch, maxDepth: parts.length - fixed.length - 1);
}

/// The cited paths of [hunks] (their new texts) against the project (R20).
Future<List<CitedPath>> checkCitedPaths(
  String root,
  Iterable<InstructionProposalHunk> hunks,
) async => [
  for (final p in citedPaths(hunks.map((h) => h.newText)))
    CitedPath(p, exists: await citedPathExists(root, p)),
];

// --- Commit (R21) ----------------------------------------------------------------

/// Where "Commitar ao aplicar" would commit (R21).
@immutable
class InstructionsCommitTarget {
  const InstructionsCommitTarget({
    required this.isRepo,
    this.branch,
    this.base,
  });

  /// The project is a git repository.
  final bool isRepo;

  /// The current branch; null = HEAD solto (or not a repository).
  final String? branch;

  /// The base branch of the project (the one the specs branch from).
  final String? base;

  /// The box can be checked.
  bool get canCommit => isRepo && branch != null;

  /// The branch is not the base: new specs only get the text after the
  /// merge.
  bool get offBase => branch != null && base != null && branch != base;

  /// Why the box is off; null when it can be checked.
  String? get disabledReason => !isRepo
      ? 'O projeto não é um repositório git.'
      : branch == null
      ? 'HEAD solto: não há branch para o commit. Volte para uma branch '
            'para poder commitar.'
      : null;
}

/// The base branch of the project: `branch-base` of the project config,
/// else the default branch of `origin`, else `main` or `master` when it
/// exists; null = unknown.
Future<String?> resolveBaseBranch(String root, GitService git) async {
  final configured = ProjectConfig.loadSync(root).baseBranch;
  if (configured != null && configured.trim().isNotEmpty) {
    return configured.trim();
  }
  try {
    final head = (await git.git([
      'symbolic-ref',
      '--short',
      '-q',
      'refs/remotes/origin/HEAD',
    ])).trim();
    if (head.startsWith('origin/')) return head.substring('origin/'.length);
  } on GitException {
    // No origin/HEAD.
  }
  for (final b in const ['main', 'master']) {
    if (await git.resolveRef('refs/heads/$b') != null) return b;
  }
  return null;
}

/// Reads the target of the commit (R21): repository, branch and base.
Future<InstructionsCommitTarget> readCommitTarget(
  String root,
  GitService git,
) async {
  try {
    final inside = (await git.git(['rev-parse', '--is-inside-work-tree']))
        .trim();
    if (inside != 'true') {
      return const InstructionsCommitTarget(isRepo: false);
    }
  } on GitException {
    return const InstructionsCommitTarget(isRepo: false);
  }
  final branch = await git.currentBranch();
  return InstructionsCommitTarget(
    isRepo: true,
    branch: branch,
    base: await resolveBaseBranch(root, git),
  );
}

/// Commits only [files] (relative to the repository root of [git]) on the
/// current branch (R21): `git add -- <files>` and
/// `git commit -- <files>`, so other staged or dirty files stay out. The
/// normal hooks run; no push, no branch switch. Returns the short sha, or
/// null when the files have nothing to commit.
Future<String?> commitInstructionFiles(
  GitService git,
  List<String> files, {
  String message = instructionsCommitMessage,
}) async {
  if (files.isEmpty) return null;
  if (await git.currentBranch() == null) {
    throw const InstructionsException(
      'HEAD solto: não há branch para o commit.',
    );
  }
  await git.git(['add', '--', ...files]);
  final staged = (await git.git([
    'diff',
    '--cached',
    '--name-only',
    '--',
    ...files,
  ])).trim();
  if (staged.isEmpty) return null;
  await git.git(['commit', '-q', '-m', message, '--', ...files]);
  return (await git.git(['rev-parse', '--short', 'HEAD'])).trim();
}

// --- Aplicar ---------------------------------------------------------------------

/// What "Aplicar" did (R19, R21).
@immutable
class ProposalApplyResult {
  const ProposalApplyResult({
    required this.conflicts,
    this.write,
    this.changed = const [],
    this.commitSha,
    this.branch,
    this.commitError,
  });

  /// Index of the trecho (in the list given) → why it was not written.
  final Map<int, ProposalConflictKind> conflicts;

  /// The write (for "Desfazer", R5); null = nothing changed.
  final InstructionsWriteResult? write;

  /// `AGENTS.md` / `CLAUDE.md` written.
  final List<String> changed;

  /// The commit made (R21), on [branch].
  final String? commitSha;
  final String? branch;

  /// The files were written but the commit failed (a hook, say).
  final String? commitError;

  bool get wrote => write != null;
}

/// Applies the accepted [hunks] (already edited) to the root files of
/// [root] (R19): reads both, applies in order, writes the changed ones
/// together (T1, R5; [InstructionsConflict] when a file changed in
/// between) and, with [commit], commits only them on the current branch
/// (R21). Trechos that do not match are returned in
/// [ProposalApplyResult.conflicts] and not written.
Future<ProposalApplyResult> applyInstructionProposal({
  required String root,
  required List<InstructionProposalHunk> hunks,
  bool commit = false,
  GitService? git,
}) async {
  if (commit) {
    final g = git ?? GitService(root);
    if (await g.currentBranch() == null) {
      throw const InstructionsException(
        'HEAD solto: não há branch para o commit. Nada foi gravado.',
      );
    }
  }
  final snaps = {
    for (final f in instructionRootFiles)
      f: await readInstructionsSnapshot('$root/$f'),
  };
  final plan = planProposal({
    for (final e in snaps.entries) e.key: e.value.text,
  }, hunks);
  final changed = plan.changed;
  if (changed.isEmpty) return ProposalApplyResult(conflicts: plan.conflicts);
  final write = await writeInstructionFiles([
    for (final f in changed) InstructionsWrite(snaps[f]!, plan.after[f]),
  ]);
  if (!commit) {
    return ProposalApplyResult(
      conflicts: plan.conflicts,
      write: write,
      changed: changed,
    );
  }
  final g = git ?? GitService(root);
  try {
    final branch = await g.currentBranch();
    final sha = await commitInstructionFiles(g, changed);
    return ProposalApplyResult(
      conflicts: plan.conflicts,
      write: write,
      changed: changed,
      commitSha: sha,
      branch: branch,
    );
  } catch (e) {
    final detail = e is GitException ? e.stderr.trim() : '';
    return ProposalApplyResult(
      conflicts: plan.conflicts,
      write: write,
      changed: changed,
      commitError: detail.isEmpty ? '$e' : detail,
    );
  }
}
