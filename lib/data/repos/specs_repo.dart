import 'package:drift/drift.dart';

import '../db/app_database.dart';

class SpecsRepo {
  SpecsRepo(this._db);

  final AppDatabase _db;

  $SpecsTable get _t => _db.specs;

  Stream<List<Spec>> watchByWorkspace(int workspaceId) =>
      (_db.select(_t)
            ..where((s) => s.workspaceId.equals(workspaceId))
            ..orderBy([(s) => OrderingTerm.asc(s.code)]))
          .watch();

  Stream<Spec?> watchById(int id) =>
      (_db.select(_t)..where((s) => s.id.equals(id))).watchSingleOrNull();

  Future<Spec?> getById(int id) =>
      (_db.select(_t)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<Spec?> getByCode(int workspaceId, String code) =>
      (_db.select(_t)..where(
            (s) => s.workspaceId.equals(workspaceId) & s.code.equals(code),
          ))
          .getSingleOrNull();

  /// The workspace has no spec registered yet.
  Future<bool> isEmpty(int workspaceId) async =>
      (await (_db.select(_t)
                ..where((s) => s.workspaceId.equals(workspaceId))
                ..limit(1))
              .get())
          .isEmpty;

  /// Highest `SPEC-NNN` number registered in the workspace (0 = none);
  /// [kind] vibe looks at the `VIBE-NNN` series (SPEC-069 R3). Numbers
  /// reserved by [reserve] count even after their row is gone: a discarded
  /// VIBE never gives its number back (R10, R12).
  Future<int> maxNumber(
    int workspaceId, {
    SpecKind kind = SpecKind.spec,
  }) async {
    final rows = await (_db.select(
      _t,
    )..where((s) => s.workspaceId.equals(workspaceId))).get();
    final re = RegExp('^${kind.prefix}-(\\d+)\$');
    var max = int.tryParse(await _reserved(workspaceId, kind) ?? '') ?? 0;
    for (final r in rows) {
      final m = re.firstMatch(r.code);
      final n = m == null ? 0 : int.parse(m.group(1)!);
      if (n > max) max = n;
    }
    return max;
  }

  /// App setting with the highest number reserved in a series.
  static String reservedKey(int workspaceId, SpecKind kind) =>
      'numero.${kind.prefix}.$workspaceId';

  Future<String?> _reserved(int workspaceId, SpecKind kind) async =>
      (await (_db.select(_db.appSettings)
                ..where((s) => s.key.equals(reservedKey(workspaceId, kind))))
              .getSingleOrNull())
          ?.value;

  /// [code] is taken for good in its series (SPEC-069 R12): the number is
  /// reserved in the database the moment the VIBE (or the spec it becomes)
  /// is born.
  Future<void> reserve(int workspaceId, String code) async {
    final kind = SpecKind.ofCode(code);
    if (kind == null) return;
    final n = int.parse(code.substring(kind.prefix.length + 1));
    final cur = int.tryParse(await _reserved(workspaceId, kind) ?? '') ?? 0;
    if (n <= cur) return;
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: reservedKey(workspaceId, kind),
            value: '$n',
          ),
        );
  }

  /// The VIBE (or the spec it became) [conversationId] works on.
  Future<Spec?> ofConversation(int conversationId) async {
    final c = await (_db.select(
      _db.conversations,
    )..where((x) => x.id.equals(conversationId))).getSingleOrNull();
    return c?.specId == null ? null : getById(c!.specId!);
  }

  /// The conversation of a VIBE (null = none).
  Future<Conversation?> conversationOf(int specId) =>
      (_db.select(_db.conversations)
            ..where((x) => x.specId.equals(specId))
            ..limit(1))
          .getSingleOrNull();

  Future<Spec> insert({
    required int workspaceId,
    required String code,
    required String title,
    required String path,
    SpecStatus status = SpecStatus.draft,
    List<SpecRequirement> requirements = const [],
    List<String>? dependsOn,
    String? phase,
    bool hasPlan = false,
    bool inTray = false,
    SpecKind kind = SpecKind.spec,
    SpecStage? stage,
  }) => _db
      .into(_t)
      .insertReturning(
        SpecsCompanion.insert(
          workspaceId: workspaceId,
          code: code,
          title: title,
          path: path,
          status: Value(status),
          stage: Value(
            stage ??
                (status == SpecStatus.done || status == SpecStatus.archived
                    ? SpecStage.done
                    : SpecStage.backlog),
          ),
          kind: Value(kind),
          requirements: Value(requirements),
          dependsOn: Value.absentIfNull(dependsOn),
          phase: Value(phase),
          hasPlan: Value(hasPlan),
          // A VIBE never waits in the Bandeja (SPEC-069 R9).
          inTray: Value(inTray && kind == SpecKind.spec),
        ),
      );

  /// Writes the non-absent fields of [changes].
  Future<int> update(int id, SpecsCompanion changes) =>
      (_db.update(_t)..where((s) => s.id.equals(id))).write(changes);

  Future<int> setStatus(int id, SpecStatus status) =>
      update(id, SpecsCompanion(status: Value(status)));

  /// Column of the Quadro. Leaving the Backlog also leaves the Bandeja
  /// (SPEC-068 R7): a spec that ran is on the Quadro for good.
  Future<int> setStage(int id, SpecStage stage) => update(
    id,
    SpecsCompanion(
      stage: Value(stage),
      inTray: stage == SpecStage.backlog
          ? const Value.absent()
          : const Value(false),
    ),
  );

  /// "Levar para o Backlog" ([inTray] false) and its "Desfazer" (true),
  /// SPEC-068 R8.
  Future<void> setInTray(Iterable<int> ids, bool inTray) => (_db.update(
    _t,
  )..where((s) => s.id.isIn(ids))).write(SpecsCompanion(inTray: Value(inTray)));

  Future<int> setAgent(int id, String? agent) => update(
    id,
    SpecsCompanion(agentName: Value((agent?.isEmpty ?? true) ? null : agent)),
  );

  Future<int> setAutoAdvance(int id, bool on) =>
      update(id, SpecsCompanion(autoAdvance: Value(on)));

  /// Worktree / branch shared by the step sessions (null = none: the
  /// worktree was removed by the merge) and its [index] (port). Clearing it
  /// also forgets the preparation.
  Future<int> setWorktree(
    int id, {
    String? path,
    String? branch,
    String? baseBranch,
    int? index,
  }) => update(
    id,
    SpecsCompanion(
      worktreePath: Value(path),
      branch: Value(branch),
      baseBranch: Value(baseBranch),
      worktreeIndex: Value(index),
      preparedAt: path == null ? const Value(null) : const Value.absent(),
    ),
  );

  /// Phase of the Review column (`auto` / `human` / null) and the rounds
  /// of corrections asked by the automatic reviewer.
  Future<int> setReview(int id, {String? phase, int? rounds}) => update(
    id,
    SpecsCompanion(
      reviewPhase: Value(phase),
      reviewRounds: Value.absentIfNull(rounds),
    ),
  );

  /// One more automatic fix sent by the gate (metrics, schema v13).
  Future<void> countGateResend(int id) => _db.customUpdate(
    'UPDATE specs SET gate_resends = gate_resends + 1 WHERE id = ?',
    variables: [Variable.withInt(id)],
    updates: {_t},
  );

  /// One more hunk rejected in the Review (metrics, schema v13).
  Future<void> countRejectedHunk(int id) => _db.customUpdate(
    'UPDATE specs SET rejected_hunks = rejected_hunks + 1 WHERE id = ?',
    variables: [Variable.withInt(id)],
    updates: {_t},
  );

  /// Order of the cards of a column: [ids] get 0, 1, 2…
  Future<void> setBoardOrder(List<int> ids) => _db.transaction(() async {
    for (final (i, id) in ids.indexed) {
      await update(id, SpecsCompanion(boardOrder: Value(i)));
    }
  });

  /// The worktree got its files and ran `preparar:` (null = not yet).
  Future<int> setPrepared(int id, DateTime? at) =>
      update(id, SpecsCompanion(preparedAt: Value(at)));

  Future<int> delete(int id) =>
      (_db.delete(_t)..where((s) => s.id.equals(id))).go();
}
