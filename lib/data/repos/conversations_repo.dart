import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Prompt conversations and their stream-json events (one aggregate).
class ConversationsRepo {
  ConversationsRepo(this._db);

  final AppDatabase _db;

  $ConversationsTable get _t => _db.conversations;
  $ConversationEventsTable get _e => _db.conversationEvents;

  /// Most recent activity first (`updated_at`, else `created_at`).
  Stream<List<Conversation>> watchByWorkspace(int workspaceId) =>
      (_db.select(_t)
            ..where((c) => c.workspaceId.equals(workspaceId))
            ..orderBy([
              (c) => OrderingTerm.desc(coalesce([c.updatedAt, c.createdAt])),
              (c) => OrderingTerm.desc(c.id),
            ]))
          .watch();

  Future<Conversation?> getById(int id) =>
      (_db.select(_t)..where((c) => c.id.equals(id))).getSingleOrNull();

  Stream<Conversation?> watchById(int id) =>
      (_db.select(_t)..where((c) => c.id.equals(id))).watchSingleOrNull();

  Future<Conversation> insert({
    required int workspaceId,
    required String title,
    required String model,
    String provider = 'claude',
    String? sessionId,
    String? claudeSessionId,
    String mode = 'ask',
  }) => _db
      .into(_t)
      .insertReturning(
        ConversationsCompanion.insert(
          workspaceId: workspaceId,
          title: title,
          model: model,
          provider: Value(provider),
          sessionId: Value(sessionId),
          claudeSessionId: Value(claudeSessionId),
          mode: Value(mode),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<int> update(int id, ConversationsCompanion changes) =>
      (_db.update(_t)..where((c) => c.id.equals(id))).write(changes);

  Future<int> rename(int id, String title) =>
      update(id, ConversationsCompanion(title: Value(title)));

  /// Session created by "Continuar como sessão".
  Future<int> linkSession(int id, String? sessionId) =>
      update(id, ConversationsCompanion(sessionId: Value(sessionId)));

  Future<int> setClaudeSession(int id, String claudeSessionId) => update(
    id,
    ConversationsCompanion(claudeSessionId: Value(claudeSessionId)),
  );

  Future<int> setMode(int id, String mode) =>
      update(id, ConversationsCompanion(mode: Value(mode)));

  Future<int> setModel(int id, String model) =>
      update(id, ConversationsCompanion(model: Value(model)));

  /// One more message (user or answer) and `updated_at = now`.
  Future<void> countMessage(int id) => _db.customUpdate(
    'UPDATE conversations SET message_count = message_count + 1, '
    'updated_at = ? WHERE id = ?',
    variables: [Variable.withDateTime(DateTime.now()), Variable.withInt(id)],
    updates: {_t},
    updateKind: UpdateKind.update,
  );

  /// Records one `result`: cumulative cost replaces, tokens add.
  Future<void> recordResult(
    int id, {
    required double totalCostUsd,
    int tokensIn = 0,
    int tokensOut = 0,
  }) => _db.customUpdate(
    'UPDATE conversations SET cost_usd = ?, '
    'tokens_in = tokens_in + ?, tokens_out = tokens_out + ? WHERE id = ?',
    variables: [
      Variable.withReal(totalCostUsd),
      Variable.withInt(tokensIn),
      Variable.withInt(tokensOut),
      Variable.withInt(id),
    ],
    updates: {_t},
    updateKind: UpdateKind.update,
  );

  /// Also deletes its events (cascade).
  Future<int> delete(int id) =>
      (_db.delete(_t)..where((c) => c.id.equals(id))).go();

  // --- events --------------------------------------------------------------

  /// Appends one raw line with the next `seq` (1-based).
  Future<ConversationEvent> appendEvent(
    int conversationId, {
    required String type,
    required String json,
  }) => _db.transaction(() async {
    final maxSeq = _e.seq.max();
    final row =
        await (_db.selectOnly(_e)
              ..addColumns([maxSeq])
              ..where(_e.conversationId.equals(conversationId)))
            .getSingle();
    final next = (row.read(maxSeq) ?? 0) + 1;
    return _db
        .into(_e)
        .insertReturning(
          ConversationEventsCompanion.insert(
            conversationId: conversationId,
            seq: next,
            type: type,
            json: json,
          ),
        );
  });

  Future<List<ConversationEvent>> events(int conversationId) =>
      (_db.select(_e)
            ..where((e) => e.conversationId.equals(conversationId))
            ..orderBy([(e) => OrderingTerm.asc(e.seq)]))
          .get();
}
