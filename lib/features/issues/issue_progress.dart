import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../project/project_config.dart';
import 'issue_availability.dart';

/// The progress comment on the issue (SPEC-074 R10): with
/// `issues.comentar-andamento: true`, each note of `anotar_andamento` on a
/// linked spec rewrites one comment per spec, found by a hidden marker.

/// The hidden marker of the comment of [code].
String issueCommentMarker(String code) => '<!-- promptorium:$code -->';

/// `feito`, `em execução`, `a fazer`.
String _stateWord(StepStatus? s) => switch (s) {
  StepStatus.done => 'feito',
  StepStatus.running ||
  StepStatus.verifying ||
  StepStatus.needsInput => 'em execução',
  _ => 'a fazer',
};

/// The text of the comment (R10): the title, the state of each requirement
/// with its newest note, the PR when there is one and the line "Atualizado
/// pelo Promptorium". [notes] newest first.
String issueProgressComment({
  required Spec spec,
  required List<SpecStep> steps,
  required List<SpecNote> notes,
  String? prUrl,
}) {
  final byStep = {for (final s in steps) s.step: s.status};
  String? lastNote(String id) {
    for (final n in notes) {
      final ids = (n.steps ?? '').split(',').map((s) => s.trim());
      if (ids.contains(id)) return n.note;
    }
    return null;
  }

  final lines = [
    for (final r in spec.requirements)
      '- **${r.id}** · ${_stateWord(byStep[r.id])}'
          '${lastNote(r.id) == null ? '' : ' · “${lastNote(r.id)}”'}',
  ];
  final general = notes
      .where((n) => (n.steps ?? '').trim().isEmpty)
      .firstOrNull;
  final pr = prUrl == null
      ? null
      : RegExp(r'/pull/(\d+)').firstMatch(prUrl)?.group(1);
  return [
    issueCommentMarker(spec.code),
    '### Andamento da ${spec.code}',
    if (lines.isNotEmpty) lines.join('\n'),
    if (general != null) 'Última nota: “${general.note}”',
    '<sub>Atualizado pelo Promptorium a cada nota de andamento'
        '${pr == null ? '' : ' · PR #$pr'}</sub>',
  ].join('\n\n');
}

/// What happened to the comment, for the answer to the agent.
typedef IssuePublish = ({bool published, String? reason});

class IssueProgressPublisher {
  IssueProgressPublisher(this._ref);

  final Ref _ref;

  /// After a note on [specId] (R10): off, nothing goes to GitHub and the
  /// result is null; on, the comment is created or edited. A failure marks
  /// "comentário pendente" and the next note tries again.
  Future<IssuePublish?> afterNote(int specId) async {
    final repo = _ref.read(specsRepoProvider);
    final spec = await repo.getById(specId);
    final n = spec?.issueNumber;
    if (spec == null || n == null) return null;
    final ws = await _ref
        .read(workspacesRepoProvider)
        .getById(spec.workspaceId);
    if (ws == null) return null;
    if (!ProjectConfig.loadSync(ws.path).issues.commentProgress) return null;
    Future<IssuePublish> fail(String reason) async {
      await repo.update(
        spec.id,
        const SpecsCompanion(issueCommentPending: Value(true)),
      );
      return (published: false, reason: reason);
    }

    try {
      final (client, a) = await githubIssuesOf(_ref, ws);
      if (client == null) {
        return await fail(a.reason ?? 'GitHub indisponível');
      }
      // Never on a closed issue.
      final state = (await client.states([n])).firstOrNull;
      if (state == null || !state.found) {
        return await fail('a issue #$n não foi encontrada');
      }
      if (state.closed) {
        await repo.update(
          spec.id,
          const SpecsCompanion(
            issueCommentPending: Value(false),
            issueState: Value(IssueState.closed),
          ),
        );
        return (published: false, reason: 'a issue #$n está fechada');
      }
      final sessions = await _ref.read(sessionsRepoProvider).bySpec(spec.id);
      final prUrl = [
        for (final s in sessions)
          if (s.prUrl != null) s.prUrl!,
      ].lastOrNull;
      final body = issueProgressComment(
        spec: spec,
        steps: await _ref.read(specStepsRepoProvider).bySpec(spec.id),
        notes: await _ref.read(specNotesRepoProvider).bySpec(spec.id),
        prUrl: prUrl,
      );
      await client.upsertComment(n, issueCommentMarker(spec.code), body);
      await repo.update(
        spec.id,
        const SpecsCompanion(issueCommentPending: Value(false)),
      );
      return (published: true, reason: null);
    } catch (e) {
      return fail('$e');
    }
  }
}

final issueProgressPublisherProvider = Provider<IssueProgressPublisher>(
  IssueProgressPublisher.new,
);
