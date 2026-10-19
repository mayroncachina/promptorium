import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/widgets/question_card.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

const input = <String, dynamic>{
  'questions': [
    {
      'question': 'Qual linguagem?',
      'header': 'Linguagem',
      'multiSelect': false,
      'options': [
        {'label': 'Dart', 'description': 'Dart no projeto'},
        {'label': 'Python', 'description': 'Python no projeto'},
      ],
    },
    {
      'question': 'Quais recursos?',
      'header': 'Recursos',
      'multiSelect': true,
      'options': [
        {'label': 'Login', 'description': 'Entrar'},
        {'label': 'Relatórios', 'description': 'PDF'},
      ],
    },
  ],
};

Future<void> pumpFor(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  test('parseAskQuestions / askAnswerInput', () {
    final qs = parseAskQuestions(input)!;
    expect(qs, hasLength(2));
    expect(qs[0].header, 'Linguagem');
    expect(qs[1].multiSelect, isTrue);
    expect(qs[0].options.first.label, 'Dart');
    expect(parseAskQuestions({'command': 'ls'}), isNull);
    expect(parseAskQuestions({'questions': []}), isNull);
    expect(
      parseAskQuestions({
        'questions': [
          {'question': '', 'options': []},
        ],
      }),
      isNull,
    );
    final out = askAnswerInput(input, {'Qual linguagem?': 'Dart'});
    expect(out['answers'], {'Qual linguagem?': 'Dart'});
    expect(out['questions'], input['questions']);
    expect(jsonEncode(out), contains('"answers"'));
  });

  testWidgets('single choice, multiple choice and "Outro" build the answers; '
      'send waits until everything is answered', (tester) async {
    Map<String, String>? sent;
    var declined = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuestionCard(
                questions: parseAskQuestions(input)!,
                onSubmit: (a) => sent = a,
                onDecline: () => declined = true,
              ),
            ),
          ),
        ),
      ),
    );
    // Tapping "Enviar respostas" before everything is answered does nothing.
    Future<void> trySend() async {
      sent = null;
      await tester.tap(find.byKey(const ValueKey('question-submit')));
      await pumpFor(tester);
    }

    await trySend();
    expect(sent, isNull);
    await tester.tap(find.byKey(const ValueKey('question-0-option-1')));
    await pumpFor(tester);
    await trySend();
    expect(sent, isNull); // second question still open

    // Multiple choice: two options and free text.
    await tester.tap(find.byKey(const ValueKey('question-1-option-0')));
    await tester.tap(find.byKey(const ValueKey('question-1-other')));
    await pumpFor(tester);
    await trySend();
    // An empty "Outro" is ignored: the answer is just the marked option.
    expect(sent, {'Qual linguagem?': 'Python', 'Quais recursos?': 'Login'});
    await tester.enterText(
      find.byKey(const ValueKey('question-1-other-text')),
      'Exportar CSV',
    );
    await pumpFor(tester);
    await trySend();
    expect(sent, {
      'Qual linguagem?': 'Python',
      'Quais recursos?': 'Login, Exportar CSV',
    });

    // Single choice replaces the previous pick; "Outro" clears the options.
    await tester.tap(find.byKey(const ValueKey('question-0-option-0')));
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('question-submit')));
    expect(sent!['Qual linguagem?'], 'Dart');

    await tester.tap(find.byKey(const ValueKey('question-decline')));
    expect(declined, isTrue);
  });
}
