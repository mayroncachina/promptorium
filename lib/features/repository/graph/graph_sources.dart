import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart';
import '../../../data/providers.dart';
import '../../review/pr_babysitter.dart';
import '../../sessions/session_manager.dart';

/// An open PR on a branch tip (SPEC-045 R4).
@immutable
class GraphPr {
  const GraphPr({
    required this.number,
    this.url,
    this.ci = CiState.none,
    this.sessionId,
  });

  final int number;
  final String? url;
  final CiState ci;

  /// Session whose card the Review opens (null = the PR in the browser).
  final String? sessionId;

  /// `#101 · CI rodando`.
  String get label => switch (ci) {
    CiState.none => '#$number',
    CiState.running => '#$number · CI rodando',
    CiState.passed => '#$number · CI passou',
    CiState.failed => '#$number · CI falhou',
  };

  @override
  bool operator ==(Object other) =>
      other is GraphPr &&
      other.number == number &&
      other.url == url &&
      other.ci == ci &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(number, url, ci, sessionId);
}

final _prNumber = RegExp(r'/pull/(\d+)');

/// The open PRs by branch (R4): those the babysitter follows come from it,
/// the others from `gh pr list`. A session on the same branch gives the
/// card the Review opens.
Map<String, GraphPr> mergePrSources(
  List<GhOpenPr> listed,
  List<Session> sessions,
  Map<String, PrWatch> watches,
) {
  final sessionOf = <String, String>{};
  for (final s in sessions) {
    if (s.branch.isNotEmpty) sessionOf[s.branch] = s.id;
  }
  final out = <String, GraphPr>{
    for (final p in listed)
      if (p.headRefName.isNotEmpty)
        p.headRefName: GraphPr(
          number: p.number,
          url: p.url,
          ci: p.ci,
          sessionId: sessionOf[p.headRefName],
        ),
  };
  for (final s in sessions) {
    final status = watches[s.id]?.status;
    final url = s.prUrl;
    if (status == null || !status.open || url == null) continue;
    final n = _prNumber.firstMatch(url);
    if (n == null || s.branch.isEmpty) continue;
    out[s.branch] = GraphPr(
      number: int.parse(n.group(1)!),
      url: url,
      ci: ciStateOf(status.checks.map((c) => c.$2)),
      sessionId: s.id,
    );
  }
  return out;
}

/// `gh pr list` of the repository at a path; empty without `gh`.
final graphOpenPrsProvider = FutureProvider.family<List<GhOpenPr>, String>((
  ref,
  path,
) async {
  try {
    return await ref.watch(ghCliFactoryProvider)(path).prListOpen();
  } on GhException {
    return const [];
  }
});

/// The open PRs by branch of the repository at a path (R4).
final graphPrsProvider = Provider.family<Map<String, GraphPr>, String>((
  ref,
  path,
) {
  final ws = ref.watch(activeWorkspaceProvider);
  final sessions = ws == null
      ? const <Session>[]
      : ref.watch(sessionsProvider(ws.id)).value ?? const <Session>[];
  return mergePrSources(
    ref.watch(graphOpenPrsProvider(path)).value ?? const [],
    sessions,
    ref.watch(prBabysitterProvider),
  );
});

/// Branches with a worktree where an agent is running now (R4: "agente
/// trabalhando").
final graphBusyBranchesProvider = Provider<Set<String>>((ref) {
  final ws = ref.watch(activeWorkspaceProvider);
  if (ws == null) return const {};
  final sessions = ref.watch(sessionsProvider(ws.id)).value ?? const [];
  final live = ref.watch(sessionManagerProvider.select((m) => m.live));
  return {
    for (final s in sessions)
      if (s.branch.isNotEmpty &&
          (live[s.id]?.alive ?? false) &&
          (live[s.id]?.busy ?? false))
        s.branch,
  };
});
