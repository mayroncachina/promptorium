import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/debts/debt_table.dart';
import 'package:promptorium/features/debts/widgets/debts_screen.dart';

import 'debt_board_test.dart' show decisionsText, link;
import 'debts_screen_test.dart' show boardOf, pumpScreen;

/// SPEC-112 R12: answering a decision on the "Decisões" tab.
void main() {
  String withPending({String decision = ''}) =>
      DebtTable.parse(decisionsText, DebtKind.decision).append([
        'DP-09',
        '2026-11-24',
        '[Spec 33](docs/specs/SPEC-033-limite.md) Q7',
        '**Arquivo acima do limite: recusar no envio ou comprimir?**',
        'Recusar no envio.',
        decision,
      ]);

  testWidgets('a pending decision shows "Decisão", "Levar a resposta para a '
      'spec 33" with the preview and the line the app writes', (tester) async {
    await pumpScreen(
      tester,
      boardOf(
        decisions: withPending(),
        links: [link(90, code: 'DP-09', originSpecId: 33)],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('debts-tab-decisao')));
    await tester.pump();
    expect(find.byKey(const ValueKey('decision-panel-DP-09')), findsOneWidget);
    expect(find.text('Levar a resposta para a spec 33'), findsOneWidget);
    final save = find.byKey(const ValueKey('decision-save'));
    expect(save, findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('decision-answer')),
      'Recusar no envio, como recomendado.',
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('decision-spec-preview')))
          .data,
      'Q7 → DP-09: Recusar no envio, como recomendado.',
    );
    final line = tester
        .widget<Text>(find.byKey(const ValueKey('decision-line')))
        .data!;
    expect(line, startsWith('| DP-09 | 2026-11-24 | [Spec 33]'));
    expect(
      line,
      matches(
        RegExp(
          r'\*\*Decidido \(\d{4}-\d{2}-\d{2}\):\*\* Recusar no envio, '
          r'como recomendado\. \|$',
        ),
      ),
    );
    expect(find.byKey(const ValueKey('decision-to-debt-offer')), findsNothing);
  });

  testWidgets('a decided one offers "Virar débito" until it generated one', (
    tester,
  ) async {
    final c = await pumpScreen(
      tester,
      boardOf(
        decisions: withPending(
          decision:
              '**Decidido (2026-11-24):** Recusar no envio. Comprimir no '
              'servidor fica para depois.',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('debts-tab-decisao')));
    await tester.pump();
    c.read(selectedDecisionProvider.notifier).select('DP-09');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('decision-to-debt-offer')),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '“Comprimir no servidor fica para depois” pode virar',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('decision-answer')), findsNothing);
  });
}
