import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// SHA-1 of a snippet's code (SPEC-078 P9): "✓ Salvo" compares hashes.
String snippetHash(String body) => sha1.convert(utf8.encode(body)).toString();

/// Key of a name for the unique check (R4): case and the spaces around it
/// do not count.
String snippetNameKey(String name) => name.trim().toLowerCase();

/// A name already taken by another snippet of the workspace (R4).
class SnippetNameTaken implements Exception {
  const SnippetNameTaken(this.existing);

  final Snippet existing;

  @override
  String toString() => 'Já existe um snippet com esse nome.';
}

/// Snippets of a workspace (SPEC-078 R5).
class SnippetsRepo {
  SnippetsRepo(this._db);

  final AppDatabase _db;

  $SnippetsTable get _t => _db.snippets;

  /// Every snippet of [workspaceId], used last first (never used: by the
  /// creation, newest first).
  Stream<List<Snippet>> watch(int workspaceId) =>
      (_db.select(_t)
            ..where((s) => s.workspaceId.equals(workspaceId))
            ..orderBy([
              (s) => OrderingTerm(
                expression: coalesce([s.lastUsedAt, s.createdAt]),
                mode: OrderingMode.desc,
              ),
              (s) => OrderingTerm.desc(s.id),
            ]))
          .watch();

  /// Hashes of the codes saved in [workspaceId] (P9).
  Stream<Set<String>> hashes(int workspaceId) {
    final q = _db.selectOnly(_t)
      ..addColumns([_t.bodyHash])
      ..where(_t.workspaceId.equals(workspaceId));
    return q.watch().map(
      (rows) => {for (final r in rows) r.read(_t.bodyHash)!},
    );
  }

  Future<Snippet?> byId(int id) =>
      (_db.select(_t)..where((s) => s.id.equals(id))).getSingleOrNull();

  /// The snippet of [workspaceId] named [name] (case does not count).
  Future<Snippet?> byName(int workspaceId, String name) =>
      (_db.select(_t)..where(
            (s) =>
                s.workspaceId.equals(workspaceId) &
                s.nameKey.equals(snippetNameKey(name)),
          ))
          .getSingleOrNull();

  /// The newest snippet of [workspaceId] with exactly [body] (R4).
  Future<Snippet?> byBody(int workspaceId, String body) =>
      (_db.select(_t)
            ..where(
              (s) =>
                  s.workspaceId.equals(workspaceId) &
                  s.bodyHash.equals(snippetHash(body)),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.id)])
            ..limit(1))
          .getSingleOrNull();

  /// Saves a new snippet. A name already used in the workspace throws
  /// [SnippetNameTaken] unless [replace]: then that snippet takes the new
  /// code and the rest, and keeps its uses (R4).
  Future<Snippet> save({
    required int workspaceId,
    required String name,
    required String body,
    String? language,
    String description = '',
    int? originConversationId,
    String? originSessionId,
    String? originLabel,
    bool replace = false,
  }) => _db.transaction(() async {
    final existing = await byName(workspaceId, name);
    final now = DateTime.now();
    if (existing != null) {
      if (!replace) throw SnippetNameTaken(existing);
      return (_db.update(_t)..where((s) => s.id.equals(existing.id)))
          .writeReturning(
            SnippetsCompanion(
              name: Value(name.trim()),
              nameKey: Value(snippetNameKey(name)),
              language: Value(language),
              description: Value(description.trim()),
              body: Value(body),
              bodyHash: Value(snippetHash(body)),
              originConversationId: Value(originConversationId),
              originSessionId: Value(originSessionId),
              originLabel: Value(originLabel),
              updatedAt: Value(now),
            ),
          )
          .then((rows) => rows.single);
    }
    return _db
        .into(_t)
        .insertReturning(
          SnippetsCompanion.insert(
            workspaceId: workspaceId,
            name: name.trim(),
            nameKey: snippetNameKey(name),
            language: Value(language),
            description: Value(description.trim()),
            body: body,
            bodyHash: snippetHash(body),
            originConversationId: Value(originConversationId),
            originSessionId: Value(originSessionId),
            originLabel: Value(originLabel),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  });

  /// Edits name, language, description and code of [id] (R10). A name of
  /// another snippet throws [SnippetNameTaken].
  Future<Snippet> update(
    int id, {
    required String name,
    required String body,
    String? language,
    String description = '',
  }) => _db.transaction(() async {
    final current = await byId(id);
    if (current == null) throw StateError('Snippet $id não existe.');
    final other = await byName(current.workspaceId, name);
    if (other != null && other.id != id) throw SnippetNameTaken(other);
    final rows = await (_db.update(_t)..where((s) => s.id.equals(id)))
        .writeReturning(
          SnippetsCompanion(
            name: Value(name.trim()),
            nameKey: Value(snippetNameKey(name)),
            language: Value(language),
            description: Value(description.trim()),
            body: Value(body),
            bodyHash: Value(snippetHash(body)),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return rows.single;
  });

  Future<int> delete(int id) =>
      (_db.delete(_t)..where((s) => s.id.equals(id))).go();

  /// Puts back a deleted snippet as it was ("Desfazer", R12). The origin
  /// may have been deleted meanwhile: it then stays only as the label.
  Future<void> restore(Snippet s) => _db.transaction(() async {
    var row = s;
    final conv = s.originConversationId;
    if (conv != null &&
        await (_db.select(
              _db.conversations,
            )..where((c) => c.id.equals(conv))).getSingleOrNull() ==
            null) {
      row = row.copyWith(originConversationId: const Value(null));
    }
    final session = s.originSessionId;
    if (session != null &&
        await (_db.select(
              _db.sessions,
            )..where((x) => x.id.equals(session))).getSingleOrNull() ==
            null) {
      row = row.copyWith(originSessionId: const Value(null));
    }
    await _db.into(_t).insert(row, mode: InsertMode.insertOrReplace);
  });

  /// One more use, now (copied or inserted, R8).
  Future<void> markUsed(int id) => _db.customUpdate(
    'UPDATE snippets SET uses = uses + 1, last_used_at = ? WHERE id = ?',
    variables: [Variable.withDateTime(DateTime.now()), Variable.withInt(id)],
    updates: {_t},
    updateKind: UpdateKind.update,
  );
}
