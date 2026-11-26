import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/providers/capabilities.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/restore/restore_service.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/restore_points_section.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';
import 'package:promptorium/features/sessions/widgets/timeline_view.dart';
import 'package:promptorium/features/sessions/widgets/undo_dialog.dart';

/// SPEC-084 R5, R6, R7, R9, R10, R11, R12, R16: the header button, the
/// undo window, the panel section and the marker of the timeline.
void main() {
  RestorePoint point({
    int id = 4,
    int turn = 4,
    String state = RestoreState.active,
    bool ended = true,
    int changed = 41,
    int commits = 1,
    int files = 3,
    String? undoneSha,
    DateTime? at,
  }) => RestorePoint(
    id: id,
    workspaceId: 1,
    sessionId: 's1',
    worktreePath: '/r',
    turn: turn,
    prompt: 'Renomeie Pedido para Order no projeto todo e faça um commit.',
    startedAt: at ?? DateTime(2026, 11, 17, 14, 2),
    startBranch: 'main',
    startHead: '9f8e7d6aaaa',
    startSha: 'b' * 40,
    endedAt: ended ? DateTime(2026, 11, 17, 14, 6) : null,
    files: files,
    bytes: 100,
    changedFiles: changed,
    commits: commits,
    largeFiles: '[]',
    state: state,
    undoneSha: undoneSha,
    usedAt: DateTime(2026, 11, 17),
  );

  const m = TreeChangeKind.modified;
  UndoPlan examplePlan({
    bool pushed = false,
    ConversationPlan? conversation,
  }) => buildUndoPlan(
    conversation: conversation,
    turn: [
      const TreeChange(
        path: 'src/checkout/checkout.ts',
        kind: m,
        added: 12,
        removed: 12,
      ),
      const TreeChange(path: 'src/order.ts', kind: TreeChangeKind.created),
      const TreeChange(path: 'src/pedido.ts', kind: TreeChangeKind.deleted),
      const TreeChange(path: 'src/api/rotas.ts', kind: m, added: 3, removed: 3),
      const TreeChange(path: 'src/checkout/checkout.spec.ts', kind: m),
    ],
    after: [const TreeChange(path: 'src/checkout/checkout.spec.ts', kind: m)],
    editedDuring: {'src/api/rotas.ts'},
    editedAt: {'src/checkout/checkout.spec.ts': DateTime(2026, 11, 17, 14, 9)},
    commits: [
      GitLogEntry(
        sha: 'a1b2c3d4',
        shortSha: 'a1b2c3d',
        author: 'a',
        date: DateTime(2026),
        subject: 'wip: renomeia Pedido',
      ),
    ],
    pushed: pushed ? {'a1b2c3d4'} : const {},
    remotes: pushed ? ['origin/feat/order'] : const [],
    kept: ['src/cupom.ts'],
    ignored: ['.env'],
    large: ['dump.sql'],
    others: {
      'Ajustar CSS': {'src/checkout/checkout.ts'},
    },
    startBranch: 'main',
    currentBranch: 'main',
    startHead: '9f8e7d6aaaa',
  );

  Future<void> pumpDialog(
    WidgetTester tester,
    UndoPlan plan, {
    required List<UndoChoice> got,
    bool busy = false,
    Future<UndoPlan> Function()? onStop,
    Object? fail,
    bool redo = false,
    bool latest = true,
  }) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UndoDialog(
            point: point(),
            plan: Future.value(plan),
            busy: busy,
            redo: redo,
            latest: latest,
            onStop: onStop,
            onConfirm: (c) async {
              if (fail != null) throw fail;
              got.add(c);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the window lists what goes back, unchecks what the person '
      'changed after and confirms only the checked files', (tester) async {
    final got = <UndoChoice>[];
    await pumpDialog(tester, examplePlan(), got: got);
    expect(find.text('Desfazer o turno 4?'), findsOneWidget);
    expect(find.textContaining('às 14:02, antes de “Renomeie'), findsOneWidget);
    expect(find.text('ARQUIVOS QUE VOLTAM · 4'), findsOneWidget);
    expect(find.text('criado no turno · será apagado'), findsOneWidget);
    expect(find.text('apagado no turno · volta'), findsOneWidget);
    expect(find.text('+12 −12'), findsOneWidget);
    expect(find.text('você também editou durante o turno'), findsOneWidget);
    expect(find.text('VOCÊ MUDOU DEPOIS DO TURNO · 1'), findsOneWidget);
    expect(find.text('editado por você às 14:09 · fica'), findsOneWidget);
    expect(find.text('COMMIT DESCARTADO · 1'), findsOneWidget);
    expect(
      find.textContaining('só local · main volta para 9f8e7d6'),
      findsOneWidget,
    );
    expect(find.text('NÃO VOLTA'), findsOneWidget);
    expect(find.textContaining('dump.sql', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('src/cupom.ts não mudou neste turno'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('undo-other-Ajustar CSS')),
      findsOneWidget,
    );

    Checkbox box(String p) =>
        tester.widget<Checkbox>(find.byKey(ValueKey('undo-check-$p')));
    expect(box('src/order.ts').value, isTrue);
    expect(box('src/checkout/checkout.spec.ts').value, isFalse);
    expect(find.text('Desfazer 4 arquivos e 1 commit'), findsOneWidget);

    // Unchecking one, checking the person's (and the warning).
    await tester.tap(find.byKey(const ValueKey('undo-check-src/order.ts')));
    await tester.tap(
      find.byKey(const ValueKey('undo-check-src/checkout/checkout.spec.ts')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('undo-lost-edit')), findsOneWidget);
    expect(find.text('Desfazer 4 arquivos e 1 commit'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('undo-confirm')));
    await tester.pumpAndSettle();
    expect(got.single.paths, {
      'src/checkout/checkout.ts',
      'src/pedido.ts',
      'src/api/rotas.ts',
      'src/checkout/checkout.spec.ts',
    });
    expect(got.single.filesOnly, isFalse);
  });

  testWidgets('a pushed commit: the warning and "Desfazer só os arquivos"', (
    tester,
  ) async {
    final got = <UndoChoice>[];
    await pumpDialog(tester, examplePlan(pushed: true), got: got);
    expect(find.byKey(const ValueKey('undo-pushed')), findsOneWidget);
    expect(find.textContaining('origin/feat/order'), findsWidgets);
    expect(find.textContaining('--force'), findsOneWidget);
    expect(find.text('Desfazer só os arquivos'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('undo-confirm')));
    await tester.pumpAndSettle();
    expect(got.single.filesOnly, isTrue);
  });

  testWidgets('a failure stays in the window', (tester) async {
    await pumpDialog(
      tester,
      examplePlan(),
      got: [],
      fail: const RestoreException('Não deu para desfazer: disco cheio.'),
    );
    await tester.tap(find.byKey(const ValueKey('undo-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Não deu para desfazer: disco cheio.'), findsOneWidget);
    expect(find.byType(UndoDialog), findsOneWidget);
  });

  testWidgets('with the session in a turn only "Parar e desfazer" (P3)', (
    tester,
  ) async {
    var stopped = 0;
    await pumpDialog(
      tester,
      examplePlan(),
      got: [],
      busy: true,
      onStop: () async {
        stopped++;
        return examplePlan();
      },
    );
    expect(find.byKey(const ValueKey('undo-confirm')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('undo-stop')));
    await tester.pumpAndSettle();
    expect(stopped, 1);
    expect(find.byKey(const ValueKey('undo-confirm')), findsOneWidget);
  });

  group('session screen', () {
    late StreamController<List<RestorePoint>> points;

    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      bool busy = false,
    }) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      points = StreamController<List<RestorePoint>>.broadcast();
      addTearDown(points.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRestorePointsProvider.overrideWith(
              (ref, id) => points.stream,
            ),
            sessionManagerProvider.overrideWith(() => _FakeManager(busy)),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );
    }

    Session session() => Session(
      id: 's1',
      workspaceId: 1,
      worktreePath: '/r',
      branch: 'main',
      status: SessionStatus.completed,
      model: 'opus',
      provider: 'claude',
      costUsd: 0,
      tokensIn: 0,
      tokensOut: 0,
      startedAt: DateTime(2026, 11, 17),
    );

    testWidgets('the button shows up with a point, says what it does and is '
        'off while a turn runs', (tester) async {
      await pump(tester, UndoLastTurnButton(session: session()));
      expect(find.byKey(const ValueKey('session-undo-turn')), findsNothing);
      points.add([point()]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Desfazer o último turno'), findsOneWidget);
      expect(
        find.byTooltip(
          'Volta os arquivos e commits ao que eram antes do turno 4 (14:02)',
        ),
        findsOneWidget,
      );
      // Only undone points: no button.
      points.add([point(state: RestoreState.undone)]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('session-undo-turn')), findsNothing);
    });

    testWidgets('busy: disabled with the hint', (tester) async {
      await pump(tester, UndoLastTurnButton(session: session()), busy: true);
      points.add([point()]);
      await tester.pump();
      await tester.pump();
      expect(
        find.byTooltip('Espere o turno terminar ou pare a sessão'),
        findsOneWidget,
      );
      final InkWell ink = tester.widget(
        find.descendant(
          of: find.byKey(const ValueKey('session-undo-turn')),
          matching: find.byType(InkWell),
        ),
      );
      expect(ink.onTap, isNull);
    });

    testWidgets('the panel section: newest first, states, Refazer and '
        '"Ver todos"', (tester) async {
      await pump(
        tester,
        SizedBox(width: 300, child: RestorePointsSection(session: session())),
      );
      points.add([
        for (var t = 7; t >= 1; t--)
          point(
            id: t,
            turn: t,
            state: t == 7 ? RestoreState.undone : RestoreState.active,
            undoneSha: t == 7 ? 'c' * 40 : null,
            changed: t == 3 ? 0 : 41,
            commits: t == 3 ? 0 : 1,
            ended: t != 6,
          ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('PONTOS DE RESTAURAÇÃO'), findsOneWidget);
      expect(find.text('Turno 7 · 14:02'), findsOneWidget);
      expect(find.text('desfeito'), findsOneWidget);
      expect(find.byKey(const ValueKey('restore-redo-7')), findsOneWidget);
      expect(find.text('em andamento'), findsOneWidget);
      expect(
        find.text('41 arquivos · 1 commit · 3 não commitados guardados'),
        findsWidgets,
      );
      expect(find.byKey(const ValueKey('restore-point-2')), findsNothing);
      await tester.tap(find.text('Ver todos (7)'));
      await tester.pump();
      expect(find.byKey(const ValueKey('restore-point-2')), findsOneWidget);
      expect(find.text('só leitura · nada mudou'), findsOneWidget);
      // The menu of a point.
      await tester.tap(find.byKey(const ValueKey('restore-menu-5')));
      await tester.pumpAndSettle();
      expect(find.text('Voltar a antes deste turno…'), findsOneWidget);
    });
  });

  testWidgets('the marker beside the time of a message (R10)', (tester) async {
    final p = point(at: DateTime(2026, 11, 17, 14, 2, 5));
    final first = UserItem(
      'Mostre onde a classe Pedido é usada.',
      at: DateTime(2026, 11, 17, 13, 40),
    );
    final second = UserItem(
      'Renomeie Pedido para Order.',
      at: DateTime(2026, 11, 17, 14, 2, 5, 700),
    );
    final notice = UserItem(
      'O usuário editou x manualmente',
      at: DateTime(2026, 11, 17, 14, 3),
    );
    final byMsg = restorePointsByMessage(
      [first, second, notice],
      (m) => (m as UserItem).at,
      [p],
    );
    expect(byMsg.keys, [second]);
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineItemView(
            item: second,
            userMarker: (u) => byMsg[u] == null
                ? null
                : RestorePointMarker(point: byMsg[u]!, onTap: () => opened++),
          ),
        ),
      ),
    );
    expect(find.text('ponto'), findsOneWidget);
    expect(
      find.byTooltip(
        'Ponto de restauração: 14:02 · 3 arquivos não commitados guardados',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('ponto'));
    expect(opened, 1);
  });

  group('SPEC-110 · Conversa do agente', () {
    const codex = ConversationPlan(
      provider: 'codex',
      agent: 'Codex',
      firstTurn: 3,
      lastTurn: 5,
      beforeTurnId: 't3',
    );
    Checkbox box(WidgetTester tester) => tester.widget<Checkbox>(
      find.byKey(const ValueKey('undo-conversation-check')),
    );

    testWidgets('R7: no Codex, a caixa vem marcada, diz o efeito e a cópia, e '
        'entra no botão; desmarcada, só os arquivos', (tester) async {
      final got = <UndoChoice>[];
      await pumpDialog(
        tester,
        examplePlan(conversation: codex),
        got: got,
        latest: false,
      );
      expect(find.text('CONVERSA DO AGENTE'), findsOneWidget);
      expect(box(tester).value, isTrue);
      expect(
        find.text('Voltar também a conversa do Codex para antes do turno 3'),
        findsOneWidget,
      );
      expect(
        find.text(
          'O Codex esquece os turnos 3 a 5. A timeline do app continua '
          'mostrando os turnos, marcados como revertidos.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('undo-conversation-copy')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Desfazer 4 arquivos, 1 commit e os turnos 3 a 5 da conversa',
        ),
        findsOneWidget,
      );
      final toggle = find.byKey(const ValueKey('undo-conversation-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(box(tester).value, isFalse);
      expect(
        find.byKey(const ValueKey('undo-conversation-copy')),
        findsNothing,
      );
      expect(find.text('Desfazer 4 arquivos e 1 commit'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('undo-confirm')));
      await tester.pumpAndSettle();
      expect(got.single.revertConversation, isTrue);
    });

    testWidgets('R11: o rótulo completo da caixa para o leitor de tela', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpDialog(
        tester,
        examplePlan(
          conversation: const ConversationPlan(
            provider: 'codex',
            agent: 'Codex',
            firstTurn: 4,
            lastTurn: 4,
            beforeTurnId: 't4',
          ),
        ),
        got: [],
      );
      final node = tester.getSemantics(
        find.byKey(const ValueKey('undo-conversation-box')),
      );
      expect(
        node.label,
        'Voltar também a conversa do Codex para antes do turno 4. O Codex '
        'esquece o turno 4. A timeline do app continua mostrando o turno, '
        'marcado como revertido.',
      );
      expect(node.flagsCollection.isChecked.name, 'isTrue');
      handle.dispose();
    });

    testWidgets('R7: no Claude, desabilitada com "Só Codex" e a dica', (
      tester,
    ) async {
      final got = <UndoChoice>[];
      await pumpDialog(
        tester,
        examplePlan(
          conversation: ConversationPlan(
            provider: 'claude',
            agent: 'Claude Code',
            firstTurn: 4,
            lastTurn: 4,
            onlyCodex: true,
            reason: ProviderCapabilities.claude.reasonFor(
              ProviderCapability.revertConversation,
            ),
          ),
        ),
        got: got,
      );
      const why =
          'Só Codex: o Claude Code não volta a conversa no modo do app; o '
          'agente recebe o aviso.';
      expect(box(tester).value, isFalse);
      expect(box(tester).onChanged, isNull);
      expect(find.text(why), findsOneWidget);
      expect(find.byTooltip(why), findsOneWidget);
      expect(find.text('Desfazer 4 arquivos e 1 commit'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('undo-confirm')));
      await tester.pumpAndSettle();
      expect(got.single.revertConversation, isFalse);
    });

    testWidgets('R6: sem turno identificado, o motivo; um turno só de leitura '
        'dá para desfazer só na conversa', (tester) async {
      await pumpDialog(
        tester,
        const UndoPlan(
          conversation: ConversationPlan(
            provider: 'codex',
            agent: 'Codex',
            firstTurn: 4,
            lastTurn: 4,
            reason:
                'O turno do Codex deste ponto não foi identificado: só os '
                'arquivos voltam.',
          ),
        ),
        got: [],
      );
      expect(box(tester).onChanged, isNull);
      expect(find.textContaining('não foi identificado'), findsOneWidget);
      expect(find.textContaining('Só Codex'), findsNothing);
      SmallButton confirm() => tester.widget<SmallButton>(
        find.byKey(const ValueKey('undo-confirm')),
      );
      expect(confirm().onTap, isNull);
      await tester.pumpWidget(const SizedBox());
      await pumpDialog(tester, const UndoPlan(conversation: codex), got: []);
      expect(confirm().label, 'Desfazer os turnos 3 a 5 da conversa');
      expect(confirm().onTap, isNotNull);
    });

    testWidgets('R9: no Refazer, a cópia usada ou o aviso de que não há', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        examplePlan(
          conversation: ConversationPlan(
            provider: 'codex',
            agent: 'Codex',
            firstTurn: 3,
            lastTurn: 5,
            copyAt: DateTime(2026, 11, 17, 14, 20),
          ),
        ),
        got: [],
        redo: true,
      );
      expect(
        find.text(
          'A sessão volta para a cópia da conversa de 14:20: o Codex lembra '
          'de novo dos turnos 3 a 5.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('undo-conversation-check')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await pumpDialog(
        tester,
        examplePlan(
          conversation: const ConversationPlan(
            provider: 'codex',
            agent: 'Codex',
            firstTurn: 3,
            lastTurn: 3,
            reason: 'Não há cópia da conversa: só os arquivos voltam.',
          ),
        ),
        got: [],
        redo: true,
      );
      expect(find.textContaining('Não há cópia'), findsOneWidget);
    });
  });

  test('the timeline note after an undo', () {
    expect(
      undoneNote(
        const UndoOutcome(
          turn: 4,
          files: 41,
          commits: ['wip: renomeia Pedido'],
        ),
      ),
      'Turno 4 desfeito: 41 arquivos, 1 commit (wip).',
    );
    expect(
      undoneNote(const UndoOutcome(turn: 2, files: 1)),
      'Turno 2 desfeito: 1 arquivo.',
    );
  });
}

class _FakeManager extends SessionManager {
  _FakeManager(this.busy);

  final bool busy;

  @override
  SessionManagerState build() => SessionManagerState(
    live: {if (busy) 's1': LiveSession(busySince: DateTime(2026, 11, 17, 14))},
  );
}
