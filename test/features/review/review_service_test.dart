import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/tasks_repo.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/review/merge_options.dart';
import 'package:promptorium/features/review/review_screen.dart'
    show sinceHeader;
import 'package:promptorium/features/project/project_config.dart'
    show projectConfigProvider;
import 'package:promptorium/features/review/merge_readiness.dart';
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
  FakeCommands({this.hasGh = true, this.authed = true});

  bool hasGh;
  bool authed;

  /// `gh pr merge` merges but exits 1 (local branch still checked out).
  bool mergeExitsWithError = false;

  /// Output of `gh pr view --json` (null = the default PR URL output).
  String? prView;
  String inline = '[]';
  bool apiError = false;

  /// While set, `which` waits for it (a slow probe).
  Completer<void>? gate;
  final calls = <(String, List<String>, String?)>[];

  Future<ProcessResult> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
  }) async {
    calls.add((exe, args, workingDirectory));
    if (exe == 'which') {
      await gate?.future;
      return ProcessResult(1, hasGh ? 0 : 1, hasGh ? '/usr/bin/gh\n' : '', '');
    }
    if (exe == 'gh' && args.take(2).join(' ') == 'auth status') {
      return ProcessResult(1, authed ? 0 : 1, '', '');
    }
    if (exe == 'gh' && args.first == 'api') {
      return ProcessResult(
        1,
        apiError ? 1 : 0,
        inline,
        apiError ? 'offline' : '',
      );
    }
    if (exe == 'gh' && args.take(2).join(' ') == 'pr view') {
      return ProcessResult(1, 0, prView ?? '{}', '');
    }
    if (exe == 'gh' && args.take(2).join(' ') == 'pr merge') {
      return mergeExitsWithError
          ? ProcessResult(1, 1, '', 'failed to delete local branch\n')
          : ProcessResult(1, 0, 'merged\n', '');
    }
    if (exe == 'gh' && args.take(2).join(' ') == 'pr checks') {
      return ProcessResult(1, 0, 'build\tpass\t1m\nlint\tfail\t2s\n', '');
    }
    if (exe == 'gh') {
      return ProcessResult(1, 0, 'https://github.com/o/r/pull/7\n', '');
    }
    return ProcessResult(1, 0, '', '');
  }
}

