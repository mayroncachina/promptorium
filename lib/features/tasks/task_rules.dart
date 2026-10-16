import '../../data/db/app_database.dart';

/// Status a legacy task takes from its session (tasks are no longer shown;
/// see `TaskActions`).

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
