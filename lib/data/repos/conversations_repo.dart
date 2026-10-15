import 'package:drift/drift.dart';

import '../db/app_database.dart';

class ConversationsRepo {
  ConversationsRepo(this._db);

  final AppDatabase _db;

  $ConversationsTable get _t => _db.conversations;

  /// Newest first.
  Stream<List<Conversation>> watchByWorkspace(int workspaceId) =>
      (_db.select(_t)
            ..where((c) => c.workspaceId.equals(workspaceId))
            ..orderBy([
              (c) => OrderingTerm.desc(c.createdAt),
              (c) => OrderingTerm.desc(c.id),
            ]))
          .watch();

  Future<Conversation?> getById(int id) =>
      (_db.select(_t)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<Conversation> insert({
    required int workspaceId,
    required String title,
    required String model,
    String provider = 'claude',
    String? sessionId,
  }) => _db
      .into(_t)
      .insertReturning(
        ConversationsCompanion.insert(
          workspaceId: workspaceId,
          title: title,
          model: model,
          provider: Value(provider),
          sessionId: Value(sessionId),
        ),
      );

  Future<int> rename(int id, String title) =>
      (_db.update(_t)..where((c) => c.id.equals(id))).write(
        ConversationsCompanion(title: Value(title)),
      );

  Future<int> linkSession(int id, String? sessionId) =>
      (_db.update(_t)..where((c) => c.id.equals(id))).write(
        ConversationsCompanion(sessionId: Value(sessionId)),
      );

  Future<int> delete(int id) =>
      (_db.delete(_t)..where((c) => c.id.equals(id))).go();
}
