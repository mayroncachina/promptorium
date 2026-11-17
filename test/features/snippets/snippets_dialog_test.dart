import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';
import 'package:promptorium/features/snippets/widgets/snippets_dialog.dart';
import 'package:promptorium/ui/shell/navigation.dart';

import 'snippet_test_utils.dart';

Future<void> _open(WidgetTester tester, {int? select}) async {
  final element = tester.element(find.byType(PromptScreen));
  showSnippetsDialog(element, element as WidgetRef, selectId: select);
  await pumpFor(tester, 20);
}

TextEditingController _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!;

Finder _row(int id) => find.byKey(ValueKey('snippet-row-$id'));

void main() {
  test('filterSnippets searches name and description and orders', () {
    Snippet s(int id, String name, {String d = '', int created = 0}) => Snippet(
      id: id,
      workspaceId: 1,
      name: name,
      nameKey: name.toLowerCase(),
      description: d,
      body: 'x',
      bodyHash: 'h$id',
      uses: 0,
      createdAt: DateTime(2026, 1, 1 + created),
      updatedAt: DateTime(2026),
      lastUsedAt: id == 2 ? DateTime(2026, 6) : null,
    );
    final all = [
      s(1, 'Atrasos por transportadora', created: 1),
      s(2, 'Subir o banco local'),
      s(3, 'Seed', d: 'pedidos atrasados', created: 2),
    ];
    expect(filterSnippets(all, '').map((x) => x.id), [2, 3, 1]);
    expect(filterSnippets(all, '', order: SnippetOrder.name).map((x) => x.id), [
      1,
      3,
      2,
    ]);
    expect(
      filterSnippets(all, '', order: SnippetOrder.created).map((x) => x.id),
      [3, 1, 2],
    );
    expect(filterSnippets(all, 'atras').map((x) => x.id), containsAll([1, 3]));
    expect(filterSnippets(all, 'banco').single.id, 2);
  });

  testWidgets('lists, searches, edits with Ctrl+S and marks "não salvo" '
      '(R9, R10)', (tester) async {
    late Snippet a, b;
    final (db, _, _) = await pumpPrompt(
      tester,
      seed: (db, ws) async {
        a = await addSnippet(
          db,
          ws.id,
          'Pedidos atrasados',
          body: atrasados,
          description: 'Para o suporte',
          conversation: 1,
          originLabel: 'Pedidos atrasados no DBeaver',
          lastUsedAt: DateTime.now(),
          uses: 4,
        );
        b = await addSnippet(
          db,
          ws.id,
          'Subir o banco',
          language: 'bash',
          minutesAgo: 30,
        );
      },
    );
    await _open(tester);
    expect(find.text('repo · 2'), findsOneWidget);
    expect(_row(a.id), findsOneWidget);
    expect(_row(b.id), findsOneWidget);
    // The first one (used last) is open.
    expect(_field(tester, 'snippet-name').text, 'Pedidos atrasados');
    expect(find.text('usado 4 vezes · último uso hoje'), findsOneWidget);
    expect(find.text('da conversa '), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('snippets-search')),
      'banco',
    );
    await pumpFor(tester);
    expect(_row(a.id), findsNothing);
    expect(_row(b.id), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('snippets-search')), '');
    await pumpFor(tester);

    expect(find.byKey(const ValueKey('snippet-dirty')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('snippet-description')),
      'Para o time de suporte',
    );
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('snippet-dirty')), findsOneWidget);
    await ctrl(tester, LogicalKeyboardKey.keyS);
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('snippet-dirty')), findsNothing);
    final row = await (db.select(
      db.snippets,
    )..where((s) => s.id.equals(a.id))).getSingle();
    expect(row.description, 'Para o time de suporte');

    // A name of another snippet is refused (R4).
    await tester.enterText(
      find.byKey(const ValueKey('snippet-name')),
      'SUBIR O BANCO',
    );
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('snippet-save')));
    await pumpFor(tester);
    expect(find.text('Já existe um snippet com esse nome.'), findsOneWidget);
  });

  testWidgets('changing snippet with changes asks: Cancelar stays, '
      'Descartar goes (R10)', (tester) async {
    late Snippet a, b;
    await pumpPrompt(
      tester,
      seed: (db, ws) async {
        a = await addSnippet(db, ws.id, 'A', lastUsedAt: DateTime.now());
        b = await addSnippet(db, ws.id, 'B', body: 'select 2;', minutesAgo: 30);
      },
    );
    await _open(tester);
    expect(_field(tester, 'snippet-name').text, 'A');
    await tester.enterText(find.byKey(const ValueKey('snippet-name')), 'A2');
    await pumpFor(tester);
    await tester.tap(_row(b.id));
    await pumpFor(tester, 20);
    expect(find.text("Salvar as mudanças em 'A'?"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('snippet-unsaved-cancel')));
    await pumpFor(tester, 20);
    expect(_field(tester, 'snippet-name').text, 'A2');

    await tester.tap(_row(b.id));
    await pumpFor(tester, 20);
    await tester.tap(find.byKey(const ValueKey('snippet-unsaved-discard')));
    await pumpFor(tester, 20);
    expect(_field(tester, 'snippet-name').text, 'B');

    // Closing with changes asks too; Salvar writes and closes.
    await tester.enterText(find.byKey(const ValueKey('snippet-name')), 'B2');
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('snippets-close')));
    await pumpFor(tester, 20);
    expect(find.text("Salvar as mudanças em 'B'?"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('snippet-unsaved-save')));
    await pumpFor(tester, 30);
    expect(find.byKey(const ValueKey('snippets-dialog')), findsNothing);
    expect(a.name, 'A');
  });

  testWidgets('Excluir without asking, with Desfazer (R12)', (tester) async {
    late Snippet a;
    final (db, _, _) = await pumpPrompt(
      tester,
      seed: (db, ws) async => a = await addSnippet(db, ws.id, 'A'),
    );
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('snippet-delete')));
    await pumpFor(tester, 20);
    expect(_row(a.id), findsNothing);
    expect(find.text('Snippet excluído'), findsOneWidget);
    expect(await db.select(db.snippets).get(), isEmpty);
    final toast = tester.widget<SnackBar>(
      find.byKey(const ValueKey('snippet-deleted-toast')),
    );
    expect(toast.duration, const Duration(seconds: 5));
    await tester.tap(find.text('Desfazer'));
    await pumpFor(tester, 20);
    expect((await db.select(db.snippets).getSingle()).name, 'A');
    expect(_row(a.id), findsOneWidget);
  });

  testWidgets('the origin opens the conversation; a deleted one keeps the '
      'label with "(apagada)" (R11)', (tester) async {
    late Snippet a;
    final (db, container, _) = await pumpPrompt(
      tester,
      seed: (db, ws) async {
        a = await addSnippet(
          db,
          ws.id,
          'A',
          conversation: 1,
          originLabel: 'Pedidos atrasados no DBeaver',
        );
        await addSnippet(
          db,
          ws.id,
          'B',
          body: 'b',
          originLabel: 'Conversa que sumiu',
          minutesAgo: 30,
        );
      },
    );
    container.read(selectedConversationProvider.notifier).select(null);
    container.read(navigationProvider.notifier).go(AppSection.home);
    await _open(tester, select: a.id);
    await tester.tap(find.byKey(const ValueKey('snippet-origin-link')));
    await pumpFor(tester, 20);
    expect(find.byKey(const ValueKey('snippets-dialog')), findsNothing);
    expect(container.read(selectedConversationProvider), 1);
    expect(container.read(navigationProvider), AppSection.prompt);

    await _open(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('snippets-dialog')),
        matching: find.text('B'),
      ),
    );
    await pumpFor(tester, 20);
    expect(find.text('Conversa que sumiu (apagada)'), findsOneWidget);
    expect(find.byKey(const ValueKey('snippet-origin-link')), findsNothing);
    expect(db, isNotNull);
  });

  testWidgets('keyboard: ↓ and Enter open the next one; Inserir no composer '
      'closes and inserts (R8, R14)', (tester) async {
    late Snippet b;
    await pumpPrompt(
      tester,
      seed: (db, ws) async {
        await addSnippet(db, ws.id, 'A', lastUsedAt: DateTime.now());
        b = await addSnippet(
          db,
          ws.id,
          'B',
          body: 'echo b',
          language: 'bash',
          minutesAgo: 30,
        );
      },
    );
    await _open(tester);
    expect(_field(tester, 'snippet-name').text, 'A');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFor(tester, 20);
    expect(_field(tester, 'snippet-name').text, 'B');
    expect(b.id, isPositive);
    await tester.tap(find.byKey(const ValueKey('snippet-insert')));
    await pumpFor(tester, 30);
    expect(find.byKey(const ValueKey('snippets-dialog')), findsNothing);
    expect(composerText(tester), '```bash\necho b\n```\n');
  });
}
