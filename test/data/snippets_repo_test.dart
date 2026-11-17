import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/snippets_repo.dart';

void main() {
  late AppDatabase db;
  late SnippetsRepo repo;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = SnippetsRepo(db);
    await db.customStatement(
      "INSERT INTO workspaces (id, path, name) VALUES (1, '/a', 'a'), "
      "(2, '/b', 'b')",
    );
  });
  tearDown(() => db.close());

  test('the hash is the SHA-1 of the exact code', () {
    expect(snippetHash('abc'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
    expect(snippetHash('abc'), isNot(snippetHash('abc\n')));
  });

  test('the name is unique by workspace, case does not count (R4)', () async {
    await repo.save(workspaceId: 1, name: 'Atrasados', body: 'select 1;');
    expect(
      () => repo.save(workspaceId: 1, name: ' atrasados ', body: 'x'),
      throwsA(isA<SnippetNameTaken>()),
    );
    // Another workspace may use it.
    final other = await repo.save(workspaceId: 2, name: 'ATRASADOS', body: 'x');
    expect(other.workspaceId, 2);
  });

  test('replace keeps the row and its uses, with the new code', () async {
    final s = await repo.save(
      workspaceId: 1,
      name: 'Atrasados',
      body: 'select 1;',
      language: 'sql',
    );
    await repo.markUsed(s.id);
    final r = await repo.save(
      workspaceId: 1,
      name: 'atrasados',
      body: 'select 2;',
      language: 'sql',
      description: 'nova',
      replace: true,
    );
    expect(r.id, s.id);
    expect(r.body, 'select 2;');
    expect(r.bodyHash, snippetHash('select 2;'));
    expect(r.uses, 1);
    expect(r.description, 'nova');
    expect(await db.select(db.snippets).get(), hasLength(1));
  });

  test('hashes and byBody find the saved code (P9)', () async {
    await repo.save(workspaceId: 1, name: 'A', body: 'select 1;');
    await repo.save(workspaceId: 2, name: 'B', body: 'select 2;');
    expect(await repo.hashes(1).first, {snippetHash('select 1;')});
    expect((await repo.byBody(1, 'select 1;'))!.name, 'A');
    expect(await repo.byBody(1, 'select 2;'), isNull);
  });

  test('update renames, checks the name and changes the hash', () async {
    final a = await repo.save(workspaceId: 1, name: 'A', body: '1');
    await repo.save(workspaceId: 1, name: 'B', body: '2');
    expect(
      () => repo.update(a.id, name: 'b', body: '1'),
      throwsA(isA<SnippetNameTaken>()),
    );
    final u = await repo.update(
      a.id,
      name: 'a',
      body: '3',
      language: 'bash',
      description: 'd',
    );
    expect(u.name, 'a');
    expect(u.bodyHash, snippetHash('3'));
    expect(u.language, 'bash');
  });

  test('markUsed counts a use and the list comes used last first', () async {
    final a = await repo.save(workspaceId: 1, name: 'A', body: '1');
    final b = await repo.save(workspaceId: 1, name: 'B', body: '2');
    await (db.update(db.snippets)..where((s) => s.id.equals(b.id))).write(
      SnippetsCompanion(createdAt: Value(DateTime(2020))),
    );
    await repo.markUsed(b.id);
    final list = await repo.watch(1).first;
    expect(list.map((s) => s.name), ['B', 'A']);
    expect(list.first.uses, 1);
    expect(list.first.lastUsedAt, isNotNull);
    expect(a.uses, 0);
  });

  test('delete and restore put the snippet back as it was (R12)', () async {
    final conv = await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            workspaceId: 1,
            title: 'Pedidos',
            model: 'opus',
          ),
        );
    final s = await repo.save(
      workspaceId: 1,
      name: 'A',
      body: '1',
      originConversationId: conv,
      originLabel: 'Pedidos',
    );
    await repo.delete(s.id);
    expect(await repo.byId(s.id), isNull);
    await repo.restore(s);
    expect((await repo.byId(s.id))!.originConversationId, conv);

    // The origin went away while it was deleted: the label stays.
    await repo.delete(s.id);
    await (db.delete(db.conversations)..where((c) => c.id.equals(conv))).go();
    await repo.restore(s);
    final back = (await repo.byId(s.id))!;
    expect(back.originConversationId, isNull);
    expect(back.originLabel, 'Pedidos');
  });

  test('deleting the workspace deletes its snippets (R5)', () async {
    await repo.save(workspaceId: 1, name: 'A', body: '1');
    await repo.save(workspaceId: 2, name: 'B', body: '2');
    await db.customStatement('DELETE FROM workspaces WHERE id = 1');
    expect((await db.select(db.snippets).get()).map((s) => s.name), ['B']);
  });
}
