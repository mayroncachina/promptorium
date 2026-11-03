import 'package:flutter/foundation.dart';

import '../../core/git/git_service.dart';

/// Rebase of a stacked spec after its mother entered the base
/// (SPEC-032 R6, R7, R15).

enum RestackOutcome {
  /// The branch now sits on the new base with only its own commits.
  ok,

  /// The rebase conflicted and was aborted: the branch is as it was.
  conflict,

  /// Not attempted (dirty worktree, live session, missing old base…).
  skipped,
}

@immutable
class RestackResult {
  const RestackResult({
    required this.sessionId,
    required this.label,
    required this.outcome,
    this.files = const [],
    this.reason,
    this.warnings = const [],
  });

  final String sessionId;

  /// Spec code (or session title) for the notices.
  final String label;
  final RestackOutcome outcome;

  /// Conflicting files ([RestackOutcome.conflict]).
  final List<String> files;

  /// Why it was skipped.
  final String? reason;

  /// Steps after the rebase that failed (push, `gh pr edit`).
  final List<String> warnings;
}

/// Ref with the tip of the mother's branch as the child last saw it: the
/// "upstream" of `git rebase --onto` once the mother is squashed or gone.
String oldBaseRef(String key) => 'refs/promptorium/$key/base-antiga';

/// App setting with the mark of a failed restack of a session:
/// `conflito\n<arquivos>` or `desatualizada\n<motivo>`.
String restackMarkKey(String sessionId) => 'review.restack.$sessionId';

/// Mark stored after [r] (null = clear it).
String? restackMark(RestackResult r) => switch (r.outcome) {
  RestackOutcome.ok => null,
  RestackOutcome.conflict => 'conflito\n${r.files.join('\n')}',
  RestackOutcome.skipped => 'desatualizada\n${r.reason ?? ''}',
};

/// `git rebase --onto <newBase> <oldBase>` in the child's worktree [wt]
/// (its branch checked out there). Only with a clean worktree; on conflict
/// the rebase is aborted and the branch goes back to where it was.
Future<RestackOutcome> rebaseOnto(
  GitService wt, {
  required String newBase,
  required String oldBase,
  void Function(List<String> files)? onConflict,
  void Function(String reason)? onSkip,
}) async {
  final dirty = (await wt.status()).where((e) => !e.isUntracked).toList();
  if (dirty.isNotEmpty) {
    onSkip?.call(
      'o worktree tem ${dirty.length} alteração(ões) não commitada(s)',
    );
    return RestackOutcome.skipped;
  }
  final before = await wt.headSha();
  if (before == null) {
    onSkip?.call('o worktree não tem commits');
    return RestackOutcome.skipped;
  }
  try {
    await wt.git(['rebase', '--onto', newBase, oldBase]);
    return RestackOutcome.ok;
  } on GitException catch (e) {
    var files = <String>[];
    try {
      files = (await wt.git(['diff', '--name-only', '--diff-filter=U']))
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
    } on GitException {
      /* best effort */
    }
    try {
      await wt.git(['rebase', '--abort']);
    } on GitException {
      /* not started */
    }
    if (await wt.headSha() != before) {
      await wt.git(['reset', '-q', '--hard', before]);
    }
    if (files.isEmpty) {
      onSkip?.call('o rebase falhou: ${e.message}');
      return RestackOutcome.skipped;
    }
    onConflict?.call(files);
    return RestackOutcome.conflict;
  }
}

/// Message of "Resolver conflito" after a restack conflicted (R7).
String restackMessage({
  required String branch,
  required String base,
  String? oldBase,
  List<String> files = const [],
}) {
  final onto = oldBase == null
      ? '`git rebase $base`'
      : '`git rebase --onto $base $oldBase`';
  return 'A spec de que esta branch dependia já entrou em $base, e refazer a '
      'base de $branch conflitou'
      '${files.isEmpty ? '' : ' em ${files.join(', ')}'}. No worktree, rode '
      '$onto, resolva os conflitos mantendo o que as duas versões precisam, '
      'continue o rebase (`git rebase --continue`), rode os testes da spec e '
      'faça commit se precisar. Não troque a branch da raiz do projeto. '
      'Explique na resposta como resolveu cada conflito.';
}

/// Short notice of a batch of restacks: "base da SPEC-031 refeita",
/// "conflito ao refazer a base da SPEC-033 (a.dart)".
String restackNotice(List<RestackResult> results) => [
  for (final r in results)
    switch (r.outcome) {
      RestackOutcome.ok => 'base da ${r.label} refeita',
      RestackOutcome.conflict =>
        'conflito ao refazer a base da ${r.label} (${r.files.join(', ')})',
      RestackOutcome.skipped =>
        'base da ${r.label} desatualizada: ${r.reason ?? 'não refeita'}',
    },
].join(' · ');

/// One conflicting stretch of a file: what the base has and what the spec
/// has (SPEC-032 R17). Neither side is a removal.
@immutable
class ConflictHunk {
  const ConflictHunk({
    required this.path,
    required this.line,
    required this.base,
    required this.spec,
  });

  final String path;

  /// Line of the `<<<<<<<` marker (1-based).
  final int line;

  /// "Na main" / "Nesta spec".
  final List<String> base, spec;

  /// Last line of the stretch in the file with the markers.
  int get endLine => line + base.length + spec.length + 1;
}

final _open = RegExp(r'^<{7}(?: |$)');
final _mid = RegExp(r'^={7}$');
final _close = RegExp(r'^>{7}(?: |$)');
final _ancestor = RegExp(r'^\|{7}(?: |$)');

/// Stretches between conflict markers of [text]. In a rebase (and in
/// `git merge-tree <base> <branch>`) the first side is the base and the
/// second is the commit of the spec; a diff3 ancestor section is skipped.
List<ConflictHunk> parseConflictHunks(String path, String text) {
  final out = <ConflictHunk>[];
  final lines = text.split('\n');
  var i = 0;
  while (i < lines.length) {
    if (!_open.hasMatch(lines[i])) {
      i++;
      continue;
    }
    final start = i + 1;
    final base = <String>[], spec = <String>[];
    var side = 0; // 0 base, 1 ancestor, 2 spec
    i++;
    var closed = false;
    while (i < lines.length) {
      final l = lines[i];
      if (_ancestor.hasMatch(l) && side == 0) {
        side = 1;
      } else if (_mid.hasMatch(l) && side < 2) {
        side = 2;
      } else if (_close.hasMatch(l) && side == 2) {
        closed = true;
        break;
      } else if (side == 0) {
        base.add(l);
      } else if (side == 2) {
        spec.add(l);
      }
      i++;
    }
    if (closed) {
      out.add(ConflictHunk(path: path, line: start, base: base, spec: spec));
    }
    i++;
  }
  return out;
}

/// Conflict markers still in [text] (`<<<<<<<`, `=======`, `>>>>>>>`).
int countMarkers(String text) => text
    .split('\n')
    .where((l) => _open.hasMatch(l) || _mid.hasMatch(l) || _close.hasMatch(l))
    .length;

/// A rebase stopped in a worktree (SPEC-032 R17): which commit of how many,
/// and each conflicted file with the markers it still has.
@immutable
class RebaseStatus {
  const RebaseStatus({
    this.inProgress = false,
    this.step = 0,
    this.total = 0,
    this.files = const {},
  });

  final bool inProgress;
  final int step, total;

  /// Conflicted file → markers left (0 = resolved).
  final Map<String, int> files;

  bool get canContinue => inProgress && files.values.every((n) => n == 0);
}
