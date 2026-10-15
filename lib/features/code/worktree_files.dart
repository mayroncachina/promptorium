import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/git/diff_parser.dart';
import '../../core/git/git_service.dart';

/// User-facing failure of a file operation of the Code screen.
class CodeFileException implements Exception {
  const CodeFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Git mark of a file in the tree (`GitService.status`).
enum FileMark {
  added('A'),
  modified('M'),
  deleted('D'),
  untracked('?');

  const FileMark(this.letter);

  final String letter;

  static FileMark of(GitStatusEntry e) {
    if (e.isUntracked) return untracked;
    if (e.x == 'D' || e.y == 'D') return deleted;
    if (e.x == 'A' || e.y == 'A') return added;
    return modified;
  }
}

/// One row of the tree: a folder or a file (path relative to the worktree,
/// `/`-separated).
@immutable
class TreeEntry {
  const TreeEntry({
    required this.path,
    required this.isDir,
    this.mark,
    this.changedInside = false,
  });

  final String path;
  final bool isDir;
  final FileMark? mark;

  /// Folder containing a marked file.
  final bool changedInside;

  String get name => path.split('/').last;

  int get depth => '/'.allMatches(path).length;
}

/// Files of a worktree: `git ls-files --cached --others --exclude-standard`
/// (respects `.gitignore`, never lists `.git`) + folders created in the app
/// (git does not list empty folders) + status marks. Children of a folder
/// are computed when the folder is expanded ([children]).
class WorktreeIndex {
  WorktreeIndex({
    required List<String> files,
    Map<String, FileMark> marks = const {},
    Set<String> extraDirs = const {},
  }) : files = List.unmodifiable(files.toList()..sort()),
       marks = Map.unmodifiable(marks) {
    for (final f in this.files) {
      _addParents(f);
    }
    for (final d in extraDirs) {
      if (d.isNotEmpty) {
        _dirs.add(d);
        _addParents(d);
      }
    }
    for (final p in marks.keys) {
      var i = p.lastIndexOf('/');
      while (i > 0) {
        _changedDirs.add(p.substring(0, i));
        i = p.lastIndexOf('/', i - 1);
      }
    }
  }

  static final empty = WorktreeIndex(files: const []);

  /// Every file, sorted.
  final List<String> files;
  final Map<String, FileMark> marks;
  final Set<String> _dirs = {};
  final Set<String> _changedDirs = {};
  final Map<String, List<TreeEntry>> _cache = {};

  void _addParents(String path) {
    var i = path.indexOf('/');
    while (i > 0) {
      _dirs.add(path.substring(0, i));
      i = path.indexOf('/', i + 1);
    }
  }

  bool isDir(String path) => _dirs.contains(path);

  bool contains(String path) => isDir(path) || files.contains(path);

  /// Direct children of [dir] ('' = root): folders first, then files, by name.
  List<TreeEntry> children(String dir) => _cache[dir] ??= _children(dir);

  List<TreeEntry> _children(String dir) {
    final prefix = dir.isEmpty ? '' : '$dir/';
    final dirs = <String>{}, out = <TreeEntry>[];
    bool direct(String p) =>
        p.startsWith(prefix) && !p.substring(prefix.length).contains('/');
    for (final d in _dirs) {
      if (direct(d)) dirs.add(d);
    }
    for (final f in files) {
      if (!f.startsWith(prefix)) continue;
      final rest = f.substring(prefix.length);
      if (!rest.contains('/')) {
        out.add(TreeEntry(path: f, isDir: false, mark: marks[f]));
      }
    }
    final sortedDirs = dirs.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [
      for (final d in sortedDirs)
        TreeEntry(
          path: d,
          isDir: true,
          changedInside: _changedDirs.contains(d),
        ),
      ...out,
    ];
  }
}

/// What [WorktreeFiles.read] found.
sealed class FileContent {
  const FileContent();
}

class TextFileContent extends FileContent {
  const TextFileContent(this.text, {required this.crlf, required this.stat});

  final String text;
  final bool crlf;
  final FileStat stat;
}

/// Not opened in the editor (binary, not UTF-8 or larger than the limit).
class UnsupportedFileContent extends FileContent {
  const UnsupportedFileContent(this.reason);

