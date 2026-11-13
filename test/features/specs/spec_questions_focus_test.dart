import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/spec_answers.dart';
import 'package:promptorium/features/specs/spec_file.dart';
import 'package:promptorium/features/specs/widgets/spec_list.dart';
import 'package:promptorium/features/specs/widgets/spec_questions_focus.dart';
import 'package:promptorium/ui/theme/motion.dart';

import 'spec_action_lock_test.dart'
    show FakeDesigner, editorOf, key, pumpSpecs, specPath;
import 'spec_questions_panel_test.dart'
    show FakeApplier, FakeQuestionOptions, questionsSpec, releaseEditor;
import 'specs_screen_test.dart' show settleIo;

/// SPEC-059: "Responder perguntas" in the center of the screen.
void main() {
  late Directory tmp;
  late FakeQuestionOptions options;
  late ProviderContainer c;
  late FakeApplier applier;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-questions-focus-');
    Directory('${tmp.path}/specs').createSync();
    File(specPath(tmp)).writeAsStringSync(questionsSpec);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  String disk() => File(specPath(tmp)).readAsStringSync();

  final panel = key('spec-questions-panel');

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    bool reduceMotion = false,
  }) async {
    c = await pumpSpecs(
      tester,
      tmp,
      size: size,
      reduceMotion: reduceMotion,
      designer: FakeDesigner.new,
      overrides: [
        specQuestionOptionsProvider.overrideWith(
          (ref) => options = FakeQuestionOptions(ref),
        ),
        specAnswerApplierProvider.overrideWith(
          (ref) => applier = FakeApplier(ref),
        ),
      ],
    );
    c.read(specQuestionOptionsProvider);
    c.read(specAnswerApplierProvider);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(key('spec-more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(key('spec-answer-questions'));
    await settleIo(tester, until: () => panel.evaluate().isNotEmpty);
    await tester.pump();
  }

  /// The alternatives of [id] arrive (long ones: the options scroll).
  Future<void> alternatives(WidgetTester tester, String id) async {
    options.of(id).complete([
      QuestionAlternative(
        title: 'Menu da linha',
        consequence: 'Um clique por máquina. ' * 6,
      ),
      QuestionAlternative(
        title: 'Tela do grupo',
        consequence: 'Mais uma tela para manter. ' * 6,
      ),
    ]);
    await tester.pump();
    await tester.pump();
  }

  String subtitle(WidgetTester tester) =>
      tester.widget<Text>(key('spec-questions-subtitle')).data!;

  AnswerOption? selected(WidgetTester tester) => tester
      .widget<RadioGroup<AnswerOption>>(find.byType(RadioGroup<AnswerOption>))
      .groupValue;

  Map<String, Answer> answers() => c.read(specAnswersProvider)[1] ?? {};

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey k, {
    LogicalKeyboardKey? hold,
  }) async {
    if (hold != null) await tester.sendKeyDownEvent(hold);
    await tester.sendKeyEvent(k);
    if (hold != null) await tester.sendKeyUpEvent(hold);
    await tester.pump();
    await tester.pump();
  }

  test('R2, R9: 720 px, or the width minus 32 px on each side', () {
    expect(questionsColumnWidth(1360), 720);
    expect(questionsColumnWidth(784), 720);
    expect(questionsColumnWidth(700), 636);
    expect(questionsColumnWidth(40), 0);
    expect(questionsColumnWidth(1360, max: 1100), 1100);
  });

  testWidgets('R1, R2, R4: the session covers the list and the editor, '
      'the column has 720 px in the center and the footer stays fixed while '
      'the options scroll', (tester) async {
    await pump(tester);
    await open(tester);
    final area = tester.getRect(panel);
    // Over the list of specs and the editor.
    expect(
      area.left,
      lessThanOrEqualTo(tester.getRect(find.byType(SpecList)).left),
    );
    expect(area.width, 1440);
    expect(find.text('Responder perguntas'), findsWidgets);
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · pergunta 1 de 3');
    expect(find.text('salvo automaticamente'), findsOneWidget);
    expect(
      find.descendant(
        of: key('spec-questions-close'),
        matching: find.text('Ctrl+Esc'),
      ),
      findsOneWidget,
    );

    final column = tester.getRect(key('spec-questions-column'));
    expect(column.width, 720);
    expect(column.center.dx, closeTo(area.center.dx, 0.5));
    final footer = tester.getRect(key('spec-questions-footer'));
    expect(footer.width, 720);
    expect(footer.left, column.left);
    expect(find.text('Anterior'), findsOneWidget);
    expect(find.text('Deixar para depois'), findsOneWidget);
    expect(find.text('Próxima'), findsOneWidget);
    expect(
      find.descendant(
        of: key('spec-questions-next'),
        matching: find.text('Enter'),
      ),
      findsOneWidget,
    );
    // R2: the question in 22 px, weight 600, its number in amber.
    final q = tester.widget<Text>(key('spec-question-text'));
    expect(q.style!.fontSize, 22);
    expect(q.style!.fontWeight, FontWeight.w600);
    expect(
      find.text(
        'A primeira opção é a sugestão escrita na spec; as outras foram '
        'propostas pelo Claude.',
      ),
      findsOneWidget,
    );

    // R3: wide cards with the key of each option.
    await alternatives(tester, 'P1');
    for (final (i, o) in [
      'suggestion',
      'alternative1',
      'alternative2',
      'other',
    ].indexed) {
      final card = key('spec-question-option-$o');
      expect(tester.getRect(card).width, 720);
      expect(
        find.descendant(of: card, matching: find.text('${i + 1}')),
        findsOneWidget,
      );
    }
    expect(find.text('Sugestão da spec'), findsOneWidget);

    // The footer stays at the base of the area while the options scroll.
    tester.view.physicalSize = const Size(1440, 640);
    await tester.pump();
    final scroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: key('spec-questions-scroll'),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(scroll.maxScrollExtent, greaterThan(0));
    final nextBefore = tester.getRect(key('spec-questions-next'));
    expect(nextBefore.bottom, lessThanOrEqualTo(640));
    await tester.drag(key('spec-questions-scroll'), const Offset(0, -300));
    await tester.pump();
    expect(scroll.pixels, greaterThan(0));
    expect(tester.getRect(key('spec-questions-next')), nextBefore);

    // The last question: the primary is "Revisar respostas".
    await tester.ensureVisible(key('spec-questions-trail-P3'));
    await tester.pump();
    await tester.tap(key('spec-questions-trail-P3'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Revisar respostas'), findsOneWidget);
    expect(find.text('Próxima'), findsNothing);
    expect(disk(), questionsSpec);
  });

  testWidgets('R5: 1–4 choose, Enter goes to the next one, ←/→ and '
      'Alt+←/→ change the question, Esc closes keeping the answers', (
    tester,
  ) async {
    await pump(tester);
    await open(tester);
    await alternatives(tester, 'P1');
    // The focus starts on the chosen option.
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'spec-question-suggestion',
    );
    await press(tester, LogicalKeyboardKey.digit3);
    expect(selected(tester), AnswerOption.alternative2);
    expect(answers()['P1']!.text, 'Tela do grupo');
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'spec-question-alternative2',
    );
    await press(tester, LogicalKeyboardKey.digit2);
    expect(selected(tester), AnswerOption.alternative1);
    await press(tester, LogicalKeyboardKey.digit1);
    expect(selected(tester), AnswerOption.suggestion);
    // Past the options: nothing.
    await press(tester, LogicalKeyboardKey.digit7);
    expect(selected(tester), AnswerOption.suggestion);
    // "Outra resposta" takes the focus to its field (R6), where the digits
    // are text.
    await press(tester, LogicalKeyboardKey.digit4);
    expect(selected(tester), AnswerOption.other);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'spec-question-other-text',
    );
    await press(tester, LogicalKeyboardKey.digit2);
    expect(selected(tester), AnswerOption.other);
    // Another option chosen from the field takes the focus back (the row
    // of "Outras sugestões" pushes the options down: bring it into view).
    await tester.ensureVisible(key('spec-question-option-alternative1'));
    await tester.pump();
    await tester.tap(key('spec-question-option-alternative1'));
    await tester.pump();
    await tester.pump();
    expect(selected(tester), AnswerOption.alternative1);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'spec-question-alternative1',
    );

    await press(tester, LogicalKeyboardKey.enter);
    expect(subtitle(tester), endsWith('pergunta 2 de 3'));
    expect(answers()['P1']!.text, 'Menu da linha');

    // → / ← on a question with nothing focused but the column.
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(subtitle(tester), endsWith('pergunta 3 de 3'));
    // The radio group does not take ←/→ from a focused option.
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'spec-question-suggestion',
    );
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(subtitle(tester), endsWith('pergunta 2 de 3'));
    await press(
      tester,
      LogicalKeyboardKey.arrowRight,
      hold: LogicalKeyboardKey.altLeft,
    );
    expect(subtitle(tester), endsWith('pergunta 3 de 3'));
    await press(
      tester,
      LogicalKeyboardKey.arrowLeft,
      hold: LogicalKeyboardKey.altLeft,
    );
    expect(subtitle(tester), endsWith('pergunta 2 de 3'));

    // In the text field the digits are text, Alt+→ still changes.
    await tester.enterText(key('spec-question-other-text'), 'Sim');
    await tester.pump();
    await press(tester, LogicalKeyboardKey.digit1);
    expect(selected(tester), AnswerOption.other);
    await press(
      tester,
      LogicalKeyboardKey.arrowRight,
      hold: LogicalKeyboardKey.altLeft,
    );
    expect(subtitle(tester), endsWith('pergunta 3 de 3'));

    await press(tester, LogicalKeyboardKey.escape);
    expect(panel, findsNothing);
    expect(answers()['P1']!.text, 'Menu da linha');
    expect(answers()['P2']!.text, 'Sim');
    expect(disk(), questionsSpec);
    expect(editorOf(tester).controller!.text, questionsSpec);
    await releaseEditor(tester);
  });

  testWidgets('R10: a labeled dialog that holds the focus; the options are '
      'a radio group', (tester) async {
    await pump(tester);
    final semantics = tester.ensureSemantics();
    await open(tester);
    expect(
      find.bySemanticsLabel('Responder perguntas da SPEC-002'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Responder perguntas da SPEC-002'),
      ),
      isSemantics(scopesRoute: true, namesRoute: true),
    );
    // Tab goes around inside the session, never to the editor behind it.
    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final f = FocusManager.instance.primaryFocus;
      final ctx = f?.context;
      expect(ctx, isNotNull);
      expect(
        ctx!.widget is SpecQuestionsFocus ||
            ctx.findAncestorWidgetOfExactType<SpecQuestionsFocus>() != null,
        isTrue,
        reason: 'Tab $i left the session: ${f?.debugLabel}',
      );
    }
    expect(find.byType(RadioGroup<AnswerOption>), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('R9: 1100×700 with the header and the footer fixed, nothing '
      'on top of each other', (tester) async {
    await pump(tester, size: const Size(1100, 700));
    await open(tester);
    await alternatives(tester, 'P1');
    final column = tester.getRect(key('spec-questions-column'));
    expect(column.width, 720);
    final scroll = tester.getRect(key('spec-questions-scroll'));
    final footer = tester.getRect(key('spec-questions-footer'));
    final header = tester.getRect(key('spec-questions-subtitle'));
    expect(header.bottom, lessThanOrEqualTo(scroll.top));
    expect(scroll.bottom, lessThanOrEqualTo(footer.top));
    expect(footer.bottom, lessThanOrEqualTo(700));
    for (final k in [
      'spec-questions-previous',
      'spec-questions-defer',
      'spec-questions-next',
    ]) {
      final r = tester.getRect(key(k));
      expect(r.top, greaterThanOrEqualTo(footer.top), reason: k);
      expect(r.bottom, lessThanOrEqualTo(footer.bottom), reason: k);
    }
    expect(
      tester.getRect(key('spec-questions-defer')).right,
      lessThanOrEqualTo(tester.getRect(key('spec-questions-next')).left),
    );
    expect(tester.takeException(), isNull);
  });

  test('R7: the excerpt of a question, with its lines and the ones around '
      'it inside "Perguntas em aberto"', () {
    final doc = SpecDocument.parse(questionsSpec);
    final qs = doc.openQuestions;
    final p1 = doc.questionExcerpt(qs[0])!;
    expect((p1.first, p1.last, p1.from), (18, 19, 18));
    expect(p1.lines, [
      '- P1 · Como adicionar máquinas a um grupo?',
      '  - Sugestão: pela seleção na tabela.',
      '- P2 · O filtro deve ser lembrado?',
      '- P3 · Excluir um grupo apaga as máquinas?',
    ]);
    final p2 = doc.questionExcerpt(qs[1])!;
    expect((p2.first, p2.last, p2.from, p2.lines.length), (20, 20, 18, 5));
    expect(p2.marked(20), isTrue);
    expect(p2.marked(19), isFalse);
    final p3 = doc.questionExcerpt(qs[2])!;
    expect((p3.first, p3.last, p3.from, p3.lines.length), (21, 22, 19, 4));
  });

  testWidgets('R6: "Outra resposta" takes the focus to its field, which '
      'grows up to 6 lines; Enter breaks the line and Ctrl+Enter goes on', (
    tester,
  ) async {
    await pump(tester);
    await open(tester);
    await tester.tap(key('spec-question-radio-other'));
    await tester.pump();
    await tester.pump();
    expect(selected(tester), AnswerOption.other);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'spec-question-other-text',
    );
    final field = tester.widget<TextField>(key('spec-question-other-text'));
    expect(field.maxLines, 6);
    expect(field.keyboardType, TextInputType.multiline);
    double height() => tester.getSize(key('spec-question-other-text')).height;
    await tester.enterText(key('spec-question-other-text'), 'a\nb\nc\nd\ne\nf');
    await tester.pump();
    final six = height();
    await tester.enterText(
      key('spec-question-other-text'),
      List.generate(12, (i) => 'linha $i').join('\n'),
    );
    await tester.pump();
    expect(height(), six);
    await tester.enterText(key('spec-question-other-text'), 'a\nb');
    await tester.pump();
    expect(height(), lessThan(six));

    // Enter stays in the field.
    await press(tester, LogicalKeyboardKey.enter);
    expect(subtitle(tester), endsWith('pergunta 1 de 3'));
    await press(
      tester,
      LogicalKeyboardKey.enter,
      hold: LogicalKeyboardKey.controlLeft,
    );
    expect(subtitle(tester), endsWith('pergunta 2 de 3'));
    expect(
      answers()['P1'],
      const Answer(option: AnswerOption.other, text: 'a\nb'),
    );
    expect(disk(), questionsSpec);
  });

  testWidgets('R7: "Ver na spec" shows the excerpt with the lines of the '
      'question marked; the choice holds for the next questions until the '
      'session closes', (tester) async {
    await pump(tester);
    await open(tester);
    expect(key('spec-question-excerpt'), findsNothing);
    await tester.tap(key('spec-question-excerpt-toggle'));
    await tester.pump();
    expect(key('spec-question-excerpt'), findsOneWidget);
    expect(find.text('Linhas 18–19 de Perguntas em aberto'), findsOneWidget);
    expect(find.text('Esconder trecho'), findsOneWidget);
    expect(key('spec-question-excerpt-mark-18'), findsOneWidget);
    expect(key('spec-question-excerpt-mark-19'), findsOneWidget);
    expect(key('spec-question-excerpt-line-20'), findsOneWidget);
    // Between the question and the options.
    final excerpt = tester.getRect(key('spec-question-excerpt'));
    expect(
      excerpt.top,
      greaterThan(tester.getRect(key('spec-question-text')).bottom),
    );
    expect(
      excerpt.bottom,
      lessThan(tester.getRect(key('spec-question-options')).top),
    );

    await tester.tap(key('spec-questions-next'));
    await tester.pump();
    await tester.pump();
    expect(subtitle(tester), endsWith('pergunta 2 de 3'));
    expect(find.text('Linha 20 de Perguntas em aberto'), findsOneWidget);
    expect(key('spec-question-excerpt-mark-20'), findsOneWidget);
    expect(key('spec-question-excerpt-line-18'), findsOneWidget);

    await tester.tap(key('spec-question-excerpt-toggle'));
    await tester.pump();
    expect(key('spec-question-excerpt'), findsNothing);
    expect(find.text('Ver na spec'), findsOneWidget);
    await tester.tap(key('spec-question-excerpt-toggle'));
    await tester.pump();

    // Closing ends it: the next session starts without the excerpt.
    await press(tester, LogicalKeyboardKey.escape);
    expect(panel, findsNothing);
    await open(tester);
    expect(key('spec-question-excerpt'), findsNothing);
    expect(find.text('Ver na spec'), findsOneWidget);
    expect(disk(), questionsSpec);
  });

  testWidgets('R8: the review and the diff are in the center too: the '
      'review in the 720 px column with Editar taking back to the question, '
      'the diff up to 1100 px', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.tap(key('spec-questions-next'));
    await tester.pump();
    await tester.pump();
    await tester.tap(key('spec-questions-defer'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Revisar respostas'), findsOneWidget);
    await tester.tap(key('spec-questions-next'));
    await tester.pump();
    await tester.pump();
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · revisão');
    final area = tester.getRect(panel);
    final review = tester.getRect(key('spec-questions-review'));
    expect(review.width, 720);
    expect(review.center.dx, closeTo(area.center.dx, 0.5));
    expect(find.text('Voltar às perguntas'), findsOneWidget);
    expect(find.text('Aplicar 2 respostas na spec'), findsOneWidget);
    // The steps stay on top, none of them current.
    expect(key('spec-questions-trail'), findsOneWidget);
    expect(key('spec-questions-later-P2'), findsOneWidget);

    await tester.tap(key('spec-questions-change-P2'));
    await tester.pump();
    await tester.pump();
    expect(subtitle(tester), endsWith('pergunta 2 de 3'));
    await tester.tap(key('spec-questions-next'));
    await tester.pump();
    await tester.pump();
    await tester.tap(key('spec-questions-next'));
    await tester.pump();
    await tester.pump();
    expect(key('spec-questions-review'), findsOneWidget);

    // Without the box: only the decisions, the diff right away.
    await tester.tap(key('spec-questions-update'));
    await tester.pump();
    await tester.tap(key('spec-questions-apply'));
    await settleIo(
      tester,
      until: () => key('spec-questions-diff').evaluate().isNotEmpty,
    );
    expect(find.text('O que muda na spec'), findsOneWidget);
    final diff = tester.getRect(key('spec-questions-diff-view'));
    expect(diff.width, 1100);
    expect(diff.center.dx, closeTo(area.center.dx, 0.5));
    expect(tester.getRect(key('spec-questions-footer')).width, 1100);
    expect(
      tester.getRect(key('spec-questions-diff')).bottom,
      lessThanOrEqualTo(tester.getRect(key('spec-questions-footer')).top),
    );
    expect(find.text('Salvar na spec'), findsOneWidget);
    expect(disk(), questionsSpec);

    // Narrower: the width of the area minus 32 px on each side.
    tester.view.physicalSize = const Size(1100, 700);
    await tester.pump();
    expect(tester.getRect(key('spec-questions-diff-view')).width, 1036);
    expect(tester.takeException(), isNull);
    await tester.tap(key('spec-questions-discard'));
    await tester.pump();
    await releaseEditor(tester);
  });

  group('SPEC-060 keys of the review and the diff', () {
    /// Opens the session and answers up to the review (P2 deferred).
    Future<void> toReview(WidgetTester tester) async {
      await pump(tester);
      await open(tester);
      await tester.tap(key('spec-questions-next'));
      await tester.pump();
      await tester.pump();
      await tester.tap(key('spec-questions-defer'));
      await tester.pump();
      await tester.pump();
      await tester.tap(key('spec-questions-next'));
      await tester.pump();
      await tester.pump();
      expect(key('spec-questions-review'), findsOneWidget);
    }

    Finder kbd(String button, String k) =>
        find.descendant(of: key(button), matching: find.text(k));

    testWidgets('R1, R2, R6: in the review Esc goes back to the last '
        'question and Enter applies; the buttons show the keys', (
      tester,
    ) async {
      await toReview(tester);
      expect(kbd('spec-questions-previous', 'Esc'), findsOneWidget);
      expect(kbd('spec-questions-apply', 'Enter'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(panel, findsOneWidget);
      expect(subtitle(tester), endsWith('pergunta 3 de 3'));
      // Back to the review, Enter applies.
      await tester.tap(key('spec-questions-next'));
      await tester.pump();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.enter);
      await settleIo(tester, until: () => applier.calls.isNotEmpty);
      expect(applier.calls, hasLength(1));
      applier.next.complete(disk());
      await settleIo(
        tester,
        until: () => key('spec-questions-diff').evaluate().isNotEmpty,
      );
      await tester.tap(key('spec-questions-discard'));
      await tester.pump();
      await releaseEditor(tester);
    });

    testWidgets('R2: with the focus on Editar, Enter is the button\'s', (
      tester,
    ) async {
      await toReview(tester);
      Focus.of(
        tester.element(
          find
              .descendant(
                of: key('spec-questions-change-P2'),
                matching: find.byType(Text),
              )
              .first,
        ),
      ).requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.enter);
      expect(applier.calls, isEmpty);
      expect(subtitle(tester), endsWith('pergunta 2 de 3'));
      await press(tester, LogicalKeyboardKey.escape);
      await releaseEditor(tester);
    });

    testWidgets('R2: Enter does nothing with no answer to apply', (
      tester,
    ) async {
      await pump(tester);
      await open(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(key('spec-questions-defer'));
        await tester.pump();
        await tester.pump();
      }
      expect(key('spec-questions-review'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.enter);
      expect(key('spec-questions-review'), findsOneWidget);
      expect(applier.calls, isEmpty);
      await press(
        tester,
        LogicalKeyboardKey.escape,
        hold: LogicalKeyboardKey.controlLeft,
      );
      await releaseEditor(tester);
    });

    testWidgets('R3, R6: in the diff Esc goes back to the review keeping '
        'the diff, and Enter saves', (tester) async {
      await toReview(tester);
      await press(tester, LogicalKeyboardKey.enter);
      await settleIo(tester, until: () => applier.calls.isNotEmpty);
      final updated = disk().replaceFirst(
        'o sistema deve mostrar o grupo',
        'o sistema deve mostrar o grupo e a contagem',
      );
      applier.next.complete(updated);
      await settleIo(
        tester,
        until: () => key('spec-questions-diff').evaluate().isNotEmpty,
      );
      await tester.pump();
      expect(kbd('spec-questions-back', 'Esc'), findsOneWidget);
      expect(kbd('spec-questions-save', 'Enter'), findsOneWidget);
      expect(kbd('spec-questions-discard', 'Delete'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      expect(key('spec-questions-review'), findsOneWidget);
      // Nothing changed: Enter brings the same diff, no new run.
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      expect(key('spec-questions-diff'), findsOneWidget);
      expect(applier.calls, hasLength(1));

      await press(tester, LogicalKeyboardKey.enter);
      await settleIo(tester, until: () => panel.evaluate().isEmpty);
      expect(disk(), contains('e a contagem'));
      await releaseEditor(tester);
    });

    testWidgets('R3: an answer changed after going back runs it again', (
      tester,
    ) async {
      await toReview(tester);
      await press(tester, LogicalKeyboardKey.enter);
      await settleIo(tester, until: () => applier.calls.isNotEmpty);
      applier.next.complete(disk());
      await settleIo(
        tester,
        until: () => key('spec-questions-diff').evaluate().isNotEmpty,
      );
      await press(tester, LogicalKeyboardKey.escape);
      await tester.tap(key('spec-questions-update'));
      await tester.pump();
      applier.next = Completer<String>();
      await tester.tap(key('spec-questions-apply'));
      await settleIo(
        tester,
        until: () => key('spec-questions-diff').evaluate().isNotEmpty,
      );
      // Without the box the decisions go straight in: a new diff, made now.
      expect(applier.calls, hasLength(1));
      expect(key('spec-questions-diff'), findsOneWidget);
      await tester.tap(key('spec-questions-discard'));
      await tester.pump();
      await releaseEditor(tester);
    });

    testWidgets('R4: the first Delete arms, the second discards; another '
        'key, a click or 3 s disarm', (tester) async {
      await toReview(tester);
      await tester.tap(key('spec-questions-update'));
      await tester.pump();
      await tester.tap(key('spec-questions-apply'));
      await settleIo(
        tester,
        until: () => key('spec-questions-diff').evaluate().isNotEmpty,
      );
      await tester.pump();
      final hint = find.text('Descartar mudanças?');

      await press(tester, LogicalKeyboardKey.delete);
      expect(panel, findsOneWidget);
      expect(hint, findsOneWidget);
      // Another key disarms.
      await press(tester, LogicalKeyboardKey.keyA);
      expect(hint, findsNothing);
      // 3 s disarm.
      await press(tester, LogicalKeyboardKey.delete);
      expect(hint, findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(hint, findsNothing);
      // A click disarms.
      await press(tester, LogicalKeyboardKey.delete);
      await tester.tapAt(tester.getCenter(key('spec-questions-diff')));
      await tester.pump();
      expect(hint, findsNothing);

      await press(tester, LogicalKeyboardKey.delete);
      await press(tester, LogicalKeyboardKey.delete);
      expect(panel, findsNothing);
      expect(disk(), questionsSpec);
      // The answers stay for the next time.
      expect(answers(), isNotEmpty);
      await releaseEditor(tester);
    });

    testWidgets('R5: Ctrl+Esc closes from the questions, the review and the '
        'diff, keeping the answers; Esc still closes the questions', (
      tester,
    ) async {
      await toReview(tester);
      await press(
        tester,
        LogicalKeyboardKey.escape,
        hold: LogicalKeyboardKey.controlLeft,
      );
      expect(panel, findsNothing);
      expect(answers(), isNotEmpty);

      await open(tester);
      expect(subtitle(tester), contains('pergunta'));
      await press(
        tester,
        LogicalKeyboardKey.escape,
        hold: LogicalKeyboardKey.controlLeft,
      );
      expect(panel, findsNothing);

      await open(tester);
      await press(tester, LogicalKeyboardKey.escape);
      expect(panel, findsNothing);

      await open(tester);
      // Straight to the review: the answers were kept.
      for (var i = 0; i < 3; i++) {
        await tester.tap(key('spec-questions-next'));
        await tester.pump();
        await tester.pump();
      }
      expect(key('spec-questions-review'), findsOneWidget);
      await tester.tap(key('spec-questions-update'));
      await tester.pump();
      await tester.tap(key('spec-questions-apply'));
      await settleIo(
        tester,
        until: () => key('spec-questions-diff').evaluate().isNotEmpty,
      );
      await press(
        tester,
        LogicalKeyboardKey.escape,
        hold: LogicalKeyboardKey.controlLeft,
      );
      expect(panel, findsNothing);
      expect(disk(), questionsSpec);
      await releaseEditor(tester);
    });

    testWidgets('R5: while applying no key closes or goes back', (
      tester,
    ) async {
      await toReview(tester);
      await press(tester, LogicalKeyboardKey.enter);
      await settleIo(tester, until: () => applier.calls.isNotEmpty);
      expect(key('spec-questions-applying'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      await press(
        tester,
        LogicalKeyboardKey.escape,
        hold: LogicalKeyboardKey.controlLeft,
      );
      await press(tester, LogicalKeyboardKey.delete);
      expect(key('spec-questions-applying'), findsOneWidget);
      applier.next.complete(disk());
      await settleIo(
        tester,
        until: () => key('spec-questions-diff').evaluate().isNotEmpty,
      );
      await tester.tap(key('spec-questions-discard'));
      await tester.pump();
      await releaseEditor(tester);
    });
  });

  group('SPEC-061 three suggestions and "Outras sugestões"', () {
    const first = [
      QuestionAlternative(title: 'Menu da linha', consequence: 'Um clique.'),
      QuestionAlternative(title: 'Tela do grupo', consequence: 'Outra tela.'),
      QuestionAlternative(title: 'Arrastar', consequence: 'Mouse só.'),
    ];
    const fresh = [
      QuestionAlternative(title: 'Atalho', consequence: 'Ctrl+G agrupa.'),
      QuestionAlternative(title: 'Importar', consequence: 'De uma lista.'),
      QuestionAlternative(title: 'Regra', consequence: 'Por etiqueta.'),
    ];

    Future<void> openWithThree(WidgetTester tester) async {
      await pump(tester);
      await open(tester);
      options.of('P1').complete(first);
      await tester.pump();
      await tester.pump();
    }

    Finder card(String o) => key('spec-question-option-$o');
    Finder titleIn(String o, String t) =>
        find.descendant(of: card(o), matching: find.text(t));
    Finder badge(String o, String b) =>
        find.descendant(of: card(o), matching: find.text(b));

    Future<void> ctrlR(WidgetTester tester) => press(
      tester,
      LogicalKeyboardKey.keyR,
      hold: LogicalKeyboardKey.controlLeft,
    );

    testWidgets('R1, R2: three alternatives with the keys 2–4, "Outra '
        'resposta" on 5 and the button with Ctrl+R', (tester) async {
      await openWithThree(tester);
      expect(titleIn('alternative3', 'Arrastar'), findsOneWidget);
      expect(
        find.descendant(of: card('alternative3'), matching: find.text('4')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card('other'), matching: find.text('5')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('spec-question-more'),
          matching: find.text('Ctrl+R'),
        ),
        findsOneWidget,
      );
      await press(tester, LogicalKeyboardKey.digit4);
      expect(selected(tester), AnswerOption.alternative3);
      expect(answers()['P1']!.text, 'Arrastar');
      await releaseEditor(tester);
    });

    testWidgets('R3, R4: Ctrl+R waits with the three replaced, out of the '
        'keys, then shows three new ones without the ones shown', (
      tester,
    ) async {
      await openWithThree(tester);
      await ctrlR(tester);
      expect(options.asked.last.avoid, [
        'Menu da linha',
        'Tela do grupo',
        'Arrastar',
      ]);
      expect(options.asked.last.count, 3);
      expect(find.text('Gerando outras…'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(key('spec-question-wait-$i'), findsOneWidget);
      }
      expect(
        tester.widget<OutlinedButton>(key('spec-question-more')).onPressed,
        isNull,
      );
      // While waiting, Ctrl+R does nothing more.
      await ctrlR(tester);
      expect(options.pendingMore, hasLength(1));
      options.pendingMore.single.complete(fresh);
      await tester.pump();
      await tester.pump();
      expect(titleIn('alternative1', 'Atalho'), findsOneWidget);
      expect(titleIn('alternative3', 'Regra'), findsOneWidget);
      expect(badge('alternative2', 'nova'), findsOneWidget);
      expect(find.text('Outras sugestões'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.digit2);
      expect(answers()['P1']!.text, 'Atalho');
      await releaseEditor(tester);
    });

    testWidgets('R4: the chosen alternative stays in its place, marked '
        '"mantida"; the other two are replaced', (tester) async {
      await openWithThree(tester);
      await press(tester, LogicalKeyboardKey.digit3);
      expect(answers()['P1']!.text, 'Tela do grupo');
      await tester.tap(key('spec-question-more'));
      await tester.pump();
      expect(options.asked.last.count, 2);
      expect(titleIn('alternative2', 'Tela do grupo'), findsOneWidget);
      expect(key('spec-question-wait-0'), findsOneWidget);
      expect(key('spec-question-wait-2'), findsOneWidget);
      options.pendingMore.single.complete(fresh.take(2).toList());
      await tester.pump();
      await tester.pump();
      expect(titleIn('alternative1', 'Atalho'), findsOneWidget);
      expect(titleIn('alternative2', 'Tela do grupo'), findsOneWidget);
      expect(titleIn('alternative3', 'Importar'), findsOneWidget);
      expect(badge('alternative2', 'mantida'), findsOneWidget);
      expect(badge('alternative1', 'nova'), findsOneWidget);
      expect(selected(tester), AnswerOption.alternative2);
      expect(answers()['P1']!.text, 'Tela do grupo');

      // The next visit shows the last set.
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(titleIn('alternative1', 'Atalho'), findsOneWidget);
      expect(options.pendingMore, hasLength(1));
      await releaseEditor(tester);
    });

    testWidgets('R2: Ctrl+R works in the field of "Outra resposta" and '
        'keeps its text', (tester) async {
      await openWithThree(tester);
      await press(tester, LogicalKeyboardKey.digit5);
      await tester.enterText(key('spec-question-other-text'), 'Pelo menu');
      await tester.pump();
      await ctrlR(tester);
      expect(options.pendingMore, hasLength(1));
      expect(
        tester
            .widget<TextField>(key('spec-question-other-text'))
            .controller!
            .text,
        'Pelo menu',
      );
      expect(selected(tester), AnswerOption.other);
      options.pendingMore.single.complete(fresh);
      await tester.pump();
      await tester.pump();
      await releaseEditor(tester);
    });

    testWidgets('R5: a failure keeps the last set and "Tentar de novo" asks '
        'again', (tester) async {
      await openWithThree(tester);
      await ctrlR(tester);
      options.pendingMore.single.completeError(StateError('x'));
      await tester.pump();
      await tester.pump();
      expect(key('spec-question-more-failed'), findsOneWidget);
      expect(titleIn('alternative1', 'Menu da linha'), findsOneWidget);
      expect(key('spec-question-wait-0'), findsNothing);
      await tester.tap(key('spec-question-more-retry'));
      await tester.pump();
      expect(options.pendingMore, hasLength(2));
      expect(key('spec-question-more-failed'), findsNothing);
      options.pendingMore.last.complete(fresh);
      await tester.pump();
      await tester.pump();
      expect(titleIn('alternative1', 'Atalho'), findsOneWidget);
      await releaseEditor(tester);
    });
  });

  group('R10 motion', () {
    setUp(() => AppMotion.enabled = true);
    tearDown(() => AppMotion.enabled = false);

    double opacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find.ancestor(of: panel, matching: find.byType(Opacity)).first,
        )
        .opacity;

    double turn(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: key('spec-questions-body'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    testWidgets('the session fades in (180 ms) and the question changes '
        'with a crossfade (120 ms)', (tester) async {
      await pump(tester);
      await tester.tap(key('spec-more'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(key('spec-answer-questions'));
      await tester.pump();
      await tester.pump();
      // The first frame starts it; 60 ms later it is on the way.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(tester), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(tester), 1);
      await tester.tap(key('spec-questions-next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(turn(tester), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 120));
      expect(turn(tester), 1);
      await releaseEditor(tester);
    });

    testWidgets('with reduced motion the change is direct', (tester) async {
      await pump(tester, reduceMotion: true);
      await tester.tap(key('spec-more'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(key('spec-answer-questions'));
      await tester.pump();
      await tester.pump();
      expect(opacity(tester), 1);
      await tester.tap(key('spec-questions-next'));
      await tester.pump();
      expect(turn(tester), 1);
      await releaseEditor(tester);
    });
  });
}
