import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/review/auto_reviewer.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../board/spec_runner_test.dart' show resultLine;
import '../sessions/session_test_utils.dart';

const _spec = '''---
id: SPEC-001
status: aprovada
---

# Saudações

## Requisitos

- R1 · Criar ola.txt
- R2 · Criar tchau.txt

## Critérios de aceite

- [ ] ola.txt existe
''';

/// SPEC-102: the automatic reviewer on the Codex (fake App Server).
void main() {
  late Directory tmp;
  late String repo;
  late FakeCli cli;
  late List<FakeCodex> servers;
  late ProviderContainer c;
  late Workspace ws;
  late Spec spec;
  var codexFails = false;

  Future<Spec> row() async =>
      (await c.read(specsRepoProvider).getById(spec.id))!;

  Future<void> setUpRepo(String config, {bool ownAgent = false}) async {
    tmp = Directory.systemTemp.createTempSync('promptorium-rev-codex-');
    repo = await createRepo(tmp);
    Directory('$repo/specs').createSync();
    File('$repo/specs/SPEC-001-saudacoes.md').writeAsStringSync(_spec);
    if (ownAgent) {
      File('$repo/.claude/agents/spec-reviewer.md')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('---\nname: spec-reviewer\n---\nRevise.\n');
    }
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'spec']);
    Directory('$repo/.promptorium').createSync();
    File('$repo/.promptorium/config.yml').writeAsStringSync(config);
    cli = FakeCli();
    servers = [];
    codexFails = false;
    c = sessionContainer([
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      codexProcessStarterProvider.overrideWithValue((
        exe,
        args, {
        workingDirectory,
        environment,
      }) async {
        if (codexFails) throw const ProcessException('codex', [], 'sem login');
        final s = FakeCodex(
          threadId: 'th-${servers.length}',
          models: const [
            {
              'id': 'gpt-6.1-terra',
              'supportedReasoningEfforts': ['low', 'medium'],
              'inputModalities': ['text'],
            },
          ],
        );
        servers.add(s);
        return s;
      }),
    ]);
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    await c.read(specServiceProvider).sync(ws);
    spec = (await c.read(specsRepoProvider).getByCode(ws.id, 'SPEC-001'))!;
  }

  tearDown(() async {
    c.dispose();
    for (final s in servers) {
      await s.finish();
    }
    tmp.deleteSync(recursive: true);
  });

  /// A spec "executed" by [provider]: its worktree with one commit and a
  /// done step session of that provider, in the Review column.
  Future<String> executedBy(String provider) async {
    final wt = '${tmp.path}/wt/spec-001';
    await gitIn(repo, ['worktree', 'add', '-q', '-b', 'spec/001', wt]);
    File('$wt/ola.txt').writeAsStringSync('ola\n');
    await gitIn(wt, ['add', '.']);
    await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1: ola']);
    await c
        .read(specsRepoProvider)
        .setWorktree(spec.id, path: wt, branch: 'spec/001', baseBranch: 'main');
    await c
        .read(sessionsRepoProvider)
        .insert(
          id: 'exec',
          workspaceId: ws.id,
          worktreePath: wt,
          branch: 'spec/001',
          model: provider == 'codex' ? 'gpt-6.1-terra' : 'sonnet',
          provider: provider,
          specId: spec.id,
          steps: 'R1,R2',
          status: SessionStatus.completed,
        );
    await c.read(specStepsRepoProvider).setAll(spec.id, [
      'R1',
      'R2',
    ], StepStatus.done);
    await c.read(specsRepoProvider).setStage(spec.id, SpecStage.review);
    await c
        .read(specsRepoProvider)
        .setReview(spec.id, phase: ReviewPhase.auto, rounds: 0);
    return wt;
  }

  Future<Map<String, dynamic>> codexTurn() async {
    await until(
      () async =>
          servers.isNotEmpty &&
          servers.last.writtenJson.any((m) => m['method'] == 'turn/start'),
    );
    return servers.last.writtenJson.lastWhere(
      (m) => m['method'] == 'turn/start',
    );
  }

  Map<String, dynamic> thread() =>
      servers.last.writtenJson.lastWhere((m) => m['method'] == 'thread/start');

  test('spec executada no Codex é revisada pelo Codex com o schema atual: '
      'sem alias do Claude, agente ou orçamento; achados normalizados e '
      'autoria gravada (R2, R4–R9)', () async {
    await setUpRepo(
      'revisor:\n  ligado: true\n  modelo: haiku\n  orcamento: 0.3\n'
      '  rodadas: 2\n  modelo-codex: gpt-6.1-terra\n',
      ownAgent: true,
    );
    final wt = await executedBy('codex');
    final done = c.read(autoReviewerProvider).review(spec.id);
    final turn = await codexTurn();
    // R5: read-only, never asks; the same schema (strict variant).
    expect(thread()['params']['sandbox'], 'read-only');
    expect(thread()['params']['approvalPolicy'], 'never');
    expect(turn['params']['outputSchema'], isNotNull);
    final sent = jsonEncode(servers.last.writtenJson);
    // R4, R6, R7: no Claude alias, budget or agent reaches the Codex.
    expect(thread()['params']['model'], 'gpt-6.1-terra');
    expect(sent, isNot(contains('haiku')));
    expect(sent, isNot(contains('maxBudget')));
    expect(sent, isNot(contains('spec-reviewer')));
    // R7: the built-in reviewer instead of the project's agent.
    expect(
      jsonEncode(thread()['params']),
      contains('Você é o revisor automático do Promptorium'),
    );
    expect(jsonEncode(turn['params']), contains('Revise a implementação'));
    expect(cli.processes, isEmpty);

    servers.last.answer(
      jsonEncode({
        'veredito': 'aprovar',
        'resumo': 'Ok, com ressalvas.',
        'criterios': [
          {'indice': 1, 'atendido': true},
        ],
        'comentarios': [
          {
            'arquivo': '$wt/ola.txt',
            'linha': 1,
            'texto': 'sem quebra final',
            'severidade': 'alta',
            'requisito': 'R7',
          },
          {
            'arquivo': 'lib/legado.dart',
            'linha': 3,
            'texto': 'ainda importado',
            'severidade': 'baixa',
            'requisito': 'R1',
          },
        ],
      }),
    );
    servers.last.emit(
      jsonEncode({
        'method': 'thread/tokenUsage/updated',
        'params': {
          'threadId': servers.last.threadId,
          'tokenUsage': {
            'total': {
              'inputTokens': 41000,
              'cachedInputTokens': 0,
              'outputTokens': 300,
              'reasoningOutputTokens': 50,
            },
            'last': {'totalTokens': 41300},
          },
        },
      }),
    );
    servers.last.completeTurn();
    await done;
    await settle();

    final s = await row();
    expect(s.reviewPhase, ReviewPhase.human);
    expect(s.stage, SpecStage.review);
    final rows = await c.read(reviewCommentsRepoProvider).bySpec(spec.id);
    final head = rows.first;
    expect(head.verdict, 'aprovar');
    expect(head.provider, 'codex');
    expect(head.model, 'gpt-6.1-terra');
    // R8: relative path anchored on the diff; outside → general comment.
    expect(rows[1].path, 'ola.txt');
    expect(rows[1].line, 1);
    expect(rows[1].severity, 'alta');
    expect(rows[1].requirement, isNull);
    expect(rows[2].path, isNull);
    expect(rows[2].body, 'lib/legado.dart:3 — ainda importado');
    expect(rows[2].requirement, 'R1');
    // Only the verdict line carries the authorship.
    expect(rows.skip(1).every((r) => r.provider == null), isTrue);
    final marks = await c.read(reviewCommentsRepoProvider).criteria(spec.id);
    expect(marks.single.checked, isTrue);
    // R10: the ledger has the round, with tokens and no cost.
    final usage = await c.read(usageEntriesRepoProvider).bySpec(spec.id).first;
    expect(usage.single.provider, 'codex');
    expect(usage.single.step, 'rodada 1');
    // SPEC-097: no cost on the Codex (the row of a provider without cost).
    expect(usage.single.costUsd, 0);
    expect(usage.single.tokensIn, greaterThan(0));
  });

  test('segunda opinião: spec do Claude com provedor: outro é revisada pelo '
      'Codex, e o REV1 roda no Claude Code (R2, R9, R11)', () async {
    await setUpRepo(
      'revisor:\n  ligado: true\n  modelo: haiku\n  rodadas: 2\n'
      '  provedor: outro\n',
    );
    await c.read(specRunnerProvider).runNext(spec.id);
    await settle();
    final wt = (await row()).worktreePath!;
    File('$wt/ola.txt').writeAsStringSync('ola\n');
    await gitIn(wt, ['add', '.']);
    await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1, R2: ola']);
    cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1, R2'));

    await codexTurn();
    expect(cli.processes, hasLength(1), reason: 'the reviewer is the Codex');
    servers.last.answer(
      jsonEncode({
        'veredito': 'corrigir',
        'resumo': 'Falta tchau.txt.',
        'criterios': <Object>[],
        'comentarios': [
          {
            'arquivo': 'tchau.txt',
            'linha': 0,
            'texto': 'crie tchau.txt',
            'severidade': 'alta',
            'requisito': 'R2',
          },
        ],
      }),
    );
    servers.last.completeTurn();
    // R11: the correction runs on the provider that executed (Claude).
    await until(() async => cli.processes.length == 2);
    final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
    expect(sessions.last.steps, 'REV1');
    expect(sessions.last.provider, 'claude');
    expect(
      cli.last.writtenJson.single['message']['content'] as String,
      contains('crie tchau.txt'),
    );
    expect(servers, hasLength(1), reason: 'the Codex never edits');
    final head = (await c.read(reviewCommentsRepoProvider).bySpec(spec.id))
        .first;
    expect(head.provider, 'codex');
    expect(head.verdict, 'corrigir');
    // The general comment of a file outside the diff keeps its path.
    expect(
      (await c.read(reviewCommentsRepoProvider).bySpec(spec.id))[1].body,
      'tchau.txt — crie tchau.txt',
    );
  });

  test('Codex indisponível: a rodada falha com o motivo, não aprova e não '
      'troca de provedor; "desta vez" revisa no Claude Code (R2)', () async {
    await setUpRepo(
      'revisor:\n  ligado: true\n  modelo: haiku\n  provedor: codex\n',
    );
    await executedBy('claude');
    codexFails = true;
    await c.read(autoReviewerProvider).review(spec.id);
    await settle();
    expect(cli.processes, isEmpty, reason: 'no silent switch to Claude');
    var rows = await c.read(reviewCommentsRepoProvider).bySpec(spec.id);
    expect(rows.single.verdict, isNull);
    expect(rows.single.body, startsWith(AutoReviewer.failurePrefix));
    expect(rows.single.body, contains('Codex'));
    expect(rows.single.provider, 'codex');
    expect((await row()).reviewPhase, ReviewPhase.human);

    // "Revisar com o Claude Code desta vez": this round only.
    final again = c
        .read(autoReviewerProvider)
        .review(spec.id, providerOnce: 'claude');
    await until(() async => cli.processes.length == 1);
    expect(cli.args.last, containsAllInOrder(['--model', 'haiku']));
    final j = jsonDecode(resultLine('{}')) as Map;
    j['structured_output'] = {
      'veredito': 'aprovar',
      'resumo': 'Ok.',
      'comentarios': <Object>[],
      'criterios': <Object>[],
    };
    cli.last.emit(jsonEncode(j));
    await again;
    await settle();
    rows = await c.read(reviewCommentsRepoProvider).bySpec(spec.id);
    expect(rows.last.verdict, 'aprovar');
    expect(rows.last.provider, 'claude');
  });

  test('resposta fora do schema no Codex vira falha da rodada, sem '
      'aprovar (R5)', () async {
    await setUpRepo('revisor:\n  ligado: true\n  provedor: codex\n');
    await executedBy('claude');
    final done = c.read(autoReviewerProvider).review(spec.id);
    await codexTurn();
    servers.last.answer('{"veredito": "talvez"}');
    servers.last.completeTurn();
    await done;
    await settle();
    final rows = await c.read(reviewCommentsRepoProvider).bySpec(spec.id);
    expect(rows.single.verdict, isNull);
    expect(rows.single.body, startsWith(AutoReviewer.failurePrefix));
    expect(rows.single.provider, 'codex');
  });

  test('Automático: a regra do plano (Claude) vale sem provedor: explícito; '
      'com provedor: codex, o config vence (R3)', () async {
    await setUpRepo('revisor:\n  ligado: true\n  modelo: haiku\n');
    await executedBy('claude');
    await c
        .read(specStepsRepoProvider)
        .setPlan(
          spec.id,
          'R1',
          kind: 'implementacao',
          model: 'sonnet',
          effort: 'medium',
        );
    final first = c.read(autoReviewerProvider).review(spec.id);
    await until(() async => cli.processes.length == 1);
    expect(servers, isEmpty);
    final j = jsonDecode(resultLine('{}')) as Map;
    j['structured_output'] = {
      'veredito': 'aprovar',
      'resumo': 'Ok.',
      'comentarios': <Object>[],
      'criterios': <Object>[],
    };
    cli.last.emit(jsonEncode(j));
    await first;

    File('$repo/.promptorium/config.yml').writeAsStringSync(
      'revisor:\n  ligado: true\n  modelo: haiku\n  provedor: codex\n',
    );
    final second = c.read(autoReviewerProvider).review(spec.id);
    await codexTurn();
    expect(cli.processes, hasLength(1));
    servers.last.answer(
      jsonEncode({
        'veredito': 'aprovar',
        'resumo': 'Ok.',
        'comentarios': <Object>[],
        'criterios': <Object>[],
      }),
    );
    servers.last.completeTurn();
    await second;
    await settle();
    final heads = [
      for (final r in await c.read(reviewCommentsRepoProvider).bySpec(spec.id))
        if (r.verdict != null) r.provider,
    ];
    expect(heads, ['claude', 'codex']);
  });
}
