import 'package:flutter/foundation.dart' show immutable;

import 'spec_file.dart';

/// What a structure warning of the editor points at (SPEC-023 R8).
enum SpecWarningKind {
  /// A requirement no acceptance criterion cites.
  uncoveredRequirement,

  /// A criterion without `[Rn]`, or citing a requirement that does not exist.
  criterionRequirement,

  /// A criterion without `verificar:`.
  criterionVerify,

  /// A requirement ID repeated or out of sequence.
  requirementId,

  /// A requirement without "deve" (outside the EARS style).
  ears,
}

/// One structure warning: [line] is 1-based in the spec text.
@immutable
class SpecWarning {
  const SpecWarning({
    required this.line,
    required this.message,
    required this.kind,
  });

  final int line;
  final String message;
  final SpecWarningKind kind;

  @override
  bool operator ==(Object other) =>
      other is SpecWarning &&
      other.line == line &&
      other.message == message &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(line, message, kind);

  @override
  String toString() => 'L$line: $message';
}

final _ears = RegExp(r'\bdevem?\b', caseSensitive: false);
final _verifyWord = RegExp(r'\bverificar:', caseSensitive: false);

/// Structure warnings of a spec, in line order (SPEC-023 R8). They only
/// inform: saving and approving go on.
List<SpecWarning> lintSpec(String text) {
  final doc = SpecDocument.parse(text);
  final reqs = doc.requirementLines;
  final criteria = parseCriteria(text);
  final ids = {for (final r in reqs) r.id};
  final cited = {for (final c in criteria) ...c.requirements};
  final out = <SpecWarning>[];
  final seen = <String>{};
  var expected = 1;
  for (final r in reqs) {
    final n = int.parse(r.id.substring(1));
    if (!seen.add(r.id)) {
      out.add(
        SpecWarning(
          line: r.line,
          message: '${r.id} repetido',
          kind: SpecWarningKind.requirementId,
        ),
      );
      continue;
    }
    if (n != expected) {
      out.add(
        SpecWarning(
          line: r.line,
          message: '${r.id} fora de sequência (esperado R$expected)',
          kind: SpecWarningKind.requirementId,
        ),
      );
    }
    expected = n + 1;
    if (!_ears.hasMatch(r.text)) {
      out.add(
        SpecWarning(
          line: r.line,
          message: '${r.id} sem "deve" (fora do estilo EARS)',
          kind: SpecWarningKind.ears,
        ),
      );
    }
    if (!cited.contains(r.id)) {
      out.add(
        SpecWarning(
          line: r.line,
          message: '${r.id} sem critério de aceite',
          kind: SpecWarningKind.uncoveredRequirement,
        ),
      );
    }
  }
  for (final c in criteria) {
    final unknown = [
      for (final id in c.requirements)
        if (!ids.contains(id)) id,
    ];
    if (c.requirements.isEmpty) {
      out.add(
        SpecWarning(
          line: c.line,
          message: 'Critério sem [Rn]',
          kind: SpecWarningKind.criterionRequirement,
        ),
      );
    } else if (unknown.isNotEmpty) {
      out.add(
        SpecWarning(
          line: c.line,
          message:
              'Critério cita ${unknown.join(', ')}, que não '
              '${unknown.length == 1 ? 'existe' : 'existem'}',
          kind: SpecWarningKind.criterionRequirement,
        ),
      );
    }
    // A `verificar:` the parser could not split (backticks inside) counts.
    if (c.verify == null && !_verifyWord.hasMatch(c.text)) {
      out.add(
        SpecWarning(
          line: c.line,
          message: 'Critério sem verificar:',
          kind: SpecWarningKind.criterionVerify,
        ),
      );
    }
  }
  // List.sort is not stable: the kind keeps the order within a line.
  out.sort(
    (a, b) => a.line != b.line
        ? a.line.compareTo(b.line)
        : a.kind.index.compareTo(b.kind.index),
  );
  return out;
}
