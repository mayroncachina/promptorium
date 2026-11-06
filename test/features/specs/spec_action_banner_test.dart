import 'dart:io';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/readonly_run.dart'
    show PlannerException;
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_action.dart';
import 'package:promptorium/features/specs/widgets/spec_action_banner.dart';
import 'package:promptorium/features/specs/widgets/spec_header.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import 'spec_action_lock_test.dart'
    show FakeDesigner, desktop, editorOf, key, pumpSpecs, specPath, startDesign;
import 'spec_file_test.dart' show sample;
import 'specs_screen_test.dart' show focusedIn, settleIo, tabTo;

void main() {
  late Directory tmp;
  late FakeDesigner designer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-spec-banner-');
    Directory('${tmp.path}/specs').createSync();
    File(specPath(tmp)).writeAsStringSync(sample);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  FakeDesigner make(ref) => designer = FakeDesigner(ref);

  test('R3: the elapsed time reads "1 min 12 s"', () {
    expect(formatElapsed(const Duration(seconds: 72)), '1 min 12 s');
    expect(formatElapsed(const Duration(seconds: 41)), '0 min 41 s');
    expect(formatElapsed(Duration.zero), '0 min 0 s');
  });

  testWidgets('R3: the strip has the title, the reason, the elapsed time '
      'and "Cancelar geração" with Esc', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SpecActionBanner(
            title: 'Planejando SPEC-024…',
            startedAt: DateTime.now().subtract(const Duration(seconds: 72)),
            onCancel: () => cancelled++,
          ),
        ),
      ),
    );
    expect(find.text('Planejando SPEC-024…'), findsOneWidget);
    expect(find.text(SpecActionBanner.reason), findsOneWidget);
    expect(
      SpecActionBanner.reason,
      'A spec fica somente leitura até terminar, para que nada do que você '
      'escrever seja sobrescrito.',
    );
    expect(tester.widget<Text>(key('spec-action-elapsed')).data, '1 min 12 s');
    expect(find.text('Cancelar geração'), findsOneWidget);
    expect(
      find.descendant(
        of: key('spec-action-cancel'),
        matching: find.text('Esc'),
      ),
      findsOneWidget,
    );
    await tester.tap(key('spec-action-cancel'));
    expect(cancelled, 1);
    // Ticks every second.
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<Text>(key('spec-action-elapsed')).data,
      matches(RegExp(r'^1 min 1[2-4] s$')),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('R3, R6: "Planejar" shows the strip; a short action '
      '("Aprovar") only the button in progress and "Somente leitura enquanto '
      'aprova"', (tester) async {
    final c = await pumpSpecs(tester, tmp, designer: make);
    await startDesign(tester, () => designer);
    expect(key('spec-action-banner'), findsOneWidget);
    expect(find.text('Planejando SPEC-002…'), findsOneWidget);
    expect(find.text(SpecActionBanner.reason), findsOneWidget);
    expect(key('spec-action-elapsed'), findsOneWidget);
    expect(key('spec-action-cancel'), findsOneWidget);
    designer.next.complete(sample);
    await settleIo(
      tester,
      until: () => key('spec-action-banner').evaluate().isEmpty,
    );
    expect(key('spec-action-banner'), findsNothing);

    // A short action, as "Aprovar" holds it while the file is written.
    final ws = c.read(activeWorkspaceProvider)!;
    final spec = (await tester.runAsync(
      () => c.read(specsRepoProvider).watchByWorkspace(ws.id).first,
    ))!.single;
    final notifier = c.read(specActionProvider.notifier);
    final a = notifier.start(
      SpecActionKind.approve,
      specId: spec.id,
      specCode: spec.code,
    )!;
    await tester.pump();
    expect(key('spec-action-banner'), findsNothing);
    expect(
      tester.widget<Text>(key('spec-action-lock')).data,
      'Somente leitura enquanto aprova',
    );
    expect(
      find.descendant(
        of: key('spec-approve'),
        matching: find.text('Aprovando…'),
      ),
      findsOneWidget,
    );
    expect(editorOf(tester).readOnly, true);
    notifier.finish(a);
    await tester.pump();
    expect(editorOf(tester).readOnly, isNot(true));
    expect(find.text('Salvo'), findsOneWidget);
  }, variant: desktop);

  testWidgets('R8: a failure shows the alert with the cause, releases the '
      'spec without changing the text; "Tentar de novo" runs it again and '
      '"Fechar aviso" closes it', (tester) async {
    await pumpSpecs(tester, tmp, designer: make);
    final semantics = tester.ensureSemantics();
    designer.error = const PlannerException(
      'O Claude Code encerrou sem responder (código de saída 1)\ndetalhes',
    );
    await startDesign(tester, () => designer);
    await settleIo(
      tester,
      until: () => key('spec-action-error').evaluate().isNotEmpty,
    );
    expect(find.text('Não foi possível planejar.'), findsOneWidget);
    expect(
      tester.widget<Text>(key('spec-action-error-cause')).data,
      'O Claude Code encerrou sem responder (código de saída 1). A spec não '
      'foi alterada e está liberada para edição.',
    );
    final alert = tester
        .getSemantics(find.bySemanticsLabel(RegExp('^Não foi possível')))
        .getSemanticsData();
    expect(alert.role, SemanticsRole.alert);
    expect(editorOf(tester).readOnly, isNot(true));
    expect(editorOf(tester).controller!.text, sample);
    expect(File(specPath(tmp)).readAsStringSync(), sample);
    expect(key('spec-action-banner'), findsNothing);

    // "Tentar de novo": the same action, with the current text.
    designer.error = null;
    editorOf(tester).controller!.text = '$sample\nmais\n';
    await tester.pump();
    await tester.tap(key('spec-action-retry'));
    await settleIo(tester, until: () => designer.calls.length == 2);
    expect(designer.calls.length, 2);
    expect(designer.calls.last.text, '$sample\nmais\n');
    expect(key('spec-action-error'), findsNothing);
    expect(key('spec-action-banner'), findsOneWidget);
    designer.next.complete(sample);
    await settleIo(tester, until: () => editorOf(tester).readOnly != true);

    designer
      ..error = const PlannerException('Falhou.')
      ..next = designer.next;
    await startDesign(tester, () => designer);
    await settleIo(
      tester,
      until: () => key('spec-action-error').evaluate().isNotEmpty,
    );
    expect(find.bySemanticsLabel('Fechar aviso'), findsOneWidget);
    await tester.tap(key('spec-action-error-close'));
    await tester.pump();
    expect(key('spec-action-error'), findsNothing);
    semantics.dispose();
  }, variant: desktop);

  testWidgets('R11: with reduced motion the progress is a still icon; the '
      'strip is a status region; from the keyboard the focus goes to '
      '"Cancelar geração" and Tab follows the visual order', (tester) async {
    await pumpSpecs(tester, tmp, designer: make, reduceMotion: true);
    final semantics = tester.ensureSemantics();
    expect(await tabTo(tester, key('spec-design')), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleIo(tester, until: () => designer.calls.isNotEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    expect(key('spec-action-banner'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(key('spec-action-spinner-still'), findsNWidgets(2));

    final status = tester
        .getSemantics(find.bySemanticsLabel(RegExp('^Planejando SPEC')))
        .getSemanticsData();
    expect(status.role, SemanticsRole.status);

    expect(focusedIn(key('spec-action-cancel')), isTrue);
    // Shift+Tab goes back to the header above; Tab from there reaches the
    // strip again, then the editor below.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(focusedIn(key('spec-action-cancel')), isFalse);
    expect(focusedIn(find.byType(SpecHeader)), isTrue);
    expect(await tabTo(tester, key('spec-action-cancel')), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    // Next: below the strip (the warnings strip, then the editor).
    final banner = tester.getRect(key('spec-action-banner'));
    expect(
      FocusManager.instance.primaryFocus!.rect.top,
      greaterThanOrEqualTo(banner.bottom),
    );

    // Esc cancels (from the editor, too).
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleIo(tester, until: () => editorOf(tester).readOnly != true);
    expect(key('spec-action-banner'), findsNothing);
    expect(editorOf(tester).controller!.text, sample);
    semantics.dispose();
  }, variant: desktop);
}