  final String reason;
}

/// File operations confined to one worktree (no path traversal).
class WorktreeFiles {
  WorktreeFiles(this.root, {GitService? git}) : git = git ?? GitService(root);

  /// Absolute worktree folder.
  final String root;
  final GitService git;

  /// Files above this size are not opened (plano, Fase 10).
  static const maxEditableBytes = 2 * 1024 * 1024;

  /// `git ls-files --cached --others --exclude-standard -z`.
  Future<List<String>> listFiles() async {
    final out = await git.git([
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '-z',
    ]);
    final seen = <String>{};
    return [
      for (final p in out.split('\x00'))
        if (p.isNotEmpty && seen.add(p)) p,
    ];
  }

  /// Status marks by path (renames mark the new path).
  Future<Map<String, FileMark>> marks() async => {
    for (final e in await git.status()) e.path: FileMark.of(e),
  };

  /// Files + marks (+ [extraDirs] created in the app that still exist).
  Future<WorktreeIndex> index({Set<String> extraDirs = const {}}) async {
    final files = await listFiles();
    final marks = await this.marks();
    final dirs = {
      for (final d in extraDirs)
        if (Directory(_join(d)).existsSync()) d,
    };
    return WorktreeIndex(files: files, marks: marks, extraDirs: dirs);
  }

  // --- paths -----------------------------------------------------------------

  /// Validates a relative path typed by the user (`a/b.dart`): no absolute
  /// path, no `.`/`..`/empty segment, no `.git`, no NUL / backslash.
  static String normalizeRelative(String input) {
    final p = input.trim();
    if (p.isEmpty) throw const CodeFileException('Informe um nome.');
    if (p.startsWith('/') || p.startsWith('~')) {
      throw const CodeFileException('Use um caminho relativo ao worktree.');
    }
    if (p.contains('\x00') || p.contains('\\')) {
      throw const CodeFileException('Nome com caractere inválido.');
    }
    final parts = p.split('/');
    if (parts.last.isEmpty) parts.removeLast(); // trailing "/"
    for (final s in parts) {
      if (s.isEmpty || s == '.' || s == '..') {
        throw const CodeFileException(
          'Caminho inválido: sem "..", "." ou barras repetidas.',
        );
      }
      if (s == '.git') {
        throw const CodeFileException('A pasta .git não pode ser alterada.');
      }
      if (s.trim() != s) {
        throw const CodeFileException(
          'Nome não pode começar ou terminar com espaço.',
        );
      }
    }
    if (parts.isEmpty) throw const CodeFileException('Informe um nome.');
    return parts.join('/');
  }

  String _join(String rel) => rel.isEmpty ? root : '$root/$rel';

