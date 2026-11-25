import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/diff_parser.dart';
import '../../data/providers.dart';
import '../../data/repos/debt_links_repo.dart';
import '../../data/repos/review_comments_repo.dart';
import '../project/project_config.dart';
import 'debt_files.dart';
import 'debt_service.dart';
import 'debt_table.dart';

// --- pure helpers (R8, R9) ---------------------------------------------------

/// The first sentence as the title, the rest as the motive. A title too
/// long for "O quê" is cut at a word and the whole text goes to the motive.
({String title, String reason}) splitTitleReason(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final m = RegExp(r'^(.+?[.!?])\s+(\S.*)$').firstMatch(flat);
  var title = m?.group(1) ?? flat;
  var reason = m?.group(2) ?? '';
  title = title.replaceFirst(RegExp(r'[.:;]$'), '').trim();
  if (title.length > 120) {
    final cut = title.substring(0, 117);
    final space = cut.lastIndexOf(' ');
    title = '${(space > 40 ? cut.substring(0, space) : cut).trimRight()}…';
    reason = flat;
  }
  // The row closes the sentence after the origin: "motivo (spec 33)."
  reason = reason.replaceFirst(RegExp(r'\.$'), '');
  return (title: title, reason: reason);
}

/// R9: the selected excerpt of the message when there is one; otherwise its
/// first paragraph (the first block of text that is not a code block or a
/// rule), without the heading and list marks.
String messageDebtExcerpt(String message, {String? selection}) {
  final sel = selection?.trim() ?? '';
  if (sel.isNotEmpty) return sel;
  final blocks = <String>[];
  final b = <String>[];
  var fence = false;
  void flush() {
    if (b.isNotEmpty) blocks.add(b.join('\n'));
    b.clear();
  }

  for (final raw in message.split('\n')) {
    final line = raw.trimRight();
    if (line.trimLeft().startsWith('```') ||
        line.trimLeft().startsWith('~~~')) {
      flush();
      fence = !fence;
      continue;
    }
    if (fence) continue;
    if (line.trim().isEmpty ||
        RegExp(r'^\s*([-*_])\1{2,}\s*$').hasMatch(line)) {
      flush();
      continue;
    }
    b.add(line);
  }
  flush();
  for (final block in blocks) {
    final text = block
        .split('\n')
        .map(
          (l) => l
              .trim()
              .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
              .replaceFirst(RegExp(r'^>\s?'), '')
              .replaceFirst(RegExp(r'^(?:[-*+]|\d+[.)])\s+'), ''),
        )
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isNotEmpty) return text;
  }
  return message.trim();
}

const _notFunctions = {
  'if', 'for', 'while', 'switch', 'catch', 'return', 'else', 'new', //
  'await', 'throw', 'when', 'foreach', 'using', 'lock', 'do', 'try',
};

final _fnKeyword = RegExp(
  r'\b(?:def|function|func|fun|fn|sub|proc)\s+(?:\([^)]*\)\s*)?'
  r'([A-Za-z_$][\w$]*)',
);
final _fnArrow = RegExp(
  r'\b(?:const|let|var|final)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?'
  r'(?:function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)',
);
final _fnSignature = RegExp(
  r'^\s*(?:[\w$<>\[\],?.*&]+\s+)+\**([A-Za-z_$][\w$]*)\s*\([^;]*$',
);

/// The name of the function a line declares (`def validar_upload(`,
/// `Future<void> save(…) async {`, `const f = () =>`), or null.
String? functionNameIn(String line) {
  final k = _fnKeyword.firstMatch(line);
  if (k != null) return k.group(1);
  final a = _fnArrow.firstMatch(line);
  if (a != null) return a.group(1);
  final t = line.trimRight();
  if (!(t.endsWith('{') || t.endsWith('=>') || t.endsWith('async'))) {
    return null;
  }
  final first = RegExp(r'^\s*([\w$]+)').firstMatch(t)?.group(1);
  if (first == null || _notFunctions.contains(first)) return null;
  final name = _fnSignature.firstMatch(t)?.group(1);
  return name == null || _notFunctions.contains(name) ? null : name;
}

/// The function around [line] of [file]: the nearest declaration above it
/// inside its hunk, else the hunk's function context (`@@ … @@ def f():`).
String? enclosingFunction(DiffFile? file, int? line) {
  if (file == null || line == null || line <= 0) return null;
  DiffHunk? hunk;
  for (final h in file.hunks) {
    if (h.newStart <= line) hunk = h;
  }
  if (hunk == null) return null;
  final above = [
    for (final l in hunk.lines)
      if (l.newNo != null && l.newNo! <= line) l,
  ];
  for (final l in above.reversed) {
    final n = functionNameIn(l.text);
    if (n != null) return n;
  }
  return hunk.section.trim().isEmpty ? null : functionNameIn(hunk.section);
}

