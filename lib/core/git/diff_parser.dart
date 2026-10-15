import 'dart:convert';

import 'package:flutter/foundation.dart';

enum DiffFileStatus { added, modified, deleted, renamed }

enum DiffLineKind { add, del, context }

@immutable
class DiffLine {
  const DiffLine({
    required this.kind,
    required this.text,
    this.oldNo,
    this.newNo,
    this.noNewlineAtEnd = false,
  });

  final DiffLineKind kind;

  /// Line content without the `+`/`-`/space prefix.
  final String text;

  /// Line number in the old file (null for additions).
  final int? oldNo;

  /// Line number in the new file (null for deletions).
  final int? newNo;

  /// Followed by `\ No newline at end of file`.
  final bool noNewlineAtEnd;

  DiffLine _withNoNewline() => DiffLine(
    kind: kind,
    text: text,
    oldNo: oldNo,
    newNo: newNo,
    noNewlineAtEnd: true,
  );
}

@immutable
class DiffHunk {
  const DiffHunk({
    required this.header,
    required this.oldStart,
    required this.oldLen,
    required this.newStart,
    required this.newLen,
    required this.section,
    required this.lines,
    required this.rawLines,
  });

  /// The full `@@ -a,b +c,d @@ …` line.
  final String header;
  final int oldStart;
  final int oldLen;
  final int newStart;
  final int newLen;

  /// Text after the closing `@@` (function context), may be empty.
  final String section;
  final List<DiffLine> lines;

  /// Body lines exactly as in the diff (prefixes and `\ No newline` kept).
  final List<String> rawLines;

  int get additions => lines.where((l) => l.kind == DiffLineKind.add).length;

  int get deletions => lines.where((l) => l.kind == DiffLineKind.del).length;
}

@immutable
class DiffFile {
  const DiffFile({
    required this.oldPath,
    required this.newPath,
    required this.status,
    required this.headerLines,
    required this.hunks,
    this.isBinary = false,
  });

  /// Null for added files.
  final String? oldPath;

  /// Null for deleted files.
  final String? newPath;
  final DiffFileStatus status;

  /// `diff --git …` up to (and including) `+++ …`, as in the diff.
  final List<String> headerLines;
  final List<DiffHunk> hunks;
  final bool isBinary;

  /// Path to show (new path, or old path for deletions).
  String get path => newPath ?? oldPath ?? '';
}

/// Parser for `git diff --unified` output (plano, Fase 4 / Fase 9).
abstract final class DiffParser {
  static final _hunkRe = RegExp(
    r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$',
  );

