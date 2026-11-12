import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_answers.dart';
import 'package:promptorium/features/specs/spec_file.dart';
import 'package:promptorium/ui/widgets/diff_view.dart';

import 'package:promptorium/ui/theme/tokens.dart';
import 'package:promptorium/ui/widgets/code_editor/app_code_editor.dart';

import 'spec_file_test.dart' as file_test show oldFormatSpec;
import 'spec_action_lock_test.dart'
    show FakeDesigner, editorOf, key, pumpSpecs, specPath;
import 'specs_screen_test.dart' show settleIo;

/// Alternatives of the Claude held until the test completes them.
class FakeQuestionOptions extends SpecQuestionOptions {
  FakeQuestionOptions(super.ref);

  final calls = <String>[];
  final pending = <String, Completer<List<QuestionAlternative>>>{};

  Completer<List<QuestionAlternative>> of(String id) =>
      pending.putIfAbsent(id, Completer.new);

  /// The [avoid] list and [count] of each call (SPEC-061).
  final asked = <({String id, List<String> avoid, int count})>[];

  /// The pending "Outras sugestões", in order.
  final pendingMore = <Completer<List<QuestionAlternative>>>[];

  @override
  Future<List<QuestionAlternative>> generate(
    Workspace ws,
    String specText,
    OpenQuestion q, {
    List<QuestionAlternative> avoid = const [],
    int count = alternativesPerQuestion,
  }) {
    calls.add(q.id);
    asked.add((
      id: q.id,
      avoid: [for (final a in avoid) a.title],
      count: count,
    ));
    // "Outras sugestões" waits on a completer of its own.
    if (avoid.isEmpty) return of(q.id).future;
    final c = Completer<List<QuestionAlternative>>();
    pendingMore.add(c);
    return c.future;
  }
}

/// "Atualizar requisitos" held until the test completes it; never writes.
class FakeApplier extends SpecAnswerApplier {
  FakeApplier(super.ref);

  final calls = <({String text, Map<OpenQuestion, Answer> answers})>[];
  Completer<String> next = Completer<String>();

  @override
  Future<String> apply(
    Workspace ws,
    String withDecisions,
    Map<OpenQuestion, Answer> answers, {
    Future<void>? cancelled,
  }) {
    calls.add((text: withDecisions, answers: answers));
    return next.future;
  }
}

const questionsSpec = '''---
id: SPEC-002
status: rascunho
---

# Grupos de máquinas

## Requisitos

- R1 · Quando agrupar, o sistema deve mostrar o grupo

## Critérios de aceite

- [ ] Agrupa [R1] verificar: true

## Perguntas em aberto

- P1 · Como adicionar máquinas a um grupo?
  - Sugestão: pela seleção na tabela.
- P2 · O filtro deve ser lembrado?
- P3 · Excluir um grupo apaga as máquinas?
  - Sugestão: não; elas voltam para "Sem grupo".
''';

