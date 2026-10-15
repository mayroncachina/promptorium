import '../../data/db/app_database.dart';

/// Pure rules of the Tarefas kanban (plano, Fase 8).

/// Codes in [Task.dependsOn] whose task is not `done` yet. Codes that do not
/// exist in the workspace are ignored (they could never be satisfied).
List<String> blockersOf(Task task, Map<String, Task> byCode) => [
  for (final code in task.dependsOn)
    if (byCode[code] case final dep? when dep.status != TaskStatus.done) code,
];

/// A task is blocked while any of its dependencies is not in "Feito".
bool isBlocked(Task task, Map<String, Task> byCode) =>
    blockersOf(task, byCode).isNotEmpty;

Map<String, Task> tasksByCode(Iterable<Task> tasks) => {
  for (final t in tasks) t.code: t,
};

/// Kanban status a task should take after its session changed to [session].
/// Null = keep the current one.
///
/// - session running / waiting approval → Em execução;
/// - `result` success ([fromResult]; process idle or finished) → Review;
/// - "Feito" only comes from the merge (Fase 9) or a manual move, and is never
///   undone by a session.
TaskStatus? taskStatusForSession(
  TaskStatus current,
  SessionStatus session, {
  bool fromResult = false,
}) {
  if (current == TaskStatus.done) return null;
  final next = switch (session) {
    SessionStatus.running ||
    SessionStatus.waitingApproval => TaskStatus.running,
    SessionStatus.completed when fromResult => TaskStatus.review,
    _ => null,
  };
  return next == current ? null : next;
}