/// Hosts the transport in a local bare repository while exposing a fake GitHub URL.
class HostedTestGit extends GitService {
  HostedTestGit(super.root, {super.worktreesBase});
  @override
  Future<String> git(List<String> args) async {
    final result = await super.git(args);
    if (args.take(2).join(' ') == 'remote get-url' &&
        result.trim().startsWith('/')) {
      return 'git@github.com:o/r.git';
    }
    return result;
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
      ).where((o) => o.origin != gitServiceFactoryProvider),
      commandRunnerProvider.overrideWithValue(
        (commands ?? FakeCommands()).call,
      ),
      gitServiceFactoryProvider.overrideWithValue(
        (root) => HostedTestGit(root, worktreesBase: '${tmp.path}/wt'),
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

  test('since round includes new commits and working tree but excludes earlier work', () async {
    final e = await setUpSession();
    final sha = (await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim();
    File('${e.worktree}/later.txt').writeAsStringSync('later\n');
    await gitIn(e.worktree, ['add', 'later.txt']);
    await gitIn(e.worktree, ['commit', '-qm', 'later']);
    final detail = await e.review.loadSince(e.sessionId, sha);
    expect(detail.error, isNull);
    expect(detail.commitsAhead, 1);
    expect(detail.files.map((f) => f.path).toSet(), {
      'later.txt',
      'b.txt',
      'novo.txt',
    });
    expect(
      await e.review.roundUnavailable(e.sessionId, null),
      contains('não registrou'),
    );
    expect(
      await e.review.roundUnavailable(e.sessionId, 'abc123'),
      contains('não existe mais'),
    );
  });

  test('since round counts a renamed and an untracked file once each; '
      'with only an uncommitted change it is 0 commits · 1 arquivo', () async {
    final e = await setUpSession();
    await gitIn(e.worktree, ['add', '-A']);
    await gitIn(e.worktree, ['commit', '-qm', 'tudo']);
    final sha = (await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim();

    File('${e.worktree}/b.txt').writeAsStringSync('mudou\n');
    var detail = await e.review.loadSince(e.sessionId, sha);
    expect(detail.commitsAhead, 0);
    expect(detail.files.map((f) => f.path), ['b.txt']);
    expect(
      sinceHeader(detail.commitsAhead, detail.files.length, 3),
      '0 commits · 1 arquivo desde a rodada 3',
    );

    await gitIn(e.worktree, ['checkout', '--', 'b.txt']);
    await gitIn(e.worktree, ['mv', 'b.txt', 'renomeado.txt']);
    await gitIn(e.worktree, ['commit', '-qm', 'renomeia']);
    File('${e.worktree}/solto.txt').writeAsStringSync('solto\n');
    detail = await e.review.loadSince(e.sessionId, sha);
    expect(detail.commitsAhead, 1);
    expect(detail.files.map((f) => f.path).toList(), [
      'renomeado.txt',
      'solto.txt',
    ]);
  });

  test(
    'comment anchors follow real history: shifted by lines added above, '
    'outdated when their line changed, the file was removed or renamed',
    () async {
      final e = await setUpSession();
      await gitIn(e.worktree, ['add', '-A']);
      await gitIn(e.worktree, ['commit', '-qm', 'rodada']);
      final sha = (await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim();
      ReviewCommentRow row(int id, String path, int line) => ReviewCommentRow(
        id: id,
        specId: 1,
        round: 1,
        author: 'revisor',
        body: 'x',
        path: path,
        line: line,
        commitSha: sha,
        resolved: false,
        createdAt: DateTime(2026),
      );
      final a = File('${e.worktree}/a.txt');
      final lines = a.readAsLinesSync()
        ..insertAll(0, ['nova 1', 'nova 2'])
        ..[11] = 'linha 10 alterada';
      a.writeAsStringSync('${lines.join('\n')}\n');
      await gitIn(e.worktree, ['mv', 'b.txt', 'b2.txt']);
      await gitIn(e.worktree, ['commit', '-qam', 'depois']);
      File('${e.worktree}/novo.txt').deleteSync();
      File('${e.worktree}/solto.txt').writeAsStringSync('solto\n');
      final shifts = await e.review.anchorShifts(e.sessionId, [
        row(1, 'a.txt', 20),
        row(2, 'a.txt', 10),
        row(3, 'novo.txt', 1),
        row(4, 'b.txt', 1),
        row(5, 'solto.txt', 1),
      ]);
      expect(shifts[1], (line: 22, reason: null));
      expect(shifts[2]!.line, isNull);
      expect(shifts[2]!.reason, isNotNull);
      expect(shifts[3]!.reason, 'arquivo removido ou renomeado');
      expect(shifts[4]!.reason, 'arquivo removido ou renomeado');
      // A file not committed yet is not "out of the diff".
      expect(shifts[5]?.reason, isNull);
    },
  );

  test('a round whose commit left the branch is unavailable with its own '
      'reason', () async {
    final e = await setUpSession();
    await gitIn(e.worktree, ['add', '-A']);
    await gitIn(e.worktree, ['commit', '-qm', 'reescrito']);
    final sha = (await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim();
    await gitIn(e.worktree, ['reset', '-q', '--hard', 'HEAD~1']);
    final reason = await e.review.roundUnavailable(e.sessionId, sha);
    expect(reason, 'o commit da rodada não existe mais nesta branch');
    expect(await e.review.roundUnavailable(e.sessionId, null), isNot(reason));
    expect((await e.review.loadSince(e.sessionId, sha)).error, reason);
  });

  for (final method in MergeMethod.values) {
    test(
      'local ${method.name} integrates pending files and closes session',
      () async {
        final e = await setUpSession();
        final result = await e.review.merge(
          e.sessionId,
          options: MergeOptions(method: method),
        );
        expect(result.commit, isNotEmpty);
        expect(File('$repo/novo.txt').readAsStringSync(), 'olá\n');
        expect(
          (await e.c.read(sessionsRepoProvider).getById(e.sessionId))!.status,
          SessionStatus.merged,
        );
        final parents = (await gitIn(repo, [
          'show',
          '-s',
          '--format=%P',
          'HEAD',
        ])).trim().split(' ');
        expect(parents.length, method == MergeMethod.merge ? 2 : 1);
      },
    );
  }

  test(
    'guided switch and stash restores the original staged change by sha',
    () async {
      final e = await setUpSession();
      await gitIn(repo, ['switch', '-qc', 'other']);
      File('$repo/local.txt').writeAsStringSync('keep\n');
      await gitIn(repo, ['add', 'local.txt']);
      final result = await e.review.merge(
        e.sessionId,
        options: const MergeOptions(switchBase: true, stash: true),
      );
      expect(result.warnings, isEmpty);
      expect((await gitIn(repo, ['branch', '--show-current'])).trim(), 'other');
      expect(File('$repo/local.txt').readAsStringSync(), 'keep\n');
      expect(
        (await gitIn(repo, ['diff', '--cached', '--name-only'])).trim(),
        'local.txt',
      );
      expect((await gitIn(repo, ['stash', 'list'])).trim(), isEmpty);
      expect((await gitIn(repo, ['show', 'main:novo.txt'])).trim(), 'olá');
    },
  );

  for (final method in MergeMethod.values) {
    test(
      '${method.name} conflict preserves both repository heads and pending files',
      () async {
        final e = await setUpSession();
        File('$repo/a.txt').writeAsStringSync('base conflicts\n');
        await gitIn(repo, ['commit', '-qam', 'conflicting base']);
        final rootHead = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
        final wtHead = (await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim();
        await expectLater(
          e.review.merge(e.sessionId, options: MergeOptions(method: method)),
          throwsA(
            isA<MergeConflictException>().having(
              (e) => e.files,
              'files',
              contains('a.txt'),
            ),
          ),
        );
        expect((await gitIn(repo, ['rev-parse', 'HEAD'])).trim(), rootHead);
        expect((await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim(), wtHead);
        expect((await gitIn(repo, ['status', '--porcelain'])).trim(), isEmpty);
        expect(
          File('${e.worktree}/b.txt').readAsStringSync(),
          'um\nDOIS\ntrês\n',
        );
        expect(File('${e.worktree}/novo.txt').existsSync(), isTrue);
      },
    );
  }

  test(
    'hooks run on pending commits by default and skipHooks is explicit',
    () async {
      final e = await setUpSession();
      final hook = File('$repo/.git/hooks/pre-commit')
        ..writeAsStringSync('#!/bin/sh\nexit 1\n');
      await Process.run('chmod', ['+x', hook.path]);
      await expectLater(
        e.review.merge(e.sessionId),
        throwsA(isA<ReviewException>()),
      );
      expect(File('${e.worktree}/novo.txt').existsSync(), isTrue);
      final result = await e.review.merge(
        e.sessionId,
        options: const MergeOptions(skipHooks: true),
      );
      expect(result.commit, isNotEmpty);
    },
  );

  test('inline PR read groups replies, deduplicates and retains stored rows offline', () async {
    final cmds = FakeCommands();
    final e = await setUpSession(commands: cmds);
    final db = e.c.read(appDatabaseProvider);
    await db.customStatement(
      "INSERT INTO specs(workspace_id,code,title,path) VALUES(1,'SPEC-001','a','specs/a.md')",
    );
    await db.customStatement('UPDATE sessions SET spec_id=1 WHERE id=?', [
      e.sessionId,
    ]);
    await e.c
        .read(sessionsRepoProvider)
        .setPrUrl(e.sessionId, 'https://github.com/base/repo/pull/7');
    cmds.inline = jsonEncode([
      [
        {
          'id': 21,
          'path': 'a.txt',
          'line': null,
          'original_line': 2,
          'commit_id': (await gitIn(e.worktree, ['rev-parse', 'HEAD'])).trim(),
          'body': 'ajustar',
          'user': {'login': 'ana'},
          'created_at': '2026-10-20T10:00:00Z',
        },
        {
          'id': 22,
          'in_reply_to_id': 21,
          'body': 'concordo',
          'user': {'login': 'bia'},
          'created_at': '2026-10-20T11:00:00Z',
        },
      ],
    ]);
    final first = await e.review.prView(e.sessionId);
    expect(first!.comments.single.line, 2);
    expect(first.comments.single.body, contains('@bia: concordo'));
    await e.review.prView(e.sessionId);
    final repo = e.c.read(reviewCommentsRepoProvider);
    expect(await repo.bySpec(1), hasLength(1));
    expect((await repo.bySpec(1)).single.externalId, 'github:21');
    cmds.apiError = true;
    await expectLater(
      e.review.prView(e.sessionId),
      throwsA(isA<ReviewException>()),
    );
    expect(await repo.bySpec(1), hasLength(1));
    expect(
      cmds.calls.any(
        (c) =>
            c.$2.contains('repos/base/repo/pulls/7/comments') &&
            c.$2.contains('--paginate'),
      ),
      isTrue,
    );
  });

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

  test('selected reviewer and PR comments go in the message as '
      'arquivo:linha — texto with their line, and are marked treated; if '
      'sending fails none is', () async {
    final e = await setUpSession();
    final db = e.c.read(appDatabaseProvider);
    await db.customStatement(
      "INSERT INTO specs(workspace_id,code,title,path) VALUES(1,'SPEC-001','a','specs/a.md')",
    );
    await db.customStatement('UPDATE sessions SET spec_id=1 WHERE id=?', [
      e.sessionId,
    ]);
    final repo = e.c.read(reviewCommentsRepoProvider);
    await repo.insertAll([
      ReviewCommentsCompanion.insert(
        specId: 1,
        round: 1,
        author: 'revisor',
        body: 'Padronize a caixa.',
        path: const Value('a.txt'),
        line: const Value(2),
      ),
      ReviewCommentsCompanion.insert(
        specId: 1,
        round: 1,
        author: 'pr',
        body: '@ana: e esta linha?',
        path: const Value('a.txt'),
        line: const Value(3),
      ),
    ]);
    var rows = await repo.bySpec(1);
    await e.cli.last.finish();
    await settle();

    e.cli.failStart = true;
    await expectLater(
      e.review.requestChanges(e.sessionId, const [], selected: rows),
      throwsA(anything),
    );
    expect((await repo.bySpec(1)).where((r) => r.resolved), isEmpty);

    e.cli.failStart = false;
    final msg = await e.review.requestChanges(
      e.sessionId,
      const [],
      selected: rows,
    );
    expect(msg, contains('a.txt:2 — [revisor, rodada 1] Padronize a caixa.'));
    expect(msg, contains('a.txt:3 — [pr, rodada 1] @ana: e esta linha?'));
    expect(msg, contains('LINHA 2'));
    rows = await repo.bySpec(1);
    expect(
      rows.where((r) => r.author != 'humano').every((r) => r.resolved),
      isTrue,
    );
  });

  test('panel and merge decide on the same facts: each service blocker '
      'makes merge refuse; a warning does not', () async {
    // Root on another branch: blocker, merge refuses.
    var e = await setUpSession();
    await gitIn(repo, ['switch', '-qc', 'outra']);
    var ready = evaluateReadiness(await e.review.readinessInputs(e.sessionId));
    expect(ready.blockers.map((i) => i.id), contains('raiz'));
    await expectLater(
      e.review.merge(e.sessionId),
      throwsA(isA<ReviewException>()),
    );
    await gitIn(repo, ['switch', '-q', 'main']);

    // Root with a tracked change: blocker, merge refuses.
    File('$repo/a.txt').writeAsStringSync('mudou na raiz\n');
    ready = evaluateReadiness(await e.review.readinessInputs(e.sessionId));
    expect(ready.blockers.map((i) => i.id), contains('raiz'));
    await expectLater(
      e.review.merge(e.sessionId),
      throwsA(isA<ReviewException>()),
    );
    await gitIn(repo, ['checkout', '--', 'a.txt']);

    // Only uncommitted work in the worktree: a warning, merge goes on.
    ready = evaluateReadiness(await e.review.readinessInputs(e.sessionId));
    expect(ready.blockers, isEmpty);
    expect(ready.warnings.map((i) => i.id), contains('worktree'));
    await e.review.merge(e.sessionId);

    // Already merged: blocker on the worktree item, merge refuses.
    ready = evaluateReadiness(await e.review.readinessInputs(e.sessionId));
    expect(ready.blockers.map((i) => i.id), contains('worktree'));
    await expectLater(
      e.review.merge(e.sessionId),
      throwsA(isA<ReviewException>()),
    );
  });

  test('the readiness provider recalculates when a comment changes, and the '
      'repository watcher fires when the root switches branch', () async {
    final e = await setUpSession();
    final db = e.c.read(appDatabaseProvider);
    await db.customStatement(
      "INSERT INTO specs(workspace_id,code,title,path) VALUES(1,'SPEC-001','a','specs/a.md')",
    );
    await db.customStatement('UPDATE sessions SET spec_id=1 WHERE id=?', [
      e.sessionId,
    ]);
    final seen = <MergeReadiness>[];
    final sub = e.c.listen(
      mergeReadinessProvider(e.sessionId),
      (_, next) => next.whenData(seen.add),
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await e.c.read(mergeReadinessProvider(e.sessionId).future);
    String? comments() =>
        seen.last.items.where((i) => i.id == 'comentarios').firstOrNull?.detail;
    expect(comments(), 'OK');
    await e.c.read(reviewCommentsRepoProvider).insertAll([
      ReviewCommentsCompanion.insert(
        specId: 1,
        round: 1,
        author: 'revisor',
        body: 'falta teste',
      ),
    ]);
    for (var i = 0; i < 50 && comments() == 'OK'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(comments(), '1 comentários abertos');

    var fired = 0;
    final watcher = await e.review.watchRepositories(
      e.sessionId,
      () => fired++,
    );
    expect(watcher, isNotNull);
    addTearDown(() => watcher!.close());
    // Let the watches register before changing the repository.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await gitIn(repo, ['switch', '-qc', 'outra']);
    for (var i = 0; i < 100 && fired == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(fired, greaterThan(0));
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
    expect(a.reason, contains('remote'));
    expect(cmds.calls, isEmpty);

    cmds.hasGh = true;
    a = await e.review.prAvailability(e.sessionId);
    expect(a.available, isFalse);
    expect(a.reason, contains('remote'));
    await expectLater(
      e.review.createPr(e.sessionId),
      throwsA(isA<ReviewException>()),
    );
  });

  test('host routing diagnoses only the required CLI and does not probe unknown providers', () async {
    final cmds = FakeCommands();
    final e = await setUpSession(commands: cmds);
    await gitIn(repo, ['remote', 'add', 'origin', 'git@gitlab.com:o/r.git']);
    var a = await e.review.prAvailability(e.sessionId);
    expect(a.host, 'gitlab');
    expect(a.available, isFalse);
    expect(a.reason, contains('DT-55'));
    expect(
      cmds.calls.every(
        (c) => c.$1 == 'which' && c.$2.single == 'glab' || c.$1 == 'glab',
      ),
      isTrue,
    );
    cmds.calls.clear();
    await gitIn(repo, [
      'remote',
      'set-url',
      'origin',
      'git@github.com:o/r.git',
    ]);
    a = await e.review.prAvailability(e.sessionId);
    expect(a.host, 'github');
    expect(a.available, isTrue);
    expect(cmds.calls.any((c) => c.$1 == 'glab'), isFalse);
    cmds.calls.clear();
    await gitIn(repo, [
      'remote',
      'set-url',
      'origin',
      'git@bitbucket.org:o/r.git',
    ]);
    a = await e.review.prAvailability(e.sessionId);
    expect(a.available, isFalse);
    expect(a.reason, contains('bitbucket.org'));
    expect(cmds.calls, isEmpty);
  });

  test('a local path, an invalid URL and an invalid hospedagem.tipo have '
      'their own diagnosis and probe no CLI', () async {
    final cmds = FakeCommands();
    final e = await setUpSession(commands: cmds);
    await gitIn(repo, ['remote', 'add', 'origin', './outro-repo']);
    var a = await e.review.prAvailability(e.sessionId);
    expect(a.reason, contains('caminho local'));
    await gitIn(repo, ['remote', 'set-url', 'origin', 'nao é uma url']);
    a = await e.review.prAvailability(e.sessionId);
    expect(a.reason, contains('URL inválida'));
    Directory('$repo/.promptorium').createSync(recursive: true);
    File('$repo/.promptorium/config.yml').writeAsStringSync(
      'hospedagem:\n  host: git.exemplo.com\n  tipo: bitbucket\n',
    );
    e.c.invalidate(projectConfigProvider(repo));
    await gitIn(repo, [
      'remote',
      'set-url',
      'origin',
      'git@git.exemplo.com:o/r.git',
    ]);
    a = await e.review.prAvailability(e.sessionId);
    expect(a.reason, contains('hospedagem.tipo "bitbucket" inválido'));
    expect(cmds.calls, isEmpty);
  });

  test('changing the remote while a probe is running discards the late '
      'answer of the old remote', () async {
    final cmds = FakeCommands();
    final e = await setUpSession(commands: cmds);
    await gitIn(repo, ['remote', 'add', 'origin', 'git@github.com:o/r.git']);
    await gitIn(repo, ['remote', 'add', 'fork', 'git@gitlab.com:o/r.git']);
    final settings = e.c.read(appSettingsProvider.notifier);
    await settings.set('review.remote.${e.sessionId}', 'origin');
    final seen = <PrAvailability>[];
    final sub = e.c.listen(
      prAvailabilityProvider(e.sessionId),
      (_, next) => next.whenData(seen.add),
    );
    addTearDown(sub.close);
    cmds.gate = Completer<void>();
    e.c.invalidate(prAvailabilityProvider(e.sessionId));
    e.c.read(prAvailabilityProvider(e.sessionId));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await settings.set('review.remote.${e.sessionId}', 'fork');
    e.c.read(prAvailabilityProvider(e.sessionId));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cmds.gate!.complete();
    final a = await e.c.read(prAvailabilityProvider(e.sessionId).future);
    expect(a.remote, 'fork');
    expect(a.host, 'gitlab');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen.where((s) => s.remote == 'origin'), isEmpty);
  });

  test('switching the active project recomputes the diagnosis', () async {
    final cmds = FakeCommands();
    final e = await setUpSession(commands: cmds);
    await gitIn(repo, ['remote', 'add', 'origin', 'git@github.com:o/r.git']);
    var runs = 0;
    final sub = e.c.listen(
      prAvailabilityProvider(e.sessionId),
      (_, next) => next.whenData((_) => runs++),
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await e.c.read(prAvailabilityProvider(e.sessionId).future);
    final before = runs;
    final other = await e.c
        .read(workspacesRepoProvider)
        .add(path: '${tmp.path}/outro', name: 'outro');
    await e.c
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.activeWorkspace, '${other.id}');
    await e.c.read(prAvailabilityProvider(e.sessionId).future);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(runs, greaterThan(before));
  });

  test('ambiguous remotes require selection, and a saved GitHub PR keeps its destination', () async {
    final cmds = FakeCommands();
    final e = await setUpSession(commands: cmds);
    await gitIn(repo, ['remote', 'add', 'origin', 'git@github.com:o/r.git']);
    await gitIn(repo, ['remote', 'add', 'fork', 'git@gitlab.com:o/r.git']);
    var a = await e.review.prAvailability(e.sessionId);
    expect(a.remotes, containsAll(['origin', 'fork']));
    expect(cmds.calls, isEmpty);
    a = await e.review.prAvailability(e.sessionId, remote: 'origin');
    expect(a.available, isTrue);
    expect(a.remote, 'origin');
    await e.c
        .read(sessionsRepoProvider)
        .setPrUrl(e.sessionId, 'https://github.com/o/r/pull/7');
    await gitIn(repo, [
      'remote',
      'set-url',
      'origin',
      'git@gitlab.com:o/r.git',
    ]);
    cmds.calls.clear();
    await e.review.prView(e.sessionId);
    expect(cmds.calls.first.$1, 'gh');
    expect(cmds.calls.first.$2, contains('https://github.com/o/r/pull/7'));
    await e.c
        .read(sessionsRepoProvider)
        .setPrUrl(e.sessionId, 'https://gitlab.com/o/r/-/merge_requests/7');
    cmds.calls.clear();
    await expectLater(
      e.review.mergePr(e.sessionId, PrMergeMethod.squash),
      throwsA(isA<ReviewException>()),
    );
    expect(cmds.calls, isEmpty);
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

  test('Criar PR: gh not logged in blocks it; draft adds --draft; PR '
      'checks are read', () async {
    final cmds = FakeCommands(authed: false);
    final e = await setUpSession(commands: cmds);
    final remote = '${tmp.path}/remote.git';
    await Process.run('git', ['init', '-q', '--bare', remote]);
    await gitIn(repo, ['remote', 'add', 'origin', remote]);
    var a = await e.review.prAvailability(e.sessionId);
    expect(a.available, isFalse);
    expect(a.reason, contains('gh auth login'));
    cmds.authed = true;
    a = await e.review.prAvailability(e.sessionId);
    expect(a.available, isTrue);
    await e.review.createPr(e.sessionId, draft: true);
    final gh = cmds.calls.lastWhere((c) => c.$1 == 'gh' && c.$2.first == 'pr');
    expect(gh.$2, contains('--draft'));
    expect(await e.review.prChecks(e.sessionId), [
      ('build', 'pass'),
      ('lint', 'fail'),
    ]);
  });

  test('PR babysit: new comments go to the session once; merge via gh '
      'closes the session; conflict instructions (F16)', () async {
    final cmds = FakeCommands();
    final e = await setUpSession(commands: cmds);
    await e.c
        .read(sessionsRepoProvider)
        .setPrUrl(e.sessionId, 'https://github.com/o/r/pull/7');
    final sitter = e.c.read(prBabysitterProvider.notifier);
    await sitter.toggle(e.sessionId);
    expect(sitter.isWatching(e.sessionId), isTrue);
    final later = DateTime.now().add(const Duration(minutes: 1));
    cmds.prView = jsonEncode({
      'state': 'OPEN',
      'mergeable': 'CONFLICTING',
      'reviewDecision': 'CHANGES_REQUESTED',
      'comments': [
        {
          'author': {'login': 'ana'},
          'body': 'Faltou tratar o erro de rede.',
          'createdAt': later.toIso8601String(),
        },
      ],
      'reviews': [],
      'statusCheckRollup': [
        {'name': 'build', 'conclusion': 'FAILURE'},
      ],
    });
    final before = e.cli.processes.length;
    await sitter.check(e.sessionId);
    await settle();
    final status = e.c.read(prBabysitterProvider)[e.sessionId]!.status!;
    expect(status.summary, contains('com conflito'));
    expect(status.summary, contains('1 check(s) falhando'));
    final sent = e.cli.last.writtenJson.last['message']['content'] as String;
    expect(sent, contains('@ana (comentário):'));
    expect(sent, contains('Faltou tratar o erro de rede.'));
    expect(e.cli.processes.length, greaterThanOrEqualTo(before));
    // The same comment is not sent twice.
    final count = e.cli.last.writtenJson.length;
    await sitter.check(e.sessionId);
    await settle();
    expect(e.cli.last.writtenJson.length, count);

    await e.review.resolveConflict(e.sessionId);
    await settle();
    expect(
      e.cli.last.writtenJson.last['message']['content'],
      contains('git merge main'),
    );

    // Merged on GitHub, but gh fails deleting the local branch: still closes.
    cmds.mergeExitsWithError = true;
    cmds.prView = jsonEncode({'state': 'MERGED'});
    final branch = (await e.c.read(sessionsRepoProvider).getById(e.sessionId))!
        .branch;
    await e.review.mergePr(e.sessionId, PrMergeMethod.squash);
    expect(
      (await gitIn(e.ws.path, ['branch', '--list', branch])).trim(),
      isEmpty,
    );
    final merge = cmds.calls.lastWhere(
      (c) => c.$2.take(2).join(' ') == 'pr merge',
    );
    expect(merge.$2, containsAll(['--squash', '--delete-branch']));
    final s = (await e.c.read(sessionsRepoProvider).getById(e.sessionId))!;
    expect(s.status, SessionStatus.merged);
    expect(Directory(e.worktree).existsSync(), isFalse);
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

  test('criteria block the merge until checked or overridden; the Review '
      'filters the diff by step', () async {
    File('$repo/specs/SPEC-001-extracao.md').writeAsStringSync(
      '---\nid: SPEC-001\nstatus: aprovada\n---\n\n# Extração\n\n'
      '## Requisitos\n\n- R1 · Tabelas\n- R2 · Índices\n\n'
      '## Critérios de aceite\n\n- [ ] r1.txt existe [R1]\n'
      '- [x] já conferido\n- [ ] r2.txt existe [R2]\n',
    );
    await gitIn(repo, ['commit', '-q', '-am', 'criterios']);
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
    await c
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.singleSessionSteps, '1');
    await c.read(specRunnerProvider).runNext(spec.id);
    await settle();
    final wt = (await c.read(specsRepoProvider).getById(spec.id))!
        .worktreePath!;
    File('$wt/r1.txt').writeAsStringSync('1\n');
    await gitIn(wt, ['add', '.']);
    await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R1: tabelas']);
    cli.last.emit(steps_test.resultLine('ETAPA CONCLUÍDA: R1'));
    await settle();
    await settle();
    File('$wt/r2.txt').writeAsStringSync('2\n');
    await gitIn(wt, ['add', '.']);
    await gitIn(wt, ['commit', '-q', '-m', 'SPEC-001 R2: índices']);
    cli.last.emit(steps_test.resultLine('ETAPA CONCLUÍDA: R2'));
    await settle();
    await settle();
    final review = c.read(reviewServiceProvider);
    final row = (await c.read(specsRepoProvider).getById(spec.id))!;
    expect(row.stage, SpecStage.review);
    final session = (await c.read(sessionsRepoProvider).bySpec(spec.id)).last;

    // Diff by step.
    final byStep = await review.stepCommits(session.id);
    expect(byStep.keys, ['R1', 'R2']);
    final r2 = await review.loadStep(session.id, 'R2');
    expect(r2.files.map((f) => f.path), ['r2.txt']);

    expect(await review.pendingCriteria(row, ws), [
      'r1.txt existe [R1]',
      'r2.txt existe [R2]',
    ]);
    await expectLater(
      review.merge(session.id),
      throwsA(
        isA<ReviewException>().having(
          (e) => e.message,
          'message',
          contains('Mergear mesmo assim'),
        ),
      ),
    );
    await c
        .read(reviewCommentsRepoProvider)
        .setCriterion(
          spec.id,
          'r1.txt existe [R1]',
          checked: true,
          by: 'humano',
        );
    expect(await review.pendingCriteria(row, ws), ['r2.txt existe [R2]']);
    await review.merge(session.id, override: 'R2 conferido no terminal');
    final done = (await c.read(specsRepoProvider).getById(spec.id))!;
    expect(done.stage, SpecStage.done);
    expect(done.mergeOverride, 'R2 conferido no terminal');
    expect(
      (await gitIn(repo, ['for-each-ref', 'refs/promptorium/'])).trim(),
      isEmpty,
    );
  });
}
