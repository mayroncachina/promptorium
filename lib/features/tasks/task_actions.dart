import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

export 'task_rules.dart';

/// Moves of a legacy task (schema v8: the spec is the card now; tasks only
/// remain linked to sessions created before). Session-driven moves live in
/// `SessionManager` (`taskStatusForSession`).
class TaskActions {
  TaskActions(this._ref);

  final Ref _ref;

  Future<void> move(int taskId, TaskStatus status) =>
      _ref.read(tasksRepoProvider).setStatus(taskId, status);

  /// "Feito": called by the merge of the Review screen.
  Future<void> markDone(int taskId) => move(taskId, TaskStatus.done);
}

final taskActionsProvider = Provider(TaskActions.new);
