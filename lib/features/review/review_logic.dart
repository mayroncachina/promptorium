import 'package:flutter/foundation.dart';

import '../../core/git/diff_parser.dart';
import '../../core/git/git_service.dart' show GitLogEntry;
import '../../data/db/app_database.dart';

/// Pure rules of the Review screen (plano, Fase 9).

/// One entry of "Aguardando review".
@immutable
class ReviewItem {
  const ReviewItem({required this.session, this.task, this.spec});

  /// Session shown (of a spec: its latest one — every step session shares
  /// the spec's worktree and branch).
  final Session session;
  final Task? task;

  /// Spec (card of the Quadro) the session works on.
  final Spec? spec;
}

/// Whether [session] goes to "Aguardando review":
/// - it ran in its own worktree ([hasWorktree]) and was not merged yet;
/// - its task is in Review, **or** the session finished (`completed`) and the
///   worktree has changes ([hasChanges]: commits ahead of the base or
///   uncommitted files).
///
/// A session of a spec ([spec]) goes only when the card is in Review (every
/// step done, or moved there by hand); the card being "Feito" never does.
bool isAwaitingReview({
  required Session session,
  required Task? task,
  Spec? spec,
  required bool hasWorktree,
  required bool hasChanges,
}) {
  if (!hasWorktree || session.status == SessionStatus.merged) return false;
  if (session.mergeCommit != null) return false;
  if (spec != null) {
    if (spec.stage != SpecStage.review) return false;
    return session.status != SessionStatus.running &&
        session.status != SessionStatus.waitingApproval;
  }
  if (task?.status == TaskStatus.done) return false;
  if (session.status == SessionStatus.running ||
      session.status == SessionStatus.waitingApproval) {
    return false;
  }
  if (task?.status == TaskStatus.review) return true;
  return session.status == SessionStatus.completed && hasChanges;
}

/// Commits of a spec's branch by step: a subject `SPEC-003 R2, R3: …` goes
/// to R2 and R3 (`REV1` too); other commits are left out.
Map<String, List<GitLogEntry>> commitsByStep(
  String specCode,
  List<GitLogEntry> commits,
) {
  final out = <String, List<GitLogEntry>>{};
  for (final c in commits) {
    if (!c.subject.toUpperCase().startsWith(specCode.toUpperCase())) continue;
    final head = c.subject.split(':').first;
    for (final m in RegExp(r'\b(?:REV|R)\d+\b').allMatches(head)) {
      out.putIfAbsent(m.group(0)!, () => []).add(c);
    }
  }
  return out;
}

/// Lines of `gh pr checks` (`nome\testado\t…`) → `(nome, estado)`.
List<(String, String)> parsePrChecks(String out) => [
  for (final l in out.split('\n'))
    if (l.split('\t') case [final name, final state, ...] when name.isNotEmpty)
      (name.trim(), state.trim()),
];

/// Lines of every hunk of [f].
int diffLineCount(DiffFile f) => f.hunks.fold(0, (n, h) => n + h.lines.length);

/// A line of a hunk with its index in the hunk.
typedef IndexedLine = (int, DiffLine);

/// Rows of the side-by-side view of [h]: context on both sides; a run of
/// removed lines next to the added lines that follow it.
List<(IndexedLine?, IndexedLine?)> splitPairs(DiffHunk h) {
  final out = <(IndexedLine?, IndexedLine?)>[];
  final lines = h.lines;
  var i = 0;
  while (i < lines.length) {
    if (lines[i].kind == DiffLineKind.context) {
      out.add(((i, lines[i]), (i, lines[i])));
      i++;
      continue;
    }
    final dels = <IndexedLine>[], adds = <IndexedLine>[];
    while (i < lines.length && lines[i].kind == DiffLineKind.del) {
      dels.add((i, lines[i]));
      i++;
    }
    while (i < lines.length && lines[i].kind == DiffLineKind.add) {
      adds.add((i, lines[i]));
      i++;
    }
    final n = dels.length > adds.length ? dels.length : adds.length;
    for (var k = 0; k < n; k++) {
      out.add((
        k < dels.length ? dels[k] : null,
        k < adds.length ? adds[k] : null,
      ));
    }
  }
  return out;
}

/// `A` / `M` / `D` / `R` of the file list.
String fileStatusLetter(DiffFileStatus s) => switch (s) {
  DiffFileStatus.added => 'A',
  DiffFileStatus.modified => 'M',
  DiffFileStatus.deleted => 'D',
  DiffFileStatus.renamed => 'R',
};

/// (+added, −deleted) of a file (0/0 for binary files).
(int, int) fileStats(DiffFile f) => (
  f.hunks.fold(0, (n, h) => n + h.additions),
  f.hunks.fold(0, (n, h) => n + h.deletions),
);

/// Stable key of a hunk (accept / comments state).
String hunkKey(DiffFile f, DiffHunk h) => '${f.path}|${h.header}';