  /// Absolute path of [rel], refusing anything that resolves (also through
  /// symlinks of existing folders) outside the worktree.
  String resolve(String rel) {
    final clean = rel.isEmpty ? '' : normalizeRelative(rel);
    final abs = _join(clean);
    final realRoot = Directory(root).resolveSymbolicLinksSync();
    // Deepest existing ancestor (the target may not exist yet). Links are
    // not followed here, so a dangling symlink stops the walk and fails to
    // resolve below (writing through it could create a file outside).
    var probe = abs;
    while (FileSystemEntity.typeSync(probe, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final i = probe.lastIndexOf('/');
      if (i <= 0) break;
      probe = probe.substring(0, i);
    }
    final String real;
    try {
      real = File(probe).resolveSymbolicLinksSync();
    } on FileSystemException {
      throw const CodeFileException('Caminho fora do worktree.');
    }
    if (real != realRoot && !real.startsWith('$realRoot/')) {
      throw const CodeFileException('Caminho fora do worktree.');
    }
    return abs;
  }

  // --- operations --------------------------------------------------------------

  /// Creates an empty file at [rel] (parents created). Returns the clean path.
  Future<String> createFile(String rel) async {
    final clean = normalizeRelative(rel);
    final abs = resolve(clean);
    if (FileSystemEntity.typeSync(abs) != FileSystemEntityType.notFound) {
      throw CodeFileException('Já existe: $clean');
    }
    await File(abs).create(recursive: true, exclusive: true);
    return clean;
  }

  Future<String> createFolder(String rel) async {
    final clean = normalizeRelative(rel);
    final abs = resolve(clean);
    if (FileSystemEntity.typeSync(abs) != FileSystemEntityType.notFound) {
      throw CodeFileException('Já existe: $clean');
    }
    await Directory(abs).create(recursive: true);
    return clean;
  }

  /// Renames / moves [from] to [to] (both relative). Returns the clean `to`.
  Future<String> rename(String from, String to) async {
    final src = resolve(from);
    final clean = normalizeRelative(to);
    final dst = resolve(clean);
    if (normalizeRelative(from) == clean) return clean;
    final type = FileSystemEntity.typeSync(src, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw CodeFileException('Não encontrado: $from');
    }
    if (FileSystemEntity.typeSync(dst) != FileSystemEntityType.notFound) {
      throw CodeFileException('Já existe: $clean');
    }
    if (clean.startsWith('${normalizeRelative(from)}/')) {
      throw const CodeFileException('Não é possível mover para dentro de si.');
    }
    await Directory(File(dst).parent.path).create(recursive: true);
    if (type == FileSystemEntityType.directory) {
      await Directory(src).rename(dst);
    } else {
      await File(src).rename(dst);
    }
    return clean;
  }

  /// Deletes a file or a folder (recursively). The root cannot be deleted.
  Future<void> delete(String rel) async {
    final clean = normalizeRelative(rel);
    final abs = resolve(clean);
    final type = FileSystemEntity.typeSync(abs, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(abs).delete(recursive: true);
      case FileSystemEntityType.notFound:
        throw CodeFileException('Não encontrado: $clean');
      default:
        await File(abs).delete();
    }
  }

  /// Reads [rel] for the editor; binary / non UTF-8 / > 2 MB files are
  /// [UnsupportedFileContent].
  Future<FileContent> read(String rel) async {
    final f = File(resolve(rel));
    final stat = await f.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      throw CodeFileException('Não encontrado: $rel');
    }
    if (stat.size > maxEditableBytes) {
      return UnsupportedFileContent(
        'Arquivo grande demais para o editor '
        '(${(stat.size / (1024 * 1024)).toStringAsFixed(1)} MB; limite 2 MB).',
      );
    }
    final bytes = await f.readAsBytes();
    final head = bytes.length > 8000 ? bytes.sublist(0, 8000) : bytes;
    if (head.contains(0)) {
      return const UnsupportedFileContent(
        'Arquivo binário — não abre no editor.',
      );
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return const UnsupportedFileContent(
        'O arquivo não é UTF-8 — não abre no editor.',
      );
    }
    final body = text.startsWith('﻿') ? text.substring(1) : text;
    return TextFileContent(body, crlf: body.contains('\r\n'), stat: stat);
  }

  /// Writes [text] in place (keeps permissions). Returns the new stat.
  Future<FileStat> write(String rel, String text) async {
    final f = File(resolve(rel));
    await f.writeAsString(text, flush: true);
    return f.stat();
  }

  Future<FileStat> stat(String rel) async => File(resolve(rel)).stat();

  /// 0-based lines of [rel] that differ from [base] (a commit; `HEAD` for the
  /// workspace root, the session merge-base otherwise). Untracked file = all
  /// lines. Errors = none.
  Future<Set<int>> changedLines(String rel, {required String base}) async {
    try {
      final status = await git.git([
        'status',
        '--porcelain=v1',
        '-z',
        '-uall',
        '--',
        normalizeRelative(rel),
      ]);
      if (status.startsWith('??')) {
        final text = await File(resolve(rel)).readAsString();
        final n = '\n'.allMatches(text).length + (text.endsWith('\n') ? 0 : 1);
        return {for (var i = 0; i < n; i++) i};
      }
      final diff = await git.git([
        'diff',
        '--no-color',
        '--no-ext-diff',
        '--unified=0',
        base,
        '--',
        normalizeRelative(rel),
      ]);
      return addedLines(diff);
    } catch (e) {
      debugPrint('linhas alteradas de $rel: $e');
      return const {};
    }
  }

