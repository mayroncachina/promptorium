import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/clipboard/clipboard_image.dart';
import 'package:promptorium/features/specs/spec_planner.dart';

import '../spec_planner_test.dart' show plannerOutput, resultLine;
import '../specs_screen_test.dart' show settleIo;
import 'print_harness.dart';

void main() {
  setUpPrintHarness();

  testWidgets('R1, R3, R5, R12: Ctrl V with an image attaches the print, '
      'reduced; "Planejar a spec" waits for Bug or Referência; the '
      'sensitive data notice shows', (tester) async {
    await pump(tester);
    reader.next = ClipboardImageFound(png, 'image/png');
    await ctrlV(tester);
    await settleIo(tester, until: () => key('print-card-0').present);
    expect(reader.reads, 1);
    expect(find.text('print-1.png'), findsOneWidget);
    expect(find.text('reduzido de 2880×1800'), findsOneWidget);
    expect(find.text('1568×980'), findsOneWidget);
    expect(find.text('✓ Print 1 anexado, 1568 × 980'), findsOneWidget);
    expect(attachments(), hasLength(1));
    expect(key('print-sensitive-warning'), findsOneWidget);
    expect(
      find.textContaining('Confira se ele não mostra senha, token, e-mail'),
      findsOneWidget,
    );

    // The idea may stay empty; the type is still missing.
    expect(enabled(tester, 'new-spec-plan'), isFalse);
    expect(
      find.text('Diga se cada print é um bug ou uma referência'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Remover print 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Ver print 1'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Tipo do print 1')), findsOneWidget);
    expect(find.bySemanticsLabel('print-1.png'), findsWidgets);

    await tester.tap(key('print-kind-0-bug'));
    await tester.pump();
    expect(enabled(tester, 'new-spec-plan'), isTrue);

    // "Ver" opens the print in a dialog.
    await tester.tap(key('print-view-0'));
    await settleIo(tester, until: () => key('print-dialog').present);
    expect(find.textContaining('reduzido de 2880 × 1800'), findsOneWidget);
    await tester.tap(key('print-dialog-close'));
    await settleIo(tester, until: () => !key('print-dialog').present);
  });

  testWidgets('R1: Ctrl V anywhere on the screen, outside a text field, '
      'attaches the print', (tester) async {
    await pump(tester);
    reader.next = ClipboardImageFound(png, 'image/png');
    await tester.tap(find.text('Conte a ideia'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settleIo(tester, until: () => key('print-card-0').present);
    expect(reader.reads, 1);
  });

  testWidgets('R1: Ctrl V with text pastes the text and attaches nothing', (
    tester,
  ) async {
    await pump(tester);
    clipboardText = 'Lembrete por WhatsApp';
    await ctrlV(tester);
    await settleIo(tester);
    final field = tester.widget<TextField>(key('new-spec-idea'));
    expect(field.controller!.text, 'Lembrete por WhatsApp');
    expect(key('print-card-0'), findsNothing);
    expect(reader.reads, 1);
  });

  testWidgets('R1: with an image and a name, the image wins and the text '
      'is pasted too', (tester) async {
    await pump(tester);
    clipboardText = 'captura.png';
    reader.next = ClipboardImageFound(png, 'image/png');
    await ctrlV(tester);
    await settleIo(tester, until: () => key('print-card-0').present);
    final field = tester.widget<TextField>(key('new-spec-idea'));
    expect(field.controller!.text, 'captura.png');
  });

  testWidgets('R2: Ctrl V without wl-paste/xclip shows the notice with the '
      'install command; with text in the clipboard it does not', (
    tester,
  ) async {
    await pump(tester);
    reader.next = const ClipboardToolMissing(
      tool: 'xclip',
      command: 'sudo apt install xclip',
    );
    await ctrlV(tester);
    await settleIo(tester, until: () => key('print-tool-missing').present);
    expect(find.text(ClipboardToolMissing.message), findsOneWidget);
    expect(find.text('sudo apt install xclip'), findsOneWidget);
    expect(find.textContaining('use "Anexar print…"'), findsOneWidget);
    await tester.tap(key('print-tool-missing-close'));
    await tester.pump();
    clipboardText = 'texto';
    await ctrlV(tester);
    await settleIo(tester);
    expect(key('print-tool-missing'), findsNothing);
  });

  testWidgets('R1, R3: dropping an image and "Anexar print…" attach prints; '
      'a file that is not an image is refused with the reason; the fifth '
      'print is refused', (tester) async {
    await pump(tester);
    final img = File('${tmp.path}/Captura de tela.png');
    final bad = File('${tmp.path}/gravacao.gif')
      ..writeAsBytesSync([1, 2, 3, 4]);
    await tester.runAsync(() => img.writeAsBytes(png));
    tester.widget<DropTarget>(key('idea-drop')).onDragDone!(
      DropDoneDetails(
        files: [DropItemFile(img.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await settleIo(tester, until: () => key('print-card-0').present);
    expect(find.text('print-1.png'), findsOneWidget);

    picked = img.path;
    await tester.tap(key('idea-attach-print'));
    await settleIo(tester, until: () => key('print-card-1').present);
    expect(find.text('print-2.png'), findsOneWidget);

    picked = bad.path;
    await tester.tap(key('idea-attach-print'));
    await settleIo(tester, until: () => key('print-error').present);
    expect(
      find.text(
        '"gravacao.gif" não é uma imagem. Aceitos: PNG, JPEG, WebP e GIF, '
        'até 20 MB.',
      ),
      findsOneWidget,
    );

    picked = img.path;
    for (var i = 2; i < 4; i++) {
      await tester.tap(key('idea-attach-print'));
      await settleIo(tester, until: () => key('print-card-$i').present);
    }
    await tester.tap(key('idea-attach-print'));
    await settleIo(
      tester,
      until: () => find.textContaining('No máximo 4 prints').present,
    );
    expect(key('print-card-4'), findsNothing);
  });

  testWidgets('R4: "Remover" deletes the print and renumbers the rest', (
    tester,
  ) async {
    await pump(tester);
    reader.next = ClipboardImageFound(png, 'image/png');
    await ctrlV(tester);
    await settleIo(tester, until: () => key('print-card-0').present);
    await ctrlV(tester);
    await settleIo(tester, until: () => key('print-card-1').present);
    expect(attachments(), hasLength(2));
    await tester.tap(key('print-remove-0'));
    await settleIo(tester, until: () => attachments().length == 1);
    expect(key('print-card-1'), findsNothing);
    expect(find.text('print-1.png'), findsOneWidget);
  });

  testWidgets('R4, R6, R8: planning keeps the prints in the draft, the '
      '"Referência visual" shows them with the description, reopening shows '
      'them again and discarding deletes the files', (tester) async {
    await pump(tester);
    reader.next = ClipboardImageFound(png, 'image/png');
    await ctrlV(tester);
    await settleIo(tester, until: () => key('print-card-0').present);
    await tester.tap(key('print-kind-0-referencia'));
    await tester.pump();
    await tester.tap(key('new-spec-plan'));
    await settleIo(tester, until: () => cli.processes.isNotEmpty);
    cli.last.emit(
      resultLine({
        ...plannerOutput(),
        'prints': [
          {
            'nome': 'print-1.png',
            'descricao': 'Três colunas iguais',
            'marcas': <String>[],
          },
        ],
      }),
    );
    await settleIo(tester, until: () => key('draft-print-0').present);
    await settleIo(tester, until: () => c.read(specPlannerProvider).isEmpty);
    expect(find.text('Referência visual'), findsOneWidget);
    expect(key('draft-print-reference-note'), findsOneWidget);
    final desc = tester.widget<TextField>(key('draft-print-description-0'));
    expect(desc.controller!.text, 'Três colunas iguais');
    expect(
      find.bySemanticsLabel('print-1.png: Três colunas iguais'),
      findsWidgets,
    );
    expect(attachments(), hasLength(1));

    // "Sair e guardar", then reopen: the prints are back.
    await tester.tap(key('new-spec-leave'));
    await settleIo(tester);
    c.read(newSpecFlowProvider.notifier).open();
    await settleIo(tester, until: () => key('new-spec-continue').present);
    await tester.tap(key('new-spec-continue'));
    await settleIo(tester, until: () => key('draft-print-0').present);

    await tester.tap(key('new-spec-leave'));
    await settleIo(tester);
    c.read(newSpecFlowProvider.notifier).open();
    await settleIo(tester, until: () => key('new-spec-discard').present);
    await tester.tap(key('new-spec-discard'));
    await settleIo(
      tester,
      until: () => key('new-spec-discard-confirm').present,
    );
    await tester.tap(key('new-spec-discard-confirm'));
    await settleIo(tester, until: () => attachments().isEmpty);
    expect(attachments(), isEmpty);
  });

  testWidgets('leaving the idea without planning deletes the prints', (
    tester,
  ) async {
    await pump(tester);
    reader.next = ClipboardImageFound(png, 'image/png');
    await ctrlV(tester);
    await settleIo(tester, until: () => key('print-card-0').present);
    c.read(newSpecFlowProvider.notifier).close();
    await settleIo(tester, until: () => attachments().isEmpty);
    expect(attachments(), isEmpty);
  });
}
