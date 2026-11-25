import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/text/line_diff.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/restore_points_repo.dart';
import 'package:promptorium/features/sessions/conversation_events.dart';
import 'package:promptorium/features/sessions/replay/replay_data.dart';
import 'package:promptorium/features/sessions/replay/replay_view.dart';
import 'package:promptorium/features/sessions/sessions_screen.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';

import '../sessions_screen_test.dart'
    show assistant, pumpFor, pumpScreen, root, toolResult, toolUse;
import 'replay_fixtures.dart';

/// A finished session: two turns, a read, an edit, a failing command, a
/// subagent and a gate that failed.
final replayEvents = <Map<String, dynamic>>[
  AppEventTypes.userMessage('Implemente a R2', DateTime(2026, 11, 16, 14)),
  assistant([
    toolUse('t_read', 'Read', {'file_path': '$root/lib/a.dart'}),
  ]),
  toolResult('t_read', '     1\tx\n     2\tw'),
  assistant([
    {'type': 'text', 'text': 'O gh devolve 1; vou ignorar esse caso.'},
  ]),
  assistant([
    toolUse('t_edit', 'Edit', {
      'file_path': '$root/lib/a.dart',
      'old_string': 'x',
      'new_string': 'y\nz',
    }),
  ]),
  toolResult('t_edit', 'ok'),
  assistant([
    toolUse('t_bash', 'Bash', {
      'command': 'flutter test',
      'description': 'Roda os testes',
    }),
  ]),
  toolResult(
    't_bash',
    'Exit code 1\n00:46 +12 -1: falhou [E]\nSome tests failed.',
    error: true,
  ),
  AppEventTypes.noteMessage(
    'Verificação falhou: ✗ testes',
    error: true,
    at: DateTime(2026, 11, 16, 14, 5),
  ),
  AppEventTypes.userMessage(
    'o gate reprovou: o CI fica verde',
    DateTime(2026, 11, 16, 14, 6),
  ),
  assistant([
    toolUse('t_task', 'Task', {
      'description': 'ache onde o CI é lido',
      'prompt': 'procure o leitor do CI',
      'subagent_type': 'Explore',
    }),
  ]),
  assistant(
    [
      toolUse('t_sub_grep', 'Grep', {'pattern': 'ciFixer'}),
    ],
    parent: 't_task',
    id: 'msg_sub',
  ),
  toolResult('t_sub_grep', 'lib/a.dart', parent: 't_task'),
  toolResult('t_task', 'feito'),
  assistant([
    toolUse('t_ls', 'Bash', {'command': 'git status'}),
  ]),
  toolResult('t_ls', 'limpo'),
];

// Steps: 0 user · 1 Read · 2 text · 3 Edit · 4 Bash(err) · 5 gate(err)
// · 6 user · 7 Task · 8 Bash git status.
const total = 9;

Future<void> openReplay(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('session-tab-replay')));
  await pumpFor(tester);
}

String position(WidgetTester tester) {
  final w = tester.widget<Text>(find.byKey(const ValueKey('replay-position')));
  return w.textSpan!.toPlainText();
}

Future<void> step(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('replay-step-$index')));
  await pumpFor(tester);
}

