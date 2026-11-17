import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/prompt/widgets/prompt_side_panel.dart';

import '../snippets/snippet_test_utils.dart';

void main() {
  group('SNIPPETS do painel do Prompt (SPEC-078 R13)', () {
    testWidgets('without snippets the section says how to save one', (
      tester,
    ) async {
      await pumpPrompt(tester);
      expect(find.text('SNIPPETS'), findsOneWidget);
      expect(
        find.text('Salve um bloco de código pelo botão Salvar da resposta.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('snippets-see-all')), findsNothing);
    });

    testWidgets('the five used last, "Ver todos (N)"; a click inserts the '
        'fenced block in the composer and counts a use', (tester) async {
      final (db, _, _) = await pumpPrompt(
        tester,
        seed: (db, ws) async {
          for (var i = 0; i < 7; i++) {
            await addSnippet(
              db,
              ws.id,
              'Snippet $i',
              body: 'select $i;',
              minutesAgo: 10 - i,
            );
          }
          await addSnippet(
            db,
            ws.id,
            'Atrasados',
            body: atrasados,
            minutesAgo: 60,
            lastUsedAt: DateTime.now(),
          );
        },
      );
      expect(find.text('Ver todos (8)'), findsOneWidget);
      final tiles = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            RegExp(r'^snippet-tile-\d+$')
                .hasMatch((w.key! as ValueKey<String>).value),
      );
      expect(tiles, findsNWidgets(5));
      // Used last first: the one used now, then the newest ones.
      expect(find.text('Atrasados'), findsOneWidget);
      expect(find.text('sql · 4 linhas'), findsOneWidget);
      expect(find.text('Snippet 0'), findsNothing);

      await tester.tap(find.text('Atrasados'));
      await pumpFor(tester);
      expect(composerText(tester), '```sql\n$atrasados\n```\n');
      expect(find.textContaining('Snippet inserido: '), findsOneWidget);
      final row = await (db.select(
        db.snippets,
      )..where((s) => s.name.equals('Atrasados'))).getSingle();
      expect(row.uses, 1);

      // Editar opens the dialog on it; "Ver todos" too.
      await tester.tap(find.byKey(ValueKey('snippet-tile-edit-${row.id}')));
      await pumpFor(tester, 20);
      expect(find.byKey(const ValueKey('snippets-dialog')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('snippet-name')))
            .controller!
            .text,
        'Atrasados',
      );
    });

    testWidgets('Copiar of the hover copies the exact code', (tester) async {
      final semantics = tester.ensureSemantics();
      final copied = recordClipboard(tester);
      late int id;
      await pumpPrompt(
        tester,
        seed: (db, ws) async =>
            id = (await addSnippet(db, ws.id, 'Atrasados', body: atrasados)).id,
      );
      await tester.tap(find.byKey(ValueKey('snippet-tile-copy-$id')));
      await pumpFor(tester);
      expect(copied, [atrasados]);
      expect(find.bySemanticsLabel('Copiar snippet Atrasados'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the collapsed panel has its Snippets button', (tester) async {
      await pumpPrompt(
        tester,
        size: const Size(1000, 800),
        seed: (db, ws) => addSnippet(db, ws.id, 'Atrasados'),
      );
      expect(SideSection.values.last, SideSection.snippets);
      await tester.tap(find.byKey(const ValueKey('side-strip-snippets')));
      await pumpFor(tester);
      expect(
        find.byKey(const ValueKey('side-balloon-snippets')),
        findsOneWidget,
      );
      expect(find.text('Atrasados'), findsOneWidget);
    });
  });
}
