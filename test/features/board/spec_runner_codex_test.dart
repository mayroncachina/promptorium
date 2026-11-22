import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/codex/codex_probe.dart';
import 'package:promptorium/core/providers/agent_event.dart' show QuotaWindow;
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/quota_source.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/spec_run_provider.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/board/orchestrator/step_classifier.dart';
import 'package:promptorium/features/sessions/app_notifier.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart' show AppEventTypes;
import 'package:promptorium/features/specs/spec_service.dart';

import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

const _specText = '''---
id: SPEC-031
status: aprovada
subagentes:
  - agente: spec-reviewer
    quando: fim-da-spec
---

# Pagamento com Stripe

## Requisitos

- R1 · Cliente Stripe e chaves
- R2 · Checkout com cartão
- R3 · Testes do checkout
- R4 · Webhook
''';

/// Answers the classifier without a model: the test fails if it is called.
class _NoClassifier extends StepClassifier {
  var calls = 0;

  @override
  Future<Object?> request(
    Spec spec,
    List<ClassifierTarget> targets,
    Future<void> cancelled,
  ) async {
    calls++;
    throw StateError('o Orquestrador não roda com o Codex');
  }
}

void main() {
  late Directory tmp;
  late String repo;
  late FakeCli claude;
  late List<FakeCodex> servers;
  late ProviderContainer c;
  late Workspace ws;
  late Spec spec;
  late _NoClassifier classifier;

  final catalog = CodexModelsCache(
    version: '0.170.0',
    readAt: DateTime(2026, 11, 20),
    models: const [
      CodexModelInfo('gpt-6.1-terra', ['low', 'medium', 'high'], ['text']),
    ],
  ).encode();

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('codex-runner-');
    repo = await createRepo(tmp);
    Directory('$repo/specs').createSync();
    File('$repo/specs/SPEC-031-stripe.md').writeAsStringSync(_specText);
    Directory('$repo/.promptorium').createSync();
    File('$repo/.promptorium/config.yml').writeAsStringSync(
      'agente: spec-implementer\n'
      'git:\n'
      '  marcar-commits-de-agente: true\n',
    );
    claude = FakeCli();
    servers = [];
    classifier = _NoClassifier();
    c = sessionContainer([
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: claude,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      stepClassifierProvider.overrideWith(() => classifier),
      // The sandbox check would start one more App Server (R10a).
      providerAvailabilityProvider.overrideWith(
        (ref, id) async =>
            const ProviderAvailability(ProviderStatus.ready, 'ok'),
      ),
      codexProcessStarterProvider.overrideWithValue((
        exe,
        args, {
        workingDirectory,
        environment,
      }) async {
        final server = FakeCodex(
          threadId: 'thread-${servers.length}',
          models: const [
            {
              'id': 'gpt-6.1-terra',
              'supportedReasoningEfforts': [
                {'reasoningEffort': 'low'},
                {'reasoningEffort': 'medium'},
              ],
              'inputModalities': ['text'],
            },
          ],
        );
        servers.add(server);
        return server;
      }),
    ]);
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    await c.read(specServiceProvider).sync(ws);
    spec = (await c.read(specsRepoProvider).getByCode(ws.id, 'SPEC-031'))!;
    final settings = c.read(appSettingsProvider.notifier);
    await settings.set(codexModelsCacheKey, catalog);
    await settings.set('codex.effort.session', 'medium');
    // A Claude model for Sessões never goes to the Codex (R3).
    await settings.set('claude.model.session', 'opus');
    // The footer on the Codex: the kind "Executar spec" follows it.
    await settings.set(providerPreferenceKey(ws.id), 'codex');
  });

  tearDown(() async {
    await c.read(sessionManagerProvider.notifier).shutdown();
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<List<String>> notes(String id) async => [
    for (final e in await c.read(sessionsRepoProvider).events(id))
      if (e.type == AppEventTypes.note)
        (jsonDecode(e.json) as Map)['text'] as String,
  ];

  String sentText(FakeCodex s) {
    final turn = s.writtenJson.lastWhere((m) => m['method'] == 'turn/start');
    return ((turn['params'] as Map)['input'] as List).first['text'] as String;
  }

  Future<Map<String, StepStatus>> states() async {
    final s = (await c.read(specsRepoProvider).getById(spec.id))!;
    final rows = await c.read(specStepsRepoProvider).bySpec(spec.id);
    return {for (final v in stepsOf(s, rows)) v.id: v.status};
  }

  /// The end of a Codex turn with [text] as the final answer.
  Future<void> finishTurn(FakeCodex s, String text) async {
    s
      ..answer(text)
      ..completeTurn();
    await settle();
  }

  void usage(FakeCodex s, int tokens, int window) => s.emit(
    jsonEncode({
      'method': 'thread/tokenUsage/updated',
      'params': {
        'threadId': s.threadId,
        'turnId': 'turn-1',
        'tokenUsage': {
          'last': {'totalTokens': tokens, 'inputTokens': tokens},
          'total': {'totalTokens': tokens, 'inputTokens': tokens},
          'modelContextWindow': window,
        },
      },
    }),
  );

  test('R2, R3, R6: the spec runs on the Codex of the kind with a catalog '
      'model, the agent translated (SPEC-106) and without subagents; the '
      'footer switched mid-run does not move the next steps', () async {
    final runner = c.read(specRunnerProvider);
    final first = await runner.runNext(spec.id);
    await settle();
    final s1 = (await c.read(sessionsRepoProvider).getById(first))!;
    expect(s1.provider, 'codex');
    expect(s1.model, 'gpt-6.1-terra');
    expect(s1.effort, 'medium');
    // SPEC-106 R8: the project's agent goes to the Codex (translated; the
    // file does not exist here, so the session says so and goes on).
    expect(s1.agentName, 'spec-implementer');
    expect(s1.permissionMode, ClaudePermissionMode.acceptEdits.cliValue);
    expect(recordedSpecProvider(c.read(appSettingsProvider), spec.id), 'codex');
    final prompt = sentText(servers.last);
    expect(prompt, contains('<spec>'));
    expect(prompt, isNot(contains('Subagentes desta spec')));
    expect(prompt, isNot(contains('spec-reviewer:')));
    final thread = servers.last.writtenJson.firstWhere(
      (m) => m['method'] == 'thread/start',
    );
    expect((thread['params'] as Map)['model'], 'gpt-6.1-terra');
    expect(claude.processes, isEmpty);
    expect(
      await notes(first),
      containsAll([
        'Agente spec-implementer não encontrado em .claude/agents: a sessão '
            'segue sem ele.',
        // SPEC-106 R9: only the subagents stay with the Claude Code.
        'Esta spec define 1 subagente (`spec-reviewer`). No Codex ele não '
            'roda: a sessão principal faz o trabalho dele.',
      ]),
    );

    // The footer goes back to the Claude Code in the middle of the run.
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(ws.id), 'claude');
    await finishTurn(servers.last, 'Pronto.\nETAPA CONCLUÍDA: R1');
    await until(() async => (await states())['R2'] == StepStatus.running);
    final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
    expect(sessions, hasLength(2));
    expect(sessions.last.provider, 'codex');
    expect(sessions.last.model, 'gpt-6.1-terra');
    expect(claude.processes, isEmpty);
    // R10: without a reading, the old "só sessões do Claude" is gone.
    final why = await notes(first);
    expect(
      why,
      contains('R2 vai para uma sessão nova: sem medição do contexto.'),
    );
    expect(why.where((n) => n.contains('só sessões do Claude')), isEmpty);
    // R6: the note is written once per run.
    expect(
      (await notes(sessions.last.id))
          .where((n) => n.contains('No Codex ele não roda')),
      isEmpty,
    );
  });

  test('R10, P2: the next step continues in the same Codex session below '
      '70% of the reported window and the configured limit', () async {
    await c
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.continueContextTokens, '150');
    final runner = c.read(specRunnerProvider);
    final id = await runner.runNext(spec.id);
    await settle();
    usage(servers.last, 96000, 400000);
    await finishTurn(servers.last, 'ETAPA CONCLUÍDA: R1');
    await until(() async => (await states())['R2'] == StepStatus.running);
    expect(servers, hasLength(1));
    expect(
      await notes(id),
      contains(
        'R2 continua nesta sessão (contexto 96 mil de 400 mil, limite '
        'efetivo 150 mil).',
      ),
    );
    expect(sentText(servers.last), contains('Continue nesta sessão'));

    // A smaller window: 70% of 120 mil = 84 mil < 96 mil → new session.
    usage(servers.last, 96000, 120000);
    await finishTurn(servers.last, 'ETAPA CONCLUÍDA: R2');
    await until(() async => (await states())['R3'] == StepStatus.running);
    expect(
      await notes(id),
      contains(
        'R3 vai para uma sessão nova: contexto 96 mil passou do limite de '
        '84 mil.',
      ),
    );
    final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
    expect(sessions.map((s) => s.provider), ['codex', 'codex']);
  });

  test('R5, R14: "Abrir Executar em Automático" with the Codex runs in '
      'Manual and the timeline says why once', () async {
    await c
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.orchestratorAutoByDefault, '1');
    final runner = c.read(specRunnerProvider);
    final id = await runner.runAuto(spec.id);
    await settle();
    expect(classifier.calls, 0);
    expect(claude.processes, isEmpty);
    final s = (await c.read(sessionsRepoProvider).getById(id))!;
    expect(s.provider, 'codex');
    expect(s.model, 'gpt-6.1-terra');
    expect(await notes(id), contains(autoOnlyClaudeNote));
    final rows = await c.read(specStepsRepoProvider).bySpec(spec.id);
    expect(rows.where((r) => r.planModel != null), isEmpty);
  });

  test('R7: "Refazer etapa" keeps the provider and the Codex model of the '
      "step's last session", () async {
    final runner = c.read(specRunnerProvider);
    final first = await runner.runNext(spec.id);
    await settle();
    await finishTurn(servers.last, 'Não deu.');
    await c.read(sessionManagerProvider.notifier).stop(first);
    await settle();
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(ws.id), 'claude');
    final again = await runner.redo(spec.id, 'R1');
    await settle();
    final s = (await c.read(sessionsRepoProvider).getById(again))!;
    expect(s.provider, 'codex');
    expect(s.model, 'gpt-6.1-terra');
    expect(claude.processes, isEmpty);
  });

  test('R11: a step commit without the trailer is reported once, never '
      'invented', () async {
    final runner = c.read(specRunnerProvider);
    final id = await runner.runNext(spec.id);
    await settle();
    final wt = (await c.read(specsRepoProvider).getById(spec.id))!
        .worktreePath!;
    File('$wt/r1.txt').writeAsStringSync('ok');
    await gitIn(wt, ['add', '.']);
    await gitIn(wt, ['commit', '-q', '-m', 'SPEC-031 R1: cliente']);
    await finishTurn(servers.last, 'Sem marcador ainda.');
    await until(
      () async => (await notes(id)).any((n) => n.contains('sem o trailer')),
    );
    final log = await gitIn(wt, ['log', '-1', '--format=%B']);
    expect(log, isNot(contains('Promptorium-Agente')));
  });

  test('R14, P3: with the Codex 5-hour window above 90% the autopilot '
      'starts no Codex spec and says so', () async {
    await c
        .read(appSettingsProvider.notifier)
        .set(
          AppSettingKeys.codexLastRateLimit,
          jsonEncode(
            QuotaSnapshot(
              provider: 'codex',
              main: QuotaBucket(
                id: 'codex',
                windows: [
                  QuotaWindow(
                    id: 'primary',
                    label: '5 h',
                    usedPercent: 92,
                    minutes: 300,
                    resetsAt: DateTime.now().add(const Duration(hours: 2)),
                  ),
                ],
              ),
              ordinaryUsageAllowed: true,
            ).toJson(),
          ),
        );
    await settle();
    final notifier = c.read(appNotifierProvider) as FakeNotifier;
    await c.read(autopilotProvider.notifier).start(ws.id);
    await settle();
    expect(servers, isEmpty);
    expect(claude.processes, isEmpty);
    expect(
      notifier.shown,
      contains(
        isA<(String, String)>()
            .having((n) => n.$1, 'title', 'Autopilot parado')
            .having((n) => n.$2, 'body', contains('cota do Codex em 92%')),
      ),
    );
  });

  test(
    'R14: the budget of the day counts only sessions with a cost in US\$',
    () async {
      final repo = c.read(sessionsRepoProvider);
      await repo.insert(
        id: 'claude-1',
        workspaceId: ws.id,
        worktreePath: '/x',
        branch: 'b',
        model: 'sonnet',
        specId: spec.id,
        costUsd: 0.40,
        status: SessionStatus.completed,
      );
      await repo.insert(
        id: 'codex-1',
        workspaceId: ws.id,
        worktreePath: '/x',
        branch: 'b',
        model: 'gpt-6.1-terra',
        provider: 'codex',
        specId: spec.id,
        // A stray value never counts: the Codex has no cost in US\$.
        costUsd: 9,
        status: SessionStatus.completed,
      );
      expect(
        await c.read(autopilotProvider.notifier).spentToday(ws.id),
        closeTo(0.40, 1e-9),
      );
    },
  );

  test('R1: Executar spec released for the Codex', () {
    expect(
      specRunProviderFor(
        {providerPreferenceKey(ws.id): 'codex'},
        spec.id,
        workspaceId: ws.id,
      ),
      'codex',
    );
    // P4: a run begun on the Claude Code stays there.
    expect(
      specRunProviderFor(
        {
          providerPreferenceKey(ws.id): 'codex',
          specProviderKey(spec.id): 'claude',
        },
        spec.id,
        workspaceId: ws.id,
      ),
      'claude',
    );
  });
}