void main() {
  group('SPEC-082 · Replay', () {
    testWidgets('R1: the tab opens a finished session at the last step, '
        'the whole width', (tester) async {
      await pumpScreen(tester, events: replayEvents);
      expect(find.byKey(const ValueKey('session-tab-replay')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-tab-replay-tip')),
        findsNothing,
      );
      await openReplay(tester);
      expect(find.byType(ReplayView), findsOneWidget);
      expect(position(tester), startsWith('Passo $total de $total'));
      // The list of sessions and the side panel give way to the replay.
      expect(find.byKey(const ValueKey('session-panes-one')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('R1: disabled while the session runs; enabled when the '
        'process ends, without reloading', (tester) async {
      final (_, cli) = await pumpScreen(tester, events: replayEvents);
      await tester.enterText(
        find.byKey(const ValueKey('composer-field')),
        'continue',
      );
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await pumpFor(tester);
      expect(cli.processes, hasLength(1));
      final tip = find.byKey(const ValueKey('session-tab-replay-tip'));
      expect(tip, findsOneWidget);
      expect(
        tester.widget<Tooltip>(tip).message,
        'O replay fica disponível quando a sessão terminar',
      );
      await tester.tap(find.byKey(const ValueKey('session-tab-replay')));
      await pumpFor(tester);
      expect(find.byType(ReplayView), findsNothing);

      await tester.runAsync(() => cli.last.finish(1));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(tip, findsNothing);
      await openReplay(tester);
      expect(find.byType(ReplayView), findsOneWidget);
    });

    test('R1: an idle process (waiting for a message) counts as finished', () {
      expect(replayAvailable(SessionStatus.completed, alive: true), isTrue);
      expect(replayAvailable(SessionStatus.running, alive: true), isFalse);
      expect(
        replayAvailable(SessionStatus.waitingApproval, alive: true),
        isFalse,
      );
      expect(replayAvailable(SessionStatus.running, alive: false), isTrue);
      expect(replayAvailable(SessionStatus.failed, alive: false), isTrue);
    });

    testWidgets('R5: the panel follows the kind of the step', (tester) async {
      await pumpScreen(
        tester,
        events: replayEvents,
        overrides: [
          replayOriginalsProvider.overrideWith(
            (ref, id) async => {'t_edit': 'x\nw\n'},
          ),
        ],
      );
      await openReplay(tester);

      // Edit: the diff of the step and what the agent said before.
      await step(tester, 3);
      expect(find.byKey(const ValueKey('replay-edit-diff')), findsOneWidget);
      expect(
        find.textContaining('O gh devolve 1; vou ignorar esse caso.'),
        findsWidgets,
      );
      expect(position(tester), startsWith('Passo 4 de $total'));

      // "Arquivo neste ponto" (R7): the file right after the step.
      await tester.tap(find.byKey(const ValueKey('replay-file-at')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('replay-file-at-text')), findsOneWidget);
      expect(find.textContaining('base: jsonl do Claude Code'), findsOneWidget);

      // Read: the range and the numbered lines.
      await step(tester, 1);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('replay-read-range')))
            .data,
        'arquivo inteiro',
      );
      expect(find.byKey(const ValueKey('replay-read-lines')), findsOneWidget);

      // Run: the command, the output and the exit code.
      await step(tester, 4);
      expect(find.textContaining('saída 1'), findsOneWidget);
      expect(find.textContaining('Roda os testes'), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-run-output')), findsOneWidget);

      // Conversation: the whole text.
      await step(tester, 6);
      expect(find.byKey(const ValueKey('replay-text')), findsOneWidget);

      // Mark: the gate notice.
      await step(tester, 5);
      expect(find.text('Verificação falhou: ✗ testes'), findsWidgets);

      // Subagent: its steps open in their own lane.
      await step(tester, 7);
      expect(find.textContaining('procure o leitor do CI'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('replay-subagent-open')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('replay-subagent-7')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('replay-subagent-step-0')));
      await pumpFor(tester);
      expect(position(tester), startsWith('Passo 8.1 de $total'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('R5: "Abrir na Timeline" goes back to the Timeline tab', (
      tester,
    ) async {
      await pumpScreen(tester, events: replayEvents);
      await openReplay(tester);
      await step(tester, 4);
      await tester.tap(find.byKey(const ValueKey('replay-open-timeline')));
      await pumpFor(tester);
      expect(find.byType(ReplayView), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionsScreen)),
      );
      expect(container.read(sessionTabProvider('s1')), SessionTab.timeline);
      // Back to the tab: the same step (R4).
      await openReplay(tester);
      expect(position(tester), startsWith('Passo 5 de $total'));
    });

    testWidgets('R7: without a base the reason shows and the diff stays', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        events: replayEvents,
        overrides: [
          replayOriginalsProvider.overrideWith((ref, id) async => const {}),
        ],
      );
      await openReplay(tester);
      await step(tester, 3);
      await tester.tap(find.byKey(const ValueKey('replay-file-at')));
      await pumpFor(tester);
      expect(
        find.text('Não dá para reconstruir o arquivo neste ponto.'),
        findsOneWidget,
      );
    });

    testWidgets('R6: the state at this point', (tester) async {
      await pumpScreen(tester, events: replayEvents);
      await openReplay(tester);
      await step(tester, 4);
      expect(find.byKey(const ValueKey('replay-read-a.dart')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('replay-edited-a.dart')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('replay-blind-edit')), findsNothing);
      await step(tester, 8);
      expect(find.byKey(const ValueKey('replay-last-command')), findsOneWidget);
      expect(find.textContaining('flutter test'), findsWidgets);
    });

    testWidgets('R9: filters and search narrow the list', (tester) async {
      await pumpScreen(tester, events: replayEvents);
      await openReplay(tester);
      await tester.tap(find.byKey(const ValueKey('replay-filter-commands')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('replay-step-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-step-8')), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-step-1')), findsNothing);
      expect(position(tester), contains('Comandos: 2 de 2'));

      await tester.tap(find.byKey(const ValueKey('replay-filter-errors')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('replay-step-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-step-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-step-8')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('replay-filter-all')));
      await tester.enterText(
        find.byKey(const ValueKey('replay-search')),
        'git',
      );
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('replay-step-8')), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-step-4')), findsNothing);
    });

    testWidgets('R8: the chosen file narrows the steps; "Quem escreveu?" '
        'goes to the edit', (tester) async {
      await pumpScreen(
        tester,
        events: replayEvents,
        overrides: [
          replayFinalDiffProvider.overrideWith(
            (ref, key) async => const ReplayFinalDiff(
              rows: [
                (op: DiffOp.del, text: 'x', oldNo: 1, newNo: null),
                (op: DiffOp.add, text: 'y', oldNo: null, newNo: 1),
                (op: DiffOp.add, text: '_log.add(run);', oldNo: null, newNo: 2),
              ],
              against: 'contra o início da etapa',
            ),
          ),
        ],
      );
      await openReplay(tester);
      await tester.tap(find.byKey(const ValueKey('replay-side-result')));
      await pumpFor(tester);
      await tester.tap(find.byKey(const ValueKey('replay-result-a.dart')));
      await pumpFor(tester);
      // Only the steps that touched the file.
      expect(find.byKey(const ValueKey('replay-step-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-step-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-step-4')), findsNothing);
      expect(find.textContaining('só a.dart'), findsOneWidget);
      // The cursor (last step) is outside the file's steps: no "0 de N".
      expect(position(tester), contains('só a.dart: – de'));
      expect(find.byKey(const ValueKey('replay-final-diff')), findsOneWidget);

      // A line no edit wrote: "veio de um comando".
      await tester.tap(find.byKey(const ValueKey('replay-final-row-2')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('replay-who-command')), findsOneWidget);

      // A line of the edit: back to its step.
      await tester.tap(find.byKey(const ValueKey('replay-final-row-1')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('replay-who-edit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('replay-who-go')));
      await pumpFor(tester);
      expect(position(tester), startsWith('Passo 4 de $total'));
      expect(find.byKey(const ValueKey('replay-edit-diff')), findsOneWidget);

      // ← → walk only the file's steps.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await pumpFor(tester);
      expect(position(tester), startsWith('Passo 2 de $total'));
      await tester.tap(find.byKey(const ValueKey('replay-clear-file')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('replay-step-4')), findsOneWidget);
    });
  });

  group('SPEC-110 · Replay do Codex e turnos revertidos', () {
    /// Dois turnos; o segundo desfeito com a conversa.
    TimelineBuilder codexSession({bool reverted = true, String? output}) {
      final b = TimelineBuilder(start: DateTime(2026, 11, 25, 14))
        ..user('Leia o módulo');
      b.turn('t-1');
      b.command('c1', 'rg calcularFrete lib', [
        {
          'type': 'search',
          'command': 'rg calcularFrete lib',
          'query': 'calcularFrete',
          'path': 'lib',
        },
      ], cwd: root);
      b.command('c2', 'sed -n 1,80p lib/t.dart', [
        readAction('$root/lib/t.dart', command: 'sed -n 1,80p lib/t.dart'),
      ], cwd: root);
      b.say('As faixas ficam em t.dart');
      b.endTurn();
      b.user('Corrija a faixa');
      final seq = b.seq;
      b.turn('t-2');
      b.patch('p1', [update('$root/lib/t.dart', '@@ -1 +1 @@\n-a\n+b\n')]);
      b.command(
        'c3',
        'dart test',
        [
          {'type': 'unknown', 'command': 'dart test'},
        ],
        output: output,
        exit: 1,
        cwd: root,
      );
      b.say('Alterei um arquivo');
      b.endTurn();
      if (reverted) {
        b.codexEvent(
          ConversationRevert(
            key: 'cr-1',
            pointId: 7,
            turn: 2,
            lastTurn: 2,
            beforeTurnId: 't-2',
            threadId: 'thread-1',
            at: DateTime(2026, 11, 25, 14, 52),
            fromSeq: seq,
            copyId: 'copia-1',
            files: 1,
          ).toJson(),
        );
      }
      return b;
    }

    List<Map<String, dynamic>> events(TimelineBuilder b) => [
      for (final r in b.rows) jsonDecode(r.json) as Map<String, dynamic>,
    ];

    Override codex(ProviderStatus status) => providerAvailabilityProvider
        .overrideWith((ref, id) async => ProviderAvailability(status, 'x'));

    testWidgets('R1: as leituras por comando na lista e em "Já leu", com o '
        'comando; nada de "editou sem ler"', (tester) async {
      await pumpScreen(tester, events: events(codexSession(reverted: false)));
      await openReplay(tester);
      expect(
        find.textContaining('Buscar "calcularFrete" lib', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Ler t.dart 1–80 · sed -n', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('×1 · sed'), findsOneWidget);
      expect(find.text('×1 · rg'), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-blind-edit')), findsNothing);
      // R5: nenhuma leitura de contexto ainda.
      expect(find.text('aguardando medição'), findsOneWidget);
      // Passo Ler: o que o comando leu e a saída.
      await step(tester, 2);
      expect(
        find.byKey(const ValueKey('replay-command-read-0')),
        findsOneWidget,
      );
      expect(find.text('lib/t.dart 1–80 · sed -n'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('R4: "Buscar a saída completa" só quando falta; sem o Codex, '
        'desabilitado com o motivo', (tester) async {
      await pumpScreen(
        tester,
        events: events(codexSession(reverted: false, output: 'linha\n' * 2100)),
        overrides: [codex(ProviderStatus.missing)],
      );
      await openReplay(tester);
      await step(tester, 2);
      expect(find.byKey(const ValueKey('replay-fetch-output')), findsNothing);
      final run = find.textContaining('Rodar dart test', findRichText: true);
      await tester.tap(run.first);
      await pumpFor(tester);
      final button = find.byKey(const ValueKey('replay-fetch-output'));
      expect(button, findsOneWidget);
      expect(tester.widget<SmallButton>(button).onTap, isNull);
      expect(find.text('O Codex não está instalado.'), findsOneWidget);
      expect(find.text('… saída cortada: 100 linhas a menos'), findsOneWidget);
    });

    testWidgets('R10, R11: no Replay, o turno revertido vem com o selo, a '
        'marca e o "revertido" do leitor de tela', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, events: events(codexSession()));
      await openReplay(tester);
      expect(
        find.text('Conversa revertida para antes do turno 2'),
        findsWidgets,
      );
      final header = tester.widget<Text>(
        find.byKey(const ValueKey('replay-turn-2')),
      );
      expect(header.textSpan!.toPlainText(), startsWith('revertido · T2'));
      expect(header.semanticsLabel, 'Turno 2, revertido às 14 e 52');
      final first = tester.widget<Text>(
        find.byKey(const ValueKey('replay-turn-1')),
      );
      expect(first.semanticsLabel, isNull);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('replay-step-5'))).label,
        contains('revertido às 14 e 52'),
      );
      // O passo aberto leva o selo.
      await step(tester, 5);
      expect(
        find.byKey(const ValueKey('replay-reverted-badge')),
        findsOneWidget,
      );
      await step(tester, 1);
      expect(find.byKey(const ValueKey('replay-reverted-badge')), findsNothing);
      handle.dispose();
    });

    testWidgets('R10, R11: na timeline, os turnos revertidos esmaecidos com o '
        'selo, e o cartão com o Refazer enquanto vale', (tester) async {
      final handle = tester.ensureSemantics();
      final (db, _) = await pumpScreen(tester, events: events(codexSession()));
      expect(
        find.text('fora da conversa do agente · revertido às 14:52'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('timeline-reverted')), findsWidgets);
      final faded = find.ancestor(
        of: find.text('Corrija a faixa'),
        matching: find.byKey(const ValueKey('timeline-reverted')),
      );
      expect(tester.widget<Opacity>(faded).opacity, lessThan(1));
      expect(
        find.ancestor(
          of: find.text('Leia o módulo'),
          matching: find.byKey(const ValueKey('timeline-reverted')),
        ),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(RegExp('revertido às 14 e 52')),
        findsWidgets,
      );
      expect(
        find.text(
          'Turno 2 desfeito: 1 arquivo e a conversa do Codex. O agente não '
          'recebe aviso: ele já não conhece esse turno.',
        ),
        findsOneWidget,
      );
      // Sem o ponto (limpo), sem Refazer.
      expect(find.byKey(const ValueKey('conversation-redo')), findsNothing);
      await tester.runAsync(
        () => db
            .into(db.restorePoints)
            .insert(
              RestorePointsCompanion.insert(
                id: const Value(7),
                workspaceId: 1,
                sessionId: const Value('s1'),
                worktreePath: root,
                turn: 2,
                startedAt: DateTime(2026, 11, 25, 14, 30),
                startHead: 'a',
                startSha: 'b',
                state: const Value(RestoreState.undone),
                undoSha: const Value('c'),
                undoneSha: const Value('d'),
                usedAt: Value(DateTime(2026, 11, 25)),
              ),
            ),
      );
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('conversation-redo')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('R8: a falha do revert mostra o motivo e deixa tentar de novo', (
      tester,
    ) async {
      final b = codexSession(reverted: false);
      b.codexEvent(
        ConversationRevert(
          key: 'cr-1',
          pointId: 7,
          turn: 2,
          lastTurn: 2,
          beforeTurnId: 't-2',
          threadId: 'thread-1',
          at: DateTime(2026, 11, 25, 14, 52),
          fromSeq: 7,
          error: 'o App Server não respondeu em 10 s',
          files: 6,
        ).toJson(),
      );
      final (db, _) = await pumpScreen(tester, events: events(b));
      expect(
        find.textContaining(
          'A conversa do Codex não voltou: o App Server não respondeu em 10 s. '
          'Os arquivos continuam desfeitos e o agente recebe o aviso.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('timeline-reverted')), findsNothing);
      expect(find.byKey(const ValueKey('conversation-retry')), findsNothing);
      await tester.runAsync(
        () => db
            .into(db.restorePoints)
            .insert(
              RestorePointsCompanion.insert(
                id: const Value(7),
                workspaceId: 1,
                sessionId: const Value('s1'),
                worktreePath: root,
                turn: 2,
                startedAt: DateTime(2026, 11, 25, 14, 30),
                startHead: 'a',
                startSha: 'b',
                state: const Value(RestoreState.undone),
                undoSha: const Value('c'),
                undoneSha: const Value('d'),
                usedAt: Value(DateTime(2026, 11, 25)),
              ),
            ),
      );
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('conversation-retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('conversation-redo')), findsNothing);
    });
  });

  group('SPEC-110 R10 · a timeline marca e desmarca', () {
    ConversationRevert revert(
      String key,
      int seq, {
      int point = 1,
      String before = 't-1',
      String? error,
    }) => ConversationRevert(
      key: key,
      pointId: point,
      turn: 1,
      lastTurn: 2,
      beforeTurnId: before,
      threadId: 'x',
      at: DateTime(2026, 11, 25, 14, 20),
      fromSeq: seq,
      copyId: 'copia-$key',
      error: error,
    );

    test(
      'do turno em diante; Refazer tira só a marca dele; a falha não marca',
      () {
        final b = TimelineBuilder()..user('um');
        final s1 = b.seq;
        b.turn('t-1');
        b.say('a');
        b.endTurn();
        b.user('dois');
        final s2 = b.seq;
        b.turn('t-2');
        b.say('b');
        b.endTurn();
        b.codexEvent(revert('A', s2, point: 2, before: 't-2').toJson());
        b.codexEvent(revert('B', s1).toJson());
        bool gone(String text) =>
            b.items
                .firstWhere(
                  (i) =>
                      (i is UserItem && i.text == text) ||
                      (i is AssistantTextItem && i.text == text),
                )
                .reverted !=
            null;
        expect(
          [gone('um'), gone('a'), gone('dois'), gone('b')],
          [true, true, true, true],
        );
        expect(b.t.conversationReverts.keys, {1, 2});
        expect(b.t.conversationCopies, ['copia-A', 'copia-B']);
        b.codexEvent(
          conversationRestoredEvent(
            revert: revert('B', s1),
            previousThread: 'x',
            files: 1,
            at: DateTime(2026, 11, 25, 15),
          ),
        );
        // O turno 2 já estava fora antes do segundo desfazer.
        expect(
          [gone('um'), gone('a'), gone('dois'), gone('b')],
          [false, false, true, true],
        );
        expect(
          (b.items.last as NoticeItem).text,
          'Refeito: arquivos e conversa (cópia de 14:20)',
        );
        // Depois do revert, o contexto espera a próxima medição.
        expect(b.t.context.snapshot.current, isNull);

        final c = TimelineBuilder()..user('um');
        c.turn('t-1');
        c.codexEvent(revert('F', 1, error: 'boom').toJson());
        expect(c.items.every((i) => i.reverted == null), isTrue);
        // Sem o seq (evento antigo), pelo turno do agente.
        final d = TimelineBuilder()..user('um');
        d.turn('t-1');
        d.say('a');
        d.codexEvent({...revert('A', 99).toJson()});
        expect(d.items.first.reverted, isNotNull);
      },
    );
  });
}
