import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/review/auto_reviewer.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../board/spec_runner_test.dart' show resultLine;
import '../sessions/session_test_utils.dart';

const spec2 = '''---
id: SPEC-001
status: aprovada
---

# Saudações

## Requisitos

- R1 · Criar ola.txt
- R2 · Criar tchau.txt
''';

String verdictLine(Map<String, Object?> data, {double cost = 0.02}) {
  final j = jsonDecode(resultLine(jsonEncode(data), cost: cost)) as Map;
  j['structured_output'] = data;
  return jsonEncode(j);
}

void main() {
  test('parse: corrigir without comments approves; comments keep their '
      'place', () {
    final v = ReviewerVerdict.parse({
      'veredito': 'corrigir',
      'resumo': 'falta teste',
      'comentarios': [
        {
          'arquivo': 'lib/a.dart',
          'linha': 3,
          'texto': 'sem teste',
          'severidade': 'alta',
          'requisito': 'R2',
        },
        {'arquivo': '', 'linha': 0, 'texto': '  '},
      ],
    })!;
    expect(v.approve, isFalse);
    expect(v.comments.single.location, 'lib/a.dart:3');
    expect(
      ReviewerVerdict.parse({'veredito': 'corrigir', 'comentarios': []})!
          .approve,
      isTrue,
    );
    expect(ReviewerVerdict.parse('x'), isNull);
    expect(
      reviewStepBody(1, v.comments),
      'Corrigir os apontamentos do revisor automático (rodada 1):\n'
      '  - lib/a.dart:3 [R2] — sem teste',
    );
  });

  test('finished spec → reviewer asks for corrections → REV1 runs with the '
      'comments → reviewer approves → the user\'s Review', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-reviewer-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = await createRepo(tmp);
    Directory('$repo/specs').createSync();
    File('$repo/specs/SPEC-001-saudacoes.md').writeAsStringSync(spec2);
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'spec']);
    Directory('$repo/.promptorium').createSync();
    File('$repo/.promptorium/config.yml').writeAsStringSync(
      'revisor:\n  ligado: true\n  modelo: haiku\n  rodadas: 2\n',
    );
    final cli = FakeCli();
    final notifier = FakeNotifier();
    final c = sessionContainer(
      sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: notifier,
        worktreesBase: '${tmp.path}/wt',
      ),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    await c.read(specServiceProvider).sync(ws);
    final spec = (await c
        .read(specsRepoProvider)
        .getByCode(ws.id, 'SPEC-001'))!;
    Future<Spec> row() async =>
        (await c.read(specsRepoProvider).getById(spec.id))!;
    Future<void> until(Future<bool> Function() cond) async {
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (!await cond()) {
        if (DateTime.now().isAfter(end)) fail('condição não atingida');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await settle();
    }

    await c.read(specRunnerProvider).runNext(spec.id);
    await settle();
    final wt = (await row()).worktreePath!;
    File('$wt/ola.txt').writeAsStringSync('ola\n');
    await gitIn(wt, ['add', '.']);
    await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1, R2: ola']);
    cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1, R2'));

    // Review column, phase auto, the reviewer's read-only run.
    await until(() async => cli.processes.length == 2);
    expect((await row()).stage, SpecStage.review);
    expect((await row()).reviewPhase, ReviewPhase.auto);
    final args = cli.args.last;
    expect(args, containsAllInOrder(['--model', 'haiku']));
    expect(args, contains('--json-schema'));
    expect(args, contains('--disallowedTools'));
    // Read-only allow list and no MCP server (F12).
    expect(
      args,
      containsAllInOrder([
        '--tools',
        'Read,Glob,Grep,WebFetch,WebSearch,TodoWrite',
      ]),
    );
    expect(args, contains('--strict-mcp-config'));
    final prompt = cli.last.writtenJson.single['message']['content'] as String;
    expect(prompt, contains('Revise a implementação da spec SPEC-001'));
    expect(prompt, contains('+ola'));

    cli.last.emit(
      verdictLine({
        'veredito': 'corrigir',
        'resumo': 'Falta tchau.txt.',
        'comentarios': [
          {
            'arquivo': 'tchau.txt',
            'linha': 0,
            'texto': 'R2 não foi feito: crie tchau.txt',
            'severidade': 'alta',
            'requisito': 'R2',
          },
        ],
      }),
    );
    // REV1: back to running, a step session with the comments.
    await until(() async => cli.processes.length == 3);
    var s = await row();
    expect(s.stage, SpecStage.running);
    expect(s.reviewRounds, 1);
    final steps = stepsOf(
      s,
      await c.read(specStepsRepoProvider).bySpec(spec.id),
    );
    expect(steps.map((x) => x.id), ['R1', 'R2', 'REV1']);
    final fix = cli.last.writtenJson.single['message']['content'] as String;
    expect(fix, contains('Implemente a etapa REV1'));
    expect(fix, contains('crie tchau.txt'));
    expect(fix, contains('ETAPA CONCLUÍDA: REV1'));
    final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
    expect(sessions.last.steps, 'REV1');

    File('$wt/tchau.txt').writeAsStringSync('tchau\n');
    await gitIn(wt, ['add', '.']);
    await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 REV1: tchau']);
    cli.last.emit(resultLine('ETAPA CONCLUÍDA: REV1'));

    // Round 2: approved → the user.
    await until(() async => cli.processes.length == 4);
    final round2 = cli.last.writtenJson.single['message']['content'] as String;
    expect(round2, contains('rodada 2'));
    expect(round2, contains('rodada 1: tchau.txt — R2 não foi feito'));
    cli.last.emit(
      verdictLine({'veredito': 'aprovar', 'resumo': 'Ok.', 'comentarios': []}),
    );
    await until(() async => (await row()).reviewPhase == ReviewPhase.human);
    s = await row();
    expect(s.stage, SpecStage.review);
    final comments = await c.read(reviewCommentsRepoProvider).bySpec(spec.id);
    expect(comments.map((x) => (x.round, x.verdict)), [
      (1, 'corrigir'),
      (1, null),
      (2, 'aprovar'),
    ]);
    expect(notifier.shown.last.$1, 'Pronta para review');
  });

  test('the round prompt asks for the new file line, also for a project\'s '
      'own reviewer agent', () {
    final prompt = reviewerPrompt(
      spec: Spec(
        id: 1,
        workspaceId: 1,
        code: 'SPEC-001',
        title: 'a',
        status: SpecStatus.approved,
        path: 'specs/a.md',
        stage: SpecStage.review,
        requirements: const [],
        dependsOn: const [],
        autoAdvance: false,
        reviewRounds: 0,
        gateResends: 0,
        rejectedHunks: 0,
      ),
      specText: '# a',
      diff: '',
      round: 1,
    );
    expect(prompt, contains('linha do arquivo novo, como numerada no diff'));
    expect(builtinReviewerPrompt, contains('linha do arquivo novo'));
  });
}
