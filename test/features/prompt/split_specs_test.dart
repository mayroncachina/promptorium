import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/prompt/split_specs.dart';

import 'answer_spec_bar_test.dart' show Harness, button, pumpPrompt, until;
import 'spec_batch_dialog_test.dart' show specFiles;
import 'spec_batch_test.dart' show specText, threeSpecs;

/// A conversation that discusses, with no spec in the answer.
const talk =
    'Fechado. Com isso o plano tem três frentes: carrinho, cupom e Pix.';

/// The runner of the tests: each call waits for the next answer.
class FakeSplit {
  final calls = <String>[];
  final cancelled = <bool>[];
  Completer<String> next = Completer<String>();

  Future<String> run(Workspace ws, String prompt, {Future<void>? cancelled}) {
    calls.add(prompt);
    final i = this.cancelled.length;
    this.cancelled.add(false);
    cancelled?.then((_) => this.cancelled[i] = true);
    return next.future;
  }

  void answer(String text) {
    final c = next;
    next = Completer<String>();
    c.complete(text);
  }
}

Future<(FakeSplit, Harness)> openSplit(WidgetTester tester) async {
  final fake = FakeSplit();
  final h = await pumpPrompt(
    tester,
    answer: talk,
    overrides: [splitSpecsRunnerProvider.overrideWithValue(fake.run)],
  );
  await until(tester, () => find.text(talk).evaluate().isNotEmpty);
  await tester.tap(button('prompt-more'));
  await tester.pumpAndSettle();
  expect(find.text('Dividir em specs'), findsOneWidget);
  await tester.tap(button('conversation-menu-split'));
  await until(tester, () => fake.calls.isNotEmpty);
  await tester.pump();
  return (fake, h);
}

void main() {
  test('the prompt carries the conversation, the format and the codes', () {
    final p = splitSpecsPrompt(
      [
        (user: true, text: 'Quero refazer o checkout.'),
        (user: false, text: talk),
      ],
      existing: ['SPEC-001 (Login)'],
    );
    expect(p, contains('id: SPEC-A'));
    expect(p, contains('depende-de: [SPEC-A]'));
    expect(p, contains('Não crie nem edite arquivos'));
    expect(p, contains('SPEC-001 (Login)'));
    expect(p, contains('**Pessoa:**\nQuero refazer o checkout.'));
    expect(p, endsWith('$talk\n'));
  });

  testWidgets('"Dividir em specs" waits with "Nada é criado antes de você '
      'revisar" and opens the review list', (tester) async {
    final (fake, _) = await openSplit(tester);
    expect(button('split-specs-dialog'), findsOneWidget);
    expect(find.text('Nada é criado antes de você revisar.'), findsOneWidget);
    expect(fake.calls.single, contains(talk));

    fake.answer(threeSpecs());
    await until(
      tester,
      () => button('spec-batch-dialog').evaluate().isNotEmpty,
    );
    expect(button('split-specs-dialog'), findsNothing);
    expect(find.text('Criar 3 specs'), findsOneWidget);
  });

  testWidgets('"Cancelar" ends the run and creates nothing', (tester) async {
    final (fake, _) = await openSplit(tester);
    await tester.tap(button('split-specs-cancel'));
    await tester.pumpAndSettle();
    expect(button('split-specs-dialog'), findsNothing);
    expect(fake.cancelled.single, isTrue);
    fake.answer(threeSpecs());
    await tester.pumpAndSettle();
    expect(button('spec-batch-dialog'), findsNothing);
  });

  testWidgets('one spec opens the "Salvar spec" of today', (tester) async {
    final (fake, _) = await openSplit(tester);
    fake.answer('```markdown\n${specText('SPEC-A', 'Só o carrinho')}```');
    await until(
      tester,
      () => button('answer-spec-title-field').evaluate().isNotEmpty,
    );
    expect(find.text('Salvar spec da resposta'), findsOneWidget);
  });

  testWidgets('none says so and "Tentar de novo" asks again', (tester) async {
    final (fake, h) = await openSplit(tester);
    fake.answer('Não achei specs aqui.');
    await until(
      tester,
      () => find
          .text('O Claude não devolveu nenhuma spec.')
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(button('split-specs-retry'));
    await tester.pump();
    expect(fake.calls, hasLength(2));
    fake.answer(threeSpecs());
    await until(
      tester,
      () => button('spec-batch-dialog').evaluate().isNotEmpty,
    );
    await tester.tap(button('spec-batch-create'));
    await until(tester, () => specFiles(h.tmp).length == 3);
    final specs = await tester.runAsync(() => h.db.select(h.db.specs).get());
    expect(specs!.map((s) => s.originAnswer).toSet(), {splitAnswerIndex});
    expect(specs.map((s) => s.originConversationId).toSet(), {1});
  });
}
