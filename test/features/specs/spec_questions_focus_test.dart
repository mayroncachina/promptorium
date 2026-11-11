import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/spec_answers.dart';
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
        specAnswerApplierProvider.overrideWith(FakeApplier.new),
      ],
    );
    c.read(specQuestionOptionsProvider);
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
        matching: find.text('Esc'),
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
    await press(tester, LogicalKeyboardKey.digit4);
    expect(selected(tester), AnswerOption.other);
    // Past the options: nothing.
    await press(tester, LogicalKeyboardKey.digit7);
    expect(selected(tester), AnswerOption.other);
    await press(tester, LogicalKeyboardKey.digit2);
    expect(selected(tester), AnswerOption.alternative1);

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
