import 'package:flutter/foundation.dart';

/// Kind of table: technical debts (`DT-NN`) or pending decisions (`DP-NN`)
/// (SPEC-112 R1).
enum DebtKind {
  debt('debito', 'DT', ['ID', 'Desde', 'O quê', 'Onde', 'Para resolver']),
  decision('decisao', 'DP', [
    'ID',
    'Desde',
    'Origem',
    'Pergunta',
    'Recomendação',
    'Decisão',
  ]);

  const DebtKind(this.dbName, this.prefix, this.columns);

  /// Value of `debt_links.kind`.
  final String dbName;

  /// `DT` / `DP`.
  final String prefix;

  /// Header of the table, in order.
  final List<String> columns;

  static DebtKind fromDb(String v) =>
      values.firstWhere((k) => k.dbName == v, orElse: () => DebtKind.debt);

  /// `DT-09` for 9 (two digits or more, R3).
  String code(int n) => '$prefix-${n.toString().padLeft(2, '0')}';

  /// Number of a code of this kind (`DT-09`, `~~DT-09~~`), or null.
  int? numberOf(String code) {
    final m = RegExp('^(?:~~)?\\s*$prefix-(\\d{2,})\\s*(?:~~)?\$')
        .firstMatch(code.trim());
    return m == null ? null : int.parse(m.group(1)!);
  }
}

/// A line of the table the parser did not understand: shown raw, never
/// rewritten (R5).
@immutable
class UnrecognizedLine {
  const UnrecognizedLine(this.line, this.text);

  /// 0-based index of the line in the file.
  final int line;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is UnrecognizedLine && other.line == line && other.text == text;

  @override
  int get hashCode => Object.hash(line, text);

  @override
  String toString() => 'UnrecognizedLine($line, $text)';
}

/// A row of the table whose first cell is a code of the table's kind.
@immutable
class DebtRow {
  const DebtRow({
    required this.line,
    required this.raw,
    required this.cells,
    required this.number,
  });

  /// 0-based index of the line in the file.
  final int line;

  /// The line as it is in the file, without the line break.
  final String raw;

  /// Trimmed cells, still escaped (`\|`).
  final List<String> cells;

  /// Number of the code (`9` for `DT-09`).
  final int number;

  @override
  bool operator ==(Object other) =>
      other is DebtRow &&
      other.raw == raw &&
      other.number == number &&
      listEquals(other.cells, cells);

  @override
  int get hashCode => Object.hash(raw, number, Object.hashAll(cells));
}

/// The row of an item changed since it was read: the write gives up and
/// warns (R5).
class DebtRowChanged implements Exception {
  const DebtRowChanged(this.code);
  final String code;

  @override
  String toString() =>
      'A linha do $code mudou desde a leitura. Releia e tente de novo.';
}

/// The item is not in the file (anymore).
class DebtRowMissing implements Exception {
  const DebtRowMissing(this.code);
  final String code;

  @override
  String toString() => 'O $code não está mais no arquivo.';
}

/// A Markdown table of debts or decisions inside a file (SPEC-112, Design,
/// "Parser de tabela Markdown"). Pure: no I/O. Every byte outside the
/// changed row stays the same (R5).
@immutable
class DebtTable {
  const DebtTable._({
    required this.kind,
    required this.text,
    required this.lines,
    required this.eol,
    required this.headerLine,
    required this.endLine,
    required this.rows,
    required this.unrecognized,
  });

  final DebtKind kind;

  /// The original text.
  final String text;

  /// Lines split on `\n`; a line keeps its `\r` (CRLF files).
  final List<String> lines;

  /// Line break used for new lines: `\r\n` when the file has it.
  final String eol;

  /// Line of the header (null = no table in the file).
  final int? headerLine;

  /// First line after the table (exclusive).
  final int? endLine;
  final List<DebtRow> rows;
  final List<UnrecognizedLine> unrecognized;

  bool get hasTable => headerLine != null;

  /// Highest number in the table (0 = none), struck rows included (R3).
  int get maxNumber => rows.fold(0, (m, r) => r.number > m ? r.number : m);

  DebtRow? rowOf(String code) {
    final n = kind.numberOf(code);
    if (n == null) return null;
    for (final r in rows) {
      if (r.number == n) return r;
    }
    return null;
  }

  static DebtTable parse(String text, DebtKind kind) {
    final lines = text.split('\n');
    final eol = text.contains('\r\n') ? '\r\n' : '\n';
    String content(int i) => _stripCr(lines[i]);
    final want = [for (final c in kind.columns) _normalize(c)];

    int? header;
    for (var i = 0; i + 1 < lines.length; i++) {
      final l = content(i).trim();
      if (!l.startsWith('|')) continue;
      final cells = [for (final c in splitCells(l)) _normalize(c)];
      if (!listEquals(cells, want)) continue;
      if (!_isSeparator(content(i + 1), want.length)) continue;
      header = i;
      break;
    }
    if (header == null) {
      return DebtTable._(
        kind: kind,
        text: text,
        lines: lines,
        eol: eol,
        headerLine: null,
        endLine: null,
        rows: const [],
        unrecognized: const [],
      );
    }
    final rows = <DebtRow>[];
    final odd = <UnrecognizedLine>[];
    var i = header + 2;
    for (; i < lines.length; i++) {
      final l = content(i);
      if (!l.trim().startsWith('|')) break;
      final cells = splitCells(l.trim());
      final n = cells.isEmpty ? null : kind.numberOf(cells.first);
      if (n != null && cells.length == want.length) {
        rows.add(DebtRow(line: i, raw: l, cells: cells, number: n));
      } else {
        odd.add(UnrecognizedLine(i, l));
      }
    }
    return DebtTable._(
      kind: kind,
      text: text,
      lines: lines,
      eol: eol,
      headerLine: header,
      endLine: i,
      rows: List.unmodifiable(rows),
      unrecognized: List.unmodifiable(odd),
    );
  }

