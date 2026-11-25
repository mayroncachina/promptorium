import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/widgets/board_tray.dart';
import 'package:promptorium/features/debts/debt_board.dart';
import 'package:promptorium/features/debts/debt_files.dart';
import 'package:promptorium/features/debts/debt_item.dart';
import 'package:promptorium/features/debts/debt_table.dart';
import 'package:promptorium/features/debts/widgets/debts_screen.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import 'debt_board_test.dart' show debtsText, decisionsText, link, spec;

DebtBoard board(String debts, {List<DebtLink> links = const []}) =>
    DebtBoard.build(
      snapshot: DebtSnapshot(
        repoRoot: '/r',
        config: const DebtsConfig(),
        debts: DebtDocument.parse(debts, DebtKind.debt),
        decisions: DebtDocument.parse(decisionsText, DebtKind.decision),
        debtsExists: true,
      ),
      links: links,
      specs: [
        spec(35, 'SPEC-035'),
        spec(33, 'SPEC-033', wt: '/wt'),
      ],
      worktreeDebts: {
        // A row only in the worktree of spec 33: not in the count.
        33: DebtDocument.parse(
          '$debts| DT-09 | 2026-11-24 | **Upload** | `a.py` | x |\n',
          DebtKind.debt,
        ),
      },
    );

Future<ProviderContainer> pump(WidgetTester tester, DebtBoard? b) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        databaseOverride(memoryDatabase()),
        debtBoardProvider.overrideWith((ref, key) => b),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(child: BoardDebtsChip(workspaceId: 1, root: '/r')),
        ),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(BoardDebtsChip)));
}

/// SPEC-112 R14: the chip "Débitos · N" on the Quadro's bar.
void main() {
  testWidgets('conta só os abertos da branch principal (em pagamento '
      'inclusos, pagos e "na spec" fora) e abre a tela', (tester) async {
    final c = await pump(
      tester,
      board(debtsText, links: [link(1, code: 'DT-07', paymentSpecId: 35)]),
    );
    expect(find.text('Débitos · 7'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-debts-chip')));
    await tester.pump();
    expect(c.read(navigationProvider), AppSection.debts);
    expect(c.read(debtsTabProvider), DebtKind.debt);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('sem débitos abertos o chip some', (tester) async {
    final allPaid = debtsText
        .split('\n')
        .where((l) => !RegExp(r'^\| DT-').hasMatch(l))
        .join('\n');
    expect(
      DebtDocument.parse(allPaid, DebtKind.debt).debts.every((d) => d.paid),
      isTrue,
    );
    await pump(tester, board(allPaid));
    expect(find.byKey(const ValueKey('board-debts-chip')), findsNothing);
    await pump(tester, null);
    expect(find.byKey(const ValueKey('board-debts-chip')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
