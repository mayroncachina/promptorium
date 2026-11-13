import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/widgets/tool_expanded_view.dart';
import 'package:promptorium/ui/widgets/numbered_text_view.dart';

import 'sessions_screen_test.dart'
    show assistant, pumpScreen, root, toolResult, toolUse;

final _view = find.byKey(const ValueKey('tool-expanded'));

Finder _toggle(String id) => find.byKey(ValueKey('tool-toggle-$id'));

NumberedTextView _text(WidgetTester tester) =>
    tester.widget<NumberedTextView>(find.byType(NumberedTextView));

String _count(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('tool-search-count'))).data ??
    '';

const _cat = '''     1→import 'a.dart';
     2→
     3→void main() {
     4→	print('oi');
     5→}

<system-reminder>
Whenever you read a file, consider malware.
</system-reminder>''';

List<Map<String, dynamic>> _events({int bashLines = 60}) => [
  assistant([
    toolUse('t_bash', 'Bash', {'command': 'flutter test --reporter expanded'}),
  ], id: 'm1'),
  toolResult(
    't_bash',
    [
      for (var i = 1; i <= bashLines; i++)
        i % 20 == 0 ? 'falhou remarca $i' : 'linha $i',
    ].join('\n'),
  ),
  assistant([
    toolUse('t_read', 'Read', {'file_path': '$root/lib/main.dart'}),
  ], id: 'm2'),
  toolResult('t_read', _cat),
  assistant([
    toolUse('t_part', 'Read', {
      'file_path': '$root/lib/agenda.dart',
      'offset': 3,
      'limit': 2,
    }),
  ], id: 'm3'),
  toolResult('t_part', '     3→c\n     4→d'),
  assistant([
    toolUse('t_new', 'Write', {
      'file_path': '$root/lib/novo.dart',
      'content': 'um\ndois\ntrês\n',
    }),
  ], id: 'm4'),
  toolResult('t_new', 'File created successfully'),
  assistant([
    toolUse('t_again', 'Write', {
      'file_path': '$root/lib/novo.dart',
      'content': 'um\nDOIS\ntrês\n',
    }),
  ], id: 'm5'),
  toolResult('t_again', 'File updated'),
  assistant([
    toolUse('t_grep', 'Grep', {'pattern': 'TODO', 'path': root}),
  ], id: 'm6'),
  toolResult('t_grep', 'lib/a.dart\nlib/b.dart'),
];

