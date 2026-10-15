import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../../core/claude/claude_event_test.dart' show permissionRequestLine;
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'prompt_test_utils.dart';

void main() {
  group('ClaudeCodeProvider', () {
    List<String> args(PromptMode mode) => ClaudeCodeProvider.optionsFor(
      AgentStartOptions(
        workingDirectory: '/w',
        mode: mode,
        sessionId: 'sid',
        model: 'haiku',
      ),
    ).toArgs();

    test('Perguntar removes every writing tool (read-only, chosen in '
        'plano Fase 6)', () {
      final a = args(PromptMode.ask);
      expect(a, containsAllInOrder(['--permission-mode', 'default']));
      final i = a.indexOf('--disallowedTools');
      expect(i, greaterThan(0));
      expect(a.sublist(i + 1), ClaudeCodeProvider.readOnlyDisallowedTools);
      expect(
        a.sublist(i + 1),
        containsAll(['Edit', 'Write', 'NotebookEdit', 'Bash', 'Monitor']),
      );
      expect(a, isNot(contains('plan')));
      expect(a, containsAllInOrder(['--session-id', 'sid']));
      expect(a, containsAllInOrder(['--model', 'haiku']));
      expect(a, containsAllInOrder(['--permission-prompt-tool', 'stdio']));
      expect(a.join(' '), isNot(contains('bypassPermissions')));
      expect(a.join(' '), isNot(contains('dangerously')));
    });

    test('Planejar = plan, Editar = acceptEdits, without disallowed tools', () {
      expect(
        args(PromptMode.plan),
        containsAllInOrder(['--permission-mode', 'plan']),
      );
      expect(
        args(PromptMode.edit),
        containsAllInOrder(['--permission-mode', 'acceptEdits']),
      );
      expect(args(PromptMode.plan), isNot(contains('--disallowedTools')));
      expect(args(PromptMode.edit), isNot(contains('--disallowedTools')));
      // inherit = no --model.
      final o = ClaudeCodeProvider.optionsFor(
        const AgentStartOptions(
          workingDirectory: '/w',
          mode: PromptMode.edit,
          resumeId: 'old',
          model: 'inherit',
        ),
      );
      expect(o.toArgs(), isNot(contains('--model')));
      expect(o.toArgs(), containsAllInOrder(['--resume', 'old']));
      expect(o.permissionMode, ClaudePermissionMode.acceptEdits);
    });

    test('Refinar (DT-35) = default without disallowed tools: edits ask for '
        'approval; never acceptEdits / bypass', () {
      final a = args(PromptMode.refine);
      expect(a, containsAllInOrder(['--permission-mode', 'default']));
      expect(a, isNot(contains('acceptEdits')));
      expect(a, isNot(contains('--disallowedTools')));
      expect(a, containsAllInOrder(['--permission-prompt-tool', 'stdio']));
      expect(a.join(' '), isNot(contains('bypassPermissions')));
      expect(a.join(' '), isNot(contains('dangerously')));
      expect(PromptMode.selectable, isNot(contains(PromptMode.refine)));
      expect(PromptMode.fromName('refine'), PromptMode.refine);
    });

    test('registry: Claude Code active, Codex / Gemini CLI coming soon', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final all = c.read(agentProvidersProvider);
      expect(all.map((p) => p.displayName), [
        'Claude Code',
        'Codex',
        'Gemini CLI',
      ]);
      expect(all.map((p) => p.enabled), [true, false, false]);
      expect(
        () => all[1].start(
          const AgentStartOptions(workingDirectory: '/', mode: PromptMode.ask),
        ),
        throwsA(isA<AgentUnavailable>()),
      );
    });
  });

  group('ConversationManager (fake provider)', () {
    late AppDatabase db;
    late FakeAgentProvider provider;
    late ProviderContainer c;
    late Workspace ws;

    setUp(() async {
      db = memoryDatabase();
      provider = FakeAgentProvider();
      c = ProviderContainer(
        overrides: [databaseOverride(db), ...fakeProviderOverrides(provider)],
      );
      c.listen(conversationManagerProvider, (_, _) {});
      ws = await addWorkspace(db, '/work/repo');
      await c.read(appSettingsProvider.notifier).load();
    });

    tearDown(() => c.dispose());

    test('create → runs in the workspace root, init stores the session id, '
        'result closes the turn', () async {
      final m = c.read(conversationManagerProvider.notifier);
      final id = await m.create(
        workspace: ws,
        text: 'Como funciona o parser?\nDetalhes…',
        model: 'haiku',
      );
      final run = provider.last;
      expect(run.options.workingDirectory, '/work/repo');
      expect(run.options.mode, PromptMode.ask);
      expect(run.options.sessionId, '00000000-0000-4000-8000-000000000001');
      expect(run.options.resumeId, isNull);
      expect(run.sent, ['Como funciona o parser?\nDetalhes…']);
      expect(c.read(conversationManagerProvider).isBusy(id), isTrue);

      final conv = await c.read(conversationsRepoProvider).getById(id);
      expect(conv!.title, 'Como funciona o parser?');
      expect(conv.claudeSessionId, isNull);

      run.emit(initLine(run.options.sessionId!));
      run.emit(textLine('É um LineSplitter.'));
      run.emit(resultLine(cost: 0.02));
      await settle();

      final after = await c.read(conversationsRepoProvider).getById(id);
      expect(after!.claudeSessionId, run.options.sessionId);
      expect(after.tokensIn, 100);
      expect(after.tokensOut, 20);
      expect(after.costUsd, 0.02);
      expect(after.messageCount, 2);
      expect(c.read(conversationManagerProvider).isBusy(id), isFalse);

      final events = await c.read(conversationsRepoProvider).events(id);
      expect(events.map((e) => e.type), [
        'promptorium_user',
        'system/init',
        'assistant',
        'result/success',
      ]);
      final items = c.read(conversationTimelineProvider(id)).items;
      expect(items.whereType<UserItem>().single.text, startsWith('Como'));
      expect(
        items.whereType<AssistantTextItem>().single.text,
        'É um LineSplitter.',
      );
    });

    test(
      'approvals stay inline; changing the mode restarts with --resume',
      () async {
        final m = c.read(conversationManagerProvider.notifier);
        final id = await m.create(workspace: ws, text: 'liste os arquivos');
        final run = provider.last;
        run.emit(initLine(run.options.sessionId!));
        run.emit(jsonDecode(permissionRequestLine) as Map<String, dynamic>);
        await settle();
        final pending = c.read(conversationManagerProvider).approvalsOf(id);
        expect(pending.single.requestId, 'req-1');
        // Not in the Sessions queue.
        expect(c.read(sessionManagerProvider).approvals, isEmpty);

        await m.approve(id, 'req-1', always: true);
        expect(run.approved.single.$1, 'req-1');
        expect(run.approved.single.$2, isNotNull);
        expect(c.read(conversationManagerProvider).approvalsOf(id), isEmpty);
        run.emit(resultLine());
        await settle();

        await m.setMode(id, PromptMode.edit);
        await m.send(id, 'agora edite');
        expect(run.stopped, isTrue);
        expect(provider.runs, hasLength(2));
        final second = provider.last;
        expect(second.options.mode, PromptMode.edit);
        expect(second.options.resumeId, run.options.sessionId);
        expect(second.options.sessionId, isNull);
        expect(second.sent, ['agora edite']);
      },
    );

    test('deny and stop', () async {
      final m = c.read(conversationManagerProvider.notifier);
      final id = await m.create(workspace: ws, text: 'x');
      final run = provider.last;
      run.emit(jsonDecode(permissionRequestLine) as Map<String, dynamic>);
      await settle();
      await m.deny(id, 'req-1');
      expect(run.denied, ['req-1']);
      await m.stop(id);
      await settle();
      expect(run.stopped, isTrue);
      expect(m.isAlive(id), isFalse);
      // Without an init the next start uses a fresh --session-id.
      await m.send(id, 'de novo');
      expect(provider.last.options.resumeId, isNull);
      expect(provider.last.options.sessionId, isNotNull);
    });
  });

  test('real ClaudeCodeProvider + fake CLI: Perguntar argv and cwd', () async {
    final db = memoryDatabase();
    final cli = FakeCli();
    final c = ProviderContainer(
      overrides: sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
    );
    addTearDown(c.dispose);
    c.listen(conversationManagerProvider, (_, _) {});
    final ws = await addWorkspace(db, '/work/repo');
    await c.read(appSettingsProvider.notifier).load();
    await c
        .read(conversationManagerProvider.notifier)
        .create(workspace: ws, text: 'olá');
    expect(cli.cwds.single, '/work/repo');
    final a = cli.args.single;
    expect(a, containsAllInOrder(['--permission-mode', 'default']));
    expect(
      a,
      containsAllInOrder([
        '--disallowedTools',
        ...ClaudeCodeProvider.readOnlyDisallowedTools,
      ]),
    );
    expect(cli.last.writtenJson.single['message']['content'], 'olá');
    await settle();
  });
}
