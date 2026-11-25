import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/debts/widgets/debts_screen.dart';

import 'debts_screen_test.dart' show boardOf, pumpScreen;

/// SPEC-112 R15: "Pagar · N" and the dialog.
void main() {
  Future<void> select(WidgetTester tester, List<String> codes) async {
    for (final c in codes) {
      await tester.tap(find.byKey(ValueKey('debt-check-$c')));
      await tester.pump();
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('2 selecionados: "Pagar · 2" abre o diálogo com a VIBE '
      'sugerida, o prompt e o que acontece; a pessoa pode escolher a spec', (
    tester,
  ) async {
    final c = await pumpScreen(tester, boardOf());
    expect(find.byKey(const ValueKey('debts-pay')), findsNothing);
    await select(tester, ['DT-05', 'DT-06']);
    expect(c.read(debtsSelectionProvider), {'DT-05', 'DT-06'});
    expect(find.text('Pagar · 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('debts-pay')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pay-debts-dialog')), findsOneWidget);
    expect(find.text('Pagar 2 débitos'), findsOneWidget);
    expect(find.byKey(const ValueKey('pay-item-DT-05')), findsOneWidget);
    expect(find.byKey(const ValueKey('pay-item-DT-06')), findsOneWidget);
    expect(find.text('sugerido · até 2 débitos'), findsOneWidget);
    expect(find.text('a partir de 3'), findsOneWidget);
    expect(find.text('PROMPT DA VIBE'), findsOneWidget);
    final preview = tester.widget<SelectableText>(
      find.byKey(const ValueKey('pay-preview')),
    );
    expect(
      preview.data,
      startsWith(
        'Pagar débitos: DT-05, DT-06\nPague os débitos DT-05 e DT-06 de DEBITO_TECNICO.md.',
      ),
    );
    expect(
      find.textContaining('Agora os dois ficam', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('os dois voltam a', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Criar VIBE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pay-mode-spec')));
    await tester.pump();
    expect(find.text('TEXTO DA SPEC'), findsOneWidget);
    expect(find.text('Criar spec'), findsOneWidget);
    expect(
      tester
          .widget<SelectableText>(find.byKey(const ValueKey('pay-preview')))
          .data,
      contains('# Pagar débitos: DT-05, DT-06'),
    );

    await tester.ensureVisible(find.byKey(const ValueKey('pay-cancel')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pay-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pay-debts-dialog')), findsNothing);
    // Cancelled: the selection stays.
    expect(c.read(debtsSelectionProvider), {'DT-05', 'DT-06'});
    await unmount(tester);
  });

  testWidgets('3 selecionados: a spec vem sugerida', (tester) async {
    await pumpScreen(tester, boardOf());
    await select(tester, ['DT-01', 'DT-03', 'DT-04']);
    await tester.tap(find.byKey(const ValueKey('debts-pay')));
    await tester.pumpAndSettle();
    expect(find.text('Pagar 3 débitos'), findsOneWidget);
    expect(find.text('sugerido · a partir de 3'), findsOneWidget);
    expect(find.text('até 2 débitos'), findsOneWidget);
    expect(find.text('Criar spec'), findsOneWidget);
    await unmount(tester);
  });
}
