import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/features/ideas/widgets/idea_field.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import 'idea_import_test.dart' show FakePoppler;

/// The field on a 1440×900 page, with the file chooser answering [picks]
/// in order and PDFs read by [poppler].
class IdeaHarness {
  IdeaHarness(this.tmp);

  final Directory tmp;
  final controller = TextEditingController();
  final picks = <String?>[];
  FakePoppler poppler = FakePoppler(const []);
  final changes = <String>[];

  String file(String name, String content) {
    final f = File('${tmp.path}/$name')..writeAsStringSync(content);
    return f.path;
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ideaFilePickerProvider.overrideWithValue(
            () async => picks.isEmpty ? null : picks.removeAt(0),
          ),
          processRunnerProvider.overrideWithValue(
            (exe, args) => poppler(exe, args),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                child: IdeaField(
                  controller: controller,
                  fieldKey: const ValueKey('idea'),
                  hint: 'Avisar o paciente…',
                  onChanged: changes.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Picks [path] through the button and lets the (real) file IO finish.
  Future<void> import(WidgetTester tester, String path) async {
    picks.add(path);
    await tester.tap(find.byKey(const ValueKey('idea-import')));
    await settle(tester);
  }
}

/// File reads are real IO: give them time outside the fake clock.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

String detail(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('idea-source-detail'))).data!;

void main() {
  late Directory tmp;
  late IdeaHarness h;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('idea-field-');
    h = IdeaHarness(tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  final source = find.byKey(const ValueKey('idea-source'));
  final choice = find.byKey(const ValueKey('idea-choice'));
  final problem = find.byKey(const ValueKey('idea-problem'));

  testWidgets('footer has the button and hint; counter only with text', (
    tester,
  ) async {
    await h.pump(tester);
    expect(find.text('Importar arquivo'), findsOneWidget);
    expect(
      find.text('PDF, Markdown ou TXT · ou arraste para o campo'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('idea-counter')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('idea')), 'Oi');
    await tester.pump();
    expect(find.text('2 / 40.000'), findsOneWidget);
  });

  testWidgets('importing a TXT fills the field and shows the card', (
    tester,
  ) async {
    await h.pump(tester);
    await h.import(tester, h.file('ideia.txt', 'Lembrete por WhatsApp.\r\n'));
    expect(h.controller.text, 'Lembrete por WhatsApp.');
    expect(source, findsOneWidget);
    expect(find.text('ideia.txt'), findsOneWidget);
    expect(detail(tester), 'TXT · 22 caracteres carregados no campo');
    expect(choice, findsNothing);
    expect(h.changes.last, 'Lembrete por WhatsApp.');
    final field = tester.widget<TextField>(find.byKey(const ValueKey('idea')));
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('Ctrl+O in the field opens the chooser', (tester) async {
    await h.pump(tester);
    h.picks.add(h.file('a.md', '# Título'));
    await tester.tap(find.byKey(const ValueKey('idea')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(h.controller.text, '# Título');
    expect(detail(tester), 'Markdown · 8 caracteres carregados no campo');
  });

  testWidgets('a PDF shows its pages on the card', (tester) async {
    h.poppler = FakePoppler(['Um.', 'Dois.', 'Três.']);
    await h.pump(tester);
    await h.import(tester, h.file('b.pdf', 'x'));
    expect(h.controller.text, 'Um.\n\nDois.\n\nTrês.');
    expect(detail(tester), '3 páginas · 17 caracteres carregados no campo');
  });

  group('campo com texto (R6)', () {
    testWidgets('asks, and Adicionar ao fim is the default', (tester) async {
      await h.pump(tester);
      h.controller.text = 'Minha ideia.';
      await tester.pump();
      await h.import(tester, h.file('a.txt', 'Do arquivo.'));
      expect(choice, findsOneWidget);
      expect(h.controller.text, 'Minha ideia.');
      final append = tester.widget<RadioListTile<Object>>(
        find.byKey(const ValueKey('idea-choice-append')),
      );
      expect(append.value.toString(), contains('append'));
      expect(find.text('Adicionar'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('idea-choice-confirm')));
      await tester.pumpAndSettle();
      expect(h.controller.text, 'Minha ideia.\n\nDo arquivo.');
      expect(detail(tester), 'TXT · 11 caracteres adicionados ao fim');
      expect(choice, findsNothing);
    });

    testWidgets('Substituir replaces and Ctrl+Z undoes it', (tester) async {
      await h.pump(tester);
      await tester.enterText(find.byKey(const ValueKey('idea')), 'Antes.');
      await tester.pump();
      await h.import(tester, h.file('a.txt', 'Depois.'));
      await tester.tap(find.byKey(const ValueKey('idea-choice-replace')));
      await tester.pump();
      expect(find.text('Substituir'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('idea-choice-confirm')));
      await tester.pumpAndSettle();
      expect(h.controller.text, 'Depois.');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(h.controller.text, 'Antes.');
      expect(source, findsNothing);
    });

    testWidgets('the choice works from the keyboard', (tester) async {
      await h.pump(tester);
      h.controller.text = 'Antes.';
      await tester.pump();
      await h.import(tester, h.file('a.txt', 'Depois.'));
      // "Adicionar ao fim" has the focus; the arrow moves to "Substituir".
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('Substituir'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('idea-choice-confirm')),
          matching: find.text('Substituir'),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(choice, findsNothing);
      expect(h.controller.text, 'Antes.');
    });
  });

  group('Remover (R5)', () {
    testWidgets('takes out only the text from the file', (tester) async {
      await h.pump(tester);
      h.controller.text = 'Minha ideia.';
      await tester.pump();
      await h.import(tester, h.file('a.txt', 'Do arquivo.'));
      await tester.tap(find.byKey(const ValueKey('idea-choice-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('idea-source-remove')));
      await tester.pumpAndSettle();
      expect(h.controller.text, 'Minha ideia.');
      expect(source, findsNothing);
    });

    testWidgets('asks first when the text was edited', (tester) async {
      await h.pump(tester);
      await h.import(tester, h.file('a.txt', 'Do arquivo.'));
      await tester.enterText(
        find.byKey(const ValueKey('idea')),
        'Do arquivo, editado.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('idea-source-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('idea-remove-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('idea-remove-keep')));
      await tester.pumpAndSettle();
      expect(h.controller.text, 'Do arquivo, editado.');
      await tester.tap(find.byKey(const ValueKey('idea-source-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('idea-remove-confirm')));
      await tester.pumpAndSettle();
      expect(h.controller.text, '');
      expect(source, findsNothing);
    });

    testWidgets('Trocar swaps the file without asking', (tester) async {
      await h.pump(tester);
      h.controller.text = 'Minha ideia.';
      await tester.pump();
      await h.import(tester, h.file('a.txt', 'Primeiro.'));
      await tester.tap(find.byKey(const ValueKey('idea-choice-confirm')));
      await tester.pumpAndSettle();
      h.picks.add(h.file('b.txt', 'Segundo.'));
      await tester.tap(find.byKey(const ValueKey('idea-source-swap')));
      await settle(tester);
      // The field still has "Minha ideia.", so it asks again.
      await tester.tap(find.byKey(const ValueKey('idea-choice-confirm')));
      await tester.pumpAndSettle();
      expect(h.controller.text, 'Minha ideia.\n\nSegundo.');
      expect(find.text('b.txt'), findsOneWidget);
    });
  });

  group('problemas (R7)', () {
    testWidgets('an error leaves the field and goes away on typing', (
      tester,
    ) async {
      await h.pump(tester);
      h.controller.text = 'Minha ideia.';
      await tester.pump();
      await h.import(tester, h.file('briefing.docx', 'x'));
      expect(problem, findsOneWidget);
      expect(find.text('Ainda não dá para importar .docx.'), findsOneWidget);
      expect(h.controller.text, 'Minha ideia.');
      expect(choice, findsNothing);
      await tester.enterText(find.byKey(const ValueKey('idea')), 'Outra.');
      await tester.pump();
      expect(problem, findsNothing);
    });

    testWidgets('a scanned PDF and a password show their messages', (
      tester,
    ) async {
      h.poppler = FakePoppler(['  ']);
      await h.pump(tester);
      await h.import(tester, h.file('s.pdf', 'x'));
      expect(find.text('Este PDF não tem texto para ler.'), findsOneWidget);
      h.poppler = FakePoppler(['x'], password: true);
      await h.import(tester, h.file('p.pdf', 'x'));
      expect(find.text('Este PDF não tem texto para ler.'), findsNothing);
      expect(find.text('O PDF tem senha.'), findsOneWidget);
      h.poppler = FakePoppler(['x'], missing: true);
      await h.import(tester, h.file('p.pdf', 'x'));
      expect(
        find.text('Para ler PDF, instale o pacote poppler-utils.'),
        findsOneWidget,
      );
      expect(find.text('sudo apt install poppler-utils'), findsOneWidget);
      expect(h.controller.text, '');
    });

    testWidgets('over 40.000 goes in cut, with "Ver o que ficou de fora"', (
      tester,
    ) async {
      final para = '${'a' * 9998}.';
      await h.pump(tester);
      await h.import(
        tester,
        h.file('longo.txt', List.filled(5, para).join('\n\n')),
      );
      expect(h.controller.text, List.filled(3, para).join('\n\n'));
      expect(
        find.text('O arquivo tem 50.003 caracteres; o campo aceita 40.000.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('idea-overflow')));
      await tester.pumpAndSettle();
      final shown = tester.widget<SelectableText>(
        find.byKey(const ValueKey('idea-overflow-text')),
      );
      expect(shown.data, List.filled(2, para).join('\n\n'));
    });
  });

  group('soltar (R2)', () {
    DropTarget target(WidgetTester tester) =>
        tester.widget(find.byKey(const ValueKey('idea-drop')));

    testWidgets('dragging shows the drop area and dropping imports', (
      tester,
    ) async {
      await h.pump(tester);
      target(tester).onDragEntered!(
        DropEventDetails(
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      expect(find.text('Solte para carregar o texto'), findsOneWidget);
      target(tester).onDragDone!(
        DropDoneDetails(
          files: [DropItemFile(h.file('a.txt', 'Solto.'))],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await settle(tester);
      expect(find.text('Solte para carregar o texto'), findsNothing);
      expect(h.controller.text, 'Solto.');
      expect(source, findsOneWidget);
    });

    testWidgets('more than one file imports the first and says so', (
      tester,
    ) async {
      await h.pump(tester);
      target(tester).onDragDone!(
        DropDoneDetails(
          files: [
            DropItemFile(h.file('a.txt', 'Primeiro.')),
            DropItemFile(h.file('b.txt', 'Segundo.')),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await settle(tester);
      expect(h.controller.text, 'Primeiro.');
      expect(find.byKey(const ValueKey('idea-notice')), findsOneWidget);
      expect(find.textContaining('Importamos só a.txt'), findsOneWidget);
    });
  });

  testWidgets('button, card and messages are labelled and announced (R9)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await h.pump(tester);
    expect(
      find.bySemanticsLabel(RegExp('^Importar arquivo PDF, Markdown ou TXT')),
      findsOneWidget,
    );
    await h.import(tester, h.file('a.docx', 'x'));
    expect(tester.getSemantics(problem), isSemantics(isLiveRegion: true));
    await h.import(tester, h.file('a.txt', 'Oi.'));
    expect(
      find.bySemanticsLabel(RegExp('^Arquivo importado: a.txt')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('Cancelar in the progress keeps the field as it was', (
    tester,
  ) async {
    h.poppler = _SlowPoppler(List.filled(8, 'Página.'));
    await h.pump(tester);
    h.controller.text = 'Antes.';
    await tester.pump();
    h.picks.add(h.file('grande.pdf', 'x'));
    await tester.tap(find.byKey(const ValueKey('idea-import')));
    await settle(tester);
    expect(find.byKey(const ValueKey('idea-progress')), findsOneWidget);
    expect(find.textContaining('página 2 de 8'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('idea-progress-cancel')));
    (h.poppler as _SlowPoppler).release();
    await settle(tester);
    expect(find.byKey(const ValueKey('idea-progress')), findsNothing);
    expect(h.controller.text, 'Antes.');
    expect(choice, findsNothing);
    expect(source, findsNothing);
  });
}

/// Hangs on page 3 until [release], so the progress card can be seen.
class _SlowPoppler extends FakePoppler {
  _SlowPoppler(super.pages);

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<ProcessResult> call(String exe, List<String> args) async {
    final f = args.indexOf('-f');
    if (f >= 0 && args[f + 1] == '3') await _gate.future;
    return super.call(exe, args);
  }
}
