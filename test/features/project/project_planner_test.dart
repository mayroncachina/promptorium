import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/claude_code_provider.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/project/project_planner.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

/// `result` line of a `--json-schema` run carrying [output].
String resultLine(Object output, {double cost = 0.01}) => jsonEncode({
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'total_cost_usd': cost,
  'result': jsonEncode(output),
  'structured_output': output,
});

Map<String, Object?> visionOutput({
  String reply = 'Para quem é?',
  List<String> mvp = const ['Cadastro de receitas'],
  List<String> suggestions = const ['Família', 'Amigos'],
}) => {
  'reply': reply,
  'plan': {
    'name': 'Receitas',
    'summary': 'App de receitas da família.',
    'audience': '',
    'mvp': mvp,
    'outOfScope': <String>[],
    'openQuestions': ['Quem usa?'],
  },
  'suggestions': suggestions,
};

void main() {
  late FakeCli cli;
  late ProviderContainer c;
  late Workspace ws;

  setUp(() async {
    cli = FakeCli();
    c = ProviderContainer(
      overrides: sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
      ),
    );
    c.listen(projectPlannerProvider, (_, _) {});
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: '/r', name: 'r');
  });
  tearDown(() => c.dispose());

  ProjectPlanner planner() => c.read(projectPlannerProvider.notifier);

  Future<(ProjectPlan, ProjectPlanData)> load() async {
    final row = (await c.read(projectPlansRepoProvider).get(ws.id))!;
    return (row, ProjectPlanData.decode(row.data));
  }

  String option(List<String> args, String flag) => args[args.indexOf(flag) + 1];

  test('Visão: read-only run with --json-schema; first turn creates the '
      'session, the next resumes it; plan and messages are stored', () async {
    final first = planner().sendVision(ws, 'Quero um app de receitas');
    await settle();
    expect(c.read(projectPlannerProvider)[ws.id]?.busy, 'Pensando…');
    var args = cli.args.single;
    expect(cli.cwds.single, '/r');
    expect(args, containsAllInOrder(['--permission-mode', 'default']));
    expect(jsonDecode(option(args, '--json-schema')), visionSchema);
    expect(option(args, '--append-system-prompt'), visionSystemPrompt);
    final sid = option(args, '--session-id');
    expect(args, isNot(contains('--resume')));
    expect(
      args.sublist(args.indexOf('--disallowedTools') + 1),
      ClaudeCodeProvider.readOnlyDisallowedTools,
    );
    expect(
      cli.last.writtenJson.single['message']['content'],
      'Quero um app de receitas',
    );
    // The user's message is visible while the planner thinks.
    expect((await load()).$2.messages.single.fromUser, isTrue);

    cli.last.emit(resultLine(visionOutput()));
    await first;
    var (row, data) = await load();
    expect(row.plannerSessionId, sid);
    expect(row.costUsd, closeTo(0.01, 1e-9));
    expect(data.vision.name, 'Receitas');
    expect(data.vision.isReady, isTrue);
    expect(data.messages, hasLength(2));
    final answer = data.messages.last;
    expect(answer.text, 'Para quem é?');
    expect(answer.suggestions, ['Família', 'Amigos']);
    expect(
      answer.note,
      startsWith('Plano atualizado · Nome · Resumo · MVP +1'),
    );
    expect(cli.last.signals, isNotEmpty); // stopped after the result
    expect(c.read(projectPlannerProvider)[ws.id], isNull);

    final second = planner().sendVision(ws, 'Família');
    await settle();
    args = cli.args.last;
    expect(option(args, '--resume'), sid);
    expect(args, isNot(contains('--session-id')));
    cli.last.emit(
      resultLine(
        visionOutput(reply: 'Pronto.', mvp: ['Cadastro de receitas', 'Busca']),
      ),
    );
    await second;
    (row, data) = await load();
    expect(data.messages.map((m) => m.text), [
      'Quero um app de receitas',
      'Para quem é?',
      'Família',
      'Pronto.',
    ]);
    expect(data.messages.last.note, 'Plano atualizado · MVP +1');
    expect(row.costUsd, closeTo(0.02, 1e-9));
  });

  test(
    'Visão: a failed turn becomes a red message and keeps no session',
    () async {
      final f = planner().sendVision(ws, 'Oi');
      await settle();
      await cli.last.finish(1);
      await f;
      final (row, data) = await load();
      expect(row.plannerSessionId, isNull);
      expect(data.messages.last.error, isTrue);
      expect(data.messages.last.text, contains('encerrou antes de responder'));
      expect(c.read(projectPlannerProvider)[ws.id], isNull);
    },
  );

  test('Stack: user picks stay fixed; refreshing the CLAUDE.md fixes every '
      'choice and clears the stale flag', () async {
    await planner().start(ws);
    await c
        .read(projectPlansRepoProvider)
        .update(
          ws.id,
          ProjectPlansCompanion(
            data: Value(
              const ProjectPlanData(
                vision: VisionPlan(summary: 'Receitas', mvp: ['Cadastro']),
              ).encode(),
            ),
          ),
        );

    var f = planner().proposeStack(ws);
    await settle();
    expect(c.read(projectPlannerProvider)[ws.id]?.busy, 'Propondo a stack…');
    var sent = cli.last.writtenJson.single['message']['content'] as String;
    expect(sent, contains('"summary": "Receitas"'));
    expect(sent, isNot(contains('Escolhas fixadas')));
    cli.last.emit(
      resultLine({
        'decisions': [
          {
            'area': 'Banco',
            'choice': 'PostgreSQL',
            'why': 'Relações simples',
            'alternatives': ['SQLite'],
          },
          {
            'area': 'Deploy',
            'choice': '[A DEFINIR]',
            'why': '',
            'alternatives': ['VPS'],
          },
        ],
        'claudeMd': '# Receitas\n- PostgreSQL',
      }),
    );
    await f;
    var data = (await load()).$2;
    expect(data.stack.decisions.map((d) => d.choice), [
      'PostgreSQL',
      '[A DEFINIR]',
    ]);
    expect(data.stack.claudeMd, startsWith('# Receitas'));

    await planner().chooseStack(ws, 'Banco', 'SQLite');
    data = (await load()).$2;
    expect(data.stack.decisions.first.choice, 'SQLite');
    expect(data.stack.decisions.first.pinned, isTrue);
    expect(data.stack.claudeMdStale, isTrue);

    f = planner().proposeStack(ws, keepChoices: true);
    await settle();
    sent = cli.last.writtenJson.single['message']['content'] as String;
    expect(sent, contains('- Banco: SQLite'));
    expect(sent, contains('- Deploy: [A DEFINIR]'));
    // The planner "forgets" the pick: the app keeps it anyway.
    cli.last.emit(
      resultLine({
        'decisions': [
          {
            'area': 'Banco',
            'choice': 'PostgreSQL',
            'why': '',
            'alternatives': <String>[],
          },
        ],
        'claudeMd': '# Receitas\n- SQLite',
      }),
    );
    await f;
    data = (await load()).$2;
    expect(data.stack.decisions.map((d) => d.choice), [
      'SQLite',
      '[A DEFINIR]',
    ]);
    expect(data.stack.claudeMd, endsWith('- SQLite'));
    expect(data.stack.claudeMdStale, isFalse);
  });

  test('Roadmap: stored normalized; failures go to the activity', () async {
    await planner().start(ws);
    var f = planner().planRoadmap(ws);
    await settle();
    expect(option(cli.args.last, '--max-budget-usd'), '1');
    cli.last.emit(
      resultLine({
        'specs': [
          {
            'title': 'Receitas',
            'phase': 'mvp',
            'objective': '',
            'requirements': <Object>[],
            'acceptance': <String>[],
            'tasks': [
              {
                'code': 'T2',
                'title': 'CRUD',
                'description': '',
                'requirement': 'R1',
                'dependsOn': <String>[],
              },
            ],
          },
          {
            'title': 'Esqueleto',
            'phase': 'foundation',
            'objective': '',
            'requirements': <Object>[],
            'acceptance': <String>[],
            'tasks': [
              {
                'code': 'T1',
                'title': 'Criar projeto',
                'description': '',
                'requirement': '',
                'dependsOn': <String>[],
              },
            ],
          },
        ],
        'later': ['Offline'],
      }),
    );
    await f;
    final data = (await load()).$2;
    expect(data.roadmap.specs.first.title, 'Esqueleto');
    expect(data.roadmap.specs.last.tasks.single.dependsOn, ['T1']);

    f = planner().planRoadmap(ws);
    await settle();
    cli.last.emit(resultLine({'specs': <Object>[], 'later': <String>[]}));
    await f;
    expect(
      c.read(projectPlannerProvider)[ws.id]?.error,
      'O planner não gerou nenhuma tarefa.',
    );
    // The previous roadmap is kept.
    expect((await load()).$2.roadmap.tasks, hasLength(2));
    planner().clearError(ws.id);
    expect(c.read(projectPlannerProvider)[ws.id], isNull);
  });
}
