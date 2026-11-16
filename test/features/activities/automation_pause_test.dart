import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/automation_pause.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../board/spec_runner_test.dart' show resultLine, specText;
import '../review/ci_fixer_test.dart';
import '../sessions/session_test_utils.dart';

/// A top-level `assistant` line with [blocks].
String assistant(String id, List<Map<String, dynamic>> blocks) => jsonEncode({
  'type': 'assistant',
  'message': {'id': id, 'role': 'assistant', 'content': blocks},
});

String toolResult(String toolUseId) => jsonEncode({
  'type': 'user',
  'message': {
    'role': 'user',
    'content': [
      {'type': 'tool_result', 'tool_use_id': toolUseId, 'content': 'ok'},
    ],
  },
});

void main() {
  late Directory tmp;
  late String repo;
  late FakeCli cli;
  late ProviderContainer c;
  late Workspace ws;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-atividades-');
    repo = await createRepo(tmp);
    Directory('$repo/specs').createSync();
    File('$repo/specs/SPEC-001-extracao.md').writeAsStringSync(specText);
    cli = FakeCli();
    c = sessionContainer(
      sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
    );
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'repo');
    await c.read(specServiceProvider).sync(ws);
  });

  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<Spec> spec() async =>
      (await c.read(specsRepoProvider).getByCode(ws.id, 'SPEC-001'))!;

  test('R3: the live session keeps its newest tools, calls, edited files and '
      'text; a result means thinking', () async {
    final m = c.read(sessionManagerProvider.notifier);
    final id = await m.create(
      NewSessionRequest(workspace: ws, title: 'Robô', prompt: 'oi'),
    );
    await settle();
    final root = (await c.read(sessionsRepoProvider).getById(id))!.worktreePath;
    cli.last.emit(
      assistant('m1', [
        {'type': 'text', 'text': 'Comecei pelo   componente.\nAgora reviso.'},
        {
          'type': 'tool_use',
          'id': 't1',
          'name': 'Read',
          'input': {'file_path': '$root/lib/a.dart'},
        },
      ]),
    );
    await settle();
    var live = c.read(sessionManagerProvider).live[id]!;
    expect(live.tool?.name, 'Read');
    expect(live.tool?.done, isFalse);
    expect(live.lastText, 'Comecei pelo componente. Agora reviso.');
    cli.last.emit(toolResult('t1'));
    await settle();
    live = c.read(sessionManagerProvider).live[id]!;
    expect(live.tool?.done, isTrue);
    for (final (n, name, path) in [
      (2, 'Edit', 'lib/a.dart'),
      (3, 'Write', 'lib/b.dart'),
      (4, 'Edit', 'lib/a.dart'),
    ]) {
      cli.last.emit(
        assistant('m$n', [
          {
            'type': 'tool_use',
            'id': 't$n',
            'name': name,
            'input': {'file_path': '$root/$path'},
          },
        ]),
      );
    }
    await settle();
    live = c.read(sessionManagerProvider).live[id]!;
    expect(live.calls, 4);
    expect(live.files, 2);
    expect(live.recent.map((t) => t.id), ['t4', 't3', 't2', 't1']);
  });

  test('R8: paused, the Autopilot starts nothing; back on, it looks at the '
      'queue again', () async {
    await c.read(automationPausedProvider.notifier).set(true);
    expect(c.read(automationPausedProvider), isTrue);
    await c.read(autopilotProvider.notifier).start(ws.id);
    await settle();
    expect((await spec()).stage, SpecStage.backlog);
    expect(cli.processes, isEmpty);
    await c.read(automationPausedProvider.notifier).set(false);
    await until(() async => (await spec()).stage == SpecStage.running);
    expect(cli.processes, hasLength(1));
  });

  test('R8, P10: "Pausar após o turno" does not open the next step', () async {
    final s = await spec();
    final runner = c.read(specRunnerProvider);
    final id = await runner.runNext(s.id);
    await settle();
    c.read(pauseAfterTurnProvider.notifier).toggle(id);
    cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1'));
    await until(() async {
      final rows = await c.read(specStepsRepoProvider).bySpec(s.id);
      return stepsOf(await spec(), rows).first.isDone;
    });
    await settle();
    await settle();
    expect(cli.processes, hasLength(1));
    final rows = await c.read(specStepsRepoProvider).bySpec(s.id);
    expect(
      stepsOf(await spec(), rows).skip(1).map((x) => x.status),
      everyElement(StepStatus.pending),
    );
    expect(c.read(pauseAfterTurnProvider), isEmpty);
    final notes = [
      for (final e in await c.read(sessionsRepoProvider).events(id))
        if (e.json.contains('Pausada após o turno')) e,
    ];
    expect(notes, isNotEmpty);
  });

  group('R8: the automatic CI fix', () {
    late Directory ciTmp;
    late String ciRepo;

    setUp(() async {
      ciTmp = Directory.systemTemp.createTempSync('promptorium-ci-pause-');
      ciRepo = await createRepo(ciTmp);
    });

    tearDown(() => ciTmp.deleteSync(recursive: true));

    test('paused, a red PR does not go to the agent', () async {
      final e = await setUpCiPr(ciTmp, ciRepo);
      Directory('$ciRepo/.promptorium').createSync();
      File('$ciRepo/.promptorium/config.yml')
          .writeAsStringSync('review:\n  corrigir-ci: automatico\n');
      await e.c.read(automationPausedProvider.notifier).set(true);
      final sitter = e.c.read(prBabysitterProvider.notifier);
      await sitter.toggle(e.id);
      await settle();
      expect(e.ciMessages, isEmpty);
      await e.c.read(automationPausedProvider.notifier).set(false);
      await sitter.check(e.id);
      await until(() async => e.ciMessages.isNotEmpty);
      expect(e.ciMessages, hasLength(1));
    });
  });
}
