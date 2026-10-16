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

  /// Sessions of a spec (its steps), oldest first.
  Future<List<Session>> bySpec(int specId) =>
      (_db.select(_t)
            ..where((s) => s.specId.equals(specId))
            ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
          .get();

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
    String? effort,
    int? taskId,
    int? specId,
    String? steps,
    String? agentName,
    String? title,
    String? permissionMode,
    String? baseBranch,
    double costUsd = 0,
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
          effort: Value(effort),
          taskId: Value(taskId),
          specId: Value(specId),
          steps: Value(steps),
          agentName: Value(agentName),
          title: Value(title),
          permissionMode: Value(permissionMode),
          baseBranch: Value(baseBranch),
          costUsd: Value(costUsd),
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

  /// Records one `result`: [totalCostUsd] is the CLI's cumulative cost of the
  /// session (replaces the stored value); tokens are added.
  Future<void> recordResult(
    String id, {
    required double totalCostUsd,
    int tokensIn = 0,
    int tokensOut = 0,
  }) => _db.customUpdate(
    'UPDATE sessions SET cost_usd = ?, '
    'tokens_in = tokens_in + ?, tokens_out = tokens_out + ? WHERE id = ?',
    variables: [
      Variable.withReal(totalCostUsd),
      Variable.withInt(tokensIn),
      Variable.withInt(tokensOut),
      Variable.withString(id),
    ],
    updates: {_t},
    updateKind: UpdateKind.update,
  );

  Future<int> setPermissionMode(String id, String? mode) =>
      (_db.update(_t)..where((s) => s.id.equals(id))).write(
        SessionsCompanion(permissionMode: Value(mode)),
      );

  /// Review merge (Fase 9): status `merged` + hash of the merge commit.
  Future<int> setMerged(String id, String commit, {DateTime? at}) =>
      (_db.update(_t)..where((s) => s.id.equals(id))).write(
        SessionsCompanion(
          status: const Value(SessionStatus.merged),
          mergeCommit: Value(commit),
          endedAt: Value(at ?? DateTime.now()),
        ),
      );

  /// Pull request opened by the Review.
  Future<int> setPrUrl(String id, String url) => (_db.update(
    _t,
  )..where((s) => s.id.equals(id))).write(SessionsCompanion(prUrl: Value(url)));

  /// All sessions (every workspace), newest first.
  Stream<List<Session>> watchAll() => (_db.select(
    _t,
  )..orderBy([(s) => OrderingTerm.desc(s.startedAt)])).watch();

  /// On app start: sessions left `running`/`waitingApproval` become
  /// `interrupted` (Fase 5, item 8). Steps of specs left "running" wait for
  /// the user (no session is alive at startup). Returns how many sessions
  /// changed.
  Future<int> markLiveAsInterrupted() => _db.transaction(() async {
    await (_db.update(_db.specSteps)
          ..where((s) => s.status.equals(StepStatus.running.name)))
        .write(const SpecStepsCompanion(status: Value(StepStatus.needsInput)));
    return (_db.update(_t)..where(
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
  });

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

  /// Newest-first events of the workspace's sessions whose JSON contains
  /// [needle] (exact substring: `%`, `_` and `\\` are escaped), with their
  /// session. Used by the MCP log (Fase 11).
  Future<List<(SessionEvent, Session)>> recentEventsContaining(
    int workspaceId,
    List<String> needles, {
    int limit = 80,
  }) async {
    if (needles.isEmpty) return const [];
    final s = _db.sessions;
    String esc(String v) =>
        v.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    Expression<bool>? cond;
    for (final n in needles) {
      final e = _e.json.like('%${esc(n)}%', escapeChar: r'\');
      cond = cond == null ? e : (cond | e);
    }
    final q = _db.select(_e).join([innerJoin(s, s.id.equalsExp(_e.sessionId))])
      ..where(s.workspaceId.equals(workspaceId) & cond!)
      ..orderBy([OrderingTerm.desc(_e.id)])
      ..limit(limit);
    return [for (final r in await q.get()) (r.readTable(_e), r.readTable(s))];
  }
}
