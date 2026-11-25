import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/debt_links_repo.dart';
import 'package:promptorium/features/debts/debt_board.dart';
import 'package:promptorium/features/debts/widgets/debt_file_chip.dart';
import 'package:promptorium/features/debts/widgets/review_comment_debt.dart';
import 'package:promptorium/features/review/widgets/review_diff_view.dart';
import 'package:promptorium/features/sessions/session_changes.dart';
import 'package:promptorium/features/sessions/widgets/diff_raw_views.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import 'debt_board_test.dart' show link, snapshotOf, spec;

final spec33 = spec(33, 'SPEC-033', wt: '/wt');

DebtBoard boardWith({List<DebtLink> links = const []}) =>
    DebtBoard.build(snapshot: snapshotOf(), links: links, specs: [spec33]);

DebtLink piggyback(int id, String code, String state, {int spec = 33}) =>
    DebtLink(
      id: id,
      repoRoot: '/r',
      kind: 'debito',
      code: code,
      piggybackSpecId: spec,
      piggybackState: state,
      createdAt: DateTime(2026),
    );

DiffFile fileAt(String path) => DiffFile(
  oldPath: path,
  newPath: path,
  status: DiffFileStatus.modified,
  headerLines: const [],
  hunks: const [],
);

class _FakeLinks extends DebtLinksRepo {
  _FakeLinks(super.db);

  final updates = <(int, DebtLinksCompanion)>[];

