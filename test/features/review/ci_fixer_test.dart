import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/tasks_repo.dart';
import 'package:promptorium/features/review/ci_fixer.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/review/pr_import.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/providers/permission_policy.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import '../tasks/task_rules_test.dart' show resultLine;
import 'review_service_test.dart' show FakeCommands, HostedTestGit;

/// `gh` of the review tests plus the logs and reruns of GitHub Actions.
class CiCommands extends FakeCommands {
  final logs = <int, String>{};
  String? rerunError;

  @override
  Future<ProcessResult> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
  }) async {
    if (exe == 'gh' && args.take(2).join(' ') == 'run view') {
      calls.add((exe, args, workingDirectory));
      final log = logs[int.parse(args[2])];
      return log == null
          ? ProcessResult(1, 1, '', 'log not found')
          : ProcessResult(1, 0, log, '');
    }
    if (exe == 'gh' && args.take(2).join(' ') == 'run rerun') {
      calls.add((exe, args, workingDirectory));
      return rerunError == null
          ? ProcessResult(1, 0, '', '')
          : ProcessResult(1, 1, '', rerunError!);
    }
    return super.call(exe, args, workingDirectory: workingDirectory);
  }
}

/// A `result` with the agent's answer.
String answer(String text) => jsonEncode({
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'total_cost_usd': 0.01,
  'num_turns': 1,
  'result': text,
  'usage': {'input_tokens': 10, 'output_tokens': 5},
});

String logRow(String job, String step, String text) =>
    '$job\t$step\t2026-11-15T10:00:00.0000000Z $text';

/// The PR: two Actions jobs failed in run 11, Vercel failed without log,
/// build passed.
String prJson({
  String sha = 'a1b2c3d4e5',
  bool green = false,
  bool running = false,
}) => jsonEncode({
  'state': 'OPEN',
  'mergeable': 'MERGEABLE',
  'headRefOid': sha,
  'comments': [],
  'reviews': [],
  'statusCheckRollup': [
    {
      '__typename': 'CheckRun',
      'name': 'test (ubuntu)',
      'workflowName': 'CI',
      'status': running ? 'IN_PROGRESS' : 'COMPLETED',
      'conclusion': running
          ? ''
          : green
          ? 'SUCCESS'
          : 'FAILURE',
      'detailsUrl': 'https://github.com/o/r/actions/runs/11/job/1',
    },
    {
      '__typename': 'CheckRun',
      'name': 'lint',
      'workflowName': 'CI',
      'status': running ? 'IN_PROGRESS' : 'COMPLETED',
      'conclusion': running
          ? ''
          : green
          ? 'SUCCESS'
          : 'FAILURE',
      'detailsUrl': 'https://github.com/o/r/actions/runs/11/job/2',
    },
    {
      '__typename': 'StatusContext',
      'context': 'Vercel · Preview',
      'state': running
          ? 'PENDING'
          : green
          ? 'SUCCESS'
          : 'FAILURE',
      'targetUrl': 'https://vercel.com/o/r/1',
    },
    {
      '__typename': 'CheckRun',
      'name': 'build',
      'workflowName': 'CI',
      'status': 'COMPLETED',
      'conclusion': 'SUCCESS',
      'detailsUrl': 'https://github.com/o/r/actions/runs/12/job/3',
    },
  ],
});

final ciLog = [
  logRow(
    'test (ubuntu)',
    'Run flutter test',
    'test/cart/coupon_test.dart: aplica 10% [E]',
  ),
  logRow('test (ubuntu)', 'Run flutter test', '  Expected: <90.0>'),
  logRow('test (ubuntu)', 'Run flutter test', '  Actual: <100.0>'),
  logRow(
    'lint',
    'Run flutter analyze',
    "error • The getter 'total' isn't defined",
  ),
].join('\n');

class Env {
  Env(
    this.c,
    this.cli,
    this.cmds,
    this.id,
    this.worktree,
    this.remote,
    this.notifier,
  );

  final FakeNotifier notifier;

  final ProviderContainer c;
  final FakeCli cli;
  final CiCommands cmds;
  final String id;
  final String worktree;
  final String remote;

  CiFixer get fixer => c.read(ciFixerProvider.notifier);
  CiFixState? get st => c.read(ciFixerProvider)[id];

