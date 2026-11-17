import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/widgets/markdown/app_markdown.dart';
import 'package:promptorium/ui/widgets/markdown/code_block.dart';

import 'code_block_test.dart' show mockClipboard, pumpMarkdown;

const _doc = '''Segue a query. Ela junta pedidos e clientes.

- primeiro item
- segundo item

```sql
SELECT
    c.id,
    c.nome
FROM clientes c;
```

Fim da resposta.''';

Future<void> _selectAllAndCopy(WidgetTester tester) async {
  await tester.tap(find.text('Fim da resposta.'));
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('R6 · one SelectionArea per document, no SelectableText', (
    tester,
  ) async {
    await pumpMarkdown(tester, _doc);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(
      tester.widget<MarkdownBody>(find.byType(MarkdownBody)).selectable,
      isFalse,
    );
    expect(find.byType(CodeBlock), findsOneWidget);
  });

  testWidgets('R6 · select all + copy crosses paragraph, list and code, '
      'without the bar', (tester) async {
    final copied = mockClipboard(tester);
    await pumpMarkdown(tester, _doc);
    await _selectAllAndCopy(tester);
    expect(copied, isNotEmpty);
    final text = copied.last;
    expect(text, contains('Segue a query.'));
    expect(text, contains('segundo item'));
    expect(text, contains('SELECT\n    c.id,\n    c.nome\nFROM clientes c;'));
    expect(text, contains('Fim da resposta.'));
    // Each block on its own line; bullet and item on the same one.
    expect(text, contains('clientes.\n'));
    expect(text, contains('• segundo item'));
    expect(text, contains('segundo item\nSELECT'));
    expect(text, contains('FROM clientes c;\nFim da resposta.'));
    expect(text, isNot(contains('Copiar')));
    expect(text, isNot(contains('sql')));
    expect(text, isNot(contains('linhas')));
  });

  testWidgets('R6 · collapsed toggle stays out of the selection', (
    tester,
  ) async {
    final copied = mockClipboard(tester);
    final code = [for (var i = 1; i <= 30; i++) 'l$i'].join('\n');
    await pumpMarkdown(
      tester,
      'Antes.\n\n```\n$code\n```\n\nFim da resposta.',
      collapse: true,
    );
    await _selectAllAndCopy(tester);
    expect(copied.last, isNot(contains('Mostrar')));
    expect(copied.last, contains('l1\nl2'));
  });

  testWidgets('R10 · the default style sheet comes from the theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppMarkdown(data: '# Título')),
      ),
    );
    expect(find.text('Título'), findsOneWidget);
  });

  test('R10 · no MarkdownBody outside AppMarkdown', () {
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('app_markdown.dart') &&
            f.readAsStringSync().contains('MarkdownBody('))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
