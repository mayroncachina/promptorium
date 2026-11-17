import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';
import 'package:promptorium/features/snippets/widgets/snippets_dialog.dart';
import 'package:promptorium/ui/shell/command_palette.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/data/providers.dart';

import 'snippet_test_utils.dart';

Future<ProviderContainer> openPalette(WidgetTester tester) async {
  final (_, c, _) = await pumpPrompt(
    tester,
    seed: (db, ws) async {
      await addSnippet(
        db,
        ws.id,
        'Pedidos atrasados',
        body: atrasados,
        description: 'Relatório do suporte',
      );
    },
  );
  final element = tester.element(find.byType(PromptScreen));
  showCommandPalette(
    element,
    ref: element as WidgetRef,
    onNavigate: (s) => c.read(navigationProvider.notifier).go(s),
  );
  await pumpFor(tester, 20);
  await tester.enterText(find.byType(TextField).last, r'$atras');
  await pumpFor(tester);
  return c;
}

void main() {
  test('R6: the dollar prefix restricts results to snippets, description is searched', () {
    final snippet = PaletteCommand(
      label: 'Pedidos',
      group: 'Snippets',
      searchText: 'Relatório suporte',
      run: () {},
    );
    final other = PaletteCommand(
      label: 'Sessão suporte',
      group: 'Sessões',
      run: () {},
    );
    expect(filterCommands([snippet, other], r'$suporte'), [snippet]);
    expect(
      paletteGroups.indexOf('Snippets'),
      greaterThan(paletteGroups.indexOf('Specs')),
    );
    expect(
      paletteGroups.indexOf('Snippets'),
      lessThan(paletteGroups.indexOf('Sessões')),
    );
  });

  testWidgets('R6–R8: preview and Enter copy exact code and count use', (
    tester,
  ) async {
    final copied = recordClipboard(tester);
    final c = await openPalette(tester);
    expect(find.byKey(const ValueKey('palette-preview')), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFor(tester, 20);
    expect(copied, [atrasados]);
    expect(
      (await c.read(snippetsRepoProvider).byName(1, 'Pedidos atrasados'))!.uses,
      1,
    );
  });

  testWidgets('R8: Ctrl+Enter inserts a fenced block in the open composer', (
    tester,
  ) async {
    final c = await openPalette(tester);
    await ctrl(tester, LogicalKeyboardKey.enter);
    expect(composerText(tester), contains('```sql\n$atrasados\n```'));
    expect(
      (await c.read(snippetsRepoProvider).byName(1, 'Pedidos atrasados'))!.uses,
      1,
    );
  });

  testWidgets('R9: Ctrl+E opens the selected snippet for editing', (
    tester,
  ) async {
    await openPalette(tester);
    await ctrl(tester, LogicalKeyboardKey.keyE);
    await pumpFor(tester, 20);
    expect(find.byType(SnippetsDialog), findsOneWidget);
    expect(find.text('Pedidos atrasados'), findsWidgets);
  });
}
