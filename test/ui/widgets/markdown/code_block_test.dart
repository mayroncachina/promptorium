import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:promptorium/ui/widgets/copy_button.dart';
import 'package:promptorium/ui/widgets/markdown/app_markdown.dart';
import 'package:promptorium/ui/widgets/markdown/code_block.dart';

/// The first `pre` of [markdown], parsed as [AppMarkdown] parses it.
md.Element firstPre(String markdown) {
  final doc = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  md.Element? found;
  void walk(List<md.Node>? nodes) {
    for (final n in nodes ?? const <md.Node>[]) {
      if (found != null) return;
      if (n is md.Element) {
        if (n.tag == 'pre') {
          found = n;
          return;
        }
        walk(n.children);
      }
    }
  }

  walk(doc.parseLines(markdown.split('\n')));
  return found!;
}

/// Clipboard of the test: what the last `Clipboard.setData` wrote.
List<String> mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

Future<void> pumpMarkdown(
  WidgetTester tester,
  String data, {
  bool collapse = false,
  Object? owner,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AppMarkdown(
            data: data,
            collapseLongCode: collapse,
            owner: owner,
          ),
        ),
      ),
    ),
  );
}

const _query = '''-- atrasados
SELECT
    c.id,
\tc.nome,
    COUNT(p.id) AS pedidos

FROM pedidos p''';

String _longQuery(int lines) =>
    [for (var i = 1; i <= lines; i++) 'linha_$i,'].join('\n');

final _copy = find.byKey(const ValueKey('code-copy'));
final _copyBottom = find.byKey(const ValueKey('code-copy-bottom'));
final _toggle = find.byKey(const ValueKey('code-toggle'));

String _shownCode(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('code-block-text')))
    .textSpan!
    .toPlainText();