/// Patch used to **reject** [hunk]: [DiffParser.hunkPatch], except for renamed
/// files, whose header is rewritten to touch only the new path (rejecting a
/// content hunk must not undo the rename). Applied with `git apply -R`.
String rejectPatch(DiffFile file, DiffHunk hunk) {
  if (file.status != DiffFileStatus.renamed || file.newPath == null) {
    return DiffParser.hunkPatch(file, hunk);
  }
  final p = file.newPath!;
  final a = _quote('a/$p'), b = _quote('b/$p');
  final lines = ['diff --git $a $b', '--- $a', '+++ $b', hunk.header];
  return '${[...lines, ...hunk.rawLines].join('\n')}\n';
}

String _quote(String path) {
  if (!RegExp(r'[\s"\\]|[^\x20-\x7e]').hasMatch(path)) return path;
  final b = StringBuffer('"');
  for (final c in path.runes) {
    if (c == 0x22) {
      b.write(r'\"');
    } else if (c == 0x5c) {
      b.write(r'\\');
    } else if (c == 0x09) {
      b.write(r'\t');
    } else if (c == 0x0a) {
      b.write(r'\n');
    } else {
      b.writeCharCode(c);
    }
  }
  b.write('"');
  return b.toString();
}

/// An inline comment waiting to be sent ("Pedir ajustes ao agente").
@immutable
class ReviewComment {
  const ReviewComment({
    required this.path,
    required this.line,
    required this.text,
    required this.snippet,
    this.removedLine = false,
    this.anchor = '',
  });

  final String path;

  /// `hunkKey#lineIndex` of the diff line it was written on (inline display).
  final String anchor;

  /// Line in the new file (or in the old file when [removedLine]).
  final int line;
  final String text;

  /// Lines shown under the comment (`+`/`-`/space prefixed, ≤ 3).
  final List<String> snippet;
  final bool removedLine;

  String get location => '$path:$line${removedLine ? ' (linha removida)' : ''}';

  Map<String, Object?> toJson() => {
    'path': path,
    'line': line,
    'text': text,
    'snippet': snippet,
    if (removedLine) 'removed': true,
    if (anchor.isNotEmpty) 'anchor': anchor,
  };

  static ReviewComment? fromJson(Object? j) {
    if (j is! Map || j['path'] is! String || j['text'] is! String) return null;
    return ReviewComment(
      path: j['path'] as String,
      line: (j['line'] as num?)?.toInt() ?? 0,
      text: j['text'] as String,
      snippet: [for (final l in (j['snippet'] as List? ?? const [])) '$l'],
      removedLine: j['removed'] == true,
      anchor: '${j['anchor'] ?? ''}',
    );
  }
}

/// Builds the comment for the line at [index] of [hunk]: the snippet is the
/// commented line plus up to two lines above it (same hunk).
ReviewComment commentFor(DiffFile file, DiffHunk hunk, int index, String text) {
  final l = hunk.lines[index];
  final removed = l.kind == DiffLineKind.del;
  final from = index - 2 < 0 ? 0 : index - 2;
  return ReviewComment(
    path: file.path,
    line: (removed ? l.oldNo : l.newNo) ?? 0,
    text: text.trim(),
    removedLine: removed,
    anchor: '${hunkKey(file, hunk)}#$index',
    snippet: [
      for (final x in hunk.lines.sublist(from, index + 1))
        '${switch (x.kind) {
          DiffLineKind.add => '+',
          DiffLineKind.del => '-',
          DiffLineKind.context => ' ',
        }}${x.text}',
    ],
  );
}

/// The single message sent to the session by "Pedir ajustes ao agente":
/// each comment as `arquivo:linha — comentário` followed by its snippet.
String adjustmentMessage(List<ReviewComment> comments, {String note = ''}) {
  final b = StringBuffer('Revisão do código: ajustes pedidos.\n');
  final n = note.trim();
  if (n.isNotEmpty) {
    b
      ..writeln()
      ..writeln(n);
  }
  for (final c in comments) {
    b
      ..writeln()
      ..writeln('${c.location} — ${c.text}')
      ..writeln('```')
      ..writeln(c.snippet.join('\n'))
      ..writeln('```');
  }
  b
    ..writeln()
    ..write(
      'Faça os ajustes no worktree, rode os testes e resuma o que mudou.',
    );
  return b.toString();
}

/// Commit message of pending changes before PR / merge.
String pendingCommitMessage(Session s, Task? task, [Spec? spec]) {
  final what = spec != null
      ? '${spec.code}: ${spec.title}'
      : task != null
      ? '${task.code}: ${task.title}'
      : (s.title?.isNotEmpty ?? false)
      ? s.title!
      : 'sessão ${s.id.substring(0, s.id.length < 8 ? s.id.length : 8)}';
  return 'Promptorium: $what';
}

/// Title of the PR / merge commit.
String reviewTitle(Session s, Task? task, [Spec? spec]) => spec != null
    ? '${spec.code}: ${spec.title}'
    : task != null
    ? '${task.code}: ${task.title}'
    : (s.title?.isNotEmpty ?? false)
    ? s.title!
    : 'Sessão ${s.id.substring(0, s.id.length < 8 ? s.id.length : 8)}';
