import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/text/line_diff.dart';
import 'package:promptorium/features/sessions/widgets/tool_expanded_view.dart';
import 'package:promptorium/ui/widgets/diff_view.dart';

import 'sessions_screen_test.dart' show pumpScreen, root;

final _view = find.byKey(const ValueKey('tool-expanded'));

Finder _toggle(String id) => find.byKey(ValueKey('tool-toggle-$id'));

Finder _inView(Finder f) => find.descendant(of: _view, matching: f);

void main() {
  group('sideBySide', () {
    test('pairs removed and added runs, pads the shorter side and numbers '
        'the old side', () {
      final rows = <DiffRow>[
        (op: DiffOp.same, text: 'a', line: 10),
        (op: DiffOp.del, text: 'b', line: 11),
        (op: DiffOp.add, text: 'B', line: 11),
        (op: DiffOp.add, text: 'B2', line: 12),
        (op: DiffOp.same, text: 'c', line: 13),
        (op: DiffOp.del, text: 'd', line: 13),
        (op: DiffOp.same, text: 'e', line: 14),
      ];
      final p = sideBySide(rows);
      expect(p, hasLength(6));
      expect([p[0].leftNo, p[0].rightNo], [10, 10]);
      expect([p[1].left!.text, p[1].right!.text], ['b', 'B']);
      expect([p[1].leftNo, p[1].rightNo], [11, 11]);
      expect(p[2].left, isNull);
      expect(p[2].right!.text, 'B2');
      // One line more on the right: the old "c" is line 12.
      expect([p[3].leftNo, p[3].rightNo], [12, 13]);
      expect(p[4].right, isNull);
      expect(p[4].leftNo, 13);
      expect([p[5].leftNo, p[5].rightNo], [14, 14]);
      expect(diffHunks(rows), 2);
      expect(firstChangedLine(rows), 11);
    });

    test('firstChangedLine of a removal counts the lines added before', () {
      expect(
        firstChangedLine([(op: DiffOp.add, text: 'x', line: null)]),
        isNull,
      );
      expect(
        firstChangedLine([
          (op: DiffOp.same, text: 'a', line: 4),
          (op: DiffOp.del, text: 'b', line: 5),
        ]),
        5,
      );
      expect(lineOf('a\nb\n  return x;\n', '\n  return x;'), 3);
      expect(lineOf('a', 'zzz'), isNull);
    });
  });

  testWidgets('R6 · an Edit opens side by side with the lines aligned and '
      'the gap hatched; Unificado switches', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester);
    await tester.tap(_toggle('t_edit'));
    await tester.pump();
    expect(find.byType(SideBySideDiffView), findsOneWidget);
    expect(_inView(find.text('ANTES')), findsOneWidget);
    expect(_inView(find.text('DEPOIS')), findsOneWidget);
    expect(find.text('1 trecho'), findsOneWidget);
    // x → y on the same row; z alone on the right.
    final x = tester.getRect(find.bySemanticsLabel('antes, linha removida: x'));
    final y = tester.getRect(
      find.bySemanticsLabel('depois, linha adicionada: y'),
    );
    final z = tester.getRect(
      find.bySemanticsLabel('depois, linha adicionada: z'),
    );
    expect(x.top, y.top);
    expect(x.right, lessThan(y.left));
    expect(z.top, greaterThan(y.top));
    expect(
      find.descendant(
        of: find.byType(SideBySideDiffView),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );

    await tester.tap(find.byKey(const ValueKey('tool-expanded-tab-unified')));
    await tester.pump();
    expect(find.byType(SideBySideDiffView), findsNothing);
    expect(find.byKey(const ValueKey('tool-expanded-diff-t_edit')), findsOne);
    handle.dispose();
  });

  testWidgets('R5 · Ctrl+F also finds in the diff', (tester) async {
    await pumpScreen(tester);
    await tester.tap(_toggle('t_edit'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('tool-search-field')),
      'Z',
    );
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('tool-search-count'))).data,
      '1 de 1',
    );
    expect(
      tester.widget<SideBySideDiffView>(find.byType(SideBySideDiffView)).marks,
      hasLength(1),
    );
  });

  testWidgets('R6 · Abrir no Código opens the file at the changed line and '
      'closes the view', (tester) async {
    final calls = <(String, String, int)>[];
    await pumpScreen(
      tester,
      overrides: [
        openInCodeProvider.overrideWithValue((worktree, path, line) async {
          calls.add((worktree, path, line));
          return null;
        }),
        toolFileTextProvider.overrideWith(
          (ref, path) async => 'import a;\ny\nz\n',
        ),
      ],
    );
    await tester.tap(_toggle('t_edit'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tool-expanded-open-code')));
    await tester.pump();
    await tester.pump();
    expect(calls, [(root, '$root/lib/a.dart', 2)]);
    expect(_view, findsNothing);

    // A Read opens at its first line; a Bash has no button.
    await tester.tap(_toggle('t_read'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tool-expanded-open-code')));
    await tester.pump();
    await tester.pump();
    expect(calls.last, (root, '$root/lib/a.dart', 1));
    await tester.tap(_toggle('t_bash'));
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-expanded-open-code')), findsNothing);
  });

  testWidgets('R10 · at 1100×700 the buttons are icons with tooltips, the '
      'Edit opens unified and nothing overflows', (tester) async {
    await pumpScreen(tester, size: const Size(1100, 700));
    await tester.tap(_toggle('t_bash'));
    await tester.pump();
    expect(_inView(find.text('Anterior')), findsNothing);
    expect(_inView(find.text('Copiar')), findsNothing);
    expect(find.byTooltip('Copiar'), findsOneWidget);
    expect(find.byTooltip('Anterior (↑ ou K)'), findsOneWidget);
    expect(find.byTooltip('Próxima (↓ ou J)'), findsOneWidget);
    expect(_inView(find.text('Fechar')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byType(SideBySideDiffView), findsNothing);
    expect(find.byKey(const ValueKey('tool-expanded-diff-t_edit')), findsOne);
    expect(find.byTooltip('Abrir no Código'), findsOneWidget);
    // Lado a lado is still one click away.
    await tester.tap(find.byKey(const ValueKey('tool-expanded-tab-split')));
    await tester.pump();
    expect(find.byType(SideBySideDiffView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
