import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/usage_poller.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/quota_source.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/conversations_repo.dart';
import 'package:promptorium/features/prompt/compare/compare_controller.dart';
import 'package:promptorium/features/prompt/compare/compare_run.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/plan_ready.dart';
import 'package:promptorium/features/sessions/session_manager.dart'
    show sessionIdGeneratorProvider;
import 'package:promptorium/features/sessions/timeline.dart';

import '../../../core/claude/claude_event_test.dart' show permissionRequestLine;
import '../../../core/codex/fake_codex.dart';
import '../../../helpers/test_db.dart' show memoryDatabase;
import '../../sessions/session_test_utils.dart' show idSequence, settle;
import '../prompt_test_utils.dart';
import 'compare_test_utils.dart'
    show
        codexCommandItem,
        codexFinish,
        codexLimits,
        codexParams,
        fakeCodexProvider,
        weekReset;

String usage(int five, int week) =>
    'Current session: $five% used · resets 2pm\n'
    'Current week (all models): $week% used · resets ${weekReset()}\n';

Map<String, dynamic> resultOf({
  double cost = 0.01,
  int ms = 38000,
  int input = 14000,
  int output = 900,
}) => {
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'total_cost_usd': cost,
  'num_turns': 1,
  'duration_ms': ms,
  'usage': {
    'input_tokens': input,
    'output_tokens': output,
    'cache_read_input_tokens': 200,
  },
  'permission_denials': [],
  'result': 'ok',
  'session_id': 's',
};

Map<String, dynamic> toolLine(String id, String name) => {
  'type': 'assistant',
  'message': {
    'id': 'm-$id',
    'role': 'assistant',
    'content': [
      {
        'type': 'tool_use',
        'id': id,
        'name': name,
        'input': {'file_path': '/work/repo/lib/a.dart'},
      },
    ],
  },
  'parent_tool_use_id': null,
  'session_id': 's',
};

Map<String, dynamic> planRequest(String plan) => {
  'type': 'control_request',
  'request_id': 'plan-1',
  'request': {
    'subtype': 'can_use_tool',
    'tool_name': 'ExitPlanMode',
    'input': {'plan': plan},
    'tool_use_id': 'toolu_plan',
  },
};

