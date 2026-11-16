import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Refinar requisitos com o Claude" (R6): the spec the Nova spec rewrites
/// when it is saved, and the text of the issue for "Conte a ideia".
@immutable
class IssueRefineTarget {
  const IssueRefineTarget({
    required this.specId,
    required this.code,
    required this.issue,
    required this.text,
  });

  final int specId;
  final String code;
  final int issue;
  final String text;
}

/// The refine target of each workspace (by id).
class IssueRefine extends Notifier<Map<int, IssueRefineTarget>> {
  @override
  Map<int, IssueRefineTarget> build() => const {};

  void set(int workspaceId, IssueRefineTarget target) =>
      state = {...state, workspaceId: target};

  void clear(int workspaceId) {
    if (!state.containsKey(workspaceId)) return;
    state = {...state}..remove(workspaceId);
  }
}

final issueRefineProvider =
    NotifierProvider<IssueRefine, Map<int, IssueRefineTarget>>(IssueRefine.new);
