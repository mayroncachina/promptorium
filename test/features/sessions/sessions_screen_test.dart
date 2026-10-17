import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/session_changes.dart';
import 'package:promptorium/features/sessions/sessions_screen.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/claude/claude_event_test.dart' show permissionRequestLine;
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

const root = '/work/repo-wt';

Map<String, dynamic> assistant(
  List<Map<String, dynamic>> content, {
  String? parent,
  String id = 'msg_1',
}) => {
  'type': 'assistant',
  'message': {'id': id, 'role': 'assistant', 'content': content},
  'parent_tool_use_id': parent,
  'session_id': 's1',
};

Map<String, dynamic> toolUse(
  String id,
  String name,
  Map<String, dynamic> input,
) => {'type': 'tool_use', 'id': id, 'name': name, 'input': input};

Map<String, dynamic> toolResult(
  String id,
  String content, {
  bool error = false,
  String? parent,
}) => {
  'type': 'user',
  'message': {
    'role': 'user',
    'content': [
      {
        'type': 'tool_result',
        'tool_use_id': id,
        'content': content,
        'is_error': error,
      },
    ],
  },
  'parent_tool_use_id': parent,
  'session_id': 's1',
};

final storedEvents = <Map<String, dynamic>>[
  AppEventTypes.userMessage(
    'Implemente o shell',
    DateTime(2026, 10, 15, 21, 14),
  ),
  assistant([
    {'type': 'thinking', 'thinking': 'Preciso ler a spec antes de editar.'},
    {'type': 'text', 'text': 'Vou ler a spec.'},
  ]),
  assistant([
    toolUse('t_read', 'Read', {'file_path': '$root/lib/a.dart'}),
  ]),
  toolResult('t_read', 'l1\nl2\nl3'),
  assistant([
    toolUse('t_edit', 'Edit', {
      'file_path': '$root/lib/a.dart',
      'old_string': 'x',
      'new_string': 'y\nz',
    }),
  ]),
  toolResult('t_edit', 'ok'),
  assistant([
    toolUse('t_bash', 'Bash', {'command': 'flutter analyze'}),
  ]),
  toolResult('t_bash', 'Exit code 1\nerro grave', error: true),
  assistant([
    toolUse('t_task', 'Task', {
      'description': 'Revisar testes',
      'prompt': 'revise',
    }),
  ]),
  assistant(
    [
      {'type': 'text', 'text': 'Subagente analisando'},
    ],
    parent: 't_task',
    id: 'msg_sub',
  ),
  assistant(
    [
      toolUse('t_sub_grep', 'Grep', {'pattern': 'TODO'}),
    ],
    parent: 't_task',
    id: 'msg_sub',
  ),
  toolResult('t_sub_grep', 'a.dart\nb.dart', parent: 't_task'),
  toolResult('t_task', 'feito'),
  assistant([
    toolUse('t_run', 'Bash', {'command': 'flutter test'}),
  ]),
];

