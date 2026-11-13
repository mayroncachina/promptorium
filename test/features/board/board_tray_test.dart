import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/widgets/board_tray.dart';
import 'package:promptorium/ui/shell/navigation.dart';

import 'canvas_fixture.dart';

/// The Bandeja of the Quadro (SPEC-068 R7–R9).
void main() {
  Spec spec(
    String code, {
    SpecStatus status = SpecStatus.approved,
    SpecStage stage = SpecStage.backlog,
    bool inTray = false,
    int? conversation,
  }) => Spec(
    id: int.parse(code.substring(5)),
    workspaceId: 1,
    code: code,
    title: code,
    status: status,
    path: 'specs/$code.md',
    stage: stage,
    requirements: const [],
    dependsOn: const [],
    hasPlan: false,
    inTray: inTray,
    kind: SpecKind.spec,
    autoAdvance: true,
    reviewRounds: 0,
    gateResends: 0,
    rejectedHunks: 0,
    originConversationId: conversation,
  );

  test('approved and waiting stays out of the Quadro until taken (R8)', () {
    expect(isOnBoard(spec('SPEC-001', inTray: true)), isFalse);
    expect(isInTray(spec('SPEC-001', inTray: true)), isTrue);
    expect(canTakeFromTray(spec('SPEC-001', inTray: true)), isTrue);
    expect(isOnBoard(spec('SPEC-001')), isTrue, reason: 'already there');
    final draft = spec('SPEC-002', status: SpecStatus.draft, inTray: true);
    expect(isInTray(draft), isTrue);
    expect(canTakeFromTray(draft), isFalse, reason: 'approve it first');
    expect(
      isOnBoard(spec('SPEC-003', inTray: true, stage: SpecStage.running)),
      isTrue,
    );
    expect(
      isInTray(spec('SPEC-004', status: SpecStatus.archived, inTray: true)),
      isFalse,
    );
  });

  test('groups by conversation, newest first, "Outras" last (R7)', () {
    final groups = trayGroups([
      spec('SPEC-019', status: SpecStatus.draft, inTray: true),
      spec('SPEC-023', status: SpecStatus.draft, inTray: true, conversation: 7),
      spec('SPEC-021', inTray: true, conversation: 7),
      spec('SPEC-030', inTray: true, conversation: 9),
      spec('SPEC-018'),
    ]);
    expect(groups.map((g) => g.conversationId), [9, 7, null]);
    expect(groups[1].specs.map((s) => s.code), ['SPEC-021', 'SPEC-023']);
    expect(groups[2].specs.map((s) => s.code), ['SPEC-019']);
    expect(
      takenMessage(['SPEC-021', 'SPEC-022']),
      'SPEC-021 e SPEC-022 no '
      'Backlog',
    );
  });

  Future<(ProviderContainer, AppDatabase)> pumpTray(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    final r = await pumpCanvas(
      tester,
      const [
        CanvasSpec('SPEC-018', title: 'Busca de produtos'),
        CanvasSpec(
          'SPEC-021',
          title: 'Carrinho guarda os itens',
          inTray: true,
          conversationId: 1,
        ),
        CanvasSpec(
          'SPEC-022',
          title: 'Cupom de desconto no carrinho',
          inTray: true,
          deps: ['SPEC-021'],
          conversationId: 1,
        ),
        CanvasSpec(
          'SPEC-023',
          title: 'Pagamento com Pix',
          status: SpecStatus.draft,
          inTray: true,
          conversationId: 1,
        ),
        CanvasSpec(
          'SPEC-019',
          title: 'Tema escuro',
          status: SpecStatus.draft,
          inTray: true,
        ),
      ],
      view: BoardView.columns,
      size: size,
      overrides: (db) => [],
    );
    final (_, db) = r;
    await tester.runAsync(
      () => db
          .into(db.conversations)
          .insert(
            ConversationsCompanion.insert(
              workspaceId: 1,
              title: 'Checkout novo da loja',
              model: 'sonnet',
              createdAt: Value(DateTime.now()),
            ),
          ),
    );
    await pumpFor(tester, 20);
    return r;
  }

  testWidgets('"Bandeja · N" opens the panel: groups, states as text, '
      'approved ones checkable, drafts not (R7, R8, R9)', (tester) async {
    final semantics = tester.ensureSemantics();
    final (c, _) = await pumpTray(tester);
    expect(find.text('Bandeja'), findsOneWidget);
    expect(
      tester.widget<Text>(byKey('board-tray-count')).data,
      '4',
      reason: 'the old "N em rascunho fora do quadro" is gone',
    );
    expect(find.textContaining('fora do quadro'), findsNothing);
    expect(
      find.bySemanticsLabel('Bandeja, 4 specs fora do quadro, fechada'),
      findsOneWidget,
    );
    // Waiting specs are not cards of the Quadro.
    expect(byKey('board-card-SPEC-018'), findsOneWidget);
    expect(byKey('board-card-SPEC-021'), findsNothing);

    await tester.tap(byKey('board-tray-button'));
    await pumpFor(tester, 20);
    expect(byKey('board-tray'), findsOneWidget);
    expect(c.read(boardTrayOpenProvider), isTrue);
    expect(
      find.bySemanticsLabel('Bandeja, 4 specs fora do quadro, aberta'),
      findsOneWidget,
    );
    expect(
      find.text('DA CONVERSA “CHECKOUT NOVO DA LOJA” · 3'),
      findsOneWidget,
    );
    expect(find.text('OUTRAS · 1'), findsOneWidget);
    expect(
      tester.widget<Text>(byKey('board-tray-state-SPEC-021')).data,
      'Aprovada',
    );
    expect(
      tester.widget<Text>(byKey('board-tray-state-SPEC-023')).data,
      'Rascunho',
    );
    expect(byKey('board-tray-check-SPEC-021'), findsOneWidget);
    expect(byKey('board-tray-check-SPEC-023'), findsNothing);
    expect(find.text('aprove antes de levar'), findsNWidgets(2));
    expect(find.text('depende de SPEC-021'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('"Levar N para o Backlog" puts the checked ones on the Quadro, '
      'and "Desfazer" brings them back (R8)', (tester) async {
    await pumpTray(tester);
    await tester.tap(byKey('board-tray-button'));
    await pumpFor(tester, 20);
    expect(find.text('Levar para o Backlog'), findsOneWidget);

    await tester.tap(byKey('board-tray-check-SPEC-021'));
    await tester.tap(byKey('board-tray-check-SPEC-022'));
    await pumpFor(tester, 5);
    expect(find.text('Levar 2 para o Backlog'), findsOneWidget);
    expect(
      find.text('2 aprovadas marcadas · rascunhos se aprovam na spec'),
      findsOneWidget,
    );
    await tester.tap(byKey('board-tray-take'));
    await pumpFor(tester, 20);
    expect(byKey('board-card-SPEC-021'), findsOneWidget);
    expect(byKey('board-card-SPEC-022'), findsOneWidget);
    expect(byKey('board-tray-spec-SPEC-021'), findsNothing);
    expect(find.text('SPEC-021 e SPEC-022 no Backlog'), findsOneWidget);
    expect(tester.widget<Text>(byKey('board-tray-count')).data, '2');

    await tester.tap(find.text('Desfazer'));
    await pumpFor(tester, 20);
    expect(byKey('board-card-SPEC-021'), findsNothing);
    expect(byKey('board-tray-spec-SPEC-021'), findsOneWidget);
    expect(tester.widget<Text>(byKey('board-tray-count')).data, '4');
  });

  testWidgets('clicking a spec of the Bandeja opens it', (tester) async {
    final (c, _) = await pumpTray(tester);
    await tester.tap(byKey('board-tray-button'));
    await pumpFor(tester, 20);
    await tester.tap(find.text('Pagamento com Pix'));
    await pumpFor(tester, 5);
    expect(c.read(navigationProvider), AppSection.specs);
  });

  testWidgets('the Bandeja remembers being open, and the Quadro with it fits '
      'the minimum window (R7)', (tester) async {
    await loadAppFonts();
    final (c, _) = await pumpTray(tester, size: minimumBoard);
    await tester.tap(byKey('board-tray-button'));
    await pumpFor(tester, 20);
    expect(tester.takeException(), isNull);
    expect(c.read(appSettingsProvider.notifier).get('board.trayOpen.1'), '1');
    await tester.tap(byKey('board-tray-close'));
    await pumpFor(tester, 20);
    expect(byKey('board-tray'), findsNothing);
    expect(c.read(appSettingsProvider.notifier).get('board.trayOpen.1'), '0');
  });
}
