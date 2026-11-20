import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/usage_poller.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/conversations_repo.dart';
import 'package:promptorium/features/prompt/compare/compare_controller.dart';
import 'package:promptorium/features/prompt/compare/compare_run.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/plan_ready.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../../../core/claude/claude_event_test.dart' show permissionRequestLine;
import '../../../helpers/test_db.dart' show memoryDatabase;
import '../../sessions/session_test_utils.dart' show settle;
import '../prompt_test_utils.dart';
import 'compare_test_utils.dart' show weekReset;

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

  ProviderContainer container() {
    final k = ProviderContainer(
      overrides: [
        // Not closed with the container: "reopening the app" keeps it.
        appDatabaseProvider.overrideWithValue(db),
        ...fakeProviderOverrides(provider),
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
    usages = [usage(38, 61), usage(48, 63)];
    c = container();
    ws = await addWorkspace(db, '/work/repo');
    await c.read(appSettingsProvider.notifier).load();
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  CompareController ctl() => c.read(compareControllerProvider.notifier);
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
    CompareChoice a = (model: 'sonnet', mode: PromptMode.ask),
    CompareChoice b = (model: 'opus', mode: PromptMode.ask),
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
    expect(view(id).before!.five, 0.38);
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
      startCompare(id, b: (model: 'sonnet', mode: PromptMode.ask)),
      throwsA(isA<ConversationException>()),
    );
    await expectLater(
      startCompare(id, b: (model: 'opus', mode: PromptMode.edit)),
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
      a: (model: 'sonnet', mode: PromptMode.plan),
      b: (model: 'sonnet', mode: PromptMode.ask),
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
}