Future<(AppDatabase, FakeCli)> pumpScreen(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final cli = FakeCli();
  final ws = await db
      .into(db.workspaces)
      .insertReturning(
        WorkspacesCompanion.insert(path: '/work/repo', name: 'repo'),
      );
  await db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: AppSettingKeys.activeWorkspace,
          value: '${ws.id}',
        ),
      );
  await db
      .into(db.sessions)
      .insert(
        SessionsCompanion.insert(
          id: 's1',
          workspaceId: ws.id,
          worktreePath: root,
          branch: 'pr/shell-ide',
          model: 'sonnet',
          title: const Value.absentIfNull('Shell da IDE'),
          status: const Value(SessionStatus.interrupted),
        ),
      );
  var seq = 0;
  for (final e in storedEvents) {
    await db
        .into(db.sessionEvents)
        .insert(
          SessionEventsCompanion.insert(
            sessionId: 's1',
            seq: ++seq,
            type: '${e['type']}',
            json: jsonEncode(e),
          ),
        );
  }
  final container = ProviderContainer(
    overrides: [
      ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
      // No real git under FakeAsync.
      sessionChangesProvider.overrideWith(
        (ref, id) async => const SessionChanges(),
      ),
    ],
  );
  await container.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: SessionsScreen()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(Duration.zero);
  });
  await pumpFor(tester);
  return (db, cli);
}

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('timeline renders bubbles, tool cards and subagent group', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('session-tile-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-header-title')), findsOneWidget);
    expect(find.text('Interrompida'), findsWidgets);
    expect(find.byKey(const ValueKey('session-resume')), findsOneWidget);

    expect(find.text('Implemente o shell'), findsOneWidget);
    expect(find.text('Vou ler a spec.'), findsOneWidget);
    // Thinking is collapsed; a click opens it (UX v2, U3).
    expect(find.byKey(const ValueKey('thinking-card')), findsOneWidget);
    expect(find.text('Pensou · 7 palavras'), findsOneWidget);
    expect(find.textContaining('antes de editar'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('thinking-toggle')));
    await tester.pump();
    expect(find.textContaining('antes de editar'), findsOneWidget);
    // Subagent card: tool count.
    expect(
      find.byKey(const ValueKey('subagent-summary-t_task')),
      findsOneWidget,
    );
    expect(find.text('1 ferramenta'), findsOneWidget);
    // Read card: name, target relative to the worktree, summary.
    final read = find.byKey(const ValueKey('tool-t_read'));
    expect(
      find.descendant(of: read, matching: find.text('lib/a.dart')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: read, matching: find.text('3 linhas')),
      findsOneWidget,
    );
    // Edit stats, Bash error, running tool.
    final edit = find.byKey(const ValueKey('tool-t_edit'));
    expect(
      find.descendant(of: edit, matching: find.text('+2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: edit, matching: find.text('−1')),
      findsOneWidget,
    );
    final bash = find.byKey(const ValueKey('tool-t_bash'));
    expect(
      find.descendant(of: bash, matching: find.text('erro')),
      findsOneWidget,
    );
    final run = find.byKey(const ValueKey('tool-t_run'));
    expect(
      find.descendant(of: run, matching: find.text('executando')),
      findsOneWidget,
    );

    // Subagent messages are nested in the Task card.
    final group = find.byKey(const ValueKey('subagent-t_task'));
    expect(group, findsOneWidget);
    expect(
      find.descendant(of: group, matching: find.text('Subagente analisando')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: group,
        matching: find.byKey(const ValueKey('tool-t_sub_grep')),
      ),
      findsOneWidget,
    );

    // Clicking a finished card expands its result.
    expect(find.textContaining('erro grave'), findsNothing);
    await tester.tap(
      find.descendant(of: bash, matching: find.text('flutter analyze')),
    );
    await tester.pump();
    expect(find.textContaining('erro grave'), findsOneWidget);

    // Raw log tab lists the stored rows.
    await tester.tap(find.byKey(const ValueKey('session-tab-raw')));
    await pumpFor(tester);
    expect(find.textContaining('promptorium_user'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer resumes the session and sends the stream-json line; '
      'approval card answers', (tester) async {
    final (_, cli) = await pumpScreen(tester);

    await tester.enterText(
      find.byKey(const ValueKey('composer-field')),
      'olá, continue',
    );
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await pumpFor(tester);

    expect(cli.processes, hasLength(1));
    expect(cli.args.single, containsAllInOrder(['--resume', 's1']));
    expect(cli.args.single, containsAllInOrder(['--model', 'sonnet']));
    expect(cli.cwds.single, root);
    expect(cli.last.writtenJson.single, {
      'type': 'user',
      'message': {'role': 'user', 'content': 'olá, continue'},
      'parent_tool_use_id': null,
    });
    // The user bubble shows up and the session is live (Parar).
    expect(find.text('olá, continue'), findsOneWidget);
    expect(find.byKey(const ValueKey('session-stop')), findsOneWidget);

    // A permission request becomes a card in the approvals queue.
    cli.last.emit(permissionRequestLine);
    await pumpFor(tester);
    expect(find.text('APROVAÇÕES PENDENTES · 1'), findsOneWidget);
    expect(find.text('Shell da IDE · quer executar'), findsOneWidget);
    expect(find.text('ls -la'), findsWidgets);
    expect(
      find.text('Sempre permitir Bash(ls:*) neste projeto (local)'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('approve-req-1')));
    await pumpFor(tester);
    final resp = cli.last.writtenJson.last;
    expect(resp['type'], 'control_response');
    expect(resp['response']['request_id'], 'req-1');
    expect(resp['response']['response']['behavior'], 'allow');
    expect(find.text('APROVAÇÕES PENDENTES · 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('side by side: the list icon opens a second pane with its own '
      'tabs; × and Ctrl+\\ close it', (tester) async {
    final (db, _) = await pumpScreen(tester);
    await tester.runAsync(
      () => db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 's2',
              workspaceId: 1,
              worktreePath: root,
              branch: 'pr/outra',
              model: 'sonnet',
              title: const Value('Outra sessão'),
              status: const Value(SessionStatus.completed),
            ),
          ),
    );
    await pumpFor(tester);
    // The newest session comes first and gets selected: pick s1 by hand.
    await tester.tap(find.byKey(const ValueKey('session-tile-s1')));
    await pumpFor(tester, 3);
    expect(find.byKey(const ValueKey('session-main-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-main-s2')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('session-split-s2')));
    await pumpFor(tester, 3);
    expect(find.byKey(const ValueKey('session-main-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-main-s2')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-pane-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-pane-s2')), findsOneWidget);
    // Tabs are per pane.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('session-main-s2')),
        matching: find.byKey(const ValueKey('session-tab-raw')),
      ),
    );
    await pumpFor(tester, 3);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('session-main-s1')),
        matching: find.byKey(const ValueKey('composer-field')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('session-pane-close')));
    await pumpFor(tester, 3);
    expect(find.byKey(const ValueKey('session-main-s2')), findsNothing);

    // "Lado a lado" of the bar opens the next session.
    await tester.tap(find.byKey(const ValueKey('session-panes-split')));
    await pumpFor(tester, 3);
    expect(find.byKey(const ValueKey('session-main-s2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session-panes-one')));
    await pumpFor(tester, 3);
    expect(find.byKey(const ValueKey('session-main-s2')), findsNothing);
  });

  testWidgets('populated screen fits the minimum window (1100×700)', (
    tester,
  ) async {
    // The shell sidebar takes 56px; the screen gets the rest.
    await pumpScreen(tester, size: const Size(1044, 640));
    expect(tester.takeException(), isNull);
    for (final t in ['terminal', 'diff', 'raw', 'timeline']) {
      await tester.tap(find.byKey(ValueKey('session-tab-$t')));
      await pumpFor(tester, 3);
      expect(tester.takeException(), isNull);
    }
  });
}