  /// `+` lines (0-based new line numbers) of a unified diff.
  static Set<int> addedLines(String diff) {
    final out = <int>{};
    for (final f in DiffParser.parse(diff)) {
      for (final h in f.hunks) {
        for (final l in h.lines) {
          if (l.kind == DiffLineKind.add && l.newNo != null) {
            out.add(l.newNo! - 1);
          }
        }
      }
    }
    return out;
  }

  /// Base of the green marks: merge-base of [baseBranch] and HEAD for a
  /// session worktree, `HEAD` otherwise.
  Future<String> marksBase(String? baseBranch) async {
    if (baseBranch == null ||
        baseBranch.isEmpty ||
        baseBranch.startsWith('-')) {
      return 'HEAD';
    }
    try {
      return (await git.git(['merge-base', baseBranch, 'HEAD'])).trim();
    } on GitException {
      return 'HEAD';
    }
  }
}

/// Lines changed between [saved] and [current] (both split on `\n`):
/// common prefix / suffix; returns the changed range of [current]
/// (`start`..`end`, end exclusive) and the line delta. Cheap and good for
/// one edit region; several regions are reported as one span.
({int start, int end, int delta})? editedRange(
  List<String> saved,
  List<String> current,
) {
  final n = saved.length, m = current.length;
  var p = 0;
  while (p < n && p < m && saved[p] == current[p]) {
    p++;
  }
  if (p == n && p == m) return null;
  var s = 0;
  while (s < n - p && s < m - p && saved[n - 1 - s] == current[m - 1 - s]) {
    s++;
  }
  return (start: p, end: m - s, delta: m - n);
}

/// Gutter marks: [agentLines] (in saved-file coordinates) shifted by the
/// unsaved edit of the user, plus the user's edited lines (which win).
Map<int, T> lineMarks<T>({
  required List<String> saved,
  required List<String> current,
  required Set<int> agentLines,
  required T agent,
  required T user,
}) {
  final r = editedRange(saved, current);
  final out = <int, T>{};
  for (final l in agentLines) {
    if (r == null || l < r.start) {
      out[l] = agent;
    } else if (l >= saved.length - (current.length - r.end)) {
      out[l + r.delta] = agent;
    }
  }
  if (r != null) {
    if (r.end > r.start) {
      for (var i = r.start; i < r.end; i++) {
        out[i] = user;
      }
    } else {
      // Pure deletion: mark the line where it happened.
      out[r.start.clamp(0, current.isEmpty ? 0 : current.length - 1)] = user;
    }
  }
  return out;
}

/// Simple fuzzy score of [path] for [query] ("Ir para arquivo", Ctrl+P):
/// every query char must appear in order; consecutive matches, matches in
/// the file name and at word starts score higher. null = no match.
int? fuzzyScore(String path, String query) {
  final q = query.toLowerCase().replaceAll(' ', '');
  if (q.isEmpty) return 0;
  final p = path.toLowerCase();
  final nameStart = p.lastIndexOf('/') + 1;
  var score = 0, qi = 0, prev = -2;
  for (var i = 0; i < p.length && qi < q.length; i++) {
    if (p[i] != q[qi]) continue;
    var s = 1;
    if (i == prev + 1) s += 5;
    if (i >= nameStart) s += 2;
    if (i == nameStart || i == 0 || '/_-.'.contains(p[i - 1])) s += 4;
    score += s;
    prev = i;
    qi++;
  }
  if (qi < q.length) return null;
  if (p.substring(nameStart).contains(q)) score += 20;
  return score * 100 - path.length;
}

/// Files of [files] matching [query], best first (at most [limit]).
List<String> fuzzyFilter(List<String> files, String query, {int limit = 50}) {
  if (query.trim().isEmpty) return files.take(limit).toList();
  final scored = <(String, int)>[];
  for (final f in files) {
    final s = fuzzyScore(f, query);
    if (s != null) scored.add((f, s));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (f, _) in scored.take(limit)) f];
}
