import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../core/git/gh_issues.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/specs_repo.dart';
import '../ideas/idea_import.dart' show cutAtParagraph, ideaMaxChars;
import '../specs/spec_service.dart';

/// "Importar issues" (SPEC-074 R3–R7): an issue becomes a draft spec with
/// `issue: N`, the text of the issue as its Objetivo.

/// The line "Requisitos" and "Critérios de aceite" carry until the spec is
/// refined (R5, R6).
const issueRefineHint =
    '<!-- Veio da issue: refine os requisitos com o Claude ("Refinar '
    'requisitos com o Claude", no menu da spec). -->';

/// The text of an issue cleaned for the Objetivo (R5): HTML comments out,
/// headings moved down so the top one is `###` (inside `## Objetivo`, the
/// hierarchy kept: `##` → `###`, `#` → `###`), checklists, links and images as they are; over
/// [ideaMaxChars] it is cut at the end of the last paragraph that fits.
({String text, bool truncated, int total}) issueObjective(String body) {
  var text = body.replaceAll('\r\n', '\n');
  text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final lines = text.split('\n');
  final heading = RegExp(r'^(#{1,6})(\s+.*)$');
  final fenceLine = RegExp(r'^\s*(```|~~~)');
  // The headings outside code blocks, with their line.
  final found = <int, RegExpMatch>{};
  var fence = false;
  for (var i = 0; i < lines.length; i++) {
    if (fenceLine.hasMatch(lines[i])) fence = !fence;
    final m = fence ? null : heading.firstMatch(lines[i]);
    if (m != null) found[i] = m;
  }
  // The top heading becomes `###`: an issue that starts at `##` (the usual
  // in issue templates) goes down one level, not two.
  final top = found.values.isEmpty
      ? 3
      : found.values.map((m) => m.group(1)!.length).reduce(math.min);
  final shift = math.max(0, 3 - top);
  final out = <String>[
    for (var i = 0; i < lines.length; i++)
      if (found[i] case final m?)
        '${'#' * (m.group(1)!.length + shift).clamp(3, 6)}${m.group(2)}'
      else
        lines[i],
  ];
  text = out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  final total = text.length;
  if (total <= ideaMaxChars) {
    return (text: text, truncated: false, total: total);
  }
  final (cut, _) = cutAtParagraph(text, ideaMaxChars);
  return (text: cut, truncated: true, total: total);
}

/// The draft spec of [issue] as [code] (R5): `status: rascunho`,
/// `issue: N`, the title of the issue, its text as the Objetivo, and empty
/// "Requisitos" and "Critérios de aceite" with the line that reminds to
/// refine.
({String text, bool truncated}) issueToSpecText(GhIssue issue, String code) {
  final o = issueObjective(issue.body);
  final objective = o.text.isEmpty
      ? 'A issue #${issue.number} não tem texto: descreva o problema e o '
            'resultado esperado.'
      : o.text;
  final note = o.truncated
      ? '\n\n<!-- O texto da issue #${issue.number} tinha ${o.total} '
            'caracteres e foi cortado em $ideaMaxChars. -->'
      : '';
  final title = issue.title.trim().isEmpty
      ? 'Issue #${issue.number}'
      : issue.title.trim();
  final text =
      '''
---
id: $code
status: rascunho
$specIssueKey: ${issue.number}
---

# $title

## Objetivo

$objective$note

## Requisitos

$issueRefineHint

## Fora do escopo

<!-- O que esta spec não faz (as sessões de etapa recebem esta lista). -->

## Plano

<!-- Como implementar: componentes, arquivos e decisões. Use "Planejar". -->

## Critérios de aceite

$issueRefineHint
''';
  return (text: text, truncated: o.truncated);
}

/// The specs of [specs] by the issue they are linked to (any state, even
/// Feito): an issue here is "já importada" (R4).
Map<int, Spec> specsByIssue(Iterable<Spec> specs) => {
  for (final s in specs) ?s.issueNumber: s,
};

/// `SPEC-024`, `SPEC-025`… for the issues checked, in the order of the
/// list, from [next] (R3: "vira SPEC-024").
Map<int, String> predictedCodes(Iterable<int> checked, int next) => {
  for (final (i, n) in checked.indexed)
    n: 'SPEC-${(next + i).toString().padLeft(3, '0')}',
};

