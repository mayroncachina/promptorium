import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/board/orchestrator/step_classifier.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart' show AppEventTypes;
import 'package:promptorium/features/specs/spec_service.dart';

import '../../../core/git/git_test_utils.dart';
import '../../../helpers/test_db.dart';
import '../../sessions/session_test_utils.dart';

export '../../sessions/session_test_utils.dart'
    show FakeCli, FakeNotifier, fixtureLines, settle;

/// Four steps: one session each (more than `singleSessionMaxSteps`).
const orchestratorSpec = '''---
id: SPEC-001
status: aprovada
---

# Extração do schema

## Requisitos

- R1 · Extrair tabelas
- R2 · Extrair índices
- R3 · Extrair generators
- R4 · Ligar na CLI
''';

/// `result` line of the fixture with [text] as the final answer.
String resultLine(String text, {double cost = 0.01}) {
  final j = jsonDecode(
    fixtureLines().firstWhere((l) => l.contains('"result"')),
  ) as Map<String, dynamic>;
  j['result'] = text;
  j['total_cost_usd'] = cost;
  return jsonEncode(j);
}

/// Top-level answer whose context (input + cache) is [context] tokens.
String contextAnswer(int context) => jsonEncode({
  'type': 'assistant',
  'message': {
    'id': 'msg-$context',
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': 'Feito.'},
    ],
    'usage': {
      'input_tokens': 2,
      'cache_read_input_tokens': context - 1002,
      'cache_creation_input_tokens': 1000,
      'output_tokens': 50,
    },
  },
});

/// Answers of the classification without a CLI: [kinds] by requirement id,
/// or [error] thrown by the run.
class FakeClassifier extends StepClassifier {
  FakeClassifier({this.kinds = const {}, this.error});

  final Map<String, String> kinds;
  final Object? error;
  var calls = 0;

  @override
  Future<Object?> request(
    Spec spec,
    List<ClassifierTarget> targets,
    Future<void> cancelled,
  ) async {
    calls++;
    if (error case final e?) throw e;
    return {
      'steps': [
        for (final t in targets)
          {'id': t.id, 'kind': kinds[t.id] ?? 'implementacao', 'reason': 'x'},
      ],
    };
  }
}

/// A temporary repo with [specText] and a container with the fake CLI.
class OrchestratorFixture {
  OrchestratorFixture._(this.tmp, this.repo, this.cli, this.c);

  final Directory tmp;
  final String repo;
  final FakeCli cli;
  final ProviderContainer c;
  late final Workspace ws;
  late final Spec spec;

  static Future<OrchestratorFixture> create({
    String specText = orchestratorSpec,
    String? config,
    FakeClassifier? classifier,
  }) async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-orq-');
    final repo = await createRepo(tmp);
    Directory('$repo/specs').createSync();
    File('$repo/specs/SPEC-001-extracao.md').writeAsStringSync(specText);
    if (config != null) {
      Directory('$repo/.promptorium').createSync();
      File('$repo/.promptorium/config.yml').writeAsStringSync(config);
    }
    final cli = FakeCli();
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
        if (classifier != null)
          stepClassifierProvider.overrideWith(() => classifier),
      ],
    );
    c.listen(sessionManagerProvider, (_, _) {});
    final f = OrchestratorFixture._(tmp, repo, cli, c);
    await c.read(appSettingsProvider.notifier).load();
    f.ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'repo');
    await c.read(specServiceProvider).sync(f.ws);
    f.spec = (await c.read(specsRepoProvider).getByCode(f.ws.id, 'SPEC-001'))!;
    return f;
  }

  void dispose() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  }

  /// Stores the plan of [rules] (`R1: (kind, model, effort)`).
  Future<void> plan(Map<String, (StepKind, String, String)> rules) async {
    for (final MapEntry(:key, :value) in rules.entries) {
      await c
          .read(specStepsRepoProvider)
          .setPlan(
            spec.id,
            key,
            kind: value.$1.name,
            model: value.$2,
            effort: value.$3,
          );
    }
  }

  Future<Map<String, StepStatus>> states() async {
    final s = (await c.read(specsRepoProvider).getById(spec.id))!;
    final rows = await c.read(specStepsRepoProvider).bySpec(spec.id);
    return {for (final v in stepsOf(s, rows)) v.id: v.status};
  }

  Future<List<StepView>> views() async {
    final s = (await c.read(specsRepoProvider).getById(spec.id))!;
    return stepsOf(s, await c.read(specStepsRepoProvider).bySpec(spec.id));
  }

  Future<SpecStep> row(String step) async =>
      (await c.read(specStepsRepoProvider).byStep(spec.id, step))!;

  Future<List<Session>> sessions() =>
      c.read(sessionsRepoProvider).bySpec(spec.id);

  Future<String> worktree() async =>
      (await c.read(specsRepoProvider).getById(spec.id))!.worktreePath!;

  Future<void> commit(String step) async {
    final wt = await worktree();
    File('$wt/${step.toLowerCase()}.txt').writeAsStringSync(step);
    await gitIn(wt, ['add', '.']);
    await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 $step: feito']);
  }

  Future<List<String>> notes(String sessionId) async => [
    for (final e in await c.read(sessionsRepoProvider).events(sessionId))
      if (e.type == AppEventTypes.note)
        (jsonDecode(e.json) as Map)['text'] as String,
  ];

  /// First message written to the process [i].
  String prompt(int i) =>
      cli.processes[i].writtenJson.first['message']['content'] as String;

  /// `--model` and `--effort` of the process [i].
  (String?, String?) modelOf(int i) {
    final a = cli.args[i];
    String? after(String flag) {
      final k = a.indexOf(flag);
      return k < 0 || k + 1 >= a.length ? null : a[k + 1];
    }

    return (after('--model'), after('--effort'));
  }
}

/// Waits (up to 60 s) for [cond]: the gate runs real git / bash, slow with
/// the full suite in parallel.
Future<void> waitFor(Future<bool> Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!await cond()) {
    if (DateTime.now().isAfter(end)) fail('condição não atingida');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await settle();
}
