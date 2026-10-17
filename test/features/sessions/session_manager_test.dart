import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/claude/usage_tracker.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/sessions_repo.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/timeline_provider.dart';
import 'package:promptorium/ui/shell/footer_stats.dart';
import 'package:promptorium/ui/shell/navigation.dart';

import '../../core/claude/claude_event_test.dart' show permissionRequestLine;
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

String permissionLine(String requestId, {String toolUseId = 'toolu_01'}) =>
    permissionRequestLine
        .replaceAll('"req-1"', '"$requestId"')
        .replaceAll('"toolu_01"', '"$toolUseId"');

void main() {
  late Directory tmp;
  late String repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-sessions-');
    repo = await createRepo(tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'create with resumeFrom ("Continuar como sessão" do Prompt): new '
    'worktree, --resume <conversa> --fork-session --session-id <nova>',
    () async {
      final db = memoryDatabase();
      final cli = FakeCli();
      final c = sessionContainer(
        sessionOverrides(
          db: db,
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'repo');
      final id = await c
          .read(sessionManagerProvider.notifier)
          .create(
            NewSessionRequest(
              workspace: ws,
              title: 'Parser',
              prompt: 'Resuma e aguarde.',
              model: 'sonnet',
              resumeFrom: 'conv-sid',
              origin: 'Continuação da conversa "Parser" do Prompt',
            ),
          );
      final row = (await c.read(sessionsRepoProvider).getById(id))!;
      expect(row.worktreePath, isNot(repo));
      expect(Directory(row.worktreePath).existsSync(), isTrue);
      expect(cli.cwds.single, row.worktreePath);
      final args = cli.args.single;
      expect(args, containsAllInOrder(['--session-id', id]));
      expect(args, containsAllInOrder(['--resume', 'conv-sid']));
      expect(args, contains('--fork-session'));
      expect(
        cli.last.writtenJson.single['message']['content'],
        'Resuma e aguarde.',
      );
      await settle();
      final events = await c.read(sessionsRepoProvider).events(id);
      expect(events.first.type, AppEventTypes.note);
      expect(events.first.json, contains('Continuação da conversa'));
    },
  );

  test('managed hooks: --settings per session with the project rules; the '
      'hook log becomes timeline notes; files removed at the end', () async {
    final hooks = ManagedHooks(runBase: '${tmp.path}/run');
    final cli = FakeCli();
    final c = sessionContainer([
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      managedHooksProvider.overrideWithValue(hooks),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    Directory('$repo/.promptorium').createSync();
    File('$repo/.promptorium/config.yml')
        .writeAsStringSync('bloquear-comandos:\n  - "npm publish*"\n');
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    final m = c.read(sessionManagerProvider.notifier);
    final id = await m.create(
      NewSessionRequest(workspace: ws, title: 'Hooks', prompt: 'oi'),
    );
    if (!await pythonAvailable()) return; // no python3: no hooks
    final args = cli.args.single;
    final i = args.indexOf('--settings');
    expect(args[i + 1], '${tmp.path}/run/$id/settings.json');
    final cfg = File('${tmp.path}/run/$id/hooks-config.json')
        .readAsStringSync();
    expect(cfg, contains('npm publish'));
    expect(cfg, contains('git -C na raiz'));

    // The hook wrote to its log; the next tool result shows it.
    File(hooks.logOf(id)).writeAsStringSync(
      '${jsonEncode({'evento': 'bloqueio', 'comando': 'npm publish', 'regra': 'npm publish*'})}\n',
    );
    cli.last.emit(
      jsonEncode({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 't1',
              'content': 'PreToolUse:Bash hook error: bloqueado',
              'is_error': true,
            },
          ],
        },
        'session_id': id,
      }),
    );
    await settle();
    final events = await c.read(sessionsRepoProvider).events(id);
    expect(
      events.where((e) => e.type == AppEventTypes.note).last.json,
      contains('Hook bloqueou `npm publish`'),
    );
    expect(c.read(hookActivityProvider)[ManagedHook.block], isNotNull);

    // Turned off in Automações: no hook file for the next session.
    for (final h in ManagedHook.values) {
      await c.read(appSettingsProvider.notifier).set(h.settingKey, '0');
    }
    await m.create(
      NewSessionRequest(workspace: ws, title: 'Sem hooks', prompt: 'oi'),
    );
    expect(cli.args.last, isNot(contains('--settings')));

    await m.stop(id);
    await settle();
    expect(Directory(hooks.dirOf(id)).existsSync(), isFalse);
  });

  test('fork carries the parent worktree uncommitted changes (DT-18) and '
      'gets the worktree variables', () async {
    final cli = FakeCli();
    final c = sessionContainer(
      sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    final m = c.read(sessionManagerProvider.notifier);
    final id = await m.create(
      NewSessionRequest(workspace: ws, title: 'Pai', prompt: 'oi'),
    );
    final parent = (await c.read(sessionsRepoProvider).getById(id))!;
    expect(cli.envs.single, {
      'PROMPTORIUM_ROOT': repo,
      'PROMPTORIUM_WORKTREE': parent.worktreePath,
    });
    File('${parent.worktreePath}/a.txt').writeAsStringSync('do pai\n');
    final child = await m.fork(id, prompt: 'continue');
    final row = (await c.read(sessionsRepoProvider).getById(child))!;
    expect(row.worktreePath, isNot(parent.worktreePath));
    expect(File('${row.worktreePath}/a.txt').readAsStringSync(), 'do pai\n');
    expect(cli.envs.last!['PROMPTORIUM_WORKTREE'], row.worktreePath);
  });

  test('notification clicks: approvals → Sessões; done/failed → the screen '
      'the session was created from', () async {
    final db = memoryDatabase();
    final cli = FakeCli();
    final notifier = FakeNotifier();
    final c = sessionContainer(
      sessionOverrides(
        db: db,
        cli: cli,
        notifier: notifier,
        worktreesBase: '${tmp.path}/wt',
      ),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c
        .read(workspacesRepoProvider)
        .add(path: repo, name: 'repo');
    await c.read(workspaceActionsProvider).select(ws.id);
    final nav = c.read(navigationProvider.notifier);
    final m = c.read(sessionManagerProvider.notifier);

    // Created from Tarefas ("Executar com agente").
    nav.go(AppSection.tasks);
    final id = await m.create(
      NewSessionRequest(workspace: ws, title: 'TASK-001', prompt: 'Faça'),
    );
    final lines = fixtureLines();
    cli.last.emit(permissionLine('req-1'));
    await settle();
    nav.go(AppSection.code);
    final approval = notifier.shown.indexWhere(
      (n) => n.$1 == 'Aprovação pendente',
    );
    notifier.clicks[approval]!();
    expect(c.read(navigationProvider), AppSection.sessions);
    expect(c.read(selectedSessionProvider), id);

    await m.approve(id, 'req-1');
    cli.last.emit(lines.last); // result
    await settle();
    nav.go(AppSection.code);
    final done = notifier.shown.indexWhere((n) => n.$1 == 'Sessão concluída');
    notifier.clicks[done]!();
    expect(c.read(navigationProvider), AppSection.tasks);

    // Created from the Sessões screen itself: stays there.
    nav.go(AppSection.sessions);
    await m.create(
      NewSessionRequest(workspace: ws, title: 'Outra', prompt: 'Faça'),
    );
    cli.last.emit(lines.last);
    await settle();
    nav.go(AppSection.code);
    notifier.clicks.last!();
    expect(c.read(navigationProvider), AppSection.sessions);
  });

  test('"sem perguntar": --dangerously-skip-permissions on create and on '
      'resume (stored as bypassPermissions)', () async {
    final db = memoryDatabase();
    final cli = FakeCli();
    final c = sessionContainer(
      sessionOverrides(
        db: db,
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c
        .read(workspacesRepoProvider)
        .add(path: repo, name: 'repo');
    final m = c.read(sessionManagerProvider.notifier);
    final id = await m.create(
      NewSessionRequest(
        workspace: ws,
        title: 'Livre',
        prompt: 'Faça',
        permissionMode: ClaudePermissionMode.skipPermissions,
      ),
    );
    expect(cli.args.single, contains('--dangerously-skip-permissions'));
    expect(cli.args.single, isNot(contains('--permission-mode')));
    expect(
      (await c.read(sessionsRepoProvider).getById(id))!.permissionMode,
      'bypassPermissions',
    );
    cli.last.emit(fixtureLines().last); // result
    await settle();
    await cli.last.finish(0);
    await settle();
    await m.send(id, 'De novo');
    await settle();
    expect(cli.args.last, containsAllInOrder(['--resume', id]));
    expect(cli.args.last, contains('--dangerously-skip-permissions'));
  });

  test('idle session: process closed after the configured time, then '
      'resumes with --resume', () async {
    final cli = FakeCli();
    final c = sessionContainer(
      sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c
        .read(workspacesRepoProvider)
        .add(path: repo, name: 'repo');
    final m = c.read(sessionManagerProvider.notifier);
    final id = await m.create(
      NewSessionRequest(workspace: ws, title: 'Ociosa', prompt: 'Oi'),
    );
    // Turn running: never closed.
    var later = DateTime.now().add(const Duration(hours: 2));
    expect(await m.closeIdle(now: later), isEmpty);

    for (final l in fixtureLines()) {
      cli.last.emit(l);
    }
    await settle();
    expect(m.isAlive(id), isTrue);
    // Just finished: still within 15 min.
    expect(
      await m.closeIdle(now: DateTime.now().add(const Duration(minutes: 5))),
      isEmpty,
    );
    // Setting 0 = never.
    await c.read(appSettingsProvider.notifier).set('claude.idleMinutes', '0');
    expect(await m.closeIdle(now: later), isEmpty);
    await c.read(appSettingsProvider.notifier).remove('claude.idleMinutes');

    later = DateTime.now().add(const Duration(minutes: 16));
    expect(await m.closeIdle(now: later), [id]);
    await settle();
    expect(m.isAlive(id), isFalse);
    expect(
      (await c.read(sessionsRepoProvider).getById(id))!.status,
      SessionStatus.completed,
    );

    await m.resume(id);
    expect(m.isAlive(id), isTrue);
    expect(cli.args.last, containsAllInOrder(['--resume', id]));
  });

  test('create → events persisted → approval → result: done/idle', () async {
    final db = memoryDatabase();
    final cli = FakeCli();
    final notifier = FakeNotifier();
    final c = sessionContainer(
      sessionOverrides(
        db: db,
        cli: cli,
        notifier: notifier,
        worktreesBase: '${tmp.path}/wt',
      ),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c
        .read(workspacesRepoProvider)
        .add(path: repo, name: 'repo');
    await c.read(workspaceActionsProvider).select(ws.id);
    c.listen(footerStatsProvider, (_, _) {});
    final repoSessions = c.read(sessionsRepoProvider);
    final m = c.read(sessionManagerProvider.notifier);

    final id = await m.create(
      NewSessionRequest(
        workspace: ws,
        title: 'Shell da IDE',
        prompt: 'Implemente o shell',
        model: 'haiku',
        agent: 'implementer',
        permissionMode: ClaudePermissionMode.acceptEdits,
      ),
    );

    // Worktree + row + process with the right flags.
    final row = (await repoSessions.getById(id))!;
    expect(row.title, 'Shell da IDE');
    expect(row.branch, 'pr/shell-da-ide-000000');
    expect(Directory(row.worktreePath).existsSync(), isTrue);
    expect(cli.cwds.single, row.worktreePath);
    final args = cli.args.single;
    expect(args, containsAllInOrder(['--session-id', id]));
    expect(args, containsAllInOrder(['--model', 'haiku']));
    expect(args, containsAllInOrder(['--agent', 'implementer']));
    expect(args, containsAllInOrder(['--permission-mode', 'acceptEdits']));
    // Defaults of Configurações → Consumo.
    expect(args, containsAllInOrder(['--effort', 'medium']));
    expect(args, containsAllInOrder(['--autocompact', '200k']));
    expect(row.effort, 'medium');
    expect(args, isNot(contains('--resume')));
    final fake = cli.last;
    expect(fake.writtenJson.single, {
      'type': 'user',
      'message': {'role': 'user', 'content': 'Implemente o shell'},
      'parent_tool_use_id': null,
    });

    // Fixture minus the result line, then a synthetic control_request.
    final lines = fixtureLines();
    for (final l in lines.sublist(0, lines.length - 1)) {
      fake.emit(l);
    }
    fake.emit(permissionLine('req-1'));
    await settle();

    expect(
      (await repoSessions.getById(id))!.status,
      SessionStatus.waitingApproval,
    );
    final queue = c.read(sessionManagerProvider).approvals;
    expect(queue, hasLength(1));
    expect(queue.single.sessionTitle, 'Shell da IDE');
    expect(queue.single.request.toolName, 'Bash');
    expect(notifier.shown.map((n) => n.$1), contains('Aprovação pendente'));
    expect(c.read(footerStatsProvider).sessionsWaiting, 1);
    expect(c.read(footerStatsProvider).mcpTotal, greaterThan(0));

    await m.approve(id, 'req-1', always: true);
    await settle();
    final response = fake.writtenJson.last;
    expect(response['type'], 'control_response');
    final inner = response['response']['response'] as Map<String, dynamic>;
    expect(inner['behavior'], 'allow');
    expect(inner['updatedInput'], {'command': 'ls -la'});
    expect(inner['updatedPermissions'], [
      {
        'type': 'addRules',
        'rules': [
          {'toolName': 'Bash', 'ruleContent': 'ls:*'},
        ],
        'behavior': 'allow',
        'destination': 'localSettings',
      },
    ]);
    expect(c.read(sessionManagerProvider).approvals, isEmpty);
    expect((await repoSessions.getById(id))!.status, SessionStatus.running);

    fake.emit(lines.last); // result
    await settle();

    final done = (await repoSessions.getById(id))!;
    expect(done.status, SessionStatus.completed);
    expect(done.costUsd, closeTo(0.00302371, 1e-9));
    expect(done.tokensOut, 42);
    expect(m.isAlive(id), isTrue, reason: 'process stays open → idle');
    expect(notifier.shown.map((n) => n.$1), contains('Sessão concluída'));
    expect(c.read(rateLimitProvider)?.fiveHourUtilization, 0.12);
    final footer = c.read(footerStatsProvider);
    expect(footer.usage5h, 0.12);
    expect(footer.usageWeekResetsAt, isNotNull);
    expect(footer.sessionsActive, 0); // idle
    expect(footer.sessionsTotal, 1);

    // Persistence: raw lines, no stream_event, user message first.
    final events = await repoSessions.events(id);
    final types = events.map((e) => e.type).toList();
    expect(types.first, AppEventTypes.user);
    expect(types, containsAll(['system/init', 'assistant', 'control_request']));
    expect(types.last, 'result/success');
    expect(types.where((t) => t.startsWith('stream_event')), isEmpty);
    expect(jsonDecode(events.last.json)['total_cost_usd'], 0.00302371);
    expect(
      [for (final e in events) e.seq],
      [for (var i = 1; i <= events.length; i++) i],
    );

    // Timeline built live.
    final items = c.read(sessionTimelineProvider(id)).items;
    expect(items.first, isA<UserItem>());
    expect(
      items.whereType<AssistantTextItem>().map((t) => (t.text, t.live)),
      contains(('ok', false)),
    );
    expect(items.last, isA<NoticeItem>());

    // A second turn: the session cost is the cumulative total_cost_usd.
    await m.send(id, 'mais uma');
    final second = jsonDecode(lines.last) as Map<String, dynamic>;
    second['total_cost_usd'] = 0.005;
    fake.emit(jsonEncode(second));
    await settle();
    expect((await repoSessions.getById(id))!.costUsd, 0.005);
  });

  test(
    'queue aggregates sessions; cancel, deny, exit, stop, resume, fork',
    () async {
      final db = memoryDatabase();
      final cli = FakeCli();
      final notifier = FakeNotifier();
      final c = sessionContainer(
        sessionOverrides(
          db: db,
          cli: cli,
          notifier: notifier,
          worktreesBase: '${tmp.path}/wt',
        ),
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'repo');
      final sessions = c.read(sessionsRepoProvider);
      final m = c.read(sessionManagerProvider.notifier);

      final a = await m.create(
        NewSessionRequest(
          workspace: ws,
          title: 'A',
          prompt: 'pa',
          effort: 'high',
        ),
      );
      final b = await m.create(
        NewSessionRequest(
          workspace: ws,
          title: 'B',
          prompt: 'pb',
          useWorktree: false,
        ),
      );
      // No worktree: runs in the workspace root, on its branch.
      expect(cli.cwds[1], repo);
      expect((await sessions.getById(b))!.branch, 'main');
      expect(cli.args[0], isNot(contains('--model'))); // inherit
      expect(cli.args[0], containsAllInOrder(['--effort', 'high']));

      final pa = cli.processes[0], pb = cli.processes[1];
      pa.emit(permissionLine('ra'));
      await settle();
      pb.emit(permissionLine('rb1', toolUseId: 't1'));
      pb.emit(permissionLine('rb2', toolUseId: 't2'));
      await settle();

      var queue = c.read(sessionManagerProvider).approvals;
      expect(queue.map((q) => (q.sessionId, q.requestId)), [
        (a, 'ra'),
        (b, 'rb1'),
        (b, 'rb2'),
      ]);

      // control_cancel_request removes the card.
      pb.emit('{"type":"control_cancel_request","request_id":"rb1"}');
      await settle();
      queue = c.read(sessionManagerProvider).approvals;
      expect(queue.map((q) => q.requestId), ['ra', 'rb2']);
      expect(
        (await sessions.getById(b))!.status,
        SessionStatus.waitingApproval,
      );

      await m.deny(b, 'rb2');
      await settle();
      final deny = pb.writtenJson.last['response']['response'];
      expect(deny['behavior'], 'deny');
      expect(deny['message'], isNotEmpty);
      expect((await sessions.getById(b))!.status, SessionStatus.running);

      // Unexpected exit → failed; stop → stopped.
      await pb.finish(1);
      await settle();
      expect(m.isAlive(b), isFalse);
      expect((await sessions.getById(b))!.status, SessionStatus.failed);
      expect(notifier.shown.map((n) => n.$1), contains('Sessão falhou'));

      await m.stop(a);
      await settle();
      expect((await sessions.getById(a))!.status, SessionStatus.stopped);
      expect(c.read(sessionManagerProvider).approvals, isEmpty);

      // Sending to a dead session resumes it in the same worktree.
      await m.send(b, 'continue');
      await settle();
      expect(cli.args.last, containsAllInOrder(['--resume', b]));
      expect(cli.args.last, isNot(contains('--session-id')));
      expect(cli.cwds.last, repo);
      expect(cli.last.writtenJson.single['message']['content'], 'continue');
      expect((await sessions.getById(b))!.status, SessionStatus.running);

      // Fork of A: new id, new worktree from A's branch.
      final rowA = (await sessions.getById(a))!;
      final f = await m.fork(a, prompt: 'variação');
      final fork = (await sessions.getById(f))!;
      expect(f, isNot(a));
      expect(cli.args.last, containsAllInOrder(['--session-id', f]));
      expect(
        cli.args.last,
        containsAllInOrder(['--resume', a, '--fork-session']),
      );
      expect(cli.args.last, containsAllInOrder(['--effort', 'high']));
      expect(fork.worktreePath, isNot(rowA.worktreePath));
      expect(cli.cwds.last, fork.worktreePath);
      expect(fork.branch, startsWith('pr/fork-de-a-'));
      expect(fork.title, 'Fork de A');

      // Timeline shows the lifecycle notes.
      final notes = c
          .read(sessionTimelineProvider(b))
          .items
          .whereType<NoticeItem>()
          .map((n) => n.text);
      expect(notes, contains(startsWith('O processo do Claude Code encerrou')));
      expect(notes, contains('Sessão retomada (--resume)'));
    },
  );

  test(
    'concurrent sends resume once; shutdown stops without marking stopped',
    () async {
      final db = memoryDatabase();
      final cli = FakeCli();
      final c = sessionContainer(
        sessionOverrides(
          db: db,
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'repo');
      final sessions = c.read(sessionsRepoProvider);
      final m = c.read(sessionManagerProvider.notifier);

      final a = await m.create(
        NewSessionRequest(
          workspace: ws,
          title: 'A',
          prompt: 'pa',
          useWorktree: false,
        ),
      );
      await cli.processes[0].finish(1);
      await settle();
      expect(m.isAlive(a), isFalse);

      await Future.wait([m.send(a, 'um'), m.send(a, 'dois')]);
      await settle();
      expect(cli.processes, hasLength(2)); // one --resume, not two
      expect(m.isAlive(a), isTrue);
      expect((await sessions.getById(a))!.status, SessionStatus.running);

      await m.shutdown();
      await settle();
      expect(m.isAlive(a), isFalse);
      // Left as is: the next launch marks it interrupted.
      expect((await sessions.getById(a))!.status, SessionStatus.running);
      await expectLater(m.resume(a), throwsA(isA<SessionException>()));
    },
  );

  test('timeline of a stored session is rebuilt from session_events', () async {
    final db = memoryDatabase();
    final c = sessionContainer([databaseOverride(db)]);
    addTearDown(c.dispose);
    final ws = await c
        .read(workspacesRepoProvider)
        .add(path: repo, name: 'repo');
    final r = c.read(sessionsRepoProvider);
    await r.insert(
      id: 's1',
      workspaceId: ws.id,
      worktreePath: repo,
      branch: 'main',
      model: 'haiku',
    );
    await r.appendEvent(
      's1',
      type: AppEventTypes.user,
      json: jsonEncode(AppEventTypes.userMessage('oi', DateTime(2026))),
    );
    for (final l in fixtureLines()) {
      await r.appendEvent('s1', type: 'x', json: l);
    }
    c.listen(sessionTimelineProvider('s1'), (_, _) {});
    await settle();
    final snap = c.read(sessionTimelineProvider('s1'));
    expect(snap.loading, isFalse);
    expect(snap.timeline.model, 'claude-haiku-5-5');
    expect(snap.items.whereType<UserItem>().single.text, 'oi');
    expect(snap.items.whereType<AssistantTextItem>().single.text, 'ok');
  });

  test('markLiveAsInterrupted at startup', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final r = SessionsRepo(db);
    final ws = await db
        .into(db.workspaces)
        .insertReturning(WorkspacesCompanion.insert(path: repo, name: 'r'));
    await r.insert(
      id: 'live',
      workspaceId: ws.id,
      worktreePath: repo,
      branch: 'main',
      model: 'm',
    );
    expect(await r.markLiveAsInterrupted(), 1);
    expect((await r.getById('live'))!.status, SessionStatus.interrupted);
  });

  test('sessionSlug is a valid git slug', () {
    expect(
      sessionSlug('Ação: Parser stream-json!', 'abcdef12-0000'),
      'acao-parser-stream-json-abcdef',
    );
    expect(sessionSlug('###', 'ABCDEF12'), 'sessao-abcdef');
    expect(sessionSlug('x' * 80, '123456').length, lessThanOrEqualTo(39));
    for (final t in ['Shell da IDE', 'ñ', '  -a-  ']) {
      expect(
        GitService.slugPattern.hasMatch(sessionSlug(t, '0f0f0f0f')),
        isTrue,
      );
    }
  });
}
