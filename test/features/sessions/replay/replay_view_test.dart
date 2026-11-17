import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/text/line_diff.dart';
import 'package:promptorium/features/sessions/replay/replay_data.dart';
import 'package:promptorium/features/sessions/replay/replay_view.dart';
import 'package:promptorium/features/sessions/sessions_screen.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/data/db/enums.dart';

import '../sessions_screen_test.dart'
    show assistant, pumpFor, pumpScreen, root, toolResult, toolUse;

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
}
