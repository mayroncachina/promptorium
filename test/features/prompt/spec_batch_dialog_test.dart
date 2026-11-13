import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'answer_spec_bar_test.dart' show button, pumpPrompt, textOf, until;
import 'spec_batch_test.dart' show threeSpecs;

/// Spec files written whole (the content lands after the exclusive create).
List<File> specFiles(Directory tmp) => [
  for (final f in _files(tmp))
    if (f.readAsStringSync().contains('status: rascunho')) f,
];

List<File> _files(Directory tmp) {
  final dir = Directory('${tmp.path}/specs');
  if (!dir.existsSync()) return const [];
  return dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

Future<void> openList(WidgetTester tester) async {
  await until(
    tester,
    () => textOf(tester, 'answer-specs-subtitle')?.contains('SPEC-') ?? false,
  );
  await tester.tap(button('answer-specs-review'));
  await until(tester, () => button('spec-batch-dialog').evaluate().isNotEmpty);
}

void main() {
  testWidgets('three specs: the bar offers them with the real numbers', (
    tester,
  ) async {
    await pumpPrompt(tester, answer: threeSpecs());
    await until(
      tester,
      () => textOf(tester, 'answer-specs-subtitle')?.contains('SPEC') ?? false,
    );
    expect(textOf(tester, 'answer-specs-title'), '3 specs nesta resposta');
    expect(
      textOf(tester, 'answer-specs-subtitle'),
      '· viram SPEC-001 a SPEC-003 ao criar',
    );
    expect(find.text('SPEC-A'), findsOneWidget);
    expect(button('answer-spec-bar'), findsNothing);
  });

  testWidgets('the list: unchecking warns the dependents, "Marcar" and '
      '"Tirar a dependência" fix it, the title edits in place, and it '
      'creates the checked ones', (tester) async {
    final h = await pumpPrompt(tester, answer: threeSpecs());
    await openList(tester);
    expect(find.text('Criar 3 specs'), findsOneWidget);
    expect(textOf(tester, 'spec-batch-code-2'), 'SPEC-003');

    await tester.tap(button('spec-batch-check-0'));
    await tester.pump();
    expect(find.text('Criar 2 specs'), findsOneWidget);
    expect(button('spec-batch-warning-1-SPEC-A'), findsOneWidget);
    expect(button('spec-batch-warning-2-SPEC-A'), findsOneWidget);
    expect(
      find.text('Depende da SPEC-A, que você desmarcou. Ela não vai existir.'),
      findsNWidgets(2),
    );
    expect(textOf(tester, 'spec-batch-code-1'), 'SPEC-001');

    await tester.tap(button('spec-batch-check-dep-1-SPEC-A'));
    await tester.pump();
    expect(find.text('Criar 3 specs'), findsOneWidget);
    expect(button('spec-batch-warning-1-SPEC-A'), findsNothing);

    await tester.tap(button('spec-batch-check-0'));
    await tester.pump();
    await tester.tap(button('spec-batch-drop-dep-2-SPEC-A'));
    await tester.pump();
    expect(button('spec-batch-warning-2-SPEC-A'), findsNothing);
    expect(button('spec-batch-warning-1-SPEC-A'), findsOneWidget);

    await tester.tap(button('spec-batch-title-2'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(button('spec-batch-title-field-2'), 'Pix na loja');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Pix na loja'), findsOneWidget);

    await tester.tap(button('spec-batch-create'));
    await until(tester, () => specFiles(h.tmp).length == 2);
    final files = specFiles(h.tmp);
    expect(files.map((f) => f.uri.pathSegments.last), [
      'SPEC-001-cupom-de-desconto-no-carrinho.md',
      'SPEC-002-pix-na-loja.md',
    ]);
    final pix = files[1].readAsStringSync();
    expect(pix, startsWith('---\nid: SPEC-002\nstatus: rascunho\n---'));
    expect(pix, contains('# Pix na loja'));
    expect(pix, isNot(contains('depende-de')));
    expect(files[0].readAsStringSync(), isNot(contains('SPEC-A')));
  });

  testWidgets('Esc closes the list without creating anything', (tester) async {
    final h = await pumpPrompt(tester, answer: threeSpecs());
    await openList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(button('spec-batch-dialog'), findsNothing);
    expect(specFiles(h.tmp), isEmpty);
  });

  testWidgets('Enter creates; the same answer again shows them as created', (
    tester,
  ) async {
    final h = await pumpPrompt(tester, answer: threeSpecs());
    await openList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await until(tester, () => specFiles(h.tmp).length == 3);
    await until(
      tester,
      () => textOf(tester, 'answer-specs-subtitle') == '· já criadas',
    );
    final specs = await tester.runAsync(() => h.db.select(h.db.specs).get());
    expect(specs!.map((s) => s.originAlias), ['SPEC-A', 'SPEC-B', 'SPEC-C']);
    expect(specs.map((s) => s.originAnswer).toSet(), {0});

    await tester.tap(button('answer-specs-review'));
    await until(
      tester,
      () => button('spec-batch-dialog').evaluate().isNotEmpty,
    );
    expect(
      textOf(tester, 'spec-batch-subtitle'),
      'Esta resposta já virou specs antes. Só o que é novo pode ser criado.',
    );
    expect(find.text('✓ já criada · SPEC-001'), findsOneWidget);
    expect(find.text('✓ já criada · SPEC-003'), findsOneWidget);
    expect(button('spec-batch-open-0'), findsOneWidget);
    expect(find.text('Nada novo para criar'), findsOneWidget);
    await tester.tap(button('spec-batch-create'));
    await tester.pump();
    expect(button('spec-batch-dialog'), findsOneWidget, reason: 'disabled');
    expect(specFiles(h.tmp), hasLength(3));
  });

  testWidgets('"Transformar em spec" with several specs opens the list', (
    tester,
  ) async {
    await pumpPrompt(tester, answer: threeSpecs());
    await until(
      tester,
      () => textOf(tester, 'answer-specs-subtitle')?.contains('SPEC') ?? false,
    );
    await tester.tap(button('prompt-to-spec'));
    await until(
      tester,
      () => button('spec-batch-dialog').evaluate().isNotEmpty,
    );
    expect(find.text('Criar 3 specs'), findsOneWidget);
  });
}