  static List<DiffFile> parse(String diff) {
    // Split on \n only: a \r inside a line is content (CRLF files).
    final lines = diff.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final files = <DiffFile>[];
    var i = 0;
    while (i < lines.length) {
      if (!lines[i].startsWith('diff --git ')) {
        i++;
        continue;
      }
      // --- file header
      final header = <String>[lines[i]];
      final gitPaths = _splitGitHeader(lines[i].substring(11));
      String? oldPath = gitPaths.$1, newPath = gitPaths.$2;
      var status = DiffFileStatus.modified;
      var binary = false;
      i++;
      while (i < lines.length &&
          !lines[i].startsWith('diff --git ') &&
          !lines[i].startsWith('@@ ')) {
        final l = lines[i];
        header.add(l);
        if (l.startsWith('new file mode')) {
          status = DiffFileStatus.added;
        } else if (l.startsWith('deleted file mode')) {
          status = DiffFileStatus.deleted;
        } else if (l.startsWith('rename from ')) {
          status = DiffFileStatus.renamed;
          oldPath = _unquote(l.substring(12));
        } else if (l.startsWith('rename to ')) {
          status = DiffFileStatus.renamed;
          newPath = _unquote(l.substring(10));
        } else if (l.startsWith('--- ')) {
          final p = _stripPrefix(l.substring(4), 'a/');
          if (p != null) oldPath = p;
        } else if (l.startsWith('+++ ')) {
          final p = _stripPrefix(l.substring(4), 'b/');
          if (p != null) newPath = p;
        } else if (l.startsWith('Binary files ') || l == 'GIT binary patch') {
          binary = true;
        }
        i++;
      }
      if (status == DiffFileStatus.added) oldPath = null;
      if (status == DiffFileStatus.deleted) newPath = null;

      // --- hunks
      final hunks = <DiffHunk>[];
      while (i < lines.length && lines[i].startsWith('@@ ')) {
        final m = _hunkRe.firstMatch(lines[i]);
        if (m == null) {
          i++;
          continue;
        }
        final hunkHeader = lines[i];
        final oldStart = int.parse(m.group(1)!);
        final oldLen = m.group(2) == null ? 1 : int.parse(m.group(2)!);
        final newStart = int.parse(m.group(3)!);
        final newLen = m.group(4) == null ? 1 : int.parse(m.group(4)!);
        final section = m.group(5)!.trim();
        i++;
        final body = <DiffLine>[];
        final raw = <String>[];
        var oldLeft = oldLen, newLeft = newLen;
        var oldNo = oldStart, newNo = newStart;
        // Counters decide where the hunk ends ("--- x" may be a deleted line).
        while (i < lines.length) {
          final l = lines[i];
          if (l.startsWith(r'\')) {
            raw.add(l);
            if (body.isNotEmpty) body.add(body.removeLast()._withNoNewline());
            i++;
            continue;
          }
          if (oldLeft <= 0 && newLeft <= 0) break;
          if (l.startsWith('+')) {
            body.add(
              DiffLine(
                kind: DiffLineKind.add,
                text: l.substring(1),
                newNo: newNo++,
              ),
            );
            newLeft--;
          } else if (l.startsWith('-')) {
            body.add(
              DiffLine(
                kind: DiffLineKind.del,
                text: l.substring(1),
                oldNo: oldNo++,
              ),
            );
            oldLeft--;
          } else if (l.startsWith(' ') || l.isEmpty) {
            body.add(
              DiffLine(
                kind: DiffLineKind.context,
                text: l.isEmpty ? '' : l.substring(1),
                oldNo: oldNo++,
                newNo: newNo++,
              ),
            );
            oldLeft--;
            newLeft--;
          } else {
            break;
          }
          raw.add(l);
          i++;
        }
        hunks.add(
          DiffHunk(
            header: hunkHeader,
            oldStart: oldStart,
            oldLen: oldLen,
            newStart: newStart,
            newLen: newLen,
            section: section,
            lines: body,
            rawLines: raw,
          ),
        );
      }
      files.add(
        DiffFile(
          oldPath: oldPath,
          newPath: newPath,
          status: status,
          headerLines: header,
          hunks: hunks,
          isBinary: binary,
        ),
      );
    }
    return files;
  }

  /// Patch containing only [hunk] of [file], usable with `git apply` /
  /// `git apply -R` (Fase 9: rejeitar hunk).
  static String hunkPatch(DiffFile file, DiffHunk hunk) {
    final header = [...file.headerLines];
    // Mode-only / rename-only headers lack ---/+++; add them for git apply.
    if (!header.any((l) => l.startsWith('--- '))) {
      header.add(
        '--- ${file.oldPath == null ? '/dev/null' : 'a/${file.oldPath}'}',
      );
      header.add(
        '+++ ${file.newPath == null ? '/dev/null' : 'b/${file.newPath}'}',
      );
    }
    return '${[...header, hunk.header, ...hunk.rawLines].join('\n')}\n';
  }

  /// `--- a/path` → `path`; `/dev/null` → null.
  static String? _stripPrefix(String p, String prefix) {
    var s = p;
    if (s.endsWith('\t')) s = s.substring(0, s.length - 1);
    if (s == '/dev/null') return null;
    s = _unquote(s);
    return s.startsWith(prefix) ? s.substring(prefix.length) : s;
  }

  /// `a/x b/y` (possibly quoted) → (x, y).
  static (String?, String?) _splitGitHeader(String rest) {
    if (rest.startsWith('"')) {
      final end = _closingQuote(rest, 0);
      final a = _unquote(rest.substring(0, end + 1));
      final b = _unquote(rest.substring(end + 1).trim());
      return (_drop(a, 'a/'), _drop(b, 'b/'));
    }
    if (rest.endsWith('"')) {
      final start = rest.lastIndexOf(' "');
      if (start > 0) {
        return (
          _drop(rest.substring(0, start), 'a/'),
          _drop(_unquote(rest.substring(start + 1)), 'b/'),
        );
      }
    }
    // Unquoted: prefer the split where both halves name the same path.
    if (rest.length.isOdd) {
      final mid = rest.length ~/ 2;
      final a = rest.substring(0, mid), b = rest.substring(mid + 1);
      if (rest[mid] == ' ' && _drop(a, 'a/') == _drop(b, 'b/')) {
        return (_drop(a, 'a/'), _drop(b, 'b/'));
      }
    }
    final idx = rest.lastIndexOf(' b/');
    if (idx < 0) return (null, null);
    return (
      _drop(rest.substring(0, idx), 'a/'),
      _drop(rest.substring(idx + 1), 'b/'),
    );
  }

  static String _drop(String s, String prefix) =>
      s.startsWith(prefix) ? s.substring(prefix.length) : s;

  static int _closingQuote(String s, int open) {
    for (var i = open + 1; i < s.length; i++) {
      if (s[i] == r'\') {
        i++;
      } else if (s[i] == '"') {
        return i;
      }
    }
    return s.length - 1;
  }

  /// Git C-style quoting (`"a/caf\303\251.txt"`) → UTF-8 string.
  static String _unquote(String s) {
    if (s.length < 2 || !s.startsWith('"') || !s.endsWith('"')) return s;
    final body = s.substring(1, s.length - 1);
    final bytes = <int>[];
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (c != r'\' || i + 1 >= body.length) {
        bytes.addAll(utf8.encode(c));
        continue;
      }
      final n = body[++i];
      switch (n) {
        case 'n':
          bytes.add(0x0a);
        case 't':
          bytes.add(0x09);
        case 'r':
          bytes.add(0x0d);
        case '"':
          bytes.add(0x22);
        case r'\':
          bytes.add(0x5c);
        case 'a':
          bytes.add(0x07);
        case 'b':
          bytes.add(0x08);
        case 'f':
          bytes.add(0x0c);
        case 'v':
          bytes.add(0x0b);
        default:
          if (RegExp(r'[0-7]').hasMatch(n) && i + 2 < body.length) {
            bytes.add(int.parse(body.substring(i, i + 3), radix: 8));
            i += 2;
          } else {
            bytes.addAll(utf8.encode(n));
          }
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
