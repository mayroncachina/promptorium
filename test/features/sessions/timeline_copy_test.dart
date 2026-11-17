import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/timeline_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/widgets/copy_button.dart';
import 'package:promptorium/ui/widgets/markdown/app_markdown.dart';
import 'package:promptorium/ui/widgets/markdown/code_block.dart';

import '../../ui/widgets/markdown/code_block_test.dart' show mockClipboard;

const _answer = '''Segue a query:

```sql
SELECT id
  FROM pedidos;
```''';

const _command = 'psql "\$DATABASE_URL" \\\n  -f atrasados.sql';

ToolItem _bash() => ToolItem(
  id: 'b1',
  name: 'Bash',
  input: {'command': _command, 'description': 'roda a query'},
)..result = 'ok';

Future<void> _pump(WidgetTester tester, List<TimelineItem> items) async {
  tester.view.physicalSize = const Size(1100, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: TimelineListView(items: items)),
    ),
  );
  await tester.pump();
}

double _opacity(WidgetTester tester, Finder button) => tester
    .widget<Opacity>(find.ancestor(of: button, matching: find.byType(Opacity)))
    .opacity;

Future<TestGesture> _hover(WidgetTester tester, Finder target) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: Offset.zero);
  addTearDown(g.removePointer);
  await g.moveTo(tester.getCenter(target));
  await tester.pump();
  return g;
}

void main() {
  final copyMessage = find.byKey(const ValueKey('copy-message'));
  final copyCommand = find.byKey(const ValueKey('tool-copy-command-b1'));

  testWidgets('R7 · Copiar mensagem shows on hover and copies the markdown', (
    tester,
  ) async {
    final copied = mockClipboard(tester);
    await _pump(tester, [AssistantTextItem(_answer)]);
    expect(_opacity(tester, copyMessage), 0);
    await _hover(tester, find.text('Segue a query:'));
    expect(_opacity(tester, copyMessage), 1);
    await tester.tap(copyMessage);
    await tester.pump();
    expect(copied, [_answer]);
    expect(find.text('Copiado'), findsOneWidget);
    await tester.pump(CopyButton.copiedFor);
  });

  testWidgets('R6, R8 · the answer is an AppMarkdown that collapses', (
    tester,
  ) async {
    await _pump(tester, [AssistantTextItem(_answer)]);
    final md = tester.widget<AppMarkdown>(find.byType(AppMarkdown));
    expect(md.collapseLongCode, isTrue);
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('live text has no bar and no Copiar mensagem', (tester) async {
    await _pump(tester, [AssistantTextItem('```sql\nSELECT', live: true)]);
    expect(find.byType(CodeBlock), findsNothing);
    expect(find.byType(AppMarkdown), findsNothing);
    expect(copyMessage, findsNothing);
  });

  testWidgets('R9 · Copiar comando on a Bash card copies the command', (
    tester,
  ) async {
    final copied = mockClipboard(tester);
    await _pump(tester, [_bash()]);
    expect(_opacity(tester, copyCommand), 0);
    await _hover(tester, find.byKey(const ValueKey('tool-b1')));
    expect(_opacity(tester, copyCommand), 1);
    await tester.tap(copyCommand);
    await tester.pump();
    expect(copied, [_command]);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.pump(CopyButton.copiedFor);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('R9 · focus on the card shows Copiar comando', (tester) async {
    await _pump(tester, [_bash()]);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tool card');
    expect(_opacity(tester, copyCommand), 1);
  });

  testWidgets('R9 · other tools have no Copiar comando', (tester) async {
    await _pump(tester, [
      ToolItem(id: 'r1', name: 'Read', input: {'file_path': '/w/a.md'})
        ..result = 'x',
    ]);
    expect(find.byType(CopyButton), findsNothing);
  });
}
