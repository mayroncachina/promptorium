import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart' show cliRunnerProvider;
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/issues/issue_availability.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/widgets/board_tray.dart';
import 'package:promptorium/ui/shell/navigation.dart';

import '../../core/git/fake_issues.dart';
import '../specs/specs_screen_test.dart' show settleIo;
import 'canvas_fixture.dart';

/// The Bandeja of the Quadro (SPEC-068 R7–R9).
void main() {
  Spec spec(
    String code, {
    SpecStatus status = SpecStatus.approved,
    SpecStage stage = SpecStage.backlog,
    bool inTray = false,
    int? conversation,
    DateTime? imported,
    int? issue,
  }) => Spec(
    issueImportedAt: imported,
    issueNumber: issue,
    issueCommentPending: false,
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

  test('the specs imported from issues have their own group, before '
      '"Outras" (SPEC-074 R5)', () {
    final at = DateTime(2026, 11, 15);
    final groups = trayGroups([
      spec('SPEC-019', status: SpecStatus.draft, inTray: true),
      spec(
        'SPEC-025',
        status: SpecStatus.draft,
        inTray: true,
        imported: at,
        issue: 215,
      ),
      spec(
        'SPEC-024',
        status: SpecStatus.draft,
        inTray: true,
        imported: at,
        issue: 212,
      ),
      spec('SPEC-030', inTray: true, conversation: 9),
      // Linked by hand (issue: in the file), not imported: "Outras".
      spec('SPEC-031', inTray: true, issue: 240),
    ]);
    expect(groups.map((g) => (g.conversationId, g.fromIssues)), [
      (9, false),
      (null, true),
      (null, false),
    ]);
    expect(groups[1].specs.map((s) => s.code), ['SPEC-024', 'SPEC-025']);
    expect(groups[2].specs.map((s) => s.code), ['SPEC-019', 'SPEC-031']);
  });

  group('"Importar issues" (SPEC-074 R3, R4, R5, R12)', () {
    late Directory root;
    late FakeIssuesGh gh;

    Future<(ProviderContainer, AppDatabase)> pumpImport(
      WidgetTester tester, {
      IssueAvailability avail = const IssueAvailability.ok(
        repo: 'ana-souza/loja-da-ana',
      ),
    }) async {
      root = Directory.systemTemp.createTempSync('tray-issues-');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/specs').createSync();
      File('${root.path}/specs/SPEC-023.md').writeAsStringSync(
        '---\nid: SPEC-023\nstatus: aprovada\nissue: 226\n---\n# Pix\n',
      );
      gh = FakeIssuesGh()
        ..add(231, 'Cupom expira no meio do pagamento', labels: ['bug'])
        ..add(229, 'Endereço duplicado', labels: ['bug', 'checkout'])
        ..add(226, 'Pix com QR code na confirmação', labels: ['checkout'])
        ..add(
          218,
          'Frete grátis acima de R\$ 199',
          body: '![a](x.png) ![b](y.png)',
          milestone: 'v1.2',
        )
        ..add(
          215,
          'Cupom não aplica em produto já com desconto',
          body: '- [ ] a\n- [ ] b\n- [ ] c',
          assignees: ['ana-souza'],
        )
        ..add(212, 'Carrinho some ao trocar de aba', labels: ['checkout'])
        ..add(220, 'PR do frete', pr: true);
      final r = await pumpCanvas(
        tester,
        const [
          CanvasSpec('SPEC-018', title: 'Busca de produtos'),
          CanvasSpec('SPEC-023', title: 'Pix com QR code'),
        ],
        path: root.path,
        view: BoardView.columns,
        overrides: (db) => [
          cliRunnerProvider.overrideWithValue(gh.call),
          issueAvailabilityProvider.overrideWith((ref, _) async => avail),
        ],
      );
      final (c, _) = r;
      // In the zone of the test: the locks of the database were made there.
      var synced = false;
      c
          .read(specServiceProvider)
          .sync(c.read(activeWorkspaceProvider)!)
          .then((_) => synced = true);
      await settleIo(tester, until: () => synced);
      await tester.tap(byKey('board-tray-button'));
      await settleIo(
        tester,
        until: () => byKey('board-tray').evaluate().isNotEmpty,
      );
      return r;
    }

    String? fileOf(String code) {
      for (final f in Directory('${root.path}/specs').listSync()) {
        if (f is File && f.path.contains(code)) return f.readAsStringSync();
      }
      return null;
    }

    testWidgets('3 issues become 3 drafts with issue: N in the group "Das '
        'issues do GitHub"; the imported one is locked; PRs never show', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpImport(tester);
      await tester.tap(byKey('issue-import-button'));
      await settleIo(
        tester,
        until: () => byKey('issue-import-row-212').evaluate().isNotEmpty,
      );
      expect(
        tester.widget<Text>(byKey('issue-import-count')).data,
        '6 issues abertas com estes filtros · mostrando 6',
      );
      expect(byKey('issue-import-row-220'), findsNothing, reason: 'a PR');
      // Already imported: locked, with "Abrir", out of the checkboxes.
      expect(find.text('já importada · SPEC-023'), findsOneWidget);
      expect(byKey('issue-import-check-226'), findsNothing);
      expect(byKey('issue-import-open-226'), findsOneWidget);
      expect(find.text('checklist · 3 itens'), findsNothing);
      expect(find.textContaining('checklist · 3 itens'), findsOneWidget);
      expect(find.textContaining('2 imagens'), findsOneWidget);

      for (final n in [212, 215, 218]) {
        await tester.tap(byKey('issue-import-check-$n'));
        await tester.pump();
      }
      expect(find.text('Importar 3 issues'), findsOneWidget);
      expect(
        tester
            .widget<Text>(byKey('issue-import-code-215'))
            .textSpan!
            .toPlainText(),
        'vira SPEC-025',
      );
      await tester.tap(byKey('issue-import-confirm'));
      await settleIo(
        tester,
        until: () => byKey('issue-import-dialog').evaluate().isEmpty,
      );
      await settleIo(
        tester,
        until: () => find
            .text('3 issues viraram SPEC-024 a SPEC-026, na Bandeja')
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('Abrir a primeira'), findsOneWidget);
      for (final (code, n) in [
        ('SPEC-024', 212),
        ('SPEC-025', 215),
        ('SPEC-026', 218),
      ]) {
        final doc = SpecDocument.parse(fileOf(code)!);
        expect(doc.issue, n);
        expect(doc.status, SpecStatus.draft);
        expect(byKey('board-tray-spec-$code'), findsOneWidget);
      }
      expect(find.text('DAS ISSUES DO GITHUB · 3'), findsOneWidget);
      expect(find.text('#215'), findsOneWidget);
      expect(gh.writes, isEmpty, reason: 'nothing changes on GitHub');

      // Opened again: the three are locked now.
      await tester.tap(byKey('issue-import-button'));
      await settleIo(
        tester,
        until: () => byKey('issue-import-row-212').evaluate().isNotEmpty,
      );
      expect(find.text('já importada · SPEC-024'), findsOneWidget);
      expect(byKey('issue-import-check-212'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleIo(tester);
      expect(byKey('issue-import-dialog'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      semantics.dispose();
    });

    testWidgets('keyboard only: Tab reaches the boxes, Space checks, the '
        'locked one is skipped, Enter imports (R12)', (tester) async {
      await pumpImport(tester);
      await tester.tap(byKey('issue-import-button'));
      await settleIo(
        tester,
        until: () => byKey('issue-import-row-212').evaluate().isNotEmpty,
      );
      // From the search field to the first box of the list.
      Checkbox focused() => tester.widget<Checkbox>(
        find.byWidgetPredicate(
          (w) =>
              w is Checkbox &&
              Focus.of(tester.element(find.byWidget(w))).hasFocus,
        ),
      );
      var guard = 0;
      while (find
              .byWidgetPredicate(
                (w) =>
                    w is Checkbox &&
                    Focus.of(tester.element(find.byWidget(w))).hasFocus,
              )
              .evaluate()
              .isEmpty &&
          guard++ < 20) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      final first = focused().key;
      expect(first, const ValueKey('issue-import-check-231'));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('Importar 1 issue'), findsOneWidget);
      // 231 → 229 → (226 is locked: its "Abrir" comes, not a box) …
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused().key, const ValueKey('issue-import-check-229'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(
          tester.element(
            find.descendant(
              of: byKey('issue-import-open-226'),
              matching: find.text('Abrir'),
            ),
          ),
        ).hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused().key, const ValueKey('issue-import-check-218'));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('Importar 2 issues'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleIo(
        tester,
        until: () => byKey('issue-import-dialog').evaluate().isEmpty,
      );
      await settleIo(tester, until: () => fileOf('SPEC-025') != null);
      expect(
        fileOf('SPEC-024'),
        isNotNull,
        reason: Directory('${root.path}/specs').listSync().join(', '),
      );
      expect(SpecDocument.parse(fileOf('SPEC-024')!).issue, 231);
      expect(SpecDocument.parse(fileOf('SPEC-025')!).issue, 218);
      // The folder watcher's debounce.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('without GitHub: the reason and "Conferir de novo" (R2)', (
      tester,
    ) async {
      await pumpImport(
        tester,
        avail: const IssueAvailability.unavailable(
          IssueProblem.ghLoggedOut,
          'O gh não está logado em github.com. Rode gh auth login.',
        ),
      );
      final tip = tester.widget<Tooltip>(
        find
            .ancestor(
              of: byKey('issue-import-button'),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(tip.message, contains('não está logado'));
      await tester.tap(byKey('issue-import-button'));
      await settleIo(
        tester,
        until: () => byKey('issue-import-unavailable').evaluate().isNotEmpty,
      );
      expect(find.text('O gh não está logado em github.com'), findsOneWidget);
      expect(byKey('issue-import-recheck'), findsOneWidget);
      expect(byKey('issue-import-copy'), findsOneWidget);
      expect(gh.calls, isEmpty);
    });
  });
}
