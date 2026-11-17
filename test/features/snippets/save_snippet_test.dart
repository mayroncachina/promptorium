import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/snippets/snippet_scope.dart';
import 'package:promptorium/features/snippets/widgets/snippets_dialog.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/widgets/markdown/app_markdown.dart';

import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart' show addWorkspace;
import 'snippet_test_utils.dart' show pumpFor;

const code = '-- Pedidos atrasados\nSELECT  id,\n\t nome  \nFROM pedidos;';

Future<ProviderContainer> pumpSave(
  WidgetTester tester, {
  bool origin = true,
  Future<void> Function(ProviderContainer)? seed,
}) async {
  tester.view.physicalSize = const Size(1366, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final ws = await addWorkspace(db, '/work/loja-api');
  final c = ProviderContainer(overrides: [databaseOverride(db)]);
  await seed?.call(c);
  Widget markdown = const AppMarkdown(
    data: 'Segue a query:\n\n```sql\n$code\n```',
  );
  if (origin) {
    markdown = SnippetScope(
      origin: SnippetOrigin(workspaceId: ws.id, label: 'Pedidos no DBeaver'),
      child: markdown,
    );
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(width: 640, child: markdown),
          ),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  await pumpFor(tester);
  return c;
}

void main() {
  testWidgets('R1: document previews only offer Copy', (tester) async {
    await pumpSave(tester, origin: false);
    expect(find.byKey(const ValueKey('code-save-snippet')), findsNothing);
    expect(find.byKey(const ValueKey('code-copy')), findsOneWidget);
  });

  testWidgets(
    'R1–R4: anchored form suggests name, saves exact code and opens the saved snippet',
    (tester) async {
      final c = await pumpSave(tester);
      await tester.tap(find.byKey(const ValueKey('code-save-snippet')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('save-snippet-form')), findsOneWidget);
      expect(find.text('Segue a query:'), findsOneWidget);
      final name = tester
          .widget<TextField>(find.byKey(const ValueKey('snippet-save-name')))
          .controller!;
      expect(name.text, 'Pedidos atrasados');
      expect(
        name.selection,
        TextSelection(baseOffset: 0, extentOffset: name.text.length),
      );
      await tester.tap(find.byKey(const ValueKey('snippet-save-confirm')));
      await pumpFor(tester);
      final s = await c
          .read(snippetsRepoProvider)
          .byName(1, 'Pedidos atrasados');
      expect(s!.body, code);
      expect(s.language, 'sql');
      expect(s.originLabel, 'Pedidos no DBeaver');
      expect(find.text('Salvo'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('code-save-snippet')));
      await pumpFor(tester, 20);
      expect(find.byType(SnippetsDialog), findsOneWidget);
    },
  );

  testWidgets('R4: a repeated name offers Replace and preserves uses', (
    tester,
  ) async {
    final c = await pumpSave(
      tester,
      seed: (c) async {
        final repo = c.read(snippetsRepoProvider);
        final s = await repo.save(
          workspaceId: 1,
          name: 'PEDIDOS ATRASADOS',
          body: 'old',
        );
        await repo.markUsed(s.id);
      },
    );
    await tester.tap(find.byKey(const ValueKey('code-save-snippet')));
    await pumpFor(tester);
    expect(find.text('Já existe um snippet com esse nome.'), findsOneWidget);
    expect(find.text('Substituir'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('snippet-save-confirm')));
    await pumpFor(tester);
    final s = await c.read(snippetsRepoProvider).byName(1, 'Pedidos atrasados');
    expect(s!.body, code);
    expect(s.uses, 1);
  });

  testWidgets('R2: empty name cannot save; Escape closes without writing', (
    tester,
  ) async {
    final c = await pumpSave(tester);
    await tester.tap(find.byKey(const ValueKey('code-save-snippet')));
    await pumpFor(tester);
    await tester.enterText(find.byKey(const ValueKey('snippet-save-name')), '');
    await tester.tap(find.byKey(const ValueKey('snippet-save-confirm')));
    await pumpFor(tester);
    expect(find.text('Informe um nome.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('save-snippet-form')), findsNothing);
    expect(
      await c.read(snippetsRepoProvider).byName(1, 'Pedidos atrasados'),
      isNull,
    );
  });
}