/// "Onde" of a review comment: `` `backend/app/arquivos.py`, `validar_upload` ``.
String reviewCommentWhere(String? path, {String? function}) {
  final p = path?.trim() ?? '';
  final f = function?.trim() ?? '';
  return [if (p.isNotEmpty) '`$p`', if (f.isNotEmpty) '`$f`'].join(', ');
}

/// R8: the form of "Virar débito" on a review comment: the comment as the
/// title and motive, the file and the function in "Onde", "revisão da spec
/// 33" as the origin.
DebtDraft reviewCommentDraft(
  ReviewCommentRow c, {
  required String specLabel,
  String? function,
}) {
  var body = c.body.trim();
  if (c.author == 'pr') body = body.replaceFirst(RegExp(r'^@\S+:\s*'), '');
  final (:title, :reason) = splitTitleReason(body);
  return DebtDraft(
    kind: DebtKind.debt,
    title: title,
    reason: reason,
    where: reviewCommentWhere(c.path, function: function),
    origin: 'revisão da $specLabel',
  );
}

/// R9: the form of "Virar débito" on a message of the agent.
DebtDraft messageDebtDraft(
  String message, {
  String? selection,
  required String origin,
}) {
  final (:title, :reason) = splitTitleReason(
    messageDebtExcerpt(message, selection: selection),
  );
  return DebtDraft(
    kind: DebtKind.debt,
    title: title,
    reason: reason,
    origin: origin,
  );
}

// --- review comments (R8) ----------------------------------------------------

/// Result of "Desfazer" on a comment that became a debt.
enum ReviewDebtUndo {
  /// The row was removed from the file.
  removed,

  /// The row changed since it was written: it stays, only the link goes.
  rowChanged,

  /// The row is not in the file anymore.
  rowMissing,
}

/// Ties a review comment to the debt it became (R8): the comment is
/// resolved by its `resolved` column and the link keeps the row as written,
/// so "Desfazer" removes it only when nobody changed it.
class OriginDebts {
  OriginDebts({
    required this.links,
    required this.comments,
    DebtsConfig Function(String repoRoot)? config,
  }) : _config = config ?? ((r) => ProjectConfig.loadSync(r).debts);

  final DebtLinksRepo links;
  final ReviewCommentsRepo comments;
  final DebtsConfig Function(String repoRoot) _config;

  static const _rowKey = 'linha';

  /// The row as written, kept in the link (`suggestion_body`, with no
  /// suggestion state: never shown as a suggestion).
  static String? writtenRowOf(DebtLink l) {
    final v = DebtLinksRepo.suggestionOf(l)[_rowKey];
    return v is String ? v : null;
  }

  /// After [written] was saved for [commentId]: the comment leaves the
  /// count of open comments and the link keeps the row.
  Future<void> settleReviewComment(DebtWritten written, int commentId) async {
    final doc = await DebtFiles.read(
      written.root,
      written.relPath,
      DebtKind.debt,
    );
    final row = doc.table.rowOf(written.code);
    if (row != null) {
      await links.update(
        written.linkId,
        DebtLinksCompanion(
          suggestionBody: Value(jsonEncode({_rowKey: row.raw})),
        ),
      );
    }
    await comments.setResolved(commentId, true);
  }

  /// "Desfazer" before the merge: the link goes, the row leaves the file of
  /// [writeRoot] (the worktree of the spec; null = the main checkout) when
  /// it is still as written, and the comment is open again.
  Future<ReviewDebtUndo> undoReviewComment(
    int commentId, {
    String? writeRoot,
  }) async {
    final l = await links.ofReviewComment(commentId);
    var result = ReviewDebtUndo.rowMissing;
    if (l != null && l.code != null) {
      final kind = DebtKind.fromDb(l.kind);
      final rel = DebtFiles.relPath(_config(l.repoRoot), kind);
      try {
        await DebtFiles.apply(
          writeRoot ?? l.repoRoot,
          rel,
          kind,
          RemoveDebtRow(l.code!, expectedRaw: writtenRowOf(l)),
        );
        result = ReviewDebtUndo.removed;
      } on DebtRowChanged {
        result = ReviewDebtUndo.rowChanged;
      } on DebtRowMissing {
        result = ReviewDebtUndo.rowMissing;
      }
    }
    if (l != null) await links.delete(l.id);
    await comments.setResolved(commentId, false);
    return result;
  }
}

final originDebtsProvider = Provider(
  (ref) => OriginDebts(
    links: ref.watch(debtLinksRepoProvider),
    comments: ref.watch(reviewCommentsRepoProvider),
  ),
);

/// Codes of the debts born from review comments, by comment id (R8).
final reviewCommentDebtCodesProvider = StreamProvider<Map<int, String>>(
  (ref) => ref.watch(debtLinksRepoProvider).watchReviewCommentCodes(),
);