/// What an import did.
@immutable
class IssueImportResult {
  const IssueImportResult({
    required this.created,
    this.skipped = const {},
    this.truncated = const [],
  });

  /// The new specs, in the order of the issues.
  final List<Spec> created;

  /// Issues that already had a spec when the import ran (number → code).
  final Map<int, String> skipped;

  /// Issues whose text was cut at 40.000 characters.
  final List<int> truncated;

  /// "3 issues viraram SPEC-024 a SPEC-026, na Bandeja" (R5).
  String get message {
    if (created.isEmpty) {
      return skipped.isEmpty
          ? 'Nenhuma issue importada.'
          : 'Nada novo: ${skipped.length == 1 ? 'a issue já tinha spec' : 'as issues já tinham spec'}.';
    }
    final n = created.length;
    final codes = n == 1
        ? created.single.code
        : '${created.first.code} a ${created.last.code}';
    return n == 1
        ? '1 issue virou $codes, na Bandeja'
        : '$n issues viraram $codes, na Bandeja';
  }
}

/// Imports of a workspace (by its folder) run one after the other: two
/// imports at the same time never create two specs for one issue (R4).
final _locks = <String, Future<void>>{};

Future<T> _serial<T>(String root, Future<T> Function() action) {
  final previous = _locks[root] ?? Future<void>.value();
  final next = previous.catchError((Object _) {}).then((_) => action());
  _locks[root] = next.then((_) {}, onError: (Object _) {});
  return next;
}

/// Creates one draft spec per issue of [issues] in the Bandeja (R4, R5).
/// The creation is exclusive, like SPEC-068 R4: the issues are checked
/// again against the table and the files right before writing, and a
/// number taken meanwhile moves the spec to the next free one.
Future<IssueImportResult> importIssues(
  SpecService service,
  SpecsRepo repo,
  Workspace ws,
  List<GhIssue> issues, {
  DateTime Function() now = DateTime.now,
}) => _serial(ws.path, () async {
  await service.sync(ws);
  final known = specsByIssue(await repo.watchByWorkspace(ws.id).first);
  final created = <Spec>[];
  final skipped = <int, String>{};
  final truncated = <int>[];
  for (final issue in issues) {
    if (known[issue.number] case final s?) {
      skipped[issue.number] = s.code;
      continue;
    }
    if (created.any((s) => s.issueNumber == issue.number)) continue;
    Spec? spec;
    for (var attempt = 0; spec == null; attempt++) {
      try {
        spec = await service.create(
          ws,
          title: issue.title.trim().isEmpty
              ? 'Issue ${issue.number}'
              : issue.title,
          render: (code) {
            final r = issueToSpecText(issue, code);
            if (r.truncated && !truncated.contains(issue.number)) {
              truncated.add(issue.number);
            }
            return r.text;
          },
        );
      } on SpecException {
        // Exclusive creation lost the number: the next try reads it again.
        if (attempt >= 5) rethrow;
      }
    }
    await repo.update(
      spec.id,
      SpecsCompanion(
        issueImportedAt: Value(now()),
        issueState: Value(issue.closed ? IssueState.closed : IssueState.open),
      ),
    );
    created.add((await repo.getById(spec.id)) ?? spec);
  }
  return IssueImportResult(
    created: created,
    skipped: skipped,
    truncated: truncated,
  );
});

/// The issue was edited after the spec took its text (R7).
bool issueChanged(Spec spec, GhIssue issue) {
  final at = spec.issueImportedAt;
  final edited = issue.updatedAt;
  return at != null && edited != null && edited.isAfter(at);
}

/// The text of [spec] with the Objetivo replaced by the text of [issue]
/// (R7, "Atualizar com a issue").
String withIssueObjective(String text, GhIssue issue) {
  final o = issueObjective(issue.body);
  return SpecDocument.parse(text).withSection(
    'Objetivo',
    o.text.isEmpty ? 'A issue #${issue.number} não tem texto.' : o.text,
    after: 'Objetivo',
  );
}
