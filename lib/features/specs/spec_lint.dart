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

  /// `depende-de` cites a spec that does not exist in the workspace
  /// (SPEC-063 R3).
  unknownDependency,

  /// `depende-de` cites the spec itself (SPEC-063 R3).
  selfDependency,

  /// A frontmatter key the app does not know (SPEC-063 R4).
  unknownFrontmatterKey,

  /// `## Perguntas em aberto` outside the `- P<n> · …` format, with
  /// suggestions counted as questions (SPEC-028 R3). Shown as its own
  /// notice above the editor, not in the strip.
  openQuestionsFormat,
}

/// Text of the [SpecWarningKind.openQuestionsFormat] notice (SPEC-028 R3).
String openQuestionsFormatMessage(OpenQuestionsScan scan) {
  final n = scan.suggestionLines.length;
  final m = scan.questions.length;
  final perguntas = m == 1 ? '1 pergunta' : '$m perguntas';
  if (n == 0) {
    return 'Em "Perguntas em aberto", as perguntas estão fora do formato '
        '"- P<n> · …". A spec tem $perguntas.';
  }
  final itens = n == 1
      ? '1 item é sugestão, não pergunta'
      : '$n itens são sugestões, não perguntas';
  return 'Em "Perguntas em aberto", $itens. A spec tem $perguntas, não '
      '${n + m}. As linhas marcadas são sugestões.';
}

/// One structure warning: [line] is 1-based in the spec text.
@immutable
class SpecWarning {
  const SpecWarning({
    required this.line,
    required this.message,
    required this.kind,
    this.fixLabel,
    this.key,
  });

  final int line;
  final String message;
  final SpecWarningKind kind;

  /// The button of a warning that can be fixed ("Trocar para depende-de").
  final String? fixLabel;

  /// The frontmatter key the warning is about.
  final String? key;

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

/// Frontmatter keys the app reads or writes (SPEC-063 R4); variations of
/// `depende-de` are known too.
const knownFrontmatterKeys = {
  'id',
  'status',
  dependsOnKey,
  'fase',
  'design',
  SpecDocument.autoPlanKey,
  SpecDocument.previousStageKey,
  SpecDocument.previousStatusKey,
  subagentsKey,
  'issue',
  specOriginKey,
  specSessionKey,
};

/// Structure warnings of a spec, in line order (SPEC-023 R8). They only
/// inform: saving and approving go on. With [knownCodes] (the specs of the
/// workspace), a dependency on a spec outside it is a warning too
/// (SPEC-063 R3).
List<SpecWarning> lintSpec(String text, {Set<String>? knownCodes}) {
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
  out.addAll(_frontmatterWarnings(doc, knownCodes));
  final scan = doc.openQuestionsScan;
  if (scan.offFormat) {
    out.add(
      SpecWarning(
        line:
            scan.suggestionLines.firstOrNull ??
            scan.questions.firstOrNull?.line ??
            1,
        message: openQuestionsFormatMessage(scan),
        kind: SpecWarningKind.openQuestionsFormat,
      ),
    );
  }
  // List.sort is not stable: the kind keeps the order within a line.
  out.sort(
    (a, b) => a.line != b.line
        ? a.line.compareTo(b.line)
        : a.kind.index.compareTo(b.kind.index),
  );
  return out;
}

/// SPEC-063 R3, R4: dependencies that cannot hold and unknown keys.
List<SpecWarning> _frontmatterWarnings(
  SpecDocument doc,
  Set<String>? knownCodes,
) {
  final out = <SpecWarning>[];
  final depsKey = doc.frontmatter.containsKey(dependsOnKey)
      ? dependsOnKey
      : doc.dependsOnAlias;
  final depsLine = depsKey == null ? null : doc.frontmatterLineOf(depsKey);
  final deps = doc.dependsOn;
  final self = doc.id;
  if (depsLine != null && self != null && deps.contains(self)) {
    out.add(
      SpecWarning(
        line: depsLine,
        message: 'depende-de cita a própria spec ($self)',
        kind: SpecWarningKind.selfDependency,
      ),
    );
  }
  if (depsLine != null && knownCodes != null && knownCodes.isNotEmpty) {
    final missing = [
      for (final c in deps)
        if (c != self && !knownCodes.contains(c)) c,
    ];
    if (missing.isNotEmpty) {
      final one = missing.length == 1;
      final list = one
          ? missing.single
          : '${missing.take(missing.length - 1).join(', ')} e ${missing.last}';
      out.add(
        SpecWarning(
          line: depsLine,
          message:
              'depende-de cita $list, que não ${one ? 'existe' : 'existem'} '
              'neste workspace: a spec não vai esperar por '
              '${one ? 'ela' : 'elas'}',
          kind: SpecWarningKind.unknownDependency,
        ),
      );
    }
  }
  for (final k in doc.frontmatter.keys) {
    if (knownFrontmatterKeys.contains(k) || isDependsOnAlias(k)) continue;
    final line = doc.frontmatterLineOf(k);
    if (line == null) continue;
    out.add(
      SpecWarning(
        line: line,
        message:
            'Chave desconhecida no cabeçalho: $k. Para dependência, o app lê '
            'depende-de',
        kind: SpecWarningKind.unknownFrontmatterKey,
        fixLabel: 'Trocar para depende-de',
        key: k,
      ),
    );
  }
  return out;
}
