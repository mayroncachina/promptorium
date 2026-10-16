import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/tasks_repo.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import '../board/spec_runner_test.dart' as steps_test show resultLine;
import '../tasks/task_rules_test.dart' show resultLine;

/// `which` / `gh` simulated; everything else runs for real.
class FakeCommands {
  FakeCommands({this.hasGh = true});

  bool hasGh;
  final calls = <(String, List<String>, String?)>[];

  Future<ProcessResult> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
  }) async {
    calls.add((exe, args, workingDirectory));
    if (exe == 'which') {
      return ProcessResult(1, hasGh ? 0 : 1, hasGh ? '/usr/bin/gh\n' : '', '');
    }
    if (exe == 'gh') {
      return ProcessResult(1, 0, 'https://github.com/o/r/pull/7\n', '');
    }
    return ProcessResult(1, 0, '', '');
  }
}

class Env {
  Env(this.c, this.cli, this.ws, this.task, this.sessionId, this.worktree);

  final ProviderContainer c;
  final FakeCli cli;
  final Workspace ws;
  final Task task;
  final String sessionId;
  final String worktree;

  ReviewService get review => c.read(reviewServiceProvider);
}

void main() {
  group('spec', specReviewTests);

  late Directory tmp;
  late String repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-review-');
    repo = await createRepo(tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Session with a worktree and a task; the "agent" commits a change to
  /// `a.txt` (line 2) and leaves `b.txt` modified-uncommitted + `novo.txt`
  /// untracked. The session finishes (`result`) → task in Review.
  Future<Env> setUpSession({FakeCommands? commands}) async {
    final db = memoryDatabase();
    final cli = FakeCli();
    final c = sessionContainer([
      ...sessionOverrides(
        db: db,
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      commandRunnerProvider.overrideWithValue(
        (commands ?? FakeCommands()).call,
      ),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c
        .read(workspacesRepoProvider)
        .add(path: repo, name: 'repo');
    File('$repo/b.txt').writeAsStringSync('um\ndois\ntrês\n');
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'b']);
    final task = await TasksRepo(db).insert(
      workspaceId: ws.id,
      code: 'TASK-001',
      title: 'Barra de status',
      status: TaskStatus.running,
    );
    final id = await c
        .read(sessionManagerProvider.notifier)
        .create(
          NewSessionRequest(
            workspace: ws,
            title: 'Barra de status',
            prompt: 'Implemente',
            taskId: task.id,
          ),
        );
    final row = (await c.read(sessionsRepoProvider).getById(id))!;
    expect(row.baseBranch, 'main');
    final wt = row.worktreePath;
    final a = File('$wt/a.txt');
    a.writeAsStringSync(
      a.readAsStringSync().replaceFirst('linha 2\n', 'LINHA 2\n'),
    );
    await gitIn(wt, ['commit', '-q', '-am', 'agente: a.txt']);
    File('$wt/b.txt').writeAsStringSync('um\nDOIS\ntrês\n');
    File('$wt/novo.txt').writeAsStringSync('olá\n');
    cli.last.emit(resultLine());
    await settle();
    expect(
      (await c.read(tasksRepoProvider).getById(task.id))!.status,
      TaskStatus.review,
    );
    final t = (await c.read(tasksRepoProvider).getById(task.id))!;
    return Env(c, cli, ws, t, id, wt);
  }

  test('queue + changed files include committed, uncommitted and untracked '
      '(base...HEAD + working tree)', () async {
    final e = await setUpSession();
    final sessions = await e.c
        .read(sessionsRepoProvider)
        .watchByWorkspace(e.ws.id)
        .first;
    final tasks = await e.c
        .read(tasksRepoProvider)
        .watchByWorkspace(e.ws.id)
        .first;
    final q = await e.review.queue(e.ws, sessions, tasks);
    expect(q.map((i) => i.session.id), [e.sessionId]);
    expect(q.single.task?.code, 'TASK-001');

    final d = await e.review.load(e.sessionId);
    expect(d.error, isNull);
    expect(d.baseBranch, 'main');
    expect(d.commitsAhead, 1);
    expect(d.uncommitted, 2);
    expect(
      {for (final f in d.files) f.path: fileStatusLetter(f.status)},
      {'a.txt': 'M', 'b.txt': 'M', 'novo.txt': 'A'},
    );
    expect(d.additions, 3);
    expect(d.deletions, 2);
  });

  test('a completed session without changes is not awaiting review', () async {
    final e = await setUpSession();
    // Clean the worktree back to the base.
    await gitIn(e.worktree, ['reset', '-q', '--hard', 'main']);
    await gitIn(e.worktree, ['clean', '-qfd']);
    await e.c.read(tasksRepoProvider).setStatus(e.task.id, TaskStatus.running);
    final sessions = await e.c
        .read(sessionsRepoProvider)
        .watchByWorkspace(e.ws.id)
        .first;
    final tasks = await e.c
        .read(tasksRepoProvider)
        .watchByWorkspace(e.ws.id)
        .first;
    expect(await e.review.queue(e.ws, sessions, tasks), isEmpty);
  });

  test('rejecting a hunk changes the file (uncommitted, committed and '
      'untracked)', () async {
    final e = await setUpSession();
    var d = await e.review.load(e.sessionId);
    DiffFile file(String p) => d.files.firstWhere((f) => f.path == p);

    // Uncommitted hunk.
    await e.review.rejectHunk(
      e.sessionId,
      file('b.txt'),
      file('b.txt').hunks.single,
    );
    expect(File('${e.worktree}/b.txt').readAsStringSync(), 'um\ndois\ntrês\n');

    // Hunk already committed on the session branch: reverted in the working
    // tree, stays as an uncommitted change.
    await e.review.rejectHunk(
      e.sessionId,
      file('a.txt'),
      file('a.txt').hunks.single,
    );
    expect(
      File('${e.worktree}/a.txt').readAsStringSync(),
      contains('linha 2\n'),
    );
    expect(
      await gitIn(e.worktree, ['status', '--porcelain', '--', 'a.txt']),
      contains('M a.txt'),
    );

    // Untracked file: removed.
    await e.review.rejectHunk(
      e.sessionId,
      file('novo.txt'),
      file('novo.txt').hunks.single,
    );
    expect(File('${e.worktree}/novo.txt').existsSync(), isFalse);

    d = await e.review.load(e.sessionId);
    expect(d.files, isEmpty);
  });

  test('"Pedir ajustes" sends ONE message to the session (resume when not '
      'alive) and moves the task back to Em execução', () async {
    final e = await setUpSession();
    final d = await e.review.load(e.sessionId);
    final a = d.files.firstWhere((f) => f.path == 'a.txt');
    final h = a.hunks.single;
    final idx = h.lines.indexWhere((l) => l.kind == DiffLineKind.add);
    final c1 = commentFor(a, h, idx, 'Use maiúsculas só no título.');
    final b = d.files.firstWhere((f) => f.path == 'b.txt');
    final hb = b.hunks.single;
    final c2 = commentFor(
      b,
      hb,
      hb.lines.indexWhere((l) => l.kind == DiffLineKind.del),
      'Por que removeu?',
    );
    expect(c1.location, 'a.txt:2');
    expect(c2.location, 'b.txt:2 (linha removida)');

    // Process gone (e.g. app restarted): the message resumes the session.
    await e.cli.last.finish();
    await settle();
    expect(
      e.c.read(sessionManagerProvider.notifier).isAlive(e.sessionId),
      isFalse,
    );

    final msg = await e.review.requestChanges(e.sessionId, [c1, c2]);
    await settle();
    expect(e.cli.processes, hasLength(2));
    expect(e.cli.args.last, containsAllInOrder(['--resume', e.sessionId]));
    final sent = e.cli.last.writtenJson;
    expect(sent, hasLength(1));
    final content = sent.single['message']['content'] as String;
    expect(content, msg);
    expect(content, contains('a.txt:2 — Use maiúsculas só no título.'));
    expect(content, contains('b.txt:2 (linha removida) — Por que removeu?'));
    expect(content, contains('+LINHA 2'));
    expect(content, contains('-dois'));
    expect(
      (await e.c.read(tasksRepoProvider).getById(e.task.id))!.status,
      TaskStatus.running,
    );
    // The message is in the session timeline (session_events).
    final events = await e.c.read(sessionsRepoProvider).events(e.sessionId);
    expect(events.any((r) => r.json.contains('Use maiúsculas')), isTrue);
  });

  test('clean merge: commits pending, merges into main, removes worktree '
      'and branch, task Feito, returns the hash', () async {
    final e = await setUpSession();
    final m = e.c.read(sessionManagerProvider.notifier);
    expect(m.isAlive(e.sessionId), isTrue);
    final branch = (await e.c.read(sessionsRepoProvider).getById(e.sessionId))!
        .branch;

    final r = await e.review.merge(e.sessionId);
    await settle();
    expect(r.warnings, isEmpty);
    expect(r.commit, (await gitIn(repo, ['rev-parse', 'HEAD'])).trim());
    expect(r.commit, matches(RegExp(r'^[0-9a-f]{40}$')));
    // Merge commit with two parents.
    expect(
      (await gitIn(repo, [
        'rev-list',
        '--parents',
        '-n',
        '1',
        'HEAD',
      ])).trim().split(' '),
      hasLength(3),
    );
    expect(File('$repo/novo.txt').readAsStringSync(), 'olá\n');
    expect(File('$repo/a.txt').readAsStringSync(), contains('LINHA 2'));
    expect(File('$repo/b.txt').readAsStringSync(), contains('DOIS'));
    expect(Directory(e.worktree).existsSync(), isFalse);
    expect((await gitIn(repo, ['branch', '--list', branch])).trim(), isEmpty);
    expect(m.isAlive(e.sessionId), isFalse);
    final s = (await e.c.read(sessionsRepoProvider).getById(e.sessionId))!;
    expect(s.status, SessionStatus.merged);
    expect(s.mergeCommit, r.commit);
    expect(
      (await e.c.read(tasksRepoProvider).getById(e.task.id))!.status,
      TaskStatus.done,
    );
    // Merged sessions leave the queue and cannot be resumed.
    final sessions = await e.c
        .read(sessionsRepoProvider)
        .watchByWorkspace(e.ws.id)
        .first;
    final tasks = await e.c
        .read(tasksRepoProvider)
        .watchByWorkspace(e.ws.id)
        .first;
    expect(await e.review.queue(e.ws, sessions, tasks), isEmpty);
    await expectLater(m.resume(e.sessionId), throwsA(isA<SessionException>()));
  });

  test('merge with conflict aborts and keeps everything', () async {
    final e = await setUpSession();
    // main changes the same line of b.txt.
    File('$repo/b.txt').writeAsStringSync('um\nDois em main\ntrês\n');
    await gitIn(repo, ['commit', '-q', '-am', 'main: b']);
    final mainHead = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
    final wtHead = (await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim();

    await expectLater(
      e.review.merge(e.sessionId),
      throwsA(
        isA<ReviewException>().having(
          (x) => x.message,
          'message',
          allOf(
            contains('Conflito'),
            contains('b.txt'),
            contains('merge --abort'),
          ),
        ),
      ),
    );
    expect((await gitIn(repo, ['rev-parse', 'HEAD'])).trim(), mainHead);
    expect((await gitIn(repo, ['status', '--porcelain'])).trim(), isEmpty);
    expect(File('$repo/.git/MERGE_HEAD').existsSync(), isFalse);
    expect(Directory(e.worktree).existsSync(), isTrue);
    // The pending commit was undone: same HEAD, changes still uncommitted.
    expect((await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim(), wtHead);
    expect(File('${e.worktree}/b.txt').readAsStringSync(), contains('DOIS'));
    expect(File('${e.worktree}/novo.txt').existsSync(), isTrue);
    final st = await gitIn(e.worktree, ['status', '--porcelain']);
    expect(st, contains(' M b.txt'));
    expect(st, contains('?? novo.txt'));
    final s = (await e.c.read(sessionsRepoProvider).getById(e.sessionId))!;
    expect(s.status, isNot(SessionStatus.merged));
    expect(s.mergeCommit, isNull);
    expect(
      (await e.c.read(tasksRepoProvider).getById(e.task.id))!.status,
      TaskStatus.review,
    );
  });

  test('dirty main repository blocks the merge (nothing touched)', () async {
    final e = await setUpSession();
    File('$repo/a.txt').writeAsStringSync('sujo\n');
    final wtHead = (await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim();
    await expectLater(
      e.review.merge(e.sessionId),
      throwsA(
        isA<ReviewException>().having(
          (x) => x.message,
          'message',
          contains('alterações não commitadas'),
        ),
      ),
    );
    expect((await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim(), wtHead);
    expect(Directory(e.worktree).existsSync(), isTrue);
    expect(
      e.c.read(sessionManagerProvider.notifier).isAlive(e.sessionId),
      isTrue,
    );
    expect(
      (await e.c.read(tasksRepoProvider).getById(e.task.id))!.status,
      TaskStatus.review,
    );
  });

  test('Criar PR unavailable without gh or without remote', () async {
    final cmds = FakeCommands(hasGh: false);
    final e = await setUpSession(commands: cmds);
    var a = await e.review.prAvailability(e.sessionId);
    expect(a.available, isFalse);
    expect(a.reason, contains('gh'));

    cmds.hasGh = true;
    a = await e.review.prAvailability(e.sessionId);
    expect(a.available, isFalse);
    expect(a.reason, contains('remote'));
    await expectLater(
      e.review.createPr(e.sessionId),
      throwsA(isA<ReviewException>()),
    );
  });

  test('Criar PR: commits pending, pushes the branch and calls gh', () async {
    final cmds = FakeCommands();
    final e = await setUpSession(commands: cmds);
    final remote = '${tmp.path}/remote.git';
    await Process.run('git', ['init', '-q', '--bare', remote]);
    await gitIn(repo, ['remote', 'add', 'origin', remote]);
    final a = await e.review.prAvailability(e.sessionId);
    expect(a.available, isTrue);
    expect(a.remote, 'origin');

    final url = await e.review.createPr(e.sessionId);
    expect(url, 'https://github.com/o/r/pull/7');
    final s = (await e.c.read(sessionsRepoProvider).getById(e.sessionId))!;
    expect(s.prUrl, url);
    expect(
      (await gitIn(e.worktree, ['status', '--porcelain'])).trim(),
      isEmpty,
    );
    expect(
      (await gitIn(remote, ['branch', '--list', s.branch])).trim(),
      isNotEmpty,
    );
    final gh = cmds.calls.lastWhere((c) => c.$1 == 'gh');
    expect(gh.$3, e.worktree);
    expect(
      gh.$2,
      containsAllInOrder([
        'pr',
        'create',
        '--head',
        s.branch,
        '--base',
        'main',
      ]),
    );
    expect(gh.$2, containsAllInOrder(['--title', 'TASK-001: Barra de status']));
  });

  test('rejecting a content hunk of a renamed file keeps the rename', () async {
    final e = await setUpSession();
    await gitIn(e.worktree, ['mv', 'a.txt', 'c.txt']);
    final c = File('${e.worktree}/c.txt');
    c.writeAsStringSync(
      c.readAsStringSync().replaceFirst('linha 29\n', 'LINHA 29\n'),
    );
    await gitIn(e.worktree, ['commit', '-q', '-am', 'rename']);
    final d = await e.review.load(e.sessionId);
    final f = d.files.firstWhere((f) => f.path == 'c.txt');
    expect(f.status, DiffFileStatus.renamed);
    final h = f.hunks.firstWhere(
      (h) => h.lines.any((l) => l.text == 'LINHA 29'),
    );
    await e.review.rejectHunk(e.sessionId, f, h);
    expect(c.readAsStringSync(), contains('linha 29\n'));
    expect(c.readAsStringSync(), contains('LINHA 2\n'));
    expect(File('${e.worktree}/a.txt').existsSync(), isFalse);
  });

  test('conflict without pending changes keeps the agent commits '
      '(no reset)', () async {
    final e = await setUpSession();
    // The agent committed everything: nothing pending in the worktree.
    await gitIn(e.worktree, ['add', '-A']);
    await gitIn(e.worktree, ['commit', '-q', '-m', 'agente: tudo']);
    final wtHead = (await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim();
    File('$repo/b.txt').writeAsStringSync('um\nDois em main\ntrês\n');
    await gitIn(repo, ['commit', '-q', '-am', 'main: b']);
    final mainHead = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();

    await expectLater(
      e.review.merge(e.sessionId),
      throwsA(isA<ReviewException>()),
    );
    expect((await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim(), wtHead);
    expect(
      (await gitIn(e.worktree, ['status', '--porcelain'])).trim(),
      isEmpty,
    );
    expect((await gitIn(repo, ['rev-parse', 'HEAD'])).trim(), mainHead);
    expect((await gitIn(repo, ['status', '--porcelain'])).trim(), isEmpty);
  });

  test('main repository on another branch blocks the merge', () async {
    final e = await setUpSession();
    await gitIn(repo, ['switch', '-q', '-c', 'outra']);
    final wtHead = (await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim();
    await expectLater(
      e.review.merge(e.sessionId),
      throwsA(
        isA<ReviewException>().having(
          (x) => x.message,
          'message',
          contains('git switch main'),
        ),
      ),
    );
    expect((await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim(), wtHead);
    expect(
      (await gitIn(e.worktree, ['status', '--porcelain'])),
      contains(' M b.txt'),
    );
    expect(Directory(e.worktree).existsSync(), isTrue);
  });

  test('mergeGuard only accepts the session pr/ branch and a worktree '
      'inside the worktrees folder', () {
    String? g({
      String branch = 'pr/x',
      String base = 'main',
      String wt = '/h/.promptorium/worktrees/repo-x',
      String root = '/src/repo',
    }) => ReviewService.mergeGuard(
      branch: branch,
      base: base,
      worktreePath: wt,
      workspacePath: root,
      worktreesBase: '/h/.promptorium/worktrees',
    );
    expect(g(), isNull);
    expect(g(branch: 'main'), isNotNull);
    expect(g(branch: '-D'), isNotNull);
    expect(g(branch: 'pr/'), isNotNull);
    expect(g(base: '--force'), isNotNull);
    expect(g(wt: '/src/repo'), isNotNull);
    expect(g(wt: '/src/repo/sub'), isNotNull);
    expect(g(wt: '/h/.promptorium/worktrees'), isNotNull);
    expect(g(wt: '/h/.promptorium/worktrees/../../src/repo'), isNotNull);
    expect(g(wt: '/h/.promptorium/worktrees-x/repo'), isNotNull);
    expect(
      g(
        wt: '/h/.promptorium/worktrees/repo',
        root: '/h/.promptorium/worktrees/repo/a',
      ),
      isNotNull,
    );
  });
}

/// Spec flow: two step sessions share one worktree; the Review shows one
/// item once the card is in Review, and the merge closes spec, steps and
/// file.
void specReviewTests() {
  late Directory tmp;
  late String repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-review-spec-');
    repo = await createRepo(tmp);
    Directory('$repo/specs').createSync();
    File('$repo/specs/SPEC-001-extracao.md').writeAsStringSync(
      '---\nid: SPEC-001\nstatus: aprovada\n---\n\n# Extração\n\n'
      '## Requisitos\n\n- R1 · Tabelas\n- R2 · Índices\n',
    );
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'spec']);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('one Review item per spec; merge → Feito, steps done, file '
      'concluída, every session merged', () async {
    final cli = FakeCli();
    final c = sessionContainer([
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      commandRunnerProvider.overrideWithValue(FakeCommands().call),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    await c.read(specServiceProvider).sync(ws);
    final spec = (await c
        .read(specsRepoProvider)
        .getByCode(ws.id, 'SPEC-001'))!;
    // One step per session (the spec only has two).
    await c
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.singleSessionSteps, '1');
    final runner = c.read(specRunnerProvider);

    await runner.runNext(spec.id);
    await settle();
    final wt = (await c.read(specsRepoProvider).getById(spec.id))!
        .worktreePath!;
    File('$wt/r1.txt').writeAsStringSync('1\n');
    await gitIn(wt, ['add', '.']);
    await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1']);
    cli.last.emit(steps_test.resultLine('ETAPA CONCLUÍDA: R1'));
    await settle();
    await settle();
    // R2 runs next (auto-advance) in the same worktree.
    File('$wt/r2.txt').writeAsStringSync('2\n');
    cli.last.emit(steps_test.resultLine('ETAPA CONCLUÍDA: R2'));
    await settle();
    await settle();

    expect(
      (await c.read(specsRepoProvider).getById(spec.id))!.stage,
      SpecStage.review,
    );
    final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
    expect(sessions, hasLength(2));
    expect(sessions.map((s) => s.worktreePath).toSet(), {wt});

    final specs = await c.read(specsRepoProvider).watchByWorkspace(ws.id).first;
    final all = await c
        .read(sessionsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    final q = await c
        .read(reviewServiceProvider)
        .queue(ws, all, const [], specs);
    expect(q, hasLength(1));
    expect(q.single.spec!.code, 'SPEC-001');
    // (sessions started in the same second tie: any of them stands for it)
    expect(q.single.session.specId, spec.id);

    final branch = (await c.read(specsRepoProvider).getById(spec.id))!.branch!;
    final r = await c.read(reviewServiceProvider).merge(q.single.session.id);
    expect(r.warnings, isEmpty);
    expect(File('$repo/r1.txt').existsSync(), isTrue);
    expect(File('$repo/r2.txt').existsSync(), isTrue);
    expect(
      (await gitIn(repo, [
        'log',
        '--format=%s',
        '--first-parent',
        '-2',
      ])).trim().split('\n'),
      ['SPEC-001: spec concluída', 'Merge $branch: SPEC-001: Extração'],
    );
    expect((await gitIn(repo, ['status', '--porcelain'])).trim(), isEmpty);

    final done = (await c.read(specsRepoProvider).getById(spec.id))!;
    expect(done.stage, SpecStage.done);
    expect(done.worktreePath, isNull);
    final rows = await c.read(specStepsRepoProvider).bySpec(spec.id);
    expect(rows.map((x) => x.status).toSet(), {StepStatus.done});
    final merged = await c.read(sessionsRepoProvider).bySpec(spec.id);
    expect(merged.map((s) => s.status).toSet(), {SessionStatus.merged});
    expect(
      File('$repo/specs/SPEC-001-extracao.md').readAsStringSync(),
      contains('status: concluida'),
    );
    expect(
      await c
          .read(reviewServiceProvider)
          .queue(
            ws,
            await c.read(sessionsRepoProvider).watchByWorkspace(ws.id).first,
            const [],
            await c.read(specsRepoProvider).watchByWorkspace(ws.id).first,
          ),
      isEmpty,
    );
  });
}
