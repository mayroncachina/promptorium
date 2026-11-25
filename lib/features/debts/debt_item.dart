import 'package:flutter/foundation.dart';

import 'debt_table.dart';

/// Placeholder of an empty cell (`Para resolver` of a paid debt).
const debtDash = '—';

bool _isEmptyCell(String v) {
  final t = v.trim();
  return t.isEmpty || t == debtDash || t == '-' || t == '–';
}

/// The first `**…**` or `~~…~~` of a cell (the title), without the marks.
({String title, int start, int end})? _firstMarked(String cell) {
  final m = RegExp(r'(\*\*|~~)(.+?)\1').firstMatch(cell);
  if (m == null) return null;
  var t = m.group(2)!.trim();
  // `~~**x**~~` / `**~~x~~**`
  t = t.replaceAll(RegExp(r'^(\*\*|~~)|(\*\*|~~)$'), '').trim();
  return (title: t, start: m.start, end: m.end);
}

/// A row of `DEBITO_TECNICO.md`: `| ID | Desde | O quê | Onde | Para
/// resolver |` (SPEC-112 R1).
@immutable
class DebtItem {
  const DebtItem({
    required this.code,
    required this.number,
    required this.since,
    required this.what,
    required this.title,
    required this.reason,
    required this.where,
    required this.toResolve,
    required this.paid,
    this.resolvedBy,
    this.resolvedByLink,
    this.raw = '',
  });

  /// `DT-05`, without the strike.
  final String code;
  final int number;

  /// `2026-11-21`, as written.
  final String since;

  /// The "O quê" cell as written (escapes undone).
  final String what;

  /// First bold or struck text of "O quê" (or the start of the cell).
  final String title;

  /// "O quê" without the title and the marks.
  final String reason;

  /// "Onde", as written (backticks kept).
  final String where;

  /// "Para resolver" (empty when `—`).
  final String toResolve;

  /// The ID is struck (`~~DT-02~~`).
  final bool paid;

  /// `spec 28` of "**resolvido** pela [spec 28](…)".
  final String? resolvedBy;
  final String? resolvedByLink;

  /// The row as it is in the file (for the check of R5).
  final String raw;

  /// The references of "Onde": the text inside backticks, or the whole cell
  /// when it has none (R16).
  List<String> get whereRefs {
    final codes = [
      for (final m in RegExp('`([^`]+)`').allMatches(where)) m.group(1)!.trim(),
    ];
    if (codes.isNotEmpty) return codes;
    final t = where.trim();
    return _isEmptyCell(t) ? const [] : [t];
  }

  static DebtItem? fromRow(DebtRow row) {
    if (row.cells.length != DebtKind.debt.columns.length) return null;
    final c = [for (final x in row.cells) DebtTable.unescapeCell(x)];
    final paid = c[0].trim().startsWith('~~');
    final what = c[2];
    final marked = _firstMarked(what);
    final title = marked?.title ?? _firstSentence(what);
    var reason = marked == null
        ? what
        : what.replaceRange(marked.start, marked.end, '');
    String? by, link;
    final res = RegExp(
      r'\*\*resolvido\*\*\s+pel[ao]\s+(?:\[([^\]]+)\]\(([^)]*)\)|(spec\s+\d+|VIBE[- ]\d+))',
      caseSensitive: false,
    ).firstMatch(what);
    if (res != null) {
      by = (res.group(1) ?? res.group(3))?.trim();
      link = res.group(2);
    }
    reason = reason
        .replaceFirst(RegExp(r'^\s*[:—–-]\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return DebtItem(
      code: DebtKind.debt.code(row.number),
      number: row.number,
      since: c[1].trim(),
      what: what,
      title: title,
      reason: reason,
      where: c[3].trim(),
      toResolve: _isEmptyCell(c[4]) ? '' : c[4].trim(),
      paid: paid,
      resolvedBy: by,
      resolvedByLink: link,
      raw: row.raw,
    );
  }

  /// Cells of a new row: "O quê" is `**title**: reason (origin).`.
  static List<String> newCells({
    required String code,
    required String since,
    required String title,
    String reason = '',
    String? origin,
    String where = '',
    String toResolve = '',
  }) {
    final b = StringBuffer('**${title.trim()}**');
    var r = reason.trim();
    final hasOrigin = origin != null && origin.trim().isNotEmpty;
    // "motivo. (spec 33, Q5)." would end with two full stops.
    if (hasOrigin) r = r.replaceFirst(RegExp(r'\.+$'), '');
    if (r.isNotEmpty) b.write(': $r');
    if (hasOrigin) {
      b.write(' (${origin.trim()})');
    }
    var what = b.toString();
    if (!RegExp(r'[.!?]$').hasMatch(what)) what = '$what.';
    return [
      code,
      since,
      what,
      formatWhere(where),
      toResolve.trim().isEmpty ? debtDash : toResolve.trim(),
    ];
  }

  /// "Onde" between backticks when it is a path or a name with an
  /// extension and has none yet.
  static String formatWhere(String where) {
    final w = where.trim();
    if (w.isEmpty) return debtDash;
    if (w.contains('`')) return w;
    final looksPath =
        !w.contains(' ') &&
        (w.contains('/') || RegExp(r'\.[A-Za-z0-9]{1,6}$').hasMatch(w));
    return looksPath ? '`$w`' : w;
  }

  /// Cells of the struck row (R15): ID and title struck, "— **resolvido**
  /// pela [label](link)" after the title, "—" in "Para resolver". The rest
  /// of the motive stays.
  List<String> struckCells({required String label, String? link}) {
    final by = link == null || link.isEmpty ? label : '[$label]($link)';
    final m = _firstMarked(what);
    String newWhat;
    if (m == null) {
      newWhat = '~~$title~~ — **resolvido** pela $by. $what';
    } else {
      var rest = what.substring(m.end).trimLeft();
      rest = rest
          .replaceFirst(RegExp(r'^[:—–-]\s*'), '')
          .replaceFirst(RegExp(r'\.\s*$'), '');
      newWhat =
          '~~${m.title}~~ — **resolvido** pela $by'
          '${rest.isEmpty ? '' : ' ($rest)'}.';
      if (m.start > 0) newWhat = '${what.substring(0, m.start)}$newWhat';
    }
    return ['~~$code~~', since, newWhat, where, debtDash];
  }

  /// Cells of the row as it is (to rewrite a field).
  List<String> get cells => [
    paid ? '~~$code~~' : code,
    since,
    what,
    where,
    toResolve.isEmpty ? debtDash : toResolve,
  ];

  @override
  bool operator ==(Object other) =>
      other is DebtItem &&
      other.code == code &&
      other.since == since &&
      other.what == what &&
      other.where == where &&
      other.toResolve == toResolve &&
      other.paid == paid;

  @override
  int get hashCode => Object.hash(code, since, what, where, toResolve, paid);

  @override
  String toString() => 'DebtItem($code, $title, paid: $paid)';
}

String _firstSentence(String v) {
  final t = v.trim();
  final i = t.indexOf(RegExp(r'[.:;—]'));
  return (i > 0 ? t.substring(0, i) : t).trim();
}

/// A row of `DECISOES_PENDENTES.md`: `| ID | Desde | Origem | Pergunta |
/// Recomendação | Decisão |` (SPEC-112 R1).
@immutable
class DecisionItem {
  const DecisionItem({
    required this.code,
    required this.number,
    required this.since,
    required this.origin,
    required this.question,
    required this.title,
    required this.recommendation,
    required this.decision,
    this.raw = '',
  });