  @override
  Future<void> update(int id, DebtLinksCompanion values) async {
    updates.add((id, values));
  }
}

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  DebtBoard? board,
  SessionChanges? changes,
  DebtLinksRepo? links,
}) async {
  tester.view.physicalSize = const Size(1366, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceDebtBoardProvider.overrideWith(
          (ref, id) => board ?? boardWith(),
        ),
        if (changes != null)
          sessionChangesProvider.overrideWith((ref, id) async => changes),
        if (links != null) debtLinksRepoProvider.overrideWithValue(links),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1366, 900),
            disableAnimations: true,
          ),
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// SPEC-112 R16, R17: the chips "N débitos neste arquivo" and the
/// "pago de carona?" marks in the diff, the Revisão and the card.
void main() {
  testWidgets('the chip: by path, by file name when "Onde" has only the '
      'name; a function without file has none; it opens the list', (
    tester,
  ) async {
    await pump(
      tester,
      const Column(
        children: [
          DebtFileChip(
            workspaceId: 1,
            path: 'frontend/src/lib/minhasInscricoes.js',
          ),
          DebtFileChip(workspaceId: 1, path: 'frontend/src/PagarView.vue'),
          DebtFileChip(workspaceId: 1, path: 'backend/coreografias_servico.py'),
          DebtFileChip(workspaceId: 1, path: 'backend/app/arquivos.py'),
        ],
      ),
    );
    expect(find.text('1 débito neste arquivo'), findsNWidgets(2));
    expect(
      find.byKey(
        const ValueKey('debt-file-chip-backend/coreografias_servico.py'),
      ),
      findsNothing,
    );
    // DT-02 (arquivos.py) is paid.
    expect(
      find.byKey(const ValueKey('debt-file-chip-backend/app/arquivos.py')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('debt-file-chip-frontend/src/PagarView.vue')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('debt-list-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('debt-list-DT-05')), findsOneWidget);
    expect(find.text('Pagamento simulado'), findsOneWidget);
    expect(find.text('PagarView.vue'), findsOneWidget);
    expect(find.text('Abrir Débitos e decisões'), findsOneWidget);
  });

  testWidgets('the diff of the session: the chip on the file and the '
      '"pago de carona?" of the spec with Confirmar / Recusar', (tester) async {
    final db = memoryDatabase();
    final links = _FakeLinks(db);
    await pump(
      tester,
      const SessionDiffView(sessionId: 's1', workspaceId: 1, specId: 33),
      board: boardWith(
        links: [piggyback(9, 'DT-03', DebtPiggybackState.toConfirm)],
      ),
      changes: SessionChanges(
        entries: const [
          GitStatusEntry(path: 'src/views/PagarView.vue', x: 'M', y: ' '),
        ],
        files: [fileAt('src/views/PagarView.vue')],
      ),
      links: links,
    );
    expect(
      find.byKey(const ValueKey('debt-file-chip-src/views/PagarView.vue')),
      findsOneWidget,
    );
    expect(find.text('1 débito neste arquivo'), findsOneWidget);
    expect(find.byKey(const ValueKey('piggyback-DT-03')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('piggyback-refuse-DT-03')));
    await tester.pump();
    expect(links.updates.single.$1, 9);
    expect(
      links.updates.single.$2.piggybackState,
      const Value(DebtPiggybackState.refused),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('the Revisão: the chip in the header of the file of a spec; '
      'none without spec', (tester) async {
    Widget diff(String path) => ReviewFileDiff(
      file: fileAt(path),
      comments: const [],
      accepted: const {},
      commentTarget: null,
      onOpenComment: (_) {},
      onCancelComment: () {},
      onSubmitComment: (_, _) {},
      onRemoveComment: (_) {},
      onRejectHunk: (_) {},
      onToggleAccept: (_) {},
      embedded: true,
    );
    await pump(
      tester,
      Column(
        children: [
          ReviewDebtScope(
            spec: spec33,
            workspaceId: 1,
            merged: false,
            child: diff('frontend/src/lib/minhasInscricoes.js'),
          ),
          diff('frontend/src/PagarView.vue'),
        ],
      ),
    );
    expect(
      find.byKey(
        const ValueKey('debt-file-chip-frontend/src/lib/minhasInscricoes.js'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('debt-file-chip-frontend/src/PagarView.vue')),
      findsNothing,
    );
  });

  testWidgets('the Revisão: confirming the "pago de carona?" records '
      '"confirmado"; the list of what the spec pays', (tester) async {
    final db = memoryDatabase();
    final links = _FakeLinks(db);
    await pump(
      tester,
      SpecReviewDebts(spec: spec33),
      board: boardWith(
        links: [
          piggyback(9, 'DT-03', DebtPiggybackState.toConfirm),
          link(10, code: 'DT-05', paymentSpecId: 33),
          piggyback(11, 'DT-06', DebtPiggybackState.confirmed),
          piggyback(12, 'DT-07', DebtPiggybackState.toConfirm, spec: 40),
        ],
      ),
      links: links,
    );
    expect(find.byKey(const ValueKey('piggyback-DT-03')), findsOneWidget);
    expect(find.byKey(const ValueKey('piggyback-DT-07')), findsNothing);
    expect(find.textContaining('riscada no merge da spec 33'), findsOneWidget);
    final paying = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('review-spec-paying')),
        matching: find.byType(Text),
      ),
    );
    final text = paying.textSpan!.toPlainText();
    expect(text, contains('Esta spec vai pagar: DT-05 Pagamento simulado'));
    expect(text, contains('DT-06'));
    expect(text, isNot(contains('DT-03')));
    await tester.tap(find.byKey(const ValueKey('piggyback-confirm-DT-03')));
    await tester.pump();
    expect(links.updates.single.$1, 9);
    expect(
      links.updates.single.$2.piggybackState,
      const Value(DebtPiggybackState.confirmed),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('the card of the Quadro: "N débitos nos arquivos" the spec '
      'changed and the "pago de carona?" tag', (tester) async {
    await pump(
      tester,
      SpecCardDebts(spec: spec33, sessionId: 's1'),
      board: boardWith(
        links: [piggyback(9, 'DT-03', DebtPiggybackState.toConfirm)],
      ),
      changes: SessionChanges(
        entries: const [
          GitStatusEntry(path: 'src/PagarView.vue', x: 'M', y: ' '),
          GitStatusEntry(
            path: 'frontend/src/lib/minhasInscricoes.js',
            x: 'M',
            y: ' ',
          ),
          GitStatusEntry(path: 'README.md', x: 'M', y: ' '),
        ],
      ),
    );
    expect(find.text('2 débitos nos arquivos'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('debt-card-piggyback-SPEC-033')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('debt-card-chip-SPEC-033')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('debt-list-DT-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('debt-list-DT-05')), findsOneWidget);
  });

  testWidgets('no debt in the files it changed: the card shows nothing', (
    tester,
  ) async {
    await pump(
      tester,
      SpecCardDebts(spec: spec33, sessionId: 's1'),
      changes: const SessionChanges(
        entries: [GitStatusEntry(path: 'README.md', x: 'M', y: ' ')],
      ),
    );
    expect(find.byKey(const ValueKey('debt-card-chip-SPEC-033')), findsNothing);
    expect(find.text('pago de carona?'), findsNothing);
  });
}