void main() {
  group('codeOfPre (R2)', () {
    test('fenced block: exact text, without the final line break', () {
      final c = codeOfPre(firstPre('Texto:\n\n```sql\n$_query\n```\n'));
      expect(c.code, _query);
      expect(c.language, 'sql');
    });

    test('~~~ fence and language as written', () {
      final c = codeOfPre(firstPre('~~~Postgres\nSELECT 1;\n~~~'));
      expect(c.code, 'SELECT 1;');
      expect(c.language, 'Postgres');
    });

    test('indented block has no language', () {
      final c = codeOfPre(firstPre('Texto\n\n    a = 1\n      b = 2\n'));
      expect(c.code, 'a = 1\n  b = 2');
      expect(c.language, isNull);
    });

    test('block in a list loses only the markdown indentation', () {
      final c = codeOfPre(
        firstPre(
          '- passo:\n\n  ```bash\n  if x; then\n    echo 1\n  fi\n  ```\n',
        ),
      );
      expect(c.code, 'if x; then\n  echo 1\nfi');
      expect(c.language, 'bash');
    });

    test('blank lines, tabs and trailing spaces stay', () {
      final c = codeOfPre(firstPre('```\na\t= 1  \n\n\n  b\n```'));
      expect(c.code, 'a\t= 1  \n\n\n  b');
      expect(c.language, isNull);
    });
  });

  group('CodeBlock', () {
    testWidgets('R1 · bar with language, lines and Copiar', (tester) async {
      await pumpMarkdown(tester, '```SQL\n$_query\n```');
      expect(find.text('sql  · 7 linhas', findRichText: true), findsOneWidget);
      expect(find.text('Copiar'), findsOneWidget);
    });

    testWidgets('R1 · no language shows texto; short block has no count', (
      tester,
    ) async {
      await pumpMarkdown(tester, '```\nls -la\n```');
      expect(find.text('texto', findRichText: true), findsOneWidget);
      expect(find.textContaining('linha'), findsNothing);
    });

    testWidgets('R2 · Copiar copies the exact block', (tester) async {
      final copied = mockClipboard(tester);
      await pumpMarkdown(tester, 'Segue:\n\n```sql\n$_query\n```\n\nFim.');
      await tester.tap(_copy);
      await tester.pump();
      expect(copied, [_query]);
      await tester.pump(CopyButton.copiedFor);
    });

    testWidgets('R3 · Copiado for 1.5 s, a second click restarts it', (
      tester,
    ) async {
      mockClipboard(tester);
      await pumpMarkdown(tester, '```sql\nSELECT 1;\n```');
      await tester.tap(_copy);
      await tester.pump();
      expect(find.text('Copiado'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.tap(_copy);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('Copiado'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Copiado'), findsNothing);
      expect(find.text('Copiar'), findsOneWidget);
    });

    testWidgets('R4 · semantic label with language and lines', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMarkdown(tester, '```sql\n$_query\n```');
      expect(
        find.bySemanticsLabel('Copiar código SQL, 7 linhas'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('R4 · Tab reaches Copiar; Enter and Space copy', (
      tester,
    ) async {
      final copied = mockClipboard(tester);
      await pumpMarkdown(tester, '```sh\necho oi\n```');
      // The text takes no Tab stop: the first one is the button.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(copied, ['echo oi']);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(copied, ['echo oi', 'echo oi']);
      await tester.pump(CopyButton.copiedFor);
    });

    testWidgets('R8 · more than 24 lines arrives collapsed in 16', (
      tester,
    ) async {
      final copied = mockClipboard(tester);
      final code = _longQuery(40);
      await pumpMarkdown(tester, '```sql\n$code\n```', collapse: true);
      expect(_shownCode(tester).split('\n'), hasLength(16));
      expect(find.text('Mostrar as outras 24 linhas'), findsOneWidget);
      expect(_copyBottom, findsNothing);

      // Collapsed, Copiar still copies the whole block.
      await tester.tap(_copy);
      await tester.pump();
      expect(copied.single, code);
      await tester.pump(CopyButton.copiedFor);

      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(_shownCode(tester), code);
      expect(find.text('Recolher'), findsOneWidget);
      expect(_copyBottom, findsOneWidget);
      await tester.ensureVisible(_copyBottom);
      await tester.tap(_copyBottom);
      await tester.pump();
      expect(copied.last, code);
      await tester.pump(CopyButton.copiedFor);

      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(_shownCode(tester).split('\n'), hasLength(16));
    });

    testWidgets('R8 · the toggle announces its state', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMarkdown(tester, '```\n${_longQuery(30)}\n```', collapse: true);
      expect(
        tester.getSemantics(_toggle),
        matchesSemantics(
          label: 'Mostrar as outras 14 linhas',
          isButton: true,
          hasExpandedState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('R8 · 24 lines do not collapse', (tester) async {
      await pumpMarkdown(tester, '```\n${_longQuery(24)}\n```', collapse: true);
      expect(_toggle, findsNothing);
      expect(_shownCode(tester).split('\n'), hasLength(24));
    });

    testWidgets('R8 · outside the timeline a long block never collapses', (
      tester,
    ) async {
      await pumpMarkdown(tester, '```\n${_longQuery(40)}\n```');
      expect(_toggle, findsNothing);
      expect(_shownCode(tester).split('\n'), hasLength(40));
    });

    testWidgets('R8 · expanded state survives a rebuild of the block', (
      tester,
    ) async {
      final owner = Object();
      final data = '```\n${_longQuery(40)}\n```';
      await pumpMarkdown(tester, data, collapse: true, owner: owner);
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await pumpMarkdown(tester, data, collapse: true, owner: owner);
      expect(_shownCode(tester).split('\n'), hasLength(40));
      await pumpMarkdown(tester, data, collapse: true, owner: Object());
      await tester.pumpWidget(const SizedBox());
      await pumpMarkdown(tester, data, collapse: true, owner: Object());
      expect(_shownCode(tester).split('\n'), hasLength(16));
    });
  });
}