  final String code;
  final int number;
  final String since;
  final String origin;

  /// The "Pergunta" cell as written.
  final String question;

  /// First bold text of the question (or the question itself).
  final String title;
  final String recommendation;

  /// "Decisão" (empty when pending).
  final String decision;
  final String raw;

  bool get decided => decision.trim().isNotEmpty;

  /// The spec number cited in "Origem" (`[Spec 31](…) Q1` → 31).
  int? get originSpecNumber {
    final m = RegExp(
      r'spec[\s-]*0*(\d+)',
      caseSensitive: false,
    ).firstMatch(origin);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// `Q1` / `P3` of "Origem".
  String? get originQuestion =>
      RegExp(r'\b([QP]\d+)\b').firstMatch(origin)?.group(1);

  static DecisionItem? fromRow(DebtRow row) {
    if (row.cells.length != DebtKind.decision.columns.length) return null;
    final c = [for (final x in row.cells) DebtTable.unescapeCell(x)];
    final q = c[3].trim();
    return DecisionItem(
      code: DebtKind.decision.code(row.number),
      number: row.number,
      since: c[1].trim(),
      origin: c[2].trim(),
      question: q,
      title: _firstMarked(q)?.title ?? q,
      recommendation: c[4].trim(),
      decision: _isEmptyCell(c[5]) ? '' : c[5].trim(),
      raw: row.raw,
    );
  }

  static List<String> newCells({
    required String code,
    required String since,
    required String question,
    String origin = '',
    String recommendation = '',
  }) {
    final q = question.trim();
    return [
      code,
      since,
      origin.trim().isEmpty ? debtDash : origin.trim(),
      q.contains('**') ? q : '**$q**',
      recommendation.trim().isEmpty ? debtDash : recommendation.trim(),
      '',
    ];
  }

  /// Cells with "Decisão" filled: "**Decidido (AAAA-MM-DD):** answer" (R12).
  List<String> decidedCells(String answer, {required String date}) => [
    code,
    since,
    origin.isEmpty ? debtDash : origin,
    question,
    recommendation.isEmpty ? debtDash : recommendation,
    '**Decidido ($date):** ${answer.trim()}',
  ];

  /// Cells with the decision followed by "gerou o DT-10" (R12).
  List<String> withGenerated(String debtCode) {
    final d = decision.trim();
    final tail = 'gerou o $debtCode.';
    final after = d.endsWith('.') ? 'Gerou o $debtCode.' : tail;
    return [
      code,
      since,
      origin.isEmpty ? debtDash : origin,
      question,
      recommendation.isEmpty ? debtDash : recommendation,
      d.isEmpty ? tail : (d.endsWith('.') ? '$d $after' : '$d; $tail'),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is DecisionItem &&
      other.code == code &&
      other.since == since &&
      other.origin == origin &&
      other.question == question &&
      other.recommendation == recommendation &&
      other.decision == decision;

  @override
  int get hashCode =>
      Object.hash(code, since, origin, question, recommendation, decision);

  @override
  String toString() => 'DecisionItem($code, $title, decided: $decided)';
}

/// The parsed file: the items of [table] and the lines it did not
/// understand.
@immutable
class DebtDocument {
  const DebtDocument(this.table, this.debts, this.decisions);

  factory DebtDocument.parse(String text, DebtKind kind) {
    final t = DebtTable.parse(text, kind);
    return DebtDocument(
      t,
      kind == DebtKind.debt
          ? [for (final r in t.rows) ?DebtItem.fromRow(r)]
          : const [],
      kind == DebtKind.decision
          ? [for (final r in t.rows) ?DecisionItem.fromRow(r)]
          : const [],
    );
  }

  static final empty = DebtDocument(
    DebtTable.parse('', DebtKind.debt),
    const [],
    const [],
  );

  final DebtTable table;
  final List<DebtItem> debts;
  final List<DecisionItem> decisions;

  List<UnrecognizedLine> get unrecognized => table.unrecognized;
}
