import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/debt_links_repo.dart';
import 'package:promptorium/features/debts/debt_actions.dart';
import 'package:promptorium/features/debts/debt_board.dart';
import 'package:promptorium/features/debts/debt_files.dart';
import 'package:promptorium/features/debts/debt_item.dart';
import 'package:promptorium/features/debts/debt_table.dart';
import 'package:promptorium/features/debts/widgets/debts_screen.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import 'debt_board_test.dart' show debtsText, decisionsText, link, spec;

final ws = Workspace(
  id: 1,
  path: '/r',
  name: 'inscricoes',
  createdAt: DateTime(2026),
);

Future<ProviderContainer> pumpScreen(
  WidgetTester tester,
  DebtBoard board, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseOverride(memoryDatabase()),
        debtsScreenWorkspaceProvider.overrideWithValue(ws),
        workspacesProvider.overrideWith((ref) => Stream.value([ws])),
        debtBoardProvider.overrideWith((ref, key) => board),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const MediaQuery(
          data: MediaQueryData(size: Size(1366, 768), disableAnimations: true),
          child: Scaffold(body: DebtsScreen()),
        ),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(DebtsScreen)));
}

DebtBoard boardOf({
  String? debts,
  String? decisions,
  List<DebtLink> links = const [],
  bool legacy = false,
  Map<int, DebtDocument> wt = const {},
}) => DebtBoard.build(
  snapshot: DebtSnapshot(
    repoRoot: '/r',
    config: const DebtsConfig(),
    debts: DebtDocument.parse(debts ?? debtsText, DebtKind.debt),
    decisions: DebtDocument.parse(
      decisions ?? decisionsText,
      DebtKind.decision,
    ),
    debtsExists: true,
    decisionsExists: true,
    legacyDebts: legacy ? DebtFiles.legacyDebts : null,
  ),
  links: links,
  specs: [spec(33, 'SPEC-033', wt: '/wt')],
  worktreeDebts: wt,
);