void main() {
  late AppDatabase db;
  late FakeAgentProvider provider;
  late ProviderContainer c;
  late Workspace ws;
  late List<String?> usages;
  late List<FakeCodex> servers;
  late List<Map<String, dynamic>> codexUsages;
  late ProviderAvailability codexStatus;

  CompareController ctl() => c.read(compareControllerProvider.notifier);

  ProviderContainer container() {
    final k = ProviderContainer(
      overrides: [
        // Not closed with the container: "reopening the app" keeps it.
        appDatabaseProvider.overrideWithValue(db),
        sessionIdGeneratorProvider.overrideWithValue(idSequence()),
        // SPEC-108: the Codex beside the Claude, on the App Server fake.
        agentProvidersProvider.overrideWithValue([
          provider,
          fakeCodexProvider(servers),
        ]),
        providerAvailabilityProvider.overrideWith(
          (ref, id) async => codexStatus,
        ),
        codexQuotaReaderProvider.overrideWithValue(
          () async => codexUsages.isEmpty
              ? throw StateError('sem leitura')
              : codexUsages.removeAt(0),
        ),
        usageRunnerProvider.overrideWithValue(
          () async => usages.isEmpty ? null : usages.removeAt(0),
        ),
      ],
    );
    k.listen(compareControllerProvider, (_, _) {});
    k.listen(conversationManagerProvider, (_, _) {});
    return k;
  }

  setUp(() async {
    db = memoryDatabase();
    provider = FakeAgentProvider();
    servers = [];
    codexUsages = [codexLimits(12, 30), codexLimits(15, 31)];
    codexStatus = const ProviderAvailability(ProviderStatus.ready, 'ok');
    usages = [usage(38, 61), usage(48, 63)];
    c = container();
    ws = await addWorkspace(db, '/work/repo');
    await c.read(appSettingsProvider.notifier).load();
    await c.read(providerAvailabilityProvider('codex').future);
  });

  tearDown(() async {
    await ctl().shutdown();
    for (final f in servers) {
      await f.finish();
    }
    c.dispose();
    await db.close();
  });

  ConversationsRepo repo() => c.read(conversationsRepoProvider);

  Future<int> existing({String? session = 'orig'}) async {
    final conv = await repo().insert(
      workspaceId: ws.id,
      title: 'Cupons expirados',
      model: 'sonnet',
      claudeSessionId: session,
    );
    return conv.id;
  }

  Future<int> startCompare(
    int? id, {
    CompareChoice a = const CompareChoice(
      model: 'sonnet',
      mode: PromptMode.ask,
    ),
    CompareChoice b = const CompareChoice(model: 'opus', mode: PromptMode.ask),
  }) => ctl().start(
    workspace: ws,
    conversationId: id,
    prompt: 'por que o cupom aceita cliente antigo?',
    a: a,
    b: b,
  );

  FakeRun runOf(String letter) => provider.runs[letter == 'A' ? 0 : 1];

  CompareRun view(int id) => c.read(compareProvider(id))!.run;

  test('both sides start together as forks of the conversation; the '
      'original session does not change (R5)', () async {
    final id = await existing();
    await startCompare(id);
    expect(provider.runs, hasLength(2));
    final a = runOf('A').options, b = runOf('B').options;
    expect(a.resumeId, 'orig');
    expect(b.resumeId, 'orig');
    expect(a.forkSession, isTrue);
    expect(b.forkSession, isTrue);
    expect(a.sessionId, isNot(b.sessionId));
    expect(a.sessionId, isNotNull);
    expect((a.model, a.mode), ('sonnet', PromptMode.ask));
    expect((b.model, b.mode), ('opus', PromptMode.ask));
    expect(a.workingDirectory, '/work/repo');
    expect(runOf('A').sent, ['por que o cupom aceita cliente antigo?']);
    expect(runOf('B').sent, ['por que o cupom aceita cliente antigo?']);
    expect((await repo().getById(id))!.claudeSessionId, 'orig');
    final rows = await repo().events(id);
    expect(rows.single.type, AppEventTypes.compare);
    // Open, it shows nothing in the conversation (the columns do).
    c.read(conversationTimelineProvider(id));
    await settle();
    expect(c.read(conversationTimelineProvider(id)).items, isEmpty);
    expect(view(id).before['claude']!.five, 0.38);
    expect(view(id).sides.map((s) => s.state), [
      CompareSideState.running,
      CompareSideState.running,
    ]);
    // P8: the pair is remembered for the workspace.
    expect(
      decodeCompareSides(c.read(appSettingsProvider)[compareSidesKey(ws.id)]),
      isNotNull,
    );
  });

  test('a new conversation starts new sessions, without --resume', () async {
    final id = await startCompare(null);
    final a = runOf('A').options;
    expect(a.resumeId, isNull);
    expect(a.forkSession, isFalse);
    expect(a.sessionId, isNotNull);
    final conv = await repo().getById(id);
    expect(conv!.title, 'por que o cupom aceita cliente antigo?');
    expect(conv.model, 'sonnet');
  });

  test('equal sides, Editar and a second comparison are refused (R2, R3, '
      'R14)', () async {
    final id = await existing();
    await expectLater(
      startCompare(
        id,
        b: CompareChoice(model: 'sonnet', mode: PromptMode.ask),
      ),
      throwsA(isA<ConversationException>()),
    );
    await expectLater(
      startCompare(
        id,
        b: CompareChoice(model: 'opus', mode: PromptMode.edit),
      ),
      throwsA(isA<ConversationException>()),
    );
    await startCompare(id);
    await expectLater(
      startCompare(id),
      throwsA(
        isA<ConversationException>().having(
          (e) => e.message,
          'message',
          compareBlockedMessage,
        ),
      ),
    );
  });

  test('metrics per side; requests and Parar go to one side only; the '
      'weight splits the rise of the usage (R7–R10)', () async {
    final id = await existing();
    await startCompare(id);
    final a = runOf('A'), b = runOf('B');
    a.emit(initLine(a.options.sessionId!));
    a.emit(toolLine('t1', 'Read'));
    a.emit(toolLine('t2', 'Grep'));
    a.emit(textLine('Só olha pedidos pagos.'));
    a.emit(resultOf(cost: 0.10, ms: 38000));
    await settle();
    var run = view(id);
    expect(run.a.state, CompareSideState.done);
    expect(run.a.metrics!.durationMs, 38000);
    expect(run.a.metrics!.tokensIn, 14200);
    expect(run.a.metrics!.tools, {'Read': 1, 'Grep': 1});
    expect(run.b.state, CompareSideState.running);
    // The idle process of a finished side is not kept.
    expect(a.stopped, isTrue);
    // No weight until both end.
    expect(run.a.weight, isNull);

    // R9: B asks; only B sees it, the answer goes to B.
    b.emit(initLine(b.options.sessionId!));
    b.emit(jsonDecode(permissionRequestLine) as Map<String, dynamic>);
    await settle();
    final live = c.read(compareProvider(id))!;
    expect(live.liveOf('A').approvals, isEmpty);
    expect(live.liveOf('B').approvals.single.requestId, 'req-1');
    await ctl().approve(id, 'B', 'req-1');
    expect(b.approved.single.$1, 'req-1');
    expect(a.approved, isEmpty);

    // R10: Parar of B keeps what it answered, "interrompida".
    b.emit(textLine('Parcial', id: 'mb'));
    await settle();
    await ctl().stop(id, 'B');
    await settle();
    run = view(id);
    expect(run.b.state, CompareSideState.stopped);
    expect(run.b.state.choosable, isTrue);
    expect(
      c
          .read(compareProvider(id))!
          .liveOf('B')
          .timeline
          .items
          .whereType<AssistantTextItem>()
          .single
          .text,
      'Parcial',
    );
    // R8: 10 points of the window, all of it from A (B has no cost).
    await settle();
    run = view(id);
    expect(run.measured, isTrue);
    expect(run.a.weight!.five, closeTo(0.10, 1e-9));
    expect(run.a.weight!.week, closeTo(0.02, 1e-9));
    expect(run.b.weight!.five, 0);
  });

  test(
    'both comparison forks enter the usage ledger even when discarded',
    () async {
      final id = await existing();
      await startCompare(id);
      runOf('A').emit(resultOf(cost: 0.1));
      runOf('B').emit(resultOf(cost: 0.4));
      await settle();
      await settle();
      await ctl().discard(id);
      final entries = await db.select(db.usageEntries).get();
      expect(entries, hasLength(2));
      expect(
        {for (final e in entries) e.model: e.costUsd},
        {'sonnet': 0.1, 'opus': 0.4},
      );
      expect(
        entries.every((e) => e.conversationId == id && e.specId == null),
        isTrue,
      );
      expect(entries.fold(0, (n, e) => n + e.tokensOut), 1800);
    },
  );

  test('choosing a side moves the conversation onto its fork, model and '
      'mode, and keeps the other folded (R11)', () async {
    final id = await existing();
    await startCompare(id);
    final a = runOf('A'), b = runOf('B');
    a.emit(initLine(a.options.sessionId!));
    a.emit(textLine('Resposta do Sonnet'));
    a.emit(resultOf(cost: 0.1));
    b.emit(initLine(b.options.sessionId!));
    b.emit(textLine('Resposta do Opus', id: 'mb'));
    b.emit(resultOf(cost: 0.4, ms: 112000));
    await settle();
    await settle();
    final chosen = await ctl().choose(id, 'B');
    expect(chosen.letter, 'B');
    final conv = (await repo().getById(id))!;
    expect(conv.claudeSessionId, b.options.sessionId);
    expect(conv.model, 'opus');
    expect(conv.mode, 'ask');
    expect(conv.costUsd, closeTo(0.4, 1e-9));
    expect(c.read(compareProvider(id)), isNull);

    final rows = await repo().events(id);
    expect(rows.first.type, AppEventTypes.compare);
    final stored = jsonDecode(rows.first.json) as Map<String, dynamic>;
    expect(stored['status'], 'chosen');
    expect(stored['chosen'], 'B');
    expect(rows.map((r) => r.type), contains('result/success'));
    expect(rows.map((r) => r.type), isNot(contains('system/init')));

    final items = c.read(conversationTimelineProvider(id)).items;
    await settle();
    final loaded = c.read(conversationTimelineProvider(id)).items;
    expect(loaded.whereType<UserItem>().single.text, contains('cupom'));
    final card = loaded.whereType<CompareItem>().single;
    expect(card.text, 'Comparação: Sonnet · Perguntar (não escolhida)');
    expect(
      loaded.whereType<NoticeItem>().map((n) => n.text),
      contains('escolhida entre 2 · Opus · Perguntar'),
    );
    expect(
      loaded.whereType<AssistantTextItem>().single.text,
      'Resposta do Opus',
    );
    expect(items, isNotNull);

    // The next message resumes B's fork.
    await c.read(conversationManagerProvider.notifier).send(id, 'e agora?');
    expect(provider.last.options.resumeId, b.options.sessionId);
    expect(provider.last.options.model, 'opus');
  });

  test('a Planejar side stops at "plano pronto"; chosen, it brings the plan '
      '(R3, R11)', () async {
    final id = await existing();
    await startCompare(
      id,
      a: CompareChoice(model: 'sonnet', mode: PromptMode.plan),
      b: CompareChoice(model: 'sonnet', mode: PromptMode.ask),
    );
    final a = runOf('A');
    expect(a.options.mode, PromptMode.plan);
    a.emit(initLine(a.options.sessionId!));
    a.emit(planRequest('1. Trocar o filtro'));
    await settle();
    expect(a.denied, ['plan-1']);
    a.emit(resultOf());
    await settle();
    expect(view(id).a.state, CompareSideState.planReady);
    expect(view(id).a.plan, '1. Trocar o filtro');
    await ctl().stop(id, 'B');
    await settle();
    await ctl().choose(id, 'A');
    expect(c.read(planDraftsProvider)[id], '1. Trocar o filtro');
    expect((await repo().getById(id))!.mode, 'plan');
  });

  test('a running side cannot be chosen', () async {
    final id = await existing();
    await startCompare(id);
    await expectLater(
      ctl().choose(id, 'A'),
      throwsA(isA<ConversationException>()),
    );
  });

  test('discarding stops what runs and goes back to before (R12)', () async {
    final id = await existing();
    await startCompare(id);
    final back = await ctl().discard(id);
    expect(back.prompt, 'por que o cupom aceita cliente antigo?');
    expect(back.deleted, isFalse);
    expect(runOf('A').stopped, isTrue);
    expect(runOf('B').stopped, isTrue);
    expect(await repo().events(id), isEmpty);
    expect((await repo().getById(id))!.claudeSessionId, 'orig');
    expect(c.read(compareProvider(id)), isNull);
  });

  test('discarding the comparison that created the conversation removes '
      'it', () async {
    final id = await startCompare(null);
    final back = await ctl().discard(id);
    expect(back.deleted, isTrue);
    expect(await repo().getById(id), isNull);
  });

  test(
    'reopening the app restores the comparison: the finished side is '
    'ready, the running one interrupted, and it can be resumed (R13)',
    () async {
      final id = await existing();
      await startCompare(id);
      final a = runOf('A'), b = runOf('B');
      a.emit(initLine(a.options.sessionId!));
      a.emit(textLine('Pronta'));
      a.emit(resultOf());
      b.emit(initLine(b.options.sessionId!));
      b.emit(textLine('Pela metade', id: 'mb'));
      await settle();
      await ctl().shutdown();
      c.dispose();

      c = container();
      await c.read(appSettingsProvider.notifier).load();
      await ctl().restore(id);
      final run = view(id);
      expect(run.a.state, CompareSideState.done);
      expect(run.b.state, CompareSideState.stopped);
      expect(
        c
            .read(compareProvider(id))!
            .liveOf('B')
            .timeline
            .items
            .whereType<AssistantTextItem>()
            .single
            .text,
        'Pela metade',
      );
      // R14: still blocks a new one.
      expect(ctl().openOf(id), isNotNull);

      // Retomar continues B's own fork.
      final before = provider.runs.length;
      await ctl().resume(id, 'B');
      expect(provider.runs.length, before + 1);
      final again = provider.last.options;
      expect(again.resumeId, b.options.sessionId);
      expect(again.forkSession, isFalse);
      expect(provider.last.sent, [compareResumeMessage]);
      expect(view(id).b.state, CompareSideState.running);
    },
  );

  // --- SPEC-108: one provider per side --------------------------------------

  const claudeAsk = CompareChoice(model: 'opus', mode: PromptMode.ask);
  const codexAsk = CompareChoice(
    provider: 'codex',
    model: 'gpt-6.2-sol',
    effort: 'medium',
    mode: PromptMode.ask,
  );

  /// A conversation with history.
  Future<int> withHistory({String provider = 'claude'}) async {
    final conv = await repo().insert(
      workspaceId: ws.id,
      title: 'Cupons expirados',
      model: provider == 'codex' ? 'gpt-6.2-sol' : 'opus',
      provider: provider,
      claudeSessionId: 'orig',
    );
    for (final e in [
      AppEventTypes.userMessage(
        'Onde o cupom é validado? Veja @lib/cupons/validar_cupom.dart',
        DateTime.now(),
      ),
      textLine('Em validarCupom(), com o token sk-segredo123456.'),
    ]) {
      await repo().appendEvent(
        conv.id,
        type: '${e['type']}',
        json: jsonEncode(e),
      );
    }
    return conv.id;
  }

  Future<void> wait() => Future<void>.delayed(const Duration(milliseconds: 60));

  test('SPEC-108 R4: the side of the conversation forks its session; the '
      'other starts from the package, with the question whole and no '
      'secret', () async {
    final id = await withHistory();
    await startCompare(id, a: claudeAsk, b: codexAsk);
    await wait();
    final a = runOf('A').options;
    expect((a.resumeId, a.forkSession, a.model), ('orig', true, 'opus'));
    expect(runOf('A').sent, ['por que o cupom aceita cliente antigo?']);
    final f = servers.single;
    expect(codexParams(f, 'thread/start'), isNotNull);
    expect(codexParams(f, 'thread/fork'), isNull);
    final sent =
        ((codexParams(f, 'turn/start')!['input'] as List).single as Map)['text']
            as String;
    expect(sent, contains('Onde o cupom é validado?'));
    expect(sent, contains('@lib/cupons/validar_cupom.dart'));
    expect(
      sent,
      endsWith('Pergunta atual:\npor que o cupom aceita cliente antigo?'),
    );
    expect(sent, isNot(contains('sk-segredo')));
    // R10: the event keeps the provider, the effort and the package.
    final stored =
        jsonDecode((await repo().events(id)).last.json) as Map<String, dynamic>;
    expect((stored['sides'] as List)[1], containsPair('provider', 'codex'));
    expect((stored['sides'] as List)[1], containsPair('effort', 'medium'));
    expect((stored['handoff'] as Map)['files'], [
      'lib/cupons/validar_cupom.dart',
    ]);
    expect((stored['handoff'] as Map)['text'], isNot(contains('sk-segredo')));
  });

  test('SPEC-108 R4: the package edited by the person is the one sent; with '
      '"Mesmo resumo nos dois lados" both receive it', () async {
    final id = await withHistory();
    final conv = (await repo().getById(id))!;
    final built = (await ctl().buildHandoff(conv, ws))!;
    expect(built.messages, 2);
    expect(built.tokens, greaterThan(10));
    await ctl().start(
      workspace: ws,
      conversationId: id,
      prompt: 'e agora?',
      a: claudeAsk,
      b: codexAsk,
      handoff: built.withText('Resumo revisado'),
      sameHandoff: true,
    );
    await wait();
    final a = runOf('A').options;
    expect((a.resumeId, a.forkSession), (null, false));
    expect(a.sessionId, isNotNull);
    const text = 'Resumo revisado\n\nPergunta atual:\ne agora?';
    expect(runOf('A').sent, [text]);
    expect(
      ((codexParams(servers.single, 'turn/start')!['input'] as List).single
          as Map)['text'],
      text,
    );
  });

  test('SPEC-108 R4: a Codex conversation forks on the Codex side '
      '(thread/fork) and the Claude side gets the package', () async {
    final id = await withHistory(provider: 'codex');
    await startCompare(id, a: codexAsk, b: claudeAsk);
    await wait();
    expect(codexParams(servers.single, 'thread/fork')!['threadId'], 'orig');
    final run = provider.runs.single;
    expect(run.options.resumeId, isNull);
    expect(run.sent.single, contains('Pergunta atual:'));
  });

  test('SPEC-108 R4: a new conversation starts both from zero, without a '
      'package', () async {
    final id = await startCompare(null, a: claudeAsk, b: codexAsk);
    await wait();
    expect(runOf('A').sent.single, isNot(contains('Pergunta atual')));
    expect(view(id).handoff, isNull);
    expect((await repo().getById(id))!.provider, 'claude');
  });

  test('SPEC-108 R3: the Codex side runs read-only and without approvals in '
      'Perguntar and Planejar; Planejar ends in "plano pronto"', () async {
    for (final mode in compareModes) {
      servers.clear();
      provider.runs.clear();
      final id = await startCompare(
        null,
        a: claudeAsk.copyWith(mode: mode),
        b: codexAsk.copyWith(mode: mode),
      );
      await wait();
      final f = servers.single;
      final turn = codexParams(f, 'turn/start')!;
      expect(turn['sandboxPolicy'], {'type': 'readOnly'});
      expect(turn['approvalPolicy'], 'never');
      expect(turn['effort'], 'medium');
      codexFinish(f, '1. Trocar o filtro');
      await wait();
      final b = view(id).b;
      if (mode == PromptMode.plan) {
        expect(b.state, CompareSideState.planReady);
        expect(b.plan, '1. Trocar o filtro');
      } else {
        expect(b.state, CompareSideState.done);
        expect(b.plan, isNull);
      }
      await ctl().discard(id);
      await f.finish();
    }
  });

  test('SPEC-108 R7, R8: time, tokens with the reasoning and calls of the '
      'Codex; each side takes the whole variation of its own quota', () async {
    final id = await withHistory();
    await startCompare(id, a: claudeAsk, b: codexAsk);
    await wait();
    final a = runOf('A'), f = servers.single;
    codexCommandItem(f, 'c1', 'sed -n 1,80p lib/a.dart', [
      {'type': 'read', 'command': 'sed', 'path': '/work/repo/lib/a.dart'},
    ]);
    codexCommandItem(f, 'c2', 'rg cupom lib', [
      {'type': 'search', 'command': 'rg', 'query': 'cupom', 'path': 'lib'},
    ]);
    codexCommandItem(f, 'c3', 'git log', [
      {'type': 'unknown', 'command': 'git log'},
    ]);
    codexFinish(f, 'O filtro compara com pago.');
    a.emit(initLine(a.options.sessionId!));
    a.emit(textLine('São duas causas.'));
    // The cost is not used: the quotas are different.
    a.emit(resultOf(cost: 9, ms: 112000, input: 31400, output: 2400));
    await wait();
    final run = view(id);
    expect(run.b.metrics!.durationMs, 68000);
    expect(run.b.metrics!.tokensIn, 18400);
    expect(run.b.metrics!.answerTokens, 1600);
    expect(run.b.metrics!.reasoning, 2100);
    expect(run.b.metrics!.tools, {'Read': 1, 'Grep': 1, 'Bash': 1});
    expect(run.measured, isTrue);
    expect(run.a.weight!.five, closeTo(0.10, 1e-9));
    expect(run.a.weight!.week, closeTo(0.02, 1e-9));
    expect(run.b.weight!.five, closeTo(0.03, 1e-9));
    expect(run.b.weight!.week, closeTo(0.01, 1e-9));
    // The ledger records each side with its provider.
    final entries = await db.select(db.usageEntries).get();
    expect(
      {for (final e in entries) e.model: e.provider},
      {'opus': 'claude', 'gpt-6.2-sol': 'codex'},
    );
  });

  test('SPEC-108 R8: without a reading of the Codex there is no weight for '
      'its side, and the other keeps its own', () async {
    codexUsages = [];
    final id = await withHistory();
    await startCompare(id, a: claudeAsk, b: codexAsk);
    await wait();
    codexFinish(servers.single, 'x');
    runOf('A').emit(resultOf());
    await wait();
    expect(view(id).b.weight, isNull);
    expect(view(id).a.weight!.five, closeTo(0.10, 1e-9));
    expect(view(id).measured, isFalse);
  });

  test('SPEC-108 R9: choosing the Codex side moves the conversation to it '
      '(provider, thread, model, effort, mode), with the note and the '
      'other side in the card', () async {
    final id = await withHistory();
    await startCompare(id, a: claudeAsk, b: codexAsk);
    await wait();
    final a = runOf('A');
    codexFinish(servers.single, 'O filtro compara com pago.');
    a.emit(initLine(a.options.sessionId!));
    a.emit(textLine('São duas causas.'));
    a.emit(resultOf());
    await wait();
    await ctl().choose(id, 'B');
    final conv = (await repo().getById(id))!;
    expect(conv.provider, 'codex');
    expect(conv.claudeSessionId, 'thread-codex');
    expect((conv.model, conv.mode), ('gpt-6.2-sol', 'ask'));
    expect(conversationEffort(c.read(appSettingsProvider), id), 'medium');
    c.read(conversationTimelineProvider(id));
    await settle();
    final items = c.read(conversationTimelineProvider(id)).items;
    expect(
      items.whereType<NoticeItem>().map((n) => n.text),
      contains(
        'A conversa passou para o Codex · gpt-6.2-sol · Perguntar '
        '(escolhida entre 2)',
      ),
    );
    final card = items.whereType<CompareItem>().single;
    final stored = CompareRun.fromJson(card.data, conversationId: id)!;
    expect(stored.otherSide!.provider, 'claude');
    expect(stored.otherSide!.sessionId, a.options.sessionId);
    expect(stored.chosenSide!.metrics!.reasoning, 2100);

    // The next message goes on from the thread, on the Codex, with the
    // effort of the side.
    await c.read(conversationManagerProvider.notifier).send(id, 'e agora?');
    await wait();
    expect(servers, hasLength(2));
    expect(
      codexParams(servers.last, 'thread/resume')!['threadId'],
      'thread-codex',
    );
    expect(codexParams(servers.last, 'turn/start')!['effort'], 'medium');
    await c.read(conversationManagerProvider.notifier).shutdown();
    // Another model drops the effort of the side.
    await c
        .read(conversationManagerProvider.notifier)
        .setModel(id, 'gpt-6.2-mini');
    expect(conversationEffort(c.read(appSettingsProvider), id), isNull);
  });

  test('SPEC-108 R9: a side of another provider that never started cannot '
      'take the conversation', () async {
    final id = await withHistory();
    final m = c.read(conversationManagerProvider.notifier);
    await expectLater(
      m.adoptSession(
        id,
        null,
        model: 'gpt-6.2-sol',
        mode: PromptMode.ask,
        provider: 'codex',
      ),
      throwsA(isA<ConversationException>()),
    );
    expect((await repo().getById(id))!.provider, 'claude');
  });

  test('SPEC-108 R10: an event before this version opens with the provider '
      'of the conversation', () async {
    final conv = await repo().insert(
      workspaceId: ws.id,
      title: 'Antiga',
      model: 'gpt-6.2-sol',
      provider: 'codex',
      claudeSessionId: 'orig',
    );
    await repo().appendEvent(
      conv.id,
      type: AppEventTypes.compare,
      json: jsonEncode({
        'type': AppEventTypes.compare,
        'at': DateTime.now().toIso8601String(),
        'prompt': 'por quê?',
        'status': 'open',
        'before': {'five': 0.1, 'week': 0.2},
        'sides': [
          for (final l in ['A', 'B'])
            {'letter': l, 'model': 'm-$l', 'mode': 'ask', 'state': 'done'},
        ],
      }),
    );
    await ctl().restore(conv.id);
    final run = view(conv.id);
    expect(run.sides.map((s) => s.provider), ['codex', 'codex']);
    expect(run.sides.map((s) => s.effort), [null, null]);
    expect(run.before['codex']!.five, 0.1);
  });

  test('SPEC-108 R10: an interrupted Codex side goes on with thread/resume; '
      'discarding goes back to the session and provider of before', () async {
    final id = await withHistory();
    await startCompare(id, a: claudeAsk, b: codexAsk);
    await wait();
    runOf('A').emit(resultOf());
    await wait();
    await ctl().shutdown();
    c.dispose();

    c = container();
    await c.read(appSettingsProvider.notifier).load();
    await c.read(providerAvailabilityProvider('codex').future);
    await ctl().restore(id);
    expect(view(id).b.state, CompareSideState.stopped);
    expect(view(id).b.sessionId, 'thread-codex');
    await ctl().resume(id, 'B');
    await wait();
    final f = servers.last;
    expect(codexParams(f, 'thread/resume')!['threadId'], 'thread-codex');
    expect(
      ((codexParams(f, 'turn/start')!['input'] as List).single as Map)['text'],
      compareResumeMessage,
    );
    await ctl().discard(id);
    final conv = (await repo().getById(id))!;
    expect((conv.provider, conv.claudeSessionId), ('claude', 'orig'));
  });

  test('SPEC-108 R2: an unavailable Codex is refused with the reason, before '
      'anything is stored', () async {
    codexStatus = const ProviderAvailability(ProviderStatus.missing, 'x');
    c.invalidate(providerAvailabilityProvider('codex'));
    await c.read(providerAvailabilityProvider('codex').future);
    final id = await withHistory();
    final before = (await repo().events(id)).length;
    await expectLater(
      startCompare(id, a: claudeAsk, b: codexAsk),
      throwsA(
        isA<ConversationException>().having(
          (e) => e.message,
          'message',
          'Codex não está instalado.',
        ),
      ),
    );
    expect((await repo().events(id)), hasLength(before));
    expect(provider.runs, isEmpty);
  });
}
