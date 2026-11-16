import 'package:drift/drift.dart' show Value;

import '../../core/git/gh_issues.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/specs_repo.dart';
import '../specs/spec_service.dart';

/// "Criar issue" (SPEC-074 R11): a spec without `issue:` gets an issue on
/// GitHub, and only then the link.

/// The text of the issue of [text] (the spec at [path]): the Objetivo, the
/// requirements as a checklist and the line with the path of the spec (P6).
/// The app never checks the items.
String issueBodyFromSpec(String text, {required String path}) {
  final doc = SpecDocument.parse(text);
  final objective = (doc.objective ?? '')
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .trim();
  final reqs = doc.requirements;
  return [
    if (objective.isNotEmpty) objective,
    if (reqs.isNotEmpty)
      [for (final r in reqs) '- [ ] ${r.id} · ${r.text}'].join('\n'),
    'Spec: `$path` (Promptorium)',
  ].join('\n\n');
}

/// Creates the issue with `gh issue create` and only then writes `issue: N`
/// in the file of [spec] (R11). A failure of `gh` leaves the spec as it
/// was. Returns the number of the issue.
Future<int> createIssueForSpec({
  required GhIssues client,
  required SpecService service,
  required SpecsRepo repo,
  required Workspace ws,
  required Spec spec,
  required String title,
  required String body,
  List<String> labels = const [],
  String? milestone,
  String? assignee,
}) async {
  final n = await client.create(
    title: title.trim(),
    body: body,
    labels: labels,
    milestone: milestone,
    assignee: assignee,
  );
  final text = await service.read(ws, spec);
  if (text == null) {
    throw SpecException(
      'A issue #$n foi criada, mas o arquivo de ${spec.code} sumiu: escreva '
      'issue: $n no cabeçalho da spec.',
    );
  }
  final saved = await service.save(
    ws,
    spec,
    SpecDocument.parse(text).withIssue(n),
  );
  await repo.update(
    saved.id,
    const SpecsCompanion(issueState: Value(IssueState.open)),
  );
  return n;
}