  /// The messages the agent got.
  List<String> get sent => [
    for (final p in cli.processes)
      for (final j in p.writtenJson)
        if (j['message'] is Map) '${j['message']['content']}',
  ];

  List<String> get ciMessages =>
      sent.where((m) => m.contains('O CI do PR #7 falhou')).toList();

  Future<String> head() async =>
      (await gitIn(worktree, ['rev-parse', 'HEAD'])).trim();

  Future<String> commit(String name) async {
    File('$worktree/$name').writeAsStringSync('$name\n');
    await gitIn(worktree, ['add', name]);
    await gitIn(worktree, ['commit', '-q', '-m', 'fix: $name']);
    return head();
  }
}

/// A session that finished (idle, process alive), its branch published
/// to a bare `origin` and a PR whose CI failed.
Future<Env> setUpCiPr(Directory tmp, String repo) async {
  final db = memoryDatabase();
  final cli = FakeCli();
  final notifier = FakeNotifier();
  final cmds = CiCommands()
    ..prView = prJson()
    ..logs[11] = ciLog;
  final c = sessionContainer([
    ...sessionOverrides(
      db: db,
      cli: cli,
      notifier: notifier,
      worktreesBase: '${tmp.path}/wt',
    ).where((o) => o.origin != gitServiceFactoryProvider),
    commandRunnerProvider.overrideWithValue(cmds.call),
    gitServiceFactoryProvider.overrideWithValue(
      (root) => HostedTestGit(root, worktreesBase: '${tmp.path}/wt'),
    ),
  ]);
  addTearDown(c.dispose);
  await c.read(appSettingsProvider.notifier).load();
  final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'repo');
  final task = await TasksRepo(db).insert(
    workspaceId: ws.id,
    code: 'TASK-001',
    title: 'Cupom',
    status: TaskStatus.running,
  );
  final id = await c
      .read(sessionManagerProvider.notifier)
      .create(
        NewSessionRequest(
          workspace: ws,
          title: 'Cupom',
          prompt: 'Implemente',
          taskId: task.id,
        ),
      );
  final row = (await c.read(sessionsRepoProvider).getById(id))!;
  final wt = row.worktreePath;
  File('$wt/cupom.txt').writeAsStringSync('10%\n');
  await gitIn(wt, ['add', '.']);
  await gitIn(wt, ['commit', '-q', '-m', 'cupom']);
  cli.last.emit(resultLine());
  await settle();
  final remote = '${tmp.path}/remote.git';
  await Process.run('git', ['init', '-q', '--bare', remote]);
  await gitIn(repo, ['remote', 'add', 'origin', remote]);
  await gitIn(wt, ['push', '-q', '-u', 'origin', row.branch]);
  await c
      .read(sessionsRepoProvider)
      .setPrUrl(id, 'https://github.com/o/r/pull/7');
  await c.read(prBabysitterProvider.notifier).check(id);
  return Env(c, cli, cmds, id, wt, remote, notifier);
}

