import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Sessions and their stream-json events (one aggregate).
class SessionsRepo {
  SessionsRepo(this._db);

  final AppDatabase _db;

  $SessionsTable get _t => _db.sessions;
  $SessionEventsTable get _e => _db.sessionEvents;

  Stream<List<Session>> watchByWorkspace(int workspaceId) =>
      (_db.select(_t)
            ..where((s) => s.workspaceId.equals(workspaceId))
            ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]))
          .watch();

  Stream<Session?> watchById(String id) =>
      (_db.select(_t)..where((s) => s.id.equals(id))).watchSingleOrNull();

  Future<Session?> getById(String id) =>
      (_db.select(_t)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<Session> insert({
    required String id,
    required int workspaceId,
    required String worktreePath,
    required String branch,
    required String model,
    int? taskId,
    String? agentName,
    SessionStatus status = SessionStatus.running,
  }) => _db
      .into(_t)
      .insertReturning(
        SessionsCompanion.insert(
          id: id,
          workspaceId: workspaceId,
          worktreePath: worktreePath,
          branch: branch,
          model: model,
          taskId: Value(taskId),
          agentName: Value(agentName),
          status: Value(status),
        ),
      );

  /// Sets [status]; terminal statuses also set `endedAt` (non-terminal clear it).
  Future<int> setStatus(String id, SessionStatus status, {DateTime? at}) =>
      (_db.update(_t)..where((s) => s.id.equals(id))).write(
        SessionsCompanion(
          status: Value(status),
          endedAt: Value(status.isTerminal ? (at ?? DateTime.now()) : null),
        ),
      );

  /// Adds the usage of one `result` event to the session totals.
  Future<void> addUsage(
    String id, {
    double costUsd = 0,
    int tokensIn = 0,
    int tokensOut = 0,
  }) => _db.customUpdate(
    'UPDATE sessions SET cost_usd = cost_usd + ?, '
    'tokens_in = tokens_in + ?, tokens_out = tokens_out + ? WHERE id = ?',
    variables: [
      Variable.withReal(costUsd),
      Variable.withInt(tokensIn),
      Variable.withInt(tokensOut),
      Variable.withString(id),
    ],
    updates: {_t},
    updateKind: UpdateKind.update,
  );

  /// On app start: sessions left `running`/`waitingApproval` become
  /// `interrupted` (Fase 5, item 8). Returns how many changed.
  Future<int> markLiveAsInterrupted() =>
      (_db.update(_t)..where(
            (s) => s.status.isIn([
              SessionStatus.running.name,
              SessionStatus.waitingApproval.name,
            ]),
          ))
          .write(
            SessionsCompanion(
              status: const Value(SessionStatus.interrupted),
              endedAt: Value(DateTime.now()),
            ),
          );

  /// Also deletes its events (cascade).
  Future<int> delete(String id) =>
      (_db.delete(_t)..where((s) => s.id.equals(id))).go();

  // --- events --------------------------------------------------------------

  /// Appends one raw stream-json line with the next `seq` (1-based).
  Future<SessionEvent> appendEvent(
    String sessionId, {
    required String type,
    required String json,
  }) => _db.transaction(() async {
    final maxSeq = _e.seq.max();
    final row =
        await (_db.selectOnly(_e)
              ..addColumns([maxSeq])
              ..where(_e.sessionId.equals(sessionId)))
            .getSingle();
    final next = (row.read(maxSeq) ?? 0) + 1;
    return _db
        .into(_e)
        .insertReturning(
          SessionEventsCompanion.insert(
            sessionId: sessionId,
            seq: next,
            type: type,
            json: json,
          ),
        );
  });

  SimpleSelectStatement<$SessionEventsTable, SessionEvent> _events(
    String sessionId,
  ) => _db.select(_e)
    ..where((e) => e.sessionId.equals(sessionId))
    ..orderBy([(e) => OrderingTerm.asc(e.seq)]);

  Future<List<SessionEvent>> events(String sessionId) =>
      _events(sessionId).get();

  Stream<List<SessionEvent>> watchEvents(String sessionId) =>
      _events(sessionId).watch();
}
