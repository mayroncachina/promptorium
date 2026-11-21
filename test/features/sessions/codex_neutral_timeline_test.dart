import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/core/providers/agent_registry.dart'
    show providerFlowsProvider, ProviderFlows, AppFlow;
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/context/context_sources.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/timeline_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/codex/codex_replay.dart';
import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

/// SPEC-095 R7, R9: a Codex session replayed from the real 0.170
/// transcripts shows the file card with path and diff, the command card
/// with the exit code, and the Atividades count the files of the turn.
Timeline _timeline(List<AgentEvent> events) {
  final t = Timeline();
  for (final e in events) {
    t.apply(e);
  }
  return t;
}

Future<void> _pump(WidgetTester tester, Timeline t, String root) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: TimelineListView(items: t.items, root: root),
        ),
      ),
    );

/// [t] with a completed `fileChange` (the real `update` of edicao-turno)
/// right before the end of its turn.
List<CodexLine> _withEdit(List<CodexLine> t) {
  final edit = readCodexTranscript('$codexFixtures/edicao-turno.jsonl')
      .where((l) => l.msg['method'] == 'item/completed')
      .map((l) => l.msg['params']['item'] as Map<String, dynamic>)
      .firstWhere((i) => i['type'] == 'fileChange');
  final i = t.indexWhere((l) => l.msg['method'] == 'turn/completed');
  final thread = t[i].msg['params']['threadId'];
  return [
    ...t.take(i),
    (
      dir: 'recv',
      msg: {
        'method': 'item/completed',
        'params': {'threadId': thread, 'item': edit},
      },
    ),
    ...t.skip(i),
  ];
}

void main() {
  testWidgets('file card: path, kind and diff from fileChange', (tester) async {
    final events = await tester.runAsync(() => replayCodex('edicao'));
    final t = _timeline(events!);
    final files = t.items.whereType<ToolItem>().where((i) => i.isFileChange);
    expect(files, hasLength(2));
    await _pump(tester, t, '<sonda>/repos/edicao/repo');
    expect(find.text(NeutralToolNames.file), findsNWidgets(2));
    expect(find.text('base.txt'), findsOneWidget);
    expect(find.text('nota.txt'), findsOneWidget);
    expect(find.text('novo'), findsNWidgets(2));
    expect(find.text('+1'), findsNWidgets(2));
    // In place (no expanded host): the diff opens under the card.
    final first = files.first;
    await tester.tap(find.byKey(ValueKey('tool-toggle-${first.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('tool-diff-${first.id}')), findsOneWidget);
    expect(find.textContaining('linha dois'), findsWidgets);
  });

  testWidgets('command card: command, exit code and output', (tester) async {
    final events = await tester.runAsync(
      () => replayCodex(
        'comando',
        permissionMode: ClaudePermissionMode.defaultMode,
      ),
    );
    final t = _timeline(events!);
    final cmds = t.items.whereType<ToolItem>().where((i) => i.isCommand);
    expect(cmds.map((c) => c.command!.exitCode), [0, 1, 0]);
    expect(cmds.every((c) => c.done), isTrue);
    expect(cmds.elementAt(1).isError, isTrue);
    await _pump(tester, t, '<sonda>/repos/comando/repo');
    expect(find.text(NeutralToolNames.command), findsNWidgets(3));
    expect(find.text('ls'), findsOneWidget);
    expect(find.text('cat nao-existe.txt'), findsOneWidget);
    expect(find.text('exit 1'), findsOneWidget);
    expect(find.text('exit 0'), findsNWidgets(2));
    final bad = cmds.elementAt(1);
    await tester.tap(find.byKey(ValueKey('tool-toggle-${bad.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No such file or directory'), findsOneWidget);
  });

  testWidgets('R6: an unknown item shows collapsed with its type', (
    tester,
  ) async {
    final t = Timeline()
      ..apply(
        AgentEvent.fromJson({
          'type': 'promptorium_other_item',
          'v': 1,
          'provider': 'codex',
          'item_type': 'plan',
          'summary': '1. rótulo 2. testes',
          'tool_use_id': 'plan-1',
        }),
      );
    await _pump(tester, t, '/w');
    expect(find.text(NeutralToolNames.other), findsOneWidget);
    expect(find.text('plan · "1. rótulo 2. testes"'), findsOneWidget);
    expect(find.text('recolhido ›'), findsOneWidget);
  });

  test('files cited: the files Codex changes and the ones it reads', () async {
    final events = [
      ...await replayCodex('edicao'),
      ...await replayCodex(
        'comando',
        permissionMode: ClaudePermissionMode.defaultMode,
      ),
    ];
    final t = _timeline(events);
    final files = t.context.sources.grouped[ContextSourceGroup.files]!;
    expect(
      files.map((s) => '${s.label.split('/').last}:${s.evidence.name}'),
      containsAll([
        'base.txt:edited',
        'nota.txt:edited',
        'nao-existe.txt:read',
      ]),
    );
  });

  test('Atividades: calls and files of the Codex turn', () async {
    final tmp = Directory.systemTemp.createTempSync('codex-neutral-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final root = await createRepo(tmp);
    final servers = <FakeCodex>[];
    final c = sessionContainer([
      providerFlowsProvider.overrideWithValue(
        ProviderFlows.defaults.copyWith('codex', {...AppFlow.values}),
      ),
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: FakeCli(),
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      codexProcessStarterProvider.overrideWithValue((
        exe,
        args, {
        workingDirectory,
        environment,
      }) async {
        final fake = FakeCodex.replay(
          _withEdit(readCodexTranscript('$codexFixtures/hook_turno.jsonl')),
          fallback: codexHandshake(),
        );
        servers.add(fake);
        return fake;
      }),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: root, name: 'r');
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(ws.id), 'codex');
    final m = c.read(sessionManagerProvider.notifier);
    final id = await m.create(
      NewSessionRequest(
        workspace: ws,
        title: 'Codex',
        prompt: 'Rode rm apagar.txt',
        permissionMode: ClaudePermissionMode.skipPermissions,
      ),
    );
    await until(() async {
      final s = await c.read(sessionsRepoProvider).getById(id);
      return s?.status.name == 'completed';
    });
    final live = c.read(sessionManagerProvider).live[id]!;
    // The command and the file change (two files) of the turn.
    expect(live.calls, 2);
    expect(live.files, 2);
    final file = live.recent.firstWhere((t) => t.kind == LiveToolKind.file);
    expect(file.files.map((f) => f.split('/').last), ['base.txt', 'nota.txt']);
    expect(
      poseOfTool(
        LiveTool(
          id: file.id,
          name: file.name,
          input: file.input,
          at: file.at,
          kind: file.kind,
        ),
      ),
      ActivityPose.edit,
    );
    final cmd = live.recent.firstWhere((t) => t.kind == LiveToolKind.command);
    expect(cmd.input['command'], contains('rm apagar.txt'));
    expect(toolLine(cmd), startsWith('comando rm apagar.txt'));
    // The stored rows reopen as the same neutral cards.
    final rows = await c.read(sessionsRepoProvider).events(id);
    expect(rows.map((r) => r.type), contains('promptorium_file_change'));
    expect(rows.map((r) => r.type), isNot(contains('promptorium_quota')));
    final reopened = Timeline();
    for (final r in rows) {
      reopened.applyStored(r.json);
    }
    expect(
      reopened.items.whereType<ToolItem>().where((t) => t.isFileChange),
      hasLength(2),
    );
    await m.shutdown();
  });
}
