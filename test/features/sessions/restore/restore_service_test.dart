// Real git in temporary repositories: slow on a busy runner.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/sessions_repo.dart';
import 'package:promptorium/features/sessions/codex_conversations.dart';
import 'package:promptorium/features/sessions/conversation_events.dart';
import 'package:promptorium/features/sessions/restore/restore_service.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../../../core/codex/fake_codex.dart';
import '../../../core/git/git_test_utils.dart';
import '../../../helpers/test_db.dart';
import '../session_test_utils.dart';

/// SPEC-084 R1–R4, R8, R11: recording the points of a turn and undoing it,
/// in temporary repositories only.
void main() {
  late Directory tmp;
  late String repo;
  late ProviderContainer c;
  late RestoreService restore;
  late int wsId;

  File f(String p) => File('$repo/$p');

  /// A long timeout by default: a busy machine must not turn the git work
  /// into "passou de 5 s" (the timeout test lowers it).
  Future<void> boot({
    List<Override> extra = const [],
    Duration timeout = const Duration(minutes: 1),
  }) async {
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        restoreTimeoutProvider.overrideWithValue(timeout),
        ...extra,
      ],
    );
    await c.read(appSettingsProvider.notifier).load();
    wsId =
        (await c.read(workspacesRepoProvider).add(path: repo, name: 'loja-api'))
            .id;
    await c
        .read(sessionsRepoProvider)
        .insert(
          id: 's1',
          workspaceId: wsId,
          worktreePath: repo,
          branch: 'main',
          model: 'opus',
        );
    restore = c.read(restoreServiceProvider);
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-restore-');
    repo = await createRepo(tmp, name: 'loja-api');
    Directory('$repo/src').createSync();
    for (var i = 1; i <= 40; i++) {
      f('src/m$i.ts').writeAsStringSync('import { Pedido } from "./pedido";\n');
    }
    f('src/pedido.ts').writeAsStringSync('export class Pedido {}\n');
    f('src/cupom.ts').writeAsStringSync('export const cupom = 0;\n');
    await gitIn(repo, ['add', '-A']);
    await gitIn(repo, ['commit', '-q', '-m', 'loja']);
  });

  tearDown(() {
    c.dispose();
    RestoreService.failAfterMoveForTest = false;
    tmp.deleteSync(recursive: true);
  });

  /// The turn of the example: `sed -i` in 40 files, creates order.ts,
  /// deletes pedido.ts and commits "wip".
  Future<void> agentTurn() async {
    for (var i = 1; i <= 40; i++) {
      f('src/m$i.ts').writeAsStringSync('import { Order } from "./order";\n');
    }
    f('src/order.ts').writeAsStringSync('export class Order {}\n');
    f('src/pedido.ts').deleteSync();
    await gitIn(repo, ['add', '-A']);
    await gitIn(repo, ['commit', '-q', '-m', 'wip: renomeia Pedido']);
  }

  Future<String> head() async =>
      (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();

  test('undoing the example brings back the 40 files, recreates the deleted '
      'one, deletes the created one, throws the commit away and keeps the '
      "person's file; Refazer goes back to the undone state", () async {
    await boot();
    // The person's work before the turn, not committed.
    f('src/cupom.ts').writeAsStringSync('export const cupom = 10; // à mão\n');
    final startHead = await head();

    final r = await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
      prompt: 'Renomeie Pedido para Order no projeto todo e faça um commit.',
    );
    expect(r.failure, isNull);
    final point = r.point!;
    expect(point.turn, 1);
    expect(point.startBranch, 'main');
    expect(point.files, 1);
    expect(
      await GitService(repo).resolveRef('refs/promptorium/restore/s1/1-inicio'),
      point.startSha,
    );

    await agentTurn();
    final agentHead = await head();
    await restore.end(sessionId: 's1');
    final ended = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    expect(ended.changedFiles, 42);
    expect(ended.commits, 1);

    final plan = await restore.plan(ended);
    expect(plan.restore, hasLength(42));
    expect(plan.changedAfter, isEmpty);
    expect(plan.commits.single.subject, 'wip: renomeia Pedido');
    expect(plan.filesOnly, isFalse);
    expect(plan.kept, ['src/cupom.ts']);

    final out = await restore.undo(ended, plan.defaultSelection);
    expect(out.files, 42);
    expect(out.commits, ['wip: renomeia Pedido']);
    expect(await head(), startHead);
    expect(await gitIn(repo, ['branch', '--show-current']), 'main\n');
    expect(f('src/m7.ts').readAsStringSync(), contains('Pedido'));
    expect(f('src/pedido.ts').existsSync(), isTrue);
    expect(f('src/order.ts').existsSync(), isFalse);
    expect(f('src/cupom.ts').readAsStringSync(), contains('à mão'));
    expect(await gitIn(repo, ['status', '--porcelain']), ' M src/cupom.ts\n');
    final undone = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    expect(undone.state, RestoreState.undone);
    expect(undone.undoneSha, isNotNull);

    final redoPlan = await restore.redoPlan(undone);
    expect(redoPlan.restore, hasLength(42));
    await restore.redo(undone, redoPlan.defaultSelection);
    expect(await head(), agentHead);
    expect(f('src/order.ts').existsSync(), isTrue);
    expect(f('src/pedido.ts').existsSync(), isFalse);
    expect(f('src/cupom.ts').readAsStringSync(), contains('à mão'));
    final redone = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    expect(redone.state, RestoreState.redone);
  });

  test(
    'a file the person changed after the turn stays out unless checked',
    () async {
      await boot();
      final point = (await restore.start(
        workspaceId: wsId,
        worktree: repo,
        sessionId: 's1',
      )).point!;
      f('src/m1.ts').writeAsStringSync('agente\n');
      f('src/m2.ts').writeAsStringSync('agente\n');
      await restore.end(sessionId: 's1');
      f('src/m2.ts').writeAsStringSync('agente e depois a pessoa\n');
      final p = (await c.read(restorePointsRepoProvider).byId(point.id))!;
      final plan = await restore.plan(p);
      expect(plan.restore.single.path, 'src/m1.ts');
      expect(plan.changedAfter.single.path, 'src/m2.ts');
      await restore.undo(p, plan.defaultSelection);
      expect(f('src/m1.ts').readAsStringSync(), contains('Pedido'));
      expect(f('src/m2.ts').readAsStringSync(), 'agente e depois a pessoa\n');
    },
  );

  test('a failure halfway goes back to "antes de desfazer"', () async {
    await boot();
    final point = (await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    )).point!;
    await agentTurn();
    final agentHead = await head();
    await restore.end(sessionId: 's1');
    final p = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    final plan = await restore.plan(p);
    RestoreService.failAfterMoveForTest = true;
    await expectLater(
      restore.undo(p, plan.defaultSelection),
      throwsA(isA<RestoreException>()),
    );
    expect(await head(), agentHead);
    expect(await gitIn(repo, ['status', '--porcelain']), '');
    expect(f('src/order.ts').existsSync(), isTrue);
    final after = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    expect(after.state, RestoreState.active);
  });

  test('a pushed commit: files only, the commit stays', () async {
    final remote = '${tmp.path}/remoto.git';
    await gitIn(tmp.path, ['init', '-q', '--bare', remote]);
    await gitIn(repo, ['remote', 'add', 'origin', remote]);
    await boot();
    final point = (await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    )).point!;
    await agentTurn();
    await gitIn(repo, ['push', '-q', 'origin', 'main']);
    final agentHead = await head();
    await restore.end(sessionId: 's1');
    final p = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    final plan = await restore.plan(p);
    expect(plan.filesOnly, isTrue);
    expect(plan.remotes, ['origin/main']);
    await restore.undo(p, plan.defaultSelection, filesOnly: true);
    expect(await head(), agentHead);
    expect(f('src/pedido.ts').existsSync(), isTrue);
    expect(f('src/order.ts').existsSync(), isFalse);
  });

  test('"Voltar a antes deste turno" sums the turns after it', () async {
    await boot();
    final first = (await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    )).point!;
    f('src/m1.ts').writeAsStringSync('turno 1\n');
    await restore.end(sessionId: 's1');
    final second = await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    );
    expect(second.failure, isNull);
    expect(second.point?.turn, 2);
    f('src/m2.ts').writeAsStringSync('turno 2\n');
    await restore.end(sessionId: 's1');
    final p = (await c.read(restorePointsRepoProvider).byId(first.id))!;
    final plan = await restore.plan(p);
    expect(plan.restore.map((x) => x.path).toSet(), {'src/m1.ts', 'src/m2.ts'});
    await restore.undo(p, plan.defaultSelection);
    final all = await c.read(restorePointsRepoProvider).list(sessionId: 's1');
    expect(all.map((x) => x.state), [RestoreState.undone, RestoreState.undone]);
    expect(await gitIn(repo, ['status', '--porcelain']), '');
  });

  test('more than the timeout: the turn goes on without a point', () async {
    await boot(
      timeout: const Duration(milliseconds: 50),
      extra: [
        gitServiceFactoryProvider.overrideWithValue(
          (root) => GitService(
            root,
            run: (exe, args) async {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              return Process.run(exe, args);
            },
          ),
        ),
      ],
    );
    final sw = Stopwatch()..start();
    final r = await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect(r.point, isNull);
    expect(r.failure, startsWith('passou de'));
    // The late git work does not leave a row behind.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(
      await c.read(restorePointsRepoProvider).list(sessionId: 's1'),
      isEmpty,
    );
  });

  test('a repository without commits and a folder without git', () async {
    final empty = Directory('${tmp.path}/vazio')..createSync();
    await gitIn(empty.path, ['init', '-q']);
    await boot();
    final r = await restore.start(
      workspaceId: wsId,
      worktree: empty.path,
      sessionId: 's1',
    );
    expect(r.failure, 'repositório sem commit');
    final plain = Directory('${tmp.path}/docs-antigos')..createSync();
    final r2 = await restore.start(
      workspaceId: wsId,
      worktree: plain.path,
      sessionId: 's1',
    );
    expect(r2.failure, 'docs-antigos não é um repositório git');
    // Said once.
    final r3 = await restore.start(
      workspaceId: wsId,
      worktree: plain.path,
      sessionId: 's1',
    );
    expect(r3.failure, isNull);
    expect(r3.point, isNull);
  });

  test('the switch off records nothing', () async {
    await boot();
    await c
        .read(appSettingsProvider.notifier)
        .set(RestoreSettingKeys.enabled, 'false');
    final r = await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
    );
    expect(r.point, isNull);
    expect(r.failure, isNull);
  });

  group('SessionManager', () {
    late FakeCli cli;

    Future<String> newSession() async {
      cli = FakeCli();
      c.dispose();
      c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
          restorePoints: true,
        ),
        restoreTimeoutProvider.overrideWithValue(const Duration(minutes: 1)),
      ]);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      return c
          .read(sessionManagerProvider.notifier)
          .create(
            NewSessionRequest(
              workspace: ws,
              title: 'Renomear',
              prompt: 'Renomeie.',
              useWorktree: false,
            ),
          );
    }

    setUp(() async => boot());

    test('send records the start; the result records the end; a notice in '
        'the middle of the turn records nothing', () async {
      final id = await newSession();
      final repoP = c.read(restorePointsRepoProvider);
      var points = await repoP.list(sessionId: id);
      expect(points.single.turn, 1);
      expect(points.single.eventSeq, isNotNull);
      expect(points.single.prompt, 'Renomeie.');
      expect(points.single.endedAt, isNull);

      f('src/m1.ts').writeAsStringSync('agente\n');
      await c
          .read(sessionManagerProvider.notifier)
          .notifyUserEdit(id, 'src/m1.ts');
      await settle();
      expect(await repoP.list(sessionId: id), hasLength(1));

      cli.last.emit(fixtureLines().last); // result
      await until(
        () async => (await repoP.list(sessionId: id)).single.endedAt != null,
      );
      points = await repoP.list(sessionId: id);
      expect(points.single.changedFiles, 1);

      final plan = await c.read(restoreServiceProvider).plan(points.single);
      expect(plan.restore.single.userDuring, isTrue);
    });

    test('an undo notice waits for the next message', () async {
      final id = await newSession();
      cli.last.emit(fixtureLines().last);
      await settle();
      final m = c.read(sessionManagerProvider.notifier);
      await m.queueNotice(id, SessionManager.undoNotice(4));
      await settle();
      expect(m.pendingNotices(id), [SessionManager.undoNotice(4)]);
      await m.send(id, 'Agora só o checkout.');
      await settle();
      expect(m.pendingNotices(id), isEmpty);
      expect(
        '${cli.last.writtenJson.last}',
        contains('O usuário desfez o turno 4'),
      );
    });
  });

  test('the commit the app makes at the end of a Codex turn lands before the '
      'capture: the point counts the file and the commit, and undoing it '
      'takes the file away (SPEC-096 R10 with SPEC-084 R1)', () async {
    await boot();
    final startHead = await head();
    final point = (await restore.start(
      workspaceId: wsId,
      worktree: repo,
      sessionId: 's1',
      prompt: 'crie uma nota',
    )).point!;
    // The Codex writes and leaves it uncommitted; the app commits it.
    f('NOTA.md').writeAsStringSync('# Nota\n');
    var committed = false;
    await restore.end(
      sessionId: 's1',
      beforeEnd: () async {
        committed = await GitService(repo).commitAll('Nota pelo Codex');
      },
    );
    expect(committed, isTrue);
    final ended = (await c.read(restorePointsRepoProvider).byId(point.id))!;
    expect(ended.endHead, await head());
    expect(ended.changedFiles, 1);
    expect(ended.commits, 1);

    final plan = await restore.plan(ended);
    expect(plan.changedAfter, isEmpty);
    expect(plan.restore, hasLength(1));
    await restore.undo(ended, plan.defaultSelection);
    expect(f('NOTA.md').existsSync(), isFalse);
    expect(await head(), startHead);
  });

  test('beforeEnd still runs when the turn has no open point', () async {
    await boot();
    var ran = false;
    await restore.end(sessionId: 's1', beforeEnd: () async => ran = true);
    expect(ran, isTrue);
  });

  group('SPEC-110 · a conversa do Codex', () {
    late FakeCodexStore store;
    late List<FakeCodex> servers;
    late String sid;
    late String wt;

    /// The next App Server does not start.
    var noCodex = false;

    SessionsRepo sessions() => c.read(sessionsRepoProvider);
    SessionManager manager() => c.read(sessionManagerProvider.notifier);
    Future<Session> row() async => (await sessions().getById(sid))!;
    File w(String p) => File('$wt/$p');

    Future<RestorePoint> pointOf(int turn) async =>
        (await c.read(restorePointsRepoProvider).list(sessionId: sid))
            .firstWhere((p) => p.turn == turn);

    Future<List<Map<String, dynamic>>> eventsOf(String type) async => [
      for (final e in await sessions().eventsOfTypes({type}, sessionId: sid))
        jsonDecode(e.json) as Map<String, dynamic>,
    ];

    Future<List<String>> notes() async => [
      for (final j in await eventsOf(AppEventTypes.note)) '${j['text']}',
    ];

    Future<void> start({
      Duration timeout = const Duration(seconds: 10),
      String provider = 'codex',
    }) async {
      noCodex = false;
      store = FakeCodexStore();
      servers = [];
      c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: FakeCli(),
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wts',
          restorePoints: true,
        ),
        restoreTimeoutProvider.overrideWithValue(const Duration(minutes: 1)),
        codexThreadTimeoutProvider.overrideWithValue(timeout),
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
          if (noCodex) throw ProcessException(exe, args, 'não encontrado');
          final f = FakeCodex(threadId: 'thread-${servers.length}')
            ..store = store;
          servers.add(f);
          return f;
        }),
      ]);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'loja-api');
      wsId = ws.id;
      restore = c.read(restoreServiceProvider);
      sid = await manager().create(
        NewSessionRequest(
          workspace: ws,
          title: 'Ajustar frete',
          prompt: 'turno 1',
          provider: provider,
        ),
      );
      wt = (await row()).worktreePath;
    }

    /// Ends the turn that is running: the agent changed [files].
    Future<void> finish(Map<String, String> files) async {
      for (final MapEntry(key: p, value: text) in files.entries) {
        w(p).writeAsStringSync(text);
      }
      await until(
        () async => (store.threads[(await row()).externalId] ?? []).isNotEmpty,
      );
      store.complete((await row()).externalId!);
      await until(
        () async =>
            (await c.read(restorePointsRepoProvider).list(sessionId: sid))
                .first
                .endedAt !=
            null,
      );
    }

    Future<void> turn(int n) async {
      if (n > 1) await manager().send(sid, 'turno $n');
      await finish({'src/cupom.ts': 'turno $n\n', 'src/n$n.ts': '$n\n'});
    }

    Future<UndoOutcome> undo(int n, {bool conversation = true}) async {
      final p = await pointOf(n);
      final plan = await restore.plan(p);
      return restore.undoTurn(
        p,
        plan.defaultSelection,
        revertConversation: conversation,
      );
    }

    tearDown(() async {
      await manager().shutdown();
    });

    test('R6: o ponto acha o turno pelo turn/started depois da mensagem; a '
        'janela diz os turnos', () async {
      await start();
      for (var n = 1; n <= 3; n++) {
        await turn(n);
      }
      expect((await restore.agentTurnOf(await pointOf(2))).id, 't2');
      final plan = await restore.plan(await pointOf(2));
      final conv = plan.conversation!;
      expect(conv.available, isTrue);
      expect(conv.beforeTurnId, 't2');
      expect((conv.firstTurn, conv.lastTurn), (2, 3));
      expect(conv.agent, 'Codex');
    });

    test('R6: sem turno identificado (processo que morreu, ponto no meio de '
        'um turno, eventos antigos), só os arquivos', () async {
      await boot();
      Future<int> add(Map<String, dynamic> j) async =>
          (await sessions().appendEvent(
            's1',
            type: j['subtype'] == null
                ? '${j['type']}'
                : '${j['type']}/${j['subtype']}',
            json: jsonEncode(j),
          )).seq;
      Future<RestorePoint> point(int? seq) async {
        final p = (await restore.start(
          workspaceId: wsId,
          worktree: repo,
          sessionId: 's1',
        )).point!;
        if (seq != null) await restore.attachSeq(p.id, seq);
        return (await c.read(restorePointsRepoProvider).byId(p.id))!;
      }

      final now = DateTime(2026, 11, 25);
      Map<String, dynamic> codex(String turn, {bool started = false}) => {
        'type': started ? 'system' : 'promptorium_command',
        if (started) 'subtype': 'turn_started',
        'provider': 'codex',
        'turn_id': turn,
      };
      // Sem evento antes da próxima mensagem.
      final dead = await add(AppEventTypes.userMessage('a', now));
      final ok = await add(AppEventTypes.userMessage('b', now));
      await add(codex('t1', started: true));
      // Uma mensagem no meio do turno t1.
      final steer = await add(AppEventTypes.userMessage('c', now));
      await add(codex('t1'));
      // Sessão de antes do turn_started: o primeiro evento do turno.
      final old = await add(AppEventTypes.userMessage('d', now));
      await add(codex('t2'));
      // Morreu e foi retomada antes do turno.
      final resumed = await add(AppEventTypes.userMessage('e', now));
      await add(AppEventTypes.noteMessage('Sessão retomada (--resume)'));
      await add(codex('t3', started: true));
      expect((await restore.agentTurnOf(await point(dead))).id, isNull);
      expect((await restore.agentTurnOf(await point(ok))).id, 't1');
      final mid = await restore.agentTurnOf(await point(steer));
      expect(mid.id, isNull);
      expect(mid.reason, contains('no meio de um turno'));
      expect((await restore.agentTurnOf(await point(old))).id, 't2');
      expect((await restore.agentTurnOf(await point(resumed))).id, isNull);
      expect((await restore.agentTurnOf(await point(null))).id, isNull);
    });

    test('R7: no Claude, Só Codex com o motivo', () async {
      await boot();
      final p = (await restore.start(
        workspaceId: wsId,
        worktree: repo,
        sessionId: 's1',
      )).point!;
      f('src/cupom.ts').writeAsStringSync('x');
      await restore.end(sessionId: 's1');
      final conv = (await restore.plan(p)).conversation!;
      expect(conv.available, isFalse);
      expect(conv.onlyCodex, isTrue);
      expect(
        conv.reason,
        startsWith('o Claude Code não volta a conversa no modo do app'),
      );
    });

    test('R8: arquivos, cópia e revert, nessa ordem, pelo processo vivo; sem '
        'aviso ao agente', () async {
      await start();
      for (var n = 1; n <= 3; n++) {
        await turn(n);
      }
      final files = <String>[];
      store.onCall = (m) {
        if (m.startsWith('thread/')) {
          files.add('$m: ${w('src/cupom.ts').readAsStringSync().trim()}');
        }
      };
      store.calls.clear();
      final out = await undo(2);
      expect(out.conversation!.ok, isTrue);
      // Os arquivos já tinham voltado quando o Codex foi chamado.
      expect(files, ['thread/fork: turno 1', 'thread/revert: turno 1']);
      expect(store.calls, ['fork thread-0 → copia-1', 'revert thread-0 t2']);
      expect(servers, hasLength(1));
      expect(w('src/n2.ts').existsSync(), isFalse);
      expect(store.threads['thread-0'], ['t1']);
      expect(store.threads['copia-1'], ['t1', 't2', 't3']);
      expect((await row()).externalId, 'thread-0');
      expect(manager().pendingNotices(sid), isEmpty);
      final e = (await eventsOf(AgentConversationEvents.reverted)).single;
      expect(e['before_turn_id'], 't2');
      expect(e['copy_id'], 'copia-1');
      expect((e['turn'], e['last_turn']), (2, 3));
      final rec = ConversationRevert.fromJson(e)!;
      expect(rec.note, startsWith('Turno 2 desfeito: 3 arquivos, 2 commits ('));
      expect(
        rec.note,
        contains(
          'e a conversa do Codex (turnos 2 a 3). O agente não recebe '
          'aviso: ele já não conhece esses turnos.',
        ),
      );
      expect((await notes()).where((n) => n.contains('desfeito')), isEmpty);
      // O turno seguinte vai na mesma thread, sem o turno desfeito.
      await manager().send(sid, 'de novo');
      await finish({});
      expect(store.threads['thread-0'], ['t1', 't4']);
    });

    test('R8: sem processo vivo, retoma a thread num App Server curto, sem '
        'turno, e fecha', () async {
      await start();
      await turn(1);
      await turn(2);
      await manager().release(sid);
      store.calls.clear();
      final out = await undo(2);
      expect(out.conversation!.ok, isTrue);
      expect(store.calls, [
        'resume thread-0',
        'fork thread-0 → copia-1',
        'revert thread-0 t2',
      ]);
      expect(servers, hasLength(2));
      expect(servers.last.ended, isTrue);
      final methods = servers.last.writtenJson.map((m) => m['method']);
      expect(methods, isNot(contains('turn/start')));
      final resume =
          servers.last.writtenJson.firstWhere(
                (m) => m['method'] == 'thread/resume',
              )['params']
              as Map;
      // SPEC-093 D1: nada de confiança gravada no global.
      expect(resume['sandbox'], 'read-only');
      expect(resume['approvalPolicy'], 'never');
    });

    test('R8: o primeiro turno também volta (a conversa fica vazia)', () async {
      await start();
      await turn(1);
      final out = await undo(1);
      expect(out.conversation!.ok, isTrue);
      expect(store.threads['thread-0'], isEmpty);
      expect((await row()).externalId, 'thread-0');
    });

    test('P2: desmarcada, a conversa fica e o agente recebe o aviso', () async {
      await start();
      await turn(1);
      store.calls.clear();
      final out = await undo(1, conversation: false);
      expect(out.conversation, isNull);
      expect(store.calls, isEmpty);
      expect(manager().pendingNotices(sid), [SessionManager.undoNotice(1)]);
      expect(await notes(), contains(undoneNote(out)));
    });

    test(
      'R8: falha nos arquivos — nada muda e o Codex nem é chamado',
      () async {
        await start();
        await turn(1);
        await turn(2);
        store.calls.clear();
        RestoreService.failAfterMoveForTest = true;
        await expectLater(undo(2), throwsA(isA<RestoreException>()));
        RestoreService.failAfterMoveForTest = false;
        expect(store.calls, isEmpty);
        expect(w('src/cupom.ts').readAsStringSync(), 'turno 2\n');
        expect(w('src/n2.ts').existsSync(), isTrue);
        expect(store.threads['thread-0'], ['t1', 't2']);
        expect((await pointOf(2)).state, RestoreState.active);
        expect(await eventsOf(AgentConversationEvents.reverted), isEmpty);
        // A sessão segue normal.
        await manager().send(sid, 'turno 3');
        await finish({});
        expect(store.threads['thread-0'], ['t1', 't2', 't3']);
      },
    );

    test('R8: falha no revert — os arquivos continuam desfeitos, a nota diz o '
        'motivo, o agente recebe o aviso e a thread continua inteira; tentar '
        'de novo usa a mesma cópia', () async {
      await start();
      await turn(1);
      await turn(2);
      store.fail['thread/revert'] = 'boom';
      store.calls.clear();
      final out = await undo(2);
      expect(out.conversation!.error, 'boom');
      expect(w('src/cupom.ts').readAsStringSync(), 'turno 1\n');
      expect(w('src/n2.ts').existsSync(), isFalse);
      expect((await pointOf(2)).state, RestoreState.undone);
      expect(store.threads['thread-0'], ['t1', 't2']);
      expect((await row()).externalId, 'thread-0');
      expect(manager().pendingNotices(sid), [SessionManager.undoNotice(2)]);
      expect(await notes(), contains(undoneNote(out)));
      final failed = ConversationRevert.fromJson(
        (await eventsOf(AgentConversationEvents.failed)).single,
      )!;
      expect(
        failed.note,
        'A conversa do Codex não voltou: boom. Os arquivos continuam '
        'desfeitos e o agente recebe o aviso.',
      );
      expect(await eventsOf(AgentConversationEvents.reverted), isEmpty);
      // O Refazer só mexe nos arquivos: a conversa não voltou.
      expect((await restore.redoPlan(await pointOf(2))).conversation, isNull);
      // De novo, com sucesso.
      store.fail.clear();
      final again = await restore.retryConversation(sid, failed);
      expect(again.ok, isTrue);
      expect(again.copyId, failed.copyId);
      expect(store.calls.where((x) => x.startsWith('fork')), hasLength(1));
      expect(store.threads['thread-0'], ['t1']);
      expect(manager().pendingNotices(sid), isEmpty);
    });

    test('tentar de novo só vale antes de um turno novo', () async {
      await start();
      await turn(1);
      await turn(2);
      store.fail['thread/revert'] = 'boom';
      await undo(2);
      final failed = ConversationRevert.fromJson(
        (await eventsOf(AgentConversationEvents.failed)).single,
      )!;
      store.fail.clear();
      await manager().send(sid, 'segue');
      await finish({});
      await expectLater(
        restore.retryConversation(sid, failed),
        throwsA(isA<RestoreException>()),
      );
      expect(store.threads['thread-0'], ['t1', 't2', 't3']);
    });

    test(
      'R8: o App Server não responde — vale o limite, e nada se perde',
      () async {
        await start(timeout: const Duration(milliseconds: 80));
        await turn(1);
        await turn(2);
        store.fail['thread/revert'] = null;
        final out = await undo(2);
        expect(
          out.conversation!.error,
          startsWith('o App Server não respondeu'),
        );
        expect(w('src/cupom.ts').readAsStringSync(), 'turno 1\n');
        expect((await row()).externalId, 'thread-0');
        expect(manager().pendingNotices(sid), [SessionManager.undoNotice(2)]);
      },
    );

    test('R8: o Codex não abre, ou a thread não retoma — os arquivos ficam '
        'desfeitos e a sessão na mesma thread', () async {
      await start();
      await turn(1);
      await turn(2);
      await turn(3);
      await manager().release(sid);
      noCodex = true;
      final out = await undo(3);
      expect(out.conversation!.error, 'Codex CLI não encontrado');
      noCodex = false;
      store.fail['thread/resume'] = 'no rollout found for thread id thread-0';
      final second = await undo(2);
      expect(
        second.conversation!.error,
        'o Codex não achou a conversa desta sessão',
      );
      expect(w('src/cupom.ts').readAsStringSync(), 'turno 1\n');
      expect(store.threads['thread-0'], ['t1', 't2', 't3']);
      expect((await row()).externalId, 'thread-0');
      expect(manager().pendingNotices(sid), [
        SessionManager.undoNotice(3),
        SessionManager.undoNotice(2),
      ]);
    });

    test('R8: com um turno em andamento, nada é desfeito', () async {
      await start();
      await turn(1);
      await manager().send(sid, 'turno 2');
      await until(() async => store.threads['thread-0']!.length == 2);
      w('src/cupom.ts').writeAsStringSync('no meio\n');
      final p = await pointOf(2);
      store.calls.clear();
      await expectLater(
        restore.undoTurn(p, {'src/cupom.ts'}, revertConversation: true),
        throwsA(isA<SessionException>()),
      );
      expect(w('src/cupom.ts').readAsStringSync(), 'no meio\n');
      expect(store.calls, isEmpty);
    });

    test('uma mensagem enviada durante o revert espera e vai depois', () async {
      await start();
      await turn(1);
      await turn(2);
      Future<void>? sent;
      store.onCall = (m) {
        if (m == 'thread/fork') sent ??= manager().send(sid, 'apressada');
      };
      store.calls.clear();
      final out = await undo(2);
      expect(out.conversation!.ok, isTrue);
      await sent;
      await until(() async => store.threads['thread-0']!.length == 2);
      expect(store.calls, [
        'fork thread-0 → copia-1',
        'revert thread-0 t2',
        'turn thread-0 t3',
      ]);
    });

    test('R9: Refazer volta os arquivos e adota a cópia; a próxima mensagem '
        'vai nela', () async {
      await start();
      await turn(1);
      await turn(2);
      await undo(2);
      final p = await pointOf(2);
      final plan = await restore.redoPlan(p);
      expect(plan.conversation!.copyAt, isNotNull);
      store.calls.clear();
      final out = await restore.redoTurn(p, plan.defaultSelection);
      expect(out.restored, isTrue);
      expect(w('src/cupom.ts').readAsStringSync(), 'turno 2\n');
      expect(w('src/n2.ts').existsSync(), isTrue);
      expect((await row()).externalId, 'copia-1');
      // O processo antigo saiu (ele escreve a thread velha) e a cópia foi
      // conferida antes, sem turno.
      expect(servers.first.ended, isTrue);
      expect(store.calls, ['resume copia-1']);
      final e = (await eventsOf(AgentConversationEvents.restored)).single;
      expect(
        conversationRestoredNote(e),
        startsWith('Refeito: arquivos e conversa (cópia de '),
      );
      expect(manager().pendingNotices(sid), isEmpty);
      expect(await restore.activeRevert(await pointOf(2)), isNull);
      await manager().send(sid, 'turno 3');
      await finish({});
      expect(store.threads['copia-1'], ['t1', 't2', 't3']);
      // Os ids dos turnos valem na cópia: desfazer o 2 de novo funciona.
      final again = await undo(2);
      expect(again.conversation!.ok, isTrue);
      expect(store.threads['copia-1'], ['t1']);
      expect((await row()).externalId, 'copia-1');
    });

    test('R9: sem cópia (falha no fork), o Refazer volta só os arquivos e '
        'avisa', () async {
      await start();
      await turn(1);
      await turn(2);
      store.fail['thread/fork'] = 'sem espaço';
      final out = await undo(2);
      expect(out.conversation!.ok, isTrue);
      expect(out.conversation!.copyId, isNull);
      expect(
        out.conversation!.note,
        contains('Sem cópia da conversa (sem espaço)'),
      );
      expect(store.threads['thread-0'], ['t1']);
      final p = await pointOf(2);
      final plan = await restore.redoPlan(p);
      expect(plan.conversation!.copyAt, isNull);
      expect(plan.conversation!.reason, contains('Não há cópia'));
      final redo = await restore.redoTurn(p, plan.defaultSelection);
      expect(redo.restored, isFalse);
      expect(w('src/cupom.ts').readAsStringSync(), 'turno 2\n');
      expect((await row()).externalId, 'thread-0');
      expect(manager().pendingNotices(sid), [redoNotice(2)]);
      expect((await notes()).last, contains('a conversa do Codex não volta'));
    });

    test('R9: a cópia sumiu — os arquivos são refeitos e a sessão nunca '
        'aponta para ela', () async {
      await start();
      await turn(1);
      await turn(2);
      await undo(2);
      store.archived.add('copia-1');
      final p = await pointOf(2);
      final plan = await restore.redoPlan(p);
      final out = await restore.redoTurn(p, plan.defaultSelection);
      expect(out.restored, isFalse);
      expect(w('src/cupom.ts').readAsStringSync(), 'turno 2\n');
      expect((await row()).externalId, 'thread-0');
      expect(manager().pendingNotices(sid), [redoNotice(2)]);
      expect(
        (await notes()).where((n) => n.contains('a conversa foi arquivada')),
        hasLength(1),
      );
      // A conversa continua utilizável.
      await manager().send(sid, 'segue');
      await finish({});
      expect(store.threads['thread-0'], ['t1', 't3']);
    });

    test('R9: a falha nos arquivos do Refazer não toca na conversa', () async {
      await start();
      await turn(1);
      await turn(2);
      await undo(2);
      store.calls.clear();
      RestoreService.failAfterMoveForTest = true;
      final p = await pointOf(2);
      final plan = await restore.redoPlan(p);
      await expectLater(
        restore.redoTurn(p, plan.defaultSelection),
        throwsA(isA<RestoreException>()),
      );
      RestoreService.failAfterMoveForTest = false;
      expect(store.calls, isEmpty);
      expect((await row()).externalId, 'thread-0');
      expect(w('src/cupom.ts').readAsStringSync(), 'turno 1\n');
    });

    test('R9: um turno novo tira o Refazer e a limpeza arquiva a cópia, uma '
        'vez; a que ainda dá para refazer e a adotada ficam', () async {
      await start();
      await turn(1);
      await turn(2);
      await undo(2);
      // Ainda dá para refazer.
      await restore.archiveOrphanCopies();
      expect(store.archived, isEmpty);
      await turn(3);
      expect((await pointOf(2)).undoneSha, isNull);
      await restore.prune();
      expect(store.archived, {'copia-1'});
      expect(store.calls.last, 'archive copia-1');
      final n = servers.length;
      await restore.prune();
      expect(servers, hasLength(n), reason: 'nada a arquivar: nenhum processo');
      // Adotada: nunca.
      await undo(3);
      final p = await pointOf(3);
      final plan = await restore.redoPlan(p);
      await restore.redoTurn(p, plan.defaultSelection);
      expect((await row()).externalId, 'copia-2');
      await turn(4);
      await restore.prune();
      expect(store.archived, {'copia-1'});
    });

    test('R9: sem o Codex na limpeza, nada falha e a próxima tenta', () async {
      await start();
      await turn(1);
      await turn(2);
      await undo(2);
      await turn(3);
      noCodex = true;
      await restore.prune();
      expect(store.archived, isEmpty);
      noCodex = false;
      await restore.prune();
      expect(store.archived, {'copia-1'});
    });
  });
}