void main() {
  late Directory tmp;
  late String repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-ci-');
    repo = await createRepo(tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Env> setUpPr() => setUpCiPr(tmp, repo);

  group('SPEC-073 R4 · Corrigir CI', () {
    test(
      'the log goes to the PR session, which is resumed when it has no '
      'process; one line in the session and one row in the history',
      () async {
        final e = await setUpPr();
        await e.cli.last.finish(0);
        await settle();
        expect(e.c.read(sessionManagerProvider).isAlive(e.id), isFalse);
        expect(await e.fixer.fix(e.id), isTrue);
        await settle();
        expect(e.cli.args.last, containsAllInOrder(['--resume']));
        final msg = e.ciMessages.single;
        expect(msg, contains('falhou no commit a1b2c3d (3 de 4 checks)'));
        expect(msg, contains('## test (ubuntu) · Run flutter test'));
        expect(msg, contains('Expected: <90.0>'));
        expect(msg, contains("## lint · Run flutter analyze"));
        expect(msg, contains('Sem log (fora do Actions): Vercel · Preview.'));
        expect(msg, contains('gh run view 11 --log-failed'));
        expect(msg, isNot(contains('runs/12')));
        expect(msg, contains('Não mude o teste para esconder a falha'));
        expect(msg, contains('$ciExternalPrefix: <motivo>'));
        // Only run 11 failed: its log was read once.
        expect(
          e.cmds.calls
              .where((x) => x.$2.contains('--log-failed'))
              .map((x) => x.$2[2]),
          ['11'],
        );
        expect(e.st!.phase, CiFixPhase.fixing);
        expect(e.st!.round, 1);
        final rec = e.fixer.record(e.id);
        expect(rec.sha, 'a1b2c3d4e5');
        expect(rec.auto, isFalse);
        final rows = await e.c.read(reviewCommentsRepoProvider).bySession(e.id);
        final row = rows.singleWhere((r) => r.author == ciFixAuthor);
        expect(
          row.body,
          'Corrigir CI · commit a1b2c3d · 2 checks · rodada CI1',
        );
        expect(row.round, 0);
        expect(row.resolved, isTrue);
      },
    );

    test('a VIBE: the message goes through send to its conversation', () async {
      final calls = <(String, String)>[];
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          sessionManagerProvider.overrideWith(() => _RecordingManager(calls)),
          prBabysitterProvider.overrideWith(() => _KnownPr(prJson())),
          commandRunnerProvider.overrideWithValue(
            (CiCommands()..logs[11] = ciLog).call,
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      const id = '${vibeSessionPrefix}7';
      await c
          .read(sessionsRepoProvider)
          .insert(
            id: id,
            workspaceId: ws.id,
            worktreePath: repo,
            branch: 'vibe/7',
            model: 'sonnet',
          );
      await c
          .read(sessionsRepoProvider)
          .setPrUrl(id, 'https://github.com/o/r/pull/7');
      c.read(prBabysitterProvider);
      expect(await c.read(ciFixerProvider.notifier).fix(id), isTrue);
      expect(calls.single.$1, id);
      expect(calls.single.$2, contains('O CI do PR #7 falhou'));
    });

    test('only checks without log: off, with the reason (R9)', () {
      final status = parsePrView(
        jsonEncode({
          'state': 'OPEN',
          'headRefOid': 'abc',
          'statusCheckRollup': [
            {'context': 'Vercel', 'state': 'FAILURE'},
          ],
        }),
      )!;
      final f = CiFailure(
        sha: status.headSha,
        total: 1,
        failed: status.failedChecks,
      );
      expect(f.blockReason, 'Nenhum check com log do GitHub Actions');
    });
  });

  group('SPEC-073 R4, R11 · sessão nascida em modo plano', () {
    String? modeArg(List<String> args) {
      final i = args.indexOf('--permission-mode');
      return i < 0 ? null : args[i + 1];
    }

    test('a PR brought with "Resumir o PR" (plan mode) is fixed in a mode '
        'that edits on its own, also by the automatic', () async {
      final e = await setUpPr();
      await e.c
          .read(sessionsRepoProvider)
          .setPermissionMode(e.id, ClaudePermissionMode.plan.cliValue);
      await e.cli.last.finish(0);
      await settle();
      expect(await e.fixer.fix(e.id, auto: true), isTrue);
      await settle();
      final args = e.cli.args.last;
      expect(args, contains('--resume'));
      expect(modeArg(args), 'acceptEdits');
      expect(
        (await e.c.read(sessionsRepoProvider).getById(e.id))!.permissionMode,
        'acceptEdits',
      );
      expect(e.ciMessages, hasLength(1));
    });

    test('the mode picked for new sessions wins when it edits on its '
        'own', () async {
      final e = await setUpPr();
      await e.c
          .read(appSettingsProvider.notifier)
          .set(
            permissionModePreferenceKey('claude'),
            ClaudePermissionMode.skipPermissions.cliValue,
          );
      await e.c
          .read(sessionsRepoProvider)
          .setPermissionMode(e.id, ClaudePermissionMode.plan.cliValue);
      await e.cli.last.finish(0);
      await settle();
      await e.fixer.fix(e.id);
      await settle();
      expect(e.cli.args.last, contains('--dangerously-skip-permissions'));
      expect(modeArg(e.cli.args.last), isNull);
    });

    test('ciFixMode never keeps plan nor "perguntar"', () {
      expect(ciFixMode(null), ClaudePermissionMode.acceptEdits);
      expect(
        ciFixMode(ClaudePermissionMode.plan),
        ClaudePermissionMode.acceptEdits,
      );
      expect(
        ciFixMode(ClaudePermissionMode.defaultMode),
        ClaudePermissionMode.acceptEdits,
      );
      expect(
        ciFixMode(ClaudePermissionMode.skipPermissions),
        ClaudePermissionMode.skipPermissions,
      );
    });

    test('a session not in plan keeps its mode', () async {
      final e = await setUpPr();
      final before = (await e.c.read(sessionsRepoProvider).getById(e.id))!
          .permissionMode;
      await e.fixer.fix(e.id);
      await settle();
      expect(
        (await e.c.read(sessionsRepoProvider).getById(e.id))!.permissionMode,
        before,
      );
    });
  });

  group('SPEC-073 R4, R5 · sessão ocupada e dois cliques', () {
    test('busy: the message waits for the turn to end; "Cancelar" drops '
        'it', () async {
      final e = await setUpPr();
      final m = e.c.read(sessionManagerProvider.notifier);
      await m.send(e.id, 'Outra coisa');
      await settle();
      expect(e.c.read(sessionManagerProvider).live[e.id]!.busy, isTrue);
      await e.fixer.fix(e.id);
      await settle();
      expect(e.st!.phase, CiFixPhase.queued);
      expect(e.ciMessages, isEmpty);
      // A second click while queued sends nothing more.
      expect(await e.fixer.fix(e.id), isFalse);
      e.cli.last.emit(resultLine());
      await until(() async => e.ciMessages.isNotEmpty);
      expect(e.ciMessages, hasLength(1));
      expect(e.st!.phase, CiFixPhase.fixing);
    });

    test('"Cancelar" drops a queued fix', () async {
      final e2 = await setUpPr();
      await e2.c.read(sessionManagerProvider.notifier).send(e2.id, 'x');
      await settle();
      await e2.fixer.fix(e2.id);
      await e2.fixer.cancel(e2.id);
      expect(e2.st, isNull);
      e2.cli.last.emit(resultLine());
      await settle();
      await settle();
      expect(e2.ciMessages, isEmpty);
    });

    test('two clicks at the same time send once', () async {
      final e = await setUpPr();
      final results = await Future.wait([e.fixer.fix(e.id), e.fixer.fix(e.id)]);
      await settle();
      expect(results.where((r) => r), hasLength(1));
      expect(e.ciMessages, hasLength(1));
    });
  });

  group('SPEC-073 R6 · o push é do app', () {
    test('the commit goes to the PR; the CI of the new commit says '
        '"corrigido"', () async {
      final e = await setUpPr();
      await e.fixer.fix(e.id);
      await settle();
      final sha = await e.commit('fix.txt');
      e.cli.last.emit(answer('Corrigido: o cupom lê o subtotal.'));
      await until(() async => e.st?.phase == CiFixPhase.running);
      expect(e.st!.pushedSha, sha);
      final branch = (await e.c.read(sessionsRepoProvider).getById(e.id))!
          .branch;
      expect((await gitIn(e.remote, ['rev-parse', branch])).trim(), sha);
      expect(e.fixer.record(e.id).fixSha, sha);
      // CI running on the new commit, then green.
      e.cmds.prView = prJson(sha: sha, running: true);
      await e.c.read(prBabysitterProvider.notifier).check(e.id);
      expect(e.st!.phase, CiFixPhase.running);
      e.cmds.prView = prJson(sha: sha, green: true);
      await e.c.read(prBabysitterProvider.notifier).check(e.id);
      expect(e.st!.phase, CiFixPhase.fixed);
    });

    test('without a commit the card says so with the answer', () async {
      final e = await setUpPr();
      await e.fixer.fix(e.id);
      await settle();
      e.cli.last.emit(answer('Não achei a causa.'));
      await until(() async => e.st?.phase == CiFixPhase.noCommit);
      expect(e.st!.detail, 'Não achei a causa.');
    });

    test('"CI: falha externa" keeps the reason', () async {
      final e = await setUpPr();
      await e.fixer.fix(e.id);
      await settle();
      e.cli.last.emit(answer('$ciExternalPrefix: o runner perdeu a rede.'));
      await until(() async => e.st?.phase == CiFixPhase.external);
      expect(e.st!.detail, contains('o runner perdeu a rede'));
    });

    test(
      'a refused push shows git\'s reason; "Tentar de novo" pushes',
      () async {
        final e = await setUpPr();
        final hook = File('${e.remote}/hooks/pre-receive')
          ..writeAsStringSync(
            '#!/bin/sh\necho "proteção da branch" >&2\nexit 1\n',
          );
        await Process.run('chmod', ['+x', hook.path]);
        await e.fixer.fix(e.id);
        await settle();
        final sha = await e.commit('fix.txt');
        e.cli.last.emit(answer('Corrigido.'));
        await until(() async => e.st?.phase == CiFixPhase.pushRefused);
        expect(e.st!.detail, contains('proteção da branch'));
        hook.deleteSync();
        await e.fixer.retryPush(e.id);
        expect(e.st!.phase, CiFixPhase.running);
        expect(e.st!.pushedSha, sha);
      },
    );
  });

  group('SPEC-073 R8 · Rodar de novo', () {
    test('only the failed jobs of each failed run; intermittent log '
        'suggests it', () async {
      final e = await setUpPr();
      e.cmds.logs[11] = logRow(
        'test (ubuntu)',
        'Run',
        'curl: (6) Could not resolve host: pub.dev',
      );
      final status = e.c.read(prBabysitterProvider)[e.id]!.status!;
      final f = await e.fixer.failure(e.id, status);
      expect(f.excerpt.flaky, 'host não resolvido');
      await e.fixer.rerun(e.id);
      final reruns = e.cmds.calls.where(
        (x) => x.$2.take(2).join(' ') == 'run rerun',
      );
      expect(reruns.map((x) => x.$2), [
        ['run', 'rerun', '11', '--failed'],
      ]);
      expect(e.st!.phase, CiFixPhase.rerunning);
      expect(e.st!.attempt, 2);
    });

    test('without permission the gh error comes back', () async {
      final e = await setUpPr();
      e.cmds.rerunError = 'HTTP 403: Must have admin rights to Repository.';
      await expectLater(
        e.fixer.rerun(e.id),
        throwsA(
          isA<CiFixException>().having(
            (x) => x.message,
            'message',
            contains('HTTP 403'),
          ),
        ),
      );
    });
  });

  group('SPEC-073 R10 · PR trazido sem permissão', () {
    test('the commit stays local, nothing is pushed', () async {
      final e = await setUpPr();
      await e.c
          .read(appSettingsProvider.notifier)
          .set(
            ImportedPr.key(e.id),
            const ImportedPr(
              number: 7,
              url: 'https://github.com/o/r/pull/7',
            ).encode(),
          );
      expect(e.fixer.pushBlocked(e.id), isTrue);
      final branch = (await e.c.read(sessionsRepoProvider).getById(e.id))!
          .branch;
      final before = (await gitIn(e.remote, ['rev-parse', branch])).trim();
      await e.fixer.fix(e.id);
      await settle();
      await e.commit('fix.txt');
      e.cli.last.emit(answer('Corrigido.'));
      await until(() async => e.st?.phase == CiFixPhase.local);
      expect((await gitIn(e.remote, ['rev-parse', branch])).trim(), before);
    });
  });

  test('CiRecord round-trips through app_settings', () {
    const r = CiRecord(
      sha: 'abc',
      auto: true,
      fixSha: 'def',
      stopped: true,
      rerunSha: 'abc',
      rounds: 2,
      reruns: 1,
    );
    final back = CiRecord.decode(r.encode());
    expect(back.sha, 'abc');
    expect(back.auto, isTrue);
    expect(back.fixSha, 'def');
    expect(back.stopped, isTrue);
    expect(back.rerunSha, 'abc');
    expect(back.rounds, 2);
    expect(back.reruns, 1);
    expect(jsonDecode(r.encode())['origem'], 'automatico');
    expect(CiRecord.decode('lixo').sha, '');
  });
}

class _RecordingManager extends SessionManager {
  _RecordingManager(this.calls);
  final List<(String, String)> calls;

  @override
  Future<void> send(String id, String text, {images = const []}) async {
    calls.add((id, text));
  }
}

class _KnownPr extends PrBabysitter {
  _KnownPr(this.json);
  final String json;

  @override
  Map<String, PrWatch> build() => {
    '${vibeSessionPrefix}7': PrWatch(status: parsePrView(json)),
  };
}