/// SPEC-112 R2, R5, R13, R18: the screen.
void main() {
  testWidgets('opens in Abertos, with the 7 open debts and the paid one '
      'behind "Pagos"', (tester) async {
    await pumpScreen(tester, boardOf());
    expect(find.byKey(const ValueKey('screen-debts')), findsOneWidget);
    expect(find.text('Abertos · 7'), findsOneWidget);
    expect(find.text('Pagos · 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('debt-row-DT-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('debt-row-DT-02')), findsNothing);
    expect(find.textContaining('Pagamento simulado'), findsOneWidget);
    expect(find.text('PagarView.vue'), findsOneWidget);
    expect(find.text('spec 29 · P3'), findsOneWidget);
    expect(find.text('DEBITO_TECNICO.md'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('debts-filter-right')));
    await tester.pump();
    expect(find.byKey(const ValueKey('debt-row-DT-02')), findsOneWidget);
    expect(find.byKey(const ValueKey('debt-row-DT-01')), findsNothing);
    expect(find.text('pago · spec 28'), findsOneWidget);
  });

  testWidgets('the tabs: Decisões opens in Pendentes', (tester) async {
    final pending = DebtTable.parse(decisionsText, DebtKind.decision).append([
      'DP-09',
      '2026-11-24',
      'spec 33, Q7',
      '**Limite?**',
      'Recusar.',
      '',
    ]);
    await pumpScreen(tester, boardOf(decisions: pending));
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('debts-tab-count-decisao')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '1',
    );
    await tester.tap(find.byKey(const ValueKey('debts-tab-decisao')));
    await tester.pump();
    expect(find.text('Pendentes · 1'), findsOneWidget);
    expect(find.text('Decididas · 8'), findsOneWidget);
    expect(find.byKey(const ValueKey('decision-card-DP-09')), findsOneWidget);
    expect(find.byKey(const ValueKey('decision-panel-DP-09')), findsOneWidget);
    expect(find.text('Recusar.'), findsOneWidget);
    expect(find.text('DECIDIDAS HÁ POUCO'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('decisions-filter-right')));
    await tester.pump();
    expect(find.byKey(const ValueKey('decision-card-DP-01')), findsOneWidget);
  });

  testWidgets('"N linhas não reconhecidas" shows the raw text (R5)', (
    tester,
  ) async {
    final odd = debtsText.replaceFirst(
      '| DT-03 |',
      '| nota solta |\n| DT-03 |',
    );
    await pumpScreen(tester, boardOf(debts: odd));
    expect(
      find.text('1 linha não reconhecida no arquivo · ver'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('debts-unrecognized')));
    await tester.pumpAndSettle();
    expect(find.textContaining('| nota solta |'), findsOneWidget);
  });

  testWidgets('selecting rows; "na spec N" and orphans are shown', (
    tester,
  ) async {
    final wt = DebtTable.parse(
      debtsText,
      DebtKind.debt,
    ).append(['DT-09', '2026-11-24', '**Upload fixo**: x.', '`a.py`', 'y']);
    final c = await pumpScreen(
      tester,
      boardOf(
        links: [
          link(1, code: 'DT-09', originSpecId: 33),
          link(2, code: 'DT-77'),
        ],
        wt: {33: DebtDocument.parse(wt, DebtKind.debt)},
      ),
    );
    expect(find.text('na spec 33'), findsOneWidget);
    expect(find.byKey(const ValueKey('debts-in-spec-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('debt-check-DT-09')), findsNothing);
    expect(find.textContaining('vínculo órfão: DT-77'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('debt-check-DT-05')));
    await tester.tap(find.byKey(const ValueKey('debt-check-DT-06')));
    await tester.pump();
    expect(c.read(debtsSelectionProvider), {'DT-05', 'DT-06'});
    expect(find.text('2 selecionados'), findsOneWidget);
    expect(find.text('DT-05, DT-06'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('debts-clear')));
    await tester.pump();
    expect(c.read(debtsSelectionProvider), isEmpty);
  });

  testWidgets('the old files of docs/ show the strip with both choices (R2)', (
    tester,
  ) async {
    await pumpScreen(tester, boardOf(legacy: true));
    expect(find.byKey(const ValueKey('debts-legacy')), findsOneWidget);
    expect(find.textContaining('docs/debitos-tecnicos.md'), findsOneWidget);
    expect(find.byKey(const ValueKey('debts-legacy-use')), findsOneWidget);
    expect(find.byKey(const ValueKey('debts-legacy-move')), findsOneWidget);
  });

  testWidgets('the commit dialog shows the message and asks (R18)', (
    tester,
  ) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => answer = await showDialog<bool>(
                context: context,
                builder: (_) => const DebtCommitDialog(
                  code: 'DT-09',
                  file: 'DEBITO_TECNICO.md',
                  branch: 'main',
                  message: 'docs: DT-09 lotes da equipe técnica',
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Commitar o DT-09 na main?'), findsOneWidget);
    expect(find.text('docs: DT-09 lotes da equipe técnica'), findsOneWidget);
    expect(find.textContaining('não faz push'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('debt-commit-later')));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });

  testWidgets('pending suggestions show in the strip on top', (tester) async {
    final l = DebtLink(
      id: 5,
      repoRoot: '/r',
      kind: 'debito',
      suggestionState: DebtSuggestionState.pending,
      suggestionSource: DebtSuggestionSource.mcp,
      suggestionBody:
          '{"titulo":"Comprovante sem QR Code","onde":"ComprovanteView.vue"}',
      createdAt: DateTime(2026),
    );
    await pumpScreen(tester, boardOf(links: [l]));
    expect(find.text('SUGESTÕES DO AGENTE · 1'), findsOneWidget);
    expect(find.textContaining('Comprovante sem QR Code'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('debt-suggestion-accept-5')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('debt-suggestion-discard-5')),
      findsOneWidget,
    );
    // The strip reads the specs from drift: unmount before the end.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