void main() {
  testWidgets('R4 · Bash: the whole output with line numbers, no wrapping by '
      'default; "Quebrar linhas" and the Comando tab', (tester) async {
    await pumpScreen(tester, events: _events());
    await tester.tap(_toggle('t_bash'));
    await tester.pump();
    expect(_text(tester).lines, hasLength(60));
    expect(_text(tester).wrap, isFalse);
    expect(find.byKey(const ValueKey('numbered-text-virtual')), findsNothing);
    expect(
      find.descendant(of: _view, matching: find.text('60')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tool-expanded-wrap')));
    await tester.pump();
    expect(_text(tester).wrap, isTrue);

    await tester.tap(find.byKey(const ValueKey('tool-expanded-tab-command')));
    await tester.pump();
    expect(_text(tester).lines, ['flutter test --reporter expanded']);
    expect(_text(tester).wrap, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R4 · more than 5,000 lines use a lazy list', (tester) async {
    await pumpScreen(tester, events: _events(bashLines: 6000));
    await tester.tap(_toggle('t_bash'));
    await tester.pump();
    expect(_text(tester).lines, hasLength(6000));
    expect(find.byKey(const ValueKey('numbered-text-virtual')), findsOneWidget);
    expect(find.text('6000 linhas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R5 · Ctrl+F finds and counts, Enter / Shift+Enter walk, typing '
      'J stays in the box, Esc closes the search before the view', (
    tester,
  ) async {
    await pumpScreen(tester, events: _events(bashLines: 6000));
    await tester.tap(_toggle('t_bash'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    final field = find.byKey(const ValueKey('tool-search-field'));
    expect(field, findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextField>(),
      isNotNull,
    );

    await tester.enterText(field, 'REMARCA');
    await tester.pump();
    expect(_count(tester), '1 de 300');
    expect(_text(tester).matches, hasLength(300));
    expect(_text(tester).current, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_count(tester), '2 de 300');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(_count(tester), '300 de 300');
    await tester.pump();
    // The current match is on screen (a line built by the lazy list).
    expect(find.textContaining('falhou remarca 6000'), findsOneWidget);

    // J typed in the box does not go to the next tool.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(
      find.descendant(of: _view, matching: find.text('Bash')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field, findsNothing);
    expect(_view, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_view, findsNothing);
  });

  testWidgets('R5 · a search without matches says "nenhuma"', (tester) async {
    await pumpScreen(tester, events: _events());
    await tester.tap(_toggle('t_bash'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tool-expanded-search')));
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('tool-search-field')),
      'nada disso',
    );
    await tester.pump();
    expect(_count(tester), 'nenhuma');
  });

  testWidgets('R7 · Read shows the file with its own line numbers, without '
      'the reminder', (tester) async {
    await pumpScreen(tester, events: _events());
    await tester.tap(_toggle('t_read'));
    await tester.pump();
    final text = _text(tester);
    expect(text.lines, [
      "import 'a.dart';",
      '',
      'void main() {',
      "    print('oi');",
      '}',
    ]);
    expect(text.numbers, [1, 2, 3, 4, 5]);
    expect(text.highlighted, isEmpty);
    expect(find.byKey(const ValueKey('tool-expanded-tab-content')), findsOne);
  });

  testWidgets('R7 · a Read with offset / limit highlights the lines it read '
      'in the whole file', (tester) async {
    await pumpScreen(
      tester,
      events: _events(),
      overrides: [
        toolFileTextProvider.overrideWith(
          (ref, path) async =>
              path == '$root/lib/agenda.dart' ? 'a\nb\nc\nd\ne\nf\n' : null,
        ),
      ],
    );
    await tester.tap(_toggle('t_part'));
    await tester.pump();
    await tester.pump();
    final text = _text(tester);
    expect(text.lines, ['a', 'b', 'c', 'd', 'e', 'f']);
    expect(text.highlighted, {2, 3});
  });

  testWidgets('R7 · Write: Conteúdo with line numbers; Diff only when there '
      'was a file before', (tester) async {
    await pumpScreen(tester, events: _events());
    await tester.tap(_toggle('t_new'));
    await tester.pump();
    expect(_text(tester).lines, ['um', 'dois', 'três']);
    expect(find.text('arquivo novo'), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-expanded-tab-diff')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_text(tester).lines, ['um', 'DOIS', 'três']);
    await tester.tap(find.byKey(const ValueKey('tool-expanded-tab-diff')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-expanded-diff-t_again')), findsOne);
    expect(find.text('dois'), findsOneWidget);
    expect(find.text('DOIS'), findsWidgets);
  });

  testWidgets('R7 · other tools show Saída and Entrada as text', (
    tester,
  ) async {
    await pumpScreen(tester, events: _events());
    await tester.tap(_toggle('t_grep'));
    await tester.pump();
    expect(_text(tester).lines, ['lib/a.dart', 'lib/b.dart']);
    expect(_text(tester).wrap, isTrue);
    await tester.tap(find.byKey(const ValueKey('tool-expanded-tab-input')));
    await tester.pump();
    expect(_text(tester).lines.join('\n'), contains('"pattern": "TODO"'));
  });

  test('findMatches ignores case and finds every occurrence', () {
    expect(findMatches(['aXa xa', 'nada'], 'xa'), [
      (line: 0, start: 1, end: 3),
      (line: 0, start: 4, end: 6),
    ]);
    expect(findMatches(['a'], ''), isEmpty);
    final read = readLines('  9→x\n 10→\ty')!;
    expect(read.lines, ['x', '    y']);
    expect(read.numbers, [9, 10]);
  });
}