void main() {
  late Directory tmp;
  late FakeQuestionOptions options;
  late FakeApplier applier;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-questions-');
    Directory('${tmp.path}/specs').createSync();
    File(specPath(tmp)).writeAsStringSync(questionsSpec);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  String disk() => File(specPath(tmp)).readAsStringSync();

  final panel = key('spec-questions-panel');

  Future<void> pump(WidgetTester tester) async {
    c = await pumpSpecs(
      tester,
      tmp,
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
    // Built now, so the test holds them before the first tap.
    c.read(specQuestionOptionsProvider);
    c.read(specAnswerApplierProvider);
  }

  /// "Mais ações" → "Responder perguntas" (R6).
  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(key('spec-more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(key('spec-answer-questions'));
    await settleIo(tester, until: () => panel.evaluate().isNotEmpty);
    expect(panel, findsOneWidget);
  }

  String subtitle(WidgetTester tester) =>
      tester.widget<Text>(key('spec-questions-subtitle')).data!;

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pump();
    await tester.tap(key(k));
    await tester.pump();
    await tester.pump();
  }

  AnswerOption? selected(WidgetTester tester) => tester
      .widget<RadioGroup<AnswerOption>>(find.byType(RadioGroup<AnswerOption>))
      .groupValue;

  Map<String, Answer> answers() => c.read(specAnswersProvider)[1] ?? {};

  testWidgets('R2, R3: the old format shows the notice with both counts '
      'and the suggestion lines marked; "Corrigir formato" rewrites the '
      'section in the editor; "Responder perguntas" opens the panel', (
    tester,
  ) async {
    final oldFormatSpec = file_test.oldFormatSpec.replaceFirst(
      'SPEC-012',
      'SPEC-002',
    );
    File(specPath(tmp)).writeAsStringSync(oldFormatSpec);
    await pump(tester);
    expect(
      tester.widget<Text>(key('spec-questions-format-text')).data,
      'Em "Perguntas em aberto", 4 itens são sugestões, não perguntas. A spec '
      'tem 4 perguntas, não 8. As linhas marcadas são sugestões.',
    );
    final marks = tester
        .widget<AppCodeEditor>(find.byType(AppCodeEditor))
        .lineMarks!;
    expect(marks.value.keys, [10, 12, 14, 16]);
    expect(marks.value.values.toSet(), {AppColors.amber});
    // Not counted twice in the structure strip.
    expect(key('spec-warnings'), findsNothing);

    await tapKey(tester, 'spec-questions-fix');
    final doc = SpecDocument.parse(oldFormatSpec);
    expect(
      editorOf(tester).controller!.text,
      doc.withOpenQuestions(doc.openQuestions),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(key('spec-questions-format'), findsNothing);
    expect(marks.value, isEmpty);
    expect(disk(), oldFormatSpec);

    editorOf(tester).controller!.text = oldFormatSpec;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tapKey(tester, 'spec-questions-format-answer');
    expect(panel, findsOneWidget);
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · pergunta 1 de 4');
  });

  testWidgets('R6: "Responder perguntas" opens the panel on the first '
      'question, with the trail of states and the navigation', (tester) async {
    await pump(tester);
    final semantics = tester.ensureSemantics();
    await openPanel(tester);
    expect(find.text('Responder perguntas'), findsWidgets);
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · pergunta 1 de 3');
    expect(find.text('P1 Como adicionar máquinas a um grupo?'), findsOneWidget);
    expect(find.bySemanticsLabel('P1, atual'), findsOneWidget);
    expect(find.bySemanticsLabel('P2, pendente'), findsOneWidget);
    expect(find.bySemanticsLabel('P3, pendente'), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(key('spec-questions-previous'))
          .onPressed,
      isNull,
    );
    expect(find.text('Deixar para depois'), findsOneWidget);
    expect(find.text('Próxima'), findsOneWidget);

    await tapKey(tester, 'spec-questions-next');
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · pergunta 2 de 3');
    expect(find.bySemanticsLabel('P1, respondida'), findsOneWidget);
    expect(find.bySemanticsLabel('P2, atual'), findsOneWidget);
    await tapKey(tester, 'spec-questions-defer');
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · pergunta 3 de 3');
    expect(find.bySemanticsLabel('P2, para depois'), findsOneWidget);
    // Not only the color: a check for answered, a clock for later.
    expect(
      find.descendant(
        of: key('spec-questions-trail-P1'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('spec-questions-trail-P2'),
        matching: find.byIcon(Icons.schedule),
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'spec-questions-previous');
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · pergunta 2 de 3');
    // The trail jumps to a question.
    await tapKey(tester, 'spec-questions-trail-P3');
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · pergunta 3 de 3');
    expect(disk(), questionsSpec);
    semantics.dispose();
  });

  testWidgets('R7: the suggestion pre-selected, up to two alternatives of '
      'the Claude and "Outra resposta"; the suggestion works before the '
      'alternatives arrive', (tester) async {
    await pump(tester);
    await openPanel(tester);
    expect(
      find.text(
        'A primeira opção é a sugestão escrita na spec; as outras foram '
        'propostas pelo Claude.',
      ),
      findsOneWidget,
    );
    expect(find.text('pela seleção na tabela.'), findsOneWidget);
    expect(find.text('Sugestão da spec'), findsOneWidget);
    expect(selected(tester), AnswerOption.suggestion);
    expect(find.text('Outra resposta'), findsOneWidget);
    expect(key('spec-question-loading'), findsOneWidget);
    // P1 asked when reached, the next one preloaded (P1 of the spec).
    expect(options.calls, ['P1', 'P2']);

    // Before the alternatives: "Próxima" keeps the suggestion.
    await tapKey(tester, 'spec-questions-next');
    expect(
      answers()['P1'],
      const Answer(
        option: AnswerOption.suggestion,
        text: 'pela seleção na tabela.',
      ),
    );
    expect(options.calls, ['P1', 'P2', 'P3']);
    // P2 has no suggestion: nothing pre-selected, the note says so.
    expect(selected(tester), isNull);
    expect(
      find.text(
        'A spec não traz sugestão; as opções foram propostas pelo Claude.',
      ),
      findsOneWidget,
    );

    await tapKey(tester, 'spec-questions-previous');
    options.of('P1').complete(const [
      QuestionAlternative(
        title: 'Menu da linha',
        consequence: 'Um clique por máquina.',
      ),
      QuestionAlternative(
        title: 'Tela do grupo',
        consequence: 'Mais uma tela para manter.',
      ),
    ]);
    await tester.pump();
    await tester.pump();
    expect(key('spec-question-loading'), findsNothing);
    expect(find.text('Menu da linha'), findsOneWidget);
    expect(find.text('Um clique por máquina.'), findsOneWidget);
    expect(find.text('Tela do grupo'), findsOneWidget);
    expect(selected(tester), AnswerOption.suggestion);
    await tapKey(tester, 'spec-question-option-alternative2');
    expect(selected(tester), AnswerOption.alternative2);
    expect(answers()['P1']!.text, 'Tela do grupo');

    await tester.enterText(key('spec-question-other-text'), 'Arrastar');
    await tester.pump();
    expect(selected(tester), AnswerOption.other);
    expect(
      answers()['P1'],
      const Answer(option: AnswerOption.other, text: 'Arrastar'),
    );

    // A failed generation leaves the suggestion and "Outra resposta".
    await tapKey(tester, 'spec-questions-next');
    await tapKey(tester, 'spec-questions-next');
    options.of('P3').completeError(Exception('falhou'));
    await tester.pump();
    await tester.pump();
    expect(key('spec-question-failed'), findsOneWidget);
    expect(selected(tester), AnswerOption.suggestion);
    expect(disk(), questionsSpec);
  });

  testWidgets('R8: closing and reopening the panel keeps the answers; the '
      'file does not change', (tester) async {
    await pump(tester);
    await openPanel(tester);
    await tester.enterText(key('spec-question-other-text'), 'Por arrastar');
    await tester.pump();
    await tapKey(tester, 'spec-questions-next');
    await tapKey(tester, 'spec-questions-defer');
    await tapKey(tester, 'spec-questions-close');
    expect(panel, findsNothing);
    expect(disk(), questionsSpec);
    expect(editorOf(tester).controller!.text, questionsSpec);

    await openPanel(tester);
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · pergunta 1 de 3');
    expect(selected(tester), AnswerOption.other);
    expect(
      tester
          .widget<TextField>(key('spec-question-other-text'))
          .controller!
          .text,
      'Por arrastar',
    );
    expect(find.bySemanticsLabel('P2, para depois'), findsOneWidget);
    expect(disk(), questionsSpec);
  });

  testWidgets('R9: the review lists the answers, "Editar" changes one and '
      'the box to update the requirements is checked', (tester) async {
    await pump(tester);
    await openPanel(tester);
    await tapKey(tester, 'spec-questions-next');
    await tapKey(tester, 'spec-questions-defer');
    await tapKey(tester, 'spec-questions-next');
    expect(find.text('Revise as respostas'), findsOneWidget);
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · revisão');
    expect(
      tester.widget<Text>(key('spec-questions-count')).data,
      startsWith('2 respondidas, 1 para depois.'),
    );
    expect(
      find.descendant(
        of: key('spec-questions-review'),
        matching: find.text('Editar'),
      ),
      findsNWidgets(3),
    );
    expect(find.text('pela seleção na tabela.'), findsOneWidget);
    expect(find.text('não; elas voltam para "Sem grupo".'), findsOneWidget);
    expect(key('spec-questions-later-P2'), findsOneWidget);
    expect(find.text('Para depois'), findsOneWidget);
    expect(key('spec-questions-change-P1'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(key('spec-questions-update')).value,
      isTrue,
    );
    expect(
      find.text('Atualizar requisitos e critérios com as respostas'),
      findsOneWidget,
    );
    expect(find.text('Aplicar 2 respostas na spec'), findsOneWidget);

    await tapKey(tester, 'spec-questions-change-P2');
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · pergunta 2 de 3');
    await tester.enterText(key('spec-question-other-text'), 'Sim, por usuário');
    await tester.pump();
    await tapKey(tester, 'spec-questions-next');
    await tapKey(tester, 'spec-questions-next');
    expect(find.text('Sim, por usuário'), findsOneWidget);
    expect(key('spec-questions-later-P2'), findsNothing);
    expect(find.text('Aplicar 3 respostas na spec'), findsOneWidget);
    expect(disk(), questionsSpec);
  });

  testWidgets('R10, R11: the diff comes before saving; "Descartar" keeps the '
      'file; with the box the Claude text comes back (spec held, nothing '
      'written) and "Salvar na spec" saves it without changing the status', (
    tester,
  ) async {
    await pump(tester);
    await openPanel(tester);
    await tapKey(tester, 'spec-questions-next');
    await tapKey(tester, 'spec-questions-defer');
    await tapKey(tester, 'spec-questions-next');

    // Without the box: only the decisions, no Claude.
    await tapKey(tester, 'spec-questions-update');
    await tapKey(tester, 'spec-questions-apply');
    expect(applier.calls, isEmpty);
    expect(find.text('O que muda na spec'), findsOneWidget);
    expect(
      subtitle(tester),
      'SPEC-002 · Grupos de máquinas · o que muda na spec · nada foi salvo '
      'ainda',
    );
    expect(find.byType(DiffView), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);
    expect(find.text('Voltar às respostas'), findsOneWidget);
    expect(find.text('Salvar na spec'), findsOneWidget);
    final summary = tester.widget<Text>(key('spec-questions-summary')).data!;
    expect(summary, contains('Decisões com P1 e P3'));
    expect(summary, contains('O P2 continua em aberto.'));
    await tapKey(tester, 'spec-questions-discard');
    expect(panel, findsNothing);
    expect(disk(), questionsSpec);
    expect(editorOf(tester).controller!.text, questionsSpec);

    // The answers are still there: back to the review with the box.
    await openPanel(tester);
    await tapKey(tester, 'spec-questions-next');
    await tapKey(tester, 'spec-questions-next');
    await tapKey(tester, 'spec-questions-next');
    expect(find.text('Aplicar 2 respostas na spec'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(key('spec-questions-update')).value,
      isTrue,
    );
    await tapKey(tester, 'spec-questions-apply');
    await settleIo(tester, until: () => applier.calls.isNotEmpty);
    final call = applier.calls.single;
    final decided = SpecDocument.parse(call.text);
    expect(decided.section('Decisões')!.split('\n'), [
      for (final l in [
        'P1 · pela seleção na tabela.',
        'P3 · não; elas voltam para "Sem grupo".',
      ])
        startsWith('- $l ('),
    ]);
    expect(decided.openQuestions.map((q) => q.id), ['P2']);
    expect(call.answers.keys.map((q) => q.id), ['P1', 'P3']);
    // SPEC-025: the spec is held while the Claude runs.
    expect(editorOf(tester).readOnly, isTrue);
    expect(key('spec-questions-applying'), findsOneWidget);
    expect(disk(), questionsSpec);

    final updated = call.text.replaceFirst(
      '- R1 · Quando agrupar, o sistema deve mostrar o grupo',
      '- R1 · Quando agrupar, o sistema deve mostrar o grupo\n'
          '- R2 · Quando selecionar na tabela, o sistema deve oferecer '
          '"Agrupar"',
    );
    applier.next.complete(updated);
    await settleIo(
      tester,
      until: () => find.byType(DiffView).evaluate().isNotEmpty,
    );
    expect(disk(), questionsSpec);
    expect(editorOf(tester).readOnly, isFalse);
    // R11: line numbers and an accessible label per line.
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp(r'^linha adicionada, linha \d+: ')),
      findsWidgets,
    );
    semantics.dispose();
    expect(
      tester.widget<Text>(key('spec-questions-summary')).data,
      startsWith('Requisitos e critérios atualizados pelo Claude;'),
    );
    // "Voltar às respostas" and back again keeps the result.
    await tapKey(tester, 'spec-questions-back');
    expect(find.text('Revise as respostas'), findsOneWidget);
    applier.next = Completer<String>()..complete(updated);
    await tapKey(tester, 'spec-questions-apply');
    await settleIo(
      tester,
      until: () => find.byType(DiffView).evaluate().isNotEmpty,
    );

    await tapKey(tester, 'spec-questions-save');
    // The file is written before the panel closes and the editor follows.
    await settleIo(
      tester,
      until: () =>
          disk() == updated &&
          panel.evaluate().isEmpty &&
          c.read(specAnswersProvider)[1] == null,
    );
    expect(disk(), updated);
    expect(SpecDocument.parse(disk()).status, SpecStatus.draft);
    expect(panel, findsNothing);
    expect(editorOf(tester).controller!.text, updated);
    expect(key('spec-unsaved'), findsNothing);
    expect(c.read(specAnswersProvider)[1], isNull);
    await releaseEditor(tester);
  });

  testWidgets('R12: arrows in the radio group, Enter for "Próxima", Esc '
      'closes keeping the answers, "Pergunta n de M" announced', (
    tester,
  ) async {
    final announced = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (msg) async {
        if (msg is Map && msg['type'] == 'announce') {
          announced.add('${(msg['data'] as Map)['message']}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    await pump(tester);
    final semantics = tester.ensureSemantics();
    await openPanel(tester);
    await tester.pump();
    // The focus is on the chosen option, with a visible ring.
    final focused = FocusManager.instance.primaryFocus;
    expect(focused?.debugLabel, 'spec-question-suggestion');
    expect(selected(tester), AnswerOption.suggestion);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(selected(tester), AnswerOption.other);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(selected(tester), AnswerOption.suggestion);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(subtitle(tester), 'SPEC-002 · Grupos de máquinas · pergunta 2 de 3');
    expect(announced, contains('Pergunta 2 de 3'));
    expect(answers()['P1']!.option, AnswerOption.suggestion);
    expect(
      tester.getSemantics(key('spec-questions-subtitle')),
      isSemantics(
        isLiveRegion: true,
        label: 'SPEC-002 · Grupos de máquinas · pergunta 2 de 3',
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(panel, findsNothing);
    expect(answers()['P1']!.text, 'pela seleção na tabela.');
    expect(disk(), questionsSpec);
    semantics.dispose();
    await releaseEditor(tester);
  });
}

/// Closing the panel gives the focus back to the editor, whose cursor
/// blinks until it loses it.
Future<void> releaseEditor(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(seconds: 1));
}