  /// The text with a new row after the last line of the table. Without a
  /// table, the header and the separator go at the end of the file first.
  String append(List<String> cells) {
    final row = formatRow(cells);
    if (!hasTable) {
      final head = [
        formatRow(kind.columns, escape: false),
        '|${List.filled(kind.columns.length, '---').join('|')}|',
        row,
      ].join(eol);
      if (text.isEmpty) return '$head$eol';
      final ends = text.endsWith('\n');
      return '$text${ends ? '' : eol}$eol$head$eol';
    }
    final at = endLine!;
    final out = List.of(lines);
    // The new line takes the break of the line it follows.
    final cr = lines[at - 1].endsWith('\r') ? '\r' : '';
    if (at == lines.length) {
      // The table is the last thing in the file, with no final break.
      out[at - 1] =
          '${lines[at - 1]}${eol == '\r\n' && cr.isEmpty ? '\r' : ''}';
      out.add(row);
    } else {
      out.insert(at, '$row$cr');
    }
    return out.join('\n');
  }

  /// The text with the row of [code] replaced by [cells]. [expectedRaw] is
  /// the row as it was read: when it differs, [DebtRowChanged] (R5).
  String replace(String code, List<String> cells, {String? expectedRaw}) {
    final r = rowOf(code);
    if (r == null) throw DebtRowMissing(code);
    if (expectedRaw != null && expectedRaw != r.raw) {
      throw DebtRowChanged(code);
    }
    final out = List.of(lines);
    final cr = lines[r.line].endsWith('\r') ? '\r' : '';
    // Keeps the indentation of the original row.
    final indent = RegExp(r'^\s*').firstMatch(r.raw)!.group(0)!;
    out[r.line] = '$indent${formatRow(cells)}$cr';
    return out.join('\n');
  }

  /// `| a | b |` with the cells escaped ([escapeCell]).
  static String formatRow(List<String> cells, {bool escape = true}) =>
      '| ${[for (final c in cells) escape ? escapeCell(c) : c].join(' | ')} |';

  /// A cell ready for the table: line breaks become spaces and `|` not yet
  /// escaped becomes `\|`.
  static String escapeCell(String v) {
    final flat = v.replaceAll(RegExp(r'\s*\r?\n\s*'), ' ').trim();
    final b = StringBuffer();
    for (var i = 0; i < flat.length; i++) {
      final c = flat[i];
      if (c == '\\' && i + 1 < flat.length && flat[i + 1] == '|') {
        b.write(r'\|');
        i++;
      } else if (c == '|') {
        b.write(r'\|');
      } else {
        b.write(c);
      }
    }
    return b.toString();
  }

  /// The cell as text: `\|` back to `|`.
  static String unescapeCell(String v) => v.replaceAll(r'\|', '|');

  /// Cells of a row (`| a | b |`): split on `|` not escaped and not inside
  /// backticks; trimmed, still escaped.
  static List<String> splitCells(String row) {
    var s = row.trim();
    if (s.startsWith('|')) s = s.substring(1);
    final cells = <String>[];
    final b = StringBuffer();
    var inCode = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '\\' && i + 1 < s.length) {
        b
          ..write(c)
          ..write(s[i + 1]);
        i++;
      } else if (c == '`') {
        inCode = !inCode;
        b.write(c);
      } else if (c == '|' && !inCode) {
        cells.add(b.toString().trim());
        b.clear();
      } else {
        b.write(c);
      }
    }
    final rest = b.toString().trim();
    // A row closed with `|` leaves an empty tail.
    if (rest.isNotEmpty || !s.trimRight().endsWith('|')) cells.add(rest);
    return cells;
  }

  static String _stripCr(String l) =>
      l.endsWith('\r') ? l.substring(0, l.length - 1) : l;

  static bool _isSeparator(String line, int count) {
    final l = line.trim();
    if (!l.startsWith('|')) return false;
    final cells = splitCells(l);
    return cells.length == count &&
        cells.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c));
  }

  static const _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', //
    'é': 'e', 'ê': 'e', 'è': 'e', 'ë': 'e', //
    'í': 'i', 'î': 'i', 'ì': 'i', 'ï': 'i', //
    'ó': 'o', 'ô': 'o', 'õ': 'o', 'ò': 'o', 'ö': 'o', //
    'ú': 'u', 'û': 'u', 'ù': 'u', 'ü': 'u', 'ç': 'c',
  };

  /// Without accents, lower case, without `*` and spaces at the ends.
  static String _normalize(String v) {
    final l = v.replaceAll('*', '').trim().toLowerCase();
    return l.split('').map((c) => _accents[c] ?? c).join();
  }
}
