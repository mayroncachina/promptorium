import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/review/pr_import.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/review/widgets/pr_import_dialog.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

/// `gh` simulated for "Trazer PR"; git runs for real.
class FakePrGh {
  List<Map<String, Object?>> open = [];
  Map<String, Object?>? viewed;
  String permission = 'WRITE';
  List<Map<String, Object?>> comments = [];
  final calls = <List<String>>[];

  Iterable<List<String>> gh(String sub) => [
    for (final c in calls)
      if (c.take(2).join(' ') == sub) c,
  ];

  Future<ProcessResult> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
  }) async {
    if (exe != 'gh') return ProcessResult(1, 0, '', '');
    calls.add(args);
    ProcessResult ok(Object o) => ProcessResult(1, 0, jsonEncode(o), '');
    switch (args.take(2).join(' ')) {
      case 'pr list':
        return ok(open);
      case 'pr view':
        return viewed == null
            ? ProcessResult(1, 1, '', 'no pull requests found')
            : ok(viewed!);
      case 'repo view':
        return ok({'viewerPermission': permission});
    }
    if (args.first == 'api') {
      if (args.contains('POST')) return ok({});
      return ok([comments]);
    }
    return ProcessResult(1, 0, '', '');
  }
}

/// The remote is a local bare repository shown as GitHub (or GitLab).
class PrGit extends GitService {
  PrGit(super.root, {super.worktreesBase, this.host = 'github.com'});
  final String host;
  final pushes = <List<String>>[];

  @override
  Future<String> git(List<String> args) async {
    if (args.firstOrNull == 'push' ||
        (args.length > 2 && args[0] == '-C' && args[2] == 'push')) {
      pushes.add(args);
    }
    final out = await super.git(args);
    if (args.take(2).join(' ') == 'remote get-url' &&
        out.trim().startsWith('/')) {
      return 'git@$host:o/r.git\n';
    }
    return out;
  }
}

Map<String, Object?> prJson({
  int number = 214,
  String title = 'Atalho para duplicar card no Quadro',
  String author = 'lucas-andrade',
  String head = 'feat/duplicar-card',
  String base = 'main',
  bool fork = false,
  bool canModify = false,
  bool draft = false,
  String owner = 'o',
  List<Map<String, Object?>> checks = const [
    {'name': 'ci', 'status': 'COMPLETED', 'conclusion': 'SUCCESS'},
  ],
  String body = 'Adiciona "Duplicar" ao menu do card.',
  String state = 'OPEN',
}) => {
  'number': number,
  'url': 'https://github.com/o/r/pull/$number',
  'title': title,
  'author': {'login': author},
  'headRefName': head,
  'baseRefName': base,
  'isCrossRepository': fork,
  'maintainerCanModify': canModify,
  'isDraft': draft,
  'updatedAt': '2026-11-12T10:00:00Z',
  'headRepositoryOwner': {'login': owner},
  'headRefOid': '',
  'state': state,
  'statusCheckRollup': checks,
  'body': body,
};

class PrEnv {
  PrEnv(this.c, this.gh, this.ws, this.cli, this.gits);
  final ProviderContainer c;
  final FakePrGh gh;
  final Workspace ws;
  final FakeCli cli;
  final List<PrGit> gits;
  PrImportService get service => c.read(prImportServiceProvider);
  ReviewService get review => c.read(reviewServiceProvider);
}

/// [PrImportService] with canned answers (the dialog's tests).
class FakeImportService extends PrImportService {
  FakeImportService(super.ref, this.list, {this.unavailable});

  final List<PrImportCandidate> list;
  final String? unavailable;
  PrImportCandidate? resolved;
  final brought = <(int, PrStart, String, bool)>[];

  @override
  Future<PrImportAvailability> availability(Workspace ws) async =>
      PrImportAvailability(reason: unavailable, repository: 'o/r');

  @override
  Future<List<PrImportCandidate>> candidates(Workspace ws) async {
    if (unavailable != null) throw PrImportException(unavailable!);
    return list;
  }

  @override
  Future<PrImportCandidate?> resolve(Workspace ws, String text) async =>
      parsePrReference(text) == null ? null : resolved;

  @override
  Future<List<PrComment>> openComments(Workspace ws, int number) async => [
    for (var i = 0; i < 3; i++)
      PrComment(author: 'a', body: 'c$i', at: DateTime(2026)),
  ];

  @override
  Future<String> bring(
    Workspace ws,
    PrImportCandidate candidate, {
    PrStart start = PrStart.resumir,
    String request = '',
    bool replyInPr = false,
  }) async {
    brought.add((candidate.number, start, request, replyInPr));
    return 'nova';
  }
}

class _Settings extends AppSettingsController {
  @override
  Map<String, String> build() => {};

  @override
  Future<void> set(String key, String value) async =>
      state = {...state, key: value};
}

void main() {
  late Directory tmp;
  late String repo;
  late String origin;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-pr-import-');
    repo = await createRepo(tmp);
    origin = '${tmp.path}/origin.git';
    await gitIn(tmp.path, ['init', '-q', '--bare', '-b', 'main', origin]);
    await gitIn(repo, ['remote', 'add', 'origin', origin]);
    await gitIn(repo, ['push', '-q', 'origin', 'main']);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Publishes a PR on the remote: a branch [head] (unless [fork]) and
  /// `refs/pull/<n>/head`, with one commit changing `pr.txt`.
  Future<String> publishPr(int n, String head, {bool fork = false}) async {
    await gitIn(repo, ['checkout', '-q', '-b', 'tmp-$n', 'main']);
    File('$repo/pr$n.txt').writeAsStringSync('do PR $n\n');
    await gitIn(repo, ['add', 'pr$n.txt']);
    await gitIn(repo, ['commit', '-q', '-m', 'PR $n']);
    final sha = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
    if (!fork) {
      await gitIn(repo, ['push', '-q', 'origin', 'HEAD:refs/heads/$head']);
    }
    await gitIn(repo, ['push', '-q', 'origin', 'HEAD:refs/pull/$n/head']);
    await gitIn(repo, ['checkout', '-q', 'main']);
    await gitIn(repo, ['branch', '-q', '-D', 'tmp-$n']);
    return sha;
  }

  Future<PrEnv> setUpEnv({
    String host = 'github.com',
    String config = '',
    ManagedHooks? hooks,
  }) async {
    final db = memoryDatabase();
    final cli = FakeCli();
    final gh = FakePrGh();
    final gits = <PrGit>[];
    final c = sessionContainer([
      ...sessionOverrides(
        db: db,
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ).where((o) => o.origin != gitServiceFactoryProvider),
      commandRunnerProvider.overrideWithValue(gh.call),
      gitServiceFactoryProvider.overrideWithValue((root) {
        final g = PrGit(root, worktreesBase: '${tmp.path}/wt', host: host);
        gits.add(g);
        return g;
      }),
      if (hooks != null) managedHooksProvider.overrideWithValue(hooks),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    if (config.isNotEmpty) {
      Directory('$repo/.promptorium').createSync();
      File('$repo/.promptorium/config.yml').writeAsStringSync(config);
    }
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    return PrEnv(c, gh, ws, cli, gits);
  }

  group('R1 · lista, busca e "Já no app"', () {
    test('gh pr list traz autor, branch, base, fork, rascunho e checks', () {
      final pr = parseGhOpenPr(
        prJson(
          number: 212,
          author: 'bea-lima',
          head: 'fix/scroll-diff',
          fork: true,
          draft: true,
          owner: 'bea-lima',
          checks: [
            {'name': 'ci', 'status': 'COMPLETED', 'conclusion': 'FAILURE'},
            {'context': 'lint', 'state': 'SUCCESS'},
          ],
        ),
      )!;
      expect(pr.author, 'bea-lima');
      expect(pr.headRefName, 'fix/scroll-diff');
      expect(pr.baseRefName, 'main');
      expect(pr.isCrossRepository, isTrue);
      expect(pr.isDraft, isTrue);
      expect(pr.headOwner, 'bea-lima');
      expect(pr.ci, CiState.failed);
      expect(pr.failedChecks, ['ci']);
      expect(PrImportCandidate(pr: pr).checksLabel, '1 check falhou');
      expect(pr.updatedAt, DateTime.utc(2026, 11, 12, 10));
    });

    test('a busca aceita #n, n e a URL do PR do repositório', () {
      expect(parsePrReference('#212'), 212);
      expect(parsePrReference(' 212 '), 212);
      expect(
        parsePrReference('https://github.com/o/r/pull/99', repository: 'o/r'),
        99,
      );
      expect(parsePrReference('https://github.com/o/r/pull/99/files'), 99);
      expect(parsePrReference('scroll'), isNull);
      expect(
        () => parsePrReference(
          'https://github.com/x/y/pull/1',
          repository: 'o/r',
        ),
        throwsA(isA<PrImportException>()),
      );
      final pr = parseGhOpenPr(prJson())!;
      expect(prMatches(pr, 'duplicar'), isTrue);
      expect(prMatches(pr, '@lucas'), isTrue);
      expect(prMatches(pr, '#21'), isTrue);
      expect(prMatches(pr, 'scroll'), isFalse);
    });

    test('candidates lista os PRs abertos e marca "Já no app" pela prUrl ou '
        'pela branch; resolve lê um PR fora da lista', () async {
      final e = await setUpEnv();
      e.gh.open = [
        prJson(),
        prJson(number: 211, head: 'dependabot/drift', author: 'dependabot'),
        prJson(number: 123, head: 'spec/049-tema-vidro'),
      ];
      await e.c
          .read(sessionsRepoProvider)
          .insert(
            id: 's1',
            workspaceId: e.ws.id,
            worktreePath: repo,
            branch: 'spec/049-tema-vidro',
            model: 'inherit',
            title: 'SPEC-049',
          );
      final list = await e.service.candidates(e.ws);
      expect(list.map((c) => c.number), [214, 211, 123]);
      expect(list.firstWhere((c) => c.number == 123).sessionId, 's1');
      expect(list.firstWhere((c) => c.number == 214).alreadyIn, isFalse);
      expect(list.first.canWrite, isTrue);
      expect(list.first.canPush, isTrue);
      expect(e.gh.gh('pr list').single, contains(ghOpenPrFields));

      e.gh.viewed = prJson(number: 300, title: 'Fora da lista');
      final found = await e.service.resolve(e.ws, '#300');
      expect(found!.title, 'Fora da lista');
      expect(e.gh.gh('pr view').single.take(3), ['pr', 'view', '300']);
      expect(await e.service.resolve(e.ws, 'drift'), isNull);

      e.gh.viewed = prJson(number: 301, state: 'MERGED');
      await expectLater(
        e.service.resolve(e.ws, 'https://github.com/o/r/pull/301'),
        throwsA(isA<PrImportException>()),
      );
    });

    test('sessionOfPr ignora sessões mergeadas', () {
      final pr = parseGhOpenPr(prJson())!;
      Session s(
        String branch, {
        SessionStatus status = SessionStatus.completed,
      }) => Session(
        id: branch,
        workspaceId: 1,
        worktreePath: '/x',
        branch: branch,
        model: 'inherit',
        provider: 'claude',
        status: status,
        startedAt: DateTime(2026),
        costUsd: 0,
        tokensIn: 0,
        tokensOut: 0,
        permissionMode: 'default',
        effort: 'default',
      );
      expect(sessionOfPr(pr, [s('feat/duplicar-card')]), 'feat/duplicar-card');
      expect(
        sessionOfPr(pr, [
          s('feat/duplicar-card', status: SessionStatus.merged),
        ]),
        isNull,
      );
      final fork = parseGhOpenPr(prJson(fork: true))!;
      expect(sessionOfPr(fork, [s('feat/duplicar-card')]), isNull);
      expect(sessionOfPr(fork, [s('pr/214-atalho-para-duplicar')]), isNotNull);
    });
  });

  group('R3 · worktree do PR', () {
    const config =
        'worktree:\n  copiar:\n    - .env\n  preparar: "touch preparado.txt"\n';

    test('PR do mesmo repositório vira worktree na branch do PR, com '
        'upstream no remote, copiar e preparar rodados', () async {
      File('$repo/.gitignore').writeAsStringSync('.env\n');
      await gitIn(repo, ['add', '.gitignore']);
      await gitIn(repo, ['commit', '-q', '-m', 'ignore']);
      File('$repo/.env').writeAsStringSync('SEGREDO=1\n');
      final e = await setUpEnv(config: config);
      final sha = await publishPr(214, 'feat/duplicar-card');
      final pr = parseGhOpenPr(prJson())!;
      final id = await e.service.bring(
        e.ws,
        PrImportCandidate(pr: pr, canWrite: true),
      );
      final s = (await e.c.read(sessionsRepoProvider).getById(id))!;
      expect(s.worktreePath, '${tmp.path}/wt/repo-pr-214');
      expect(s.branch, 'feat/duplicar-card');
      expect(s.baseBranch, 'main');
      expect(s.prUrl, 'https://github.com/o/r/pull/214');
      expect(s.specId, isNull);
      expect(s.taskId, isNull);
      expect(s.title, 'PR #214 · Atalho para duplicar card no Quadro');
      expect((await gitIn(s.worktreePath, ['rev-parse', 'HEAD'])).trim(), sha);
      expect(
        (await gitIn(s.worktreePath, [
          'rev-parse',
          '--abbrev-ref',
          '@{u}',
        ])).trim(),
        'origin/feat/duplicar-card',
      );
      expect(File('${s.worktreePath}/.env').existsSync(), isTrue);
      expect(File('${s.worktreePath}/preparado.txt').existsSync(), isTrue);
      final meta = importedPrOf(e.c.read(appSettingsProvider), id)!;
      expect(meta.author, 'lucas-andrade');
      expect(meta.canPush, isTrue);
      expect(meta.cross, isFalse);
    });

    test('PR de fork vira pr/<n>-<slug>, sem upstream; o push só vai para o '
        'fork com maintainerCanModify', () async {
      final e = await setUpEnv(config: config);
      await publishPr(212, 'fix/scroll-diff', fork: true);
      final pr = parseGhOpenPr(
        prJson(
          number: 212,
          title: 'Corrige o scroll do diff lado a lado',
          author: 'bea-lima',
          head: 'fix/scroll-diff',
          fork: true,
          owner: 'bea-lima',
        ),
      )!;
      final candidate = PrImportCandidate(pr: pr, canWrite: true);
      expect(candidate.canPush, isFalse);
      final id = await e.service.bring(e.ws, candidate);
      final s = (await e.c.read(sessionsRepoProvider).getById(id))!;
      expect(s.branch, 'pr/212-corrige-o-scroll');
      expect(s.worktreePath, '${tmp.path}/wt/repo-pr-212');
      expect(File('${s.worktreePath}/pr212.txt').existsSync(), isTrue);
      expect(File('${s.worktreePath}/preparado.txt').existsSync(), isTrue);
      final meta = importedPrOf(e.c.read(appSettingsProvider), id)!;
      expect(meta.canPush, isFalse);
      expect(meta.pushTo, 'git@github.com:bea-lima/r.git');

      final editable = PrImportCandidate(
        pr: parseGhOpenPr(prJson(fork: true, canModify: true))!,
        canWrite: true,
      );
      expect(editable.canPush, isTrue);
      expect(
        PrImportCandidate(
          pr: parseGhOpenPr(prJson(fork: true, canModify: true))!,
        ).canPush,
        isFalse,
      );
    });

    test('preparar que falha remove o worktree e a branch', () async {
      final e = await setUpEnv(config: 'worktree:\n  preparar: "exit 3"\n');
      await publishPr(214, 'feat/duplicar-card');
      await expectLater(
        e.service.bring(
          e.ws,
          PrImportCandidate(pr: parseGhOpenPr(prJson())!, canWrite: true),
        ),
        throwsA(isA<PrImportException>()),
      );
      expect(Directory('${tmp.path}/wt/repo-pr-214').existsSync(), isFalse);
      expect(
        await gitIn(repo, ['branch', '--list', 'feat/duplicar-card']),
        isEmpty,
      );
    });
  });

  group('R4 · primeira mensagem', () {
    final pr = parseGhOpenPr(
      prJson(
        checks: [
          {'name': 'build', 'status': 'COMPLETED', 'conclusion': 'FAILURE'},
        ],
      ),
    )!;
    final comments = [
      PrComment(
        author: 'mayroncachina',
        body: 'Ctrl+D já é "Duplicar sessão".',
        at: DateTime(2026),
        externalId: 'github:9',
        path: 'lib/board_card.dart',
        line: 144,
      ),
    ];

    String msg(PrStart start, {bool canPush = true, String request = ''}) =>
        prContextMessage(
          pr: pr,
          start: start,
          canPush: canPush,
          diffStat: ' lib/board_card.dart | 18 +++++++++++',
          comments: comments,
          request: request,
        );

    test('as três formas levam o contexto do PR e as regras', () {
      for (final start in PrStart.values) {
        final m = msg(start, request: 'Troque o atalho');
        expect(m, contains('Pull request #214: Atalho para duplicar'));
        expect(m, contains('Adiciona "Duplicar" ao menu do card.'));
        expect(m, contains('Autor: @lucas-andrade'));
        expect(m, contains('feat/duplicar-card → base main'));
        expect(m, contains('lib/board_card.dart | 18'));
        expect(m, contains('lib/board_card.dart:144 — @mayroncachina'));
        expect(m, contains('Checks que falharam: build'));
        expect(m, contains('Nunca reescreva o histórico publicado'));
        expect(m, contains('--force-with-lease'));
      }
      expect(msg(PrStart.resumir), contains('modo plano, sem editar nada'));
      expect(msg(PrStart.resumir), contains('os riscos e as perguntas'));
      expect(
        msg(PrStart.comentarios),
        contains('Corrija o que os comentários'),
      );
      expect(
        msg(PrStart.pedido, request: 'Troque o atalho para Ctrl+Shift+D'),
        endsWith('Troque o atalho para Ctrl+Shift+D'),
      );
      expect(msg(PrStart.resumir, canPush: false), contains('ficam locais'));
      expect(msg(PrStart.resumir), contains('o Promptorium publica'));
    });

    test('bring envia a mensagem com diff --stat e comentários; Resumir roda '
        'em modo plano', () async {
      final e = await setUpEnv();
      await publishPr(214, 'feat/duplicar-card');
      e.gh.comments = [
        {
          'id': 9,
          'path': 'pr214.txt',
          'line': 1,
          'body': 'Renomeie',
          'user': {'login': 'mayroncachina'},
          'created_at': '2026-11-12T10:00:00Z',
        },
      ];
      final id = await e.service.bring(
        e.ws,
        PrImportCandidate(pr: parseGhOpenPr(prJson())!, canWrite: true),
      );
      await settle();
      final args = e.cli.args.single;
      expect(args[args.indexOf('--permission-mode') + 1], 'plan');
      final events = await e.c.read(sessionsRepoProvider).events(id);
      final sent = events.map((x) => x.json).join('\n');
      expect(sent, contains('pr214.txt | 1 +'));
      expect(sent, contains('pr214.txt:1'));
      expect(sent, contains('Renomeie'));
    });

    test('Meu pedido não roda em modo plano e guarda a escolha de "Responder '
        'no PR" do workspace', () async {
      final e = await setUpEnv();
      await publishPr(214, 'feat/duplicar-card');
      await e.service.bring(
        e.ws,
        PrImportCandidate(pr: parseGhOpenPr(prJson())!, canWrite: true),
        start: PrStart.pedido,
        request: 'Troque o atalho',
        replyInPr: true,
      );
      final args = e.cli.args.single;
      expect(args[args.indexOf('--permission-mode') + 1], isNot('plan'));
      expect(e.c.read(appSettingsProvider)[replyInPrKey(e.ws.id)], '1');
    });
  });

  group('R7 · push forçado bloqueado', () {
    test('as regras do PR trazido recusam --force, -f, --force-with-lease '
        'e +refspec, e deixam o push normal', () {
      final rules = blockRules(extra: prForcePushRules);
      for (final cmd in [
        'git push --force',
        'git push origin feat --force',
        'git push -f origin feat',
        'git push --force-with-lease',
        'git push origin --force-with-lease=feat',
        'git push --force-if-includes origin feat',
        'git push origin +HEAD:feat',
        'cd x && git push -uf origin feat',
      ]) {
        expect(blockedBy(cmd, rules), isNotNull, reason: cmd);
      }
      for (final cmd in [
        'git push',
        'git push origin HEAD:feat',
        'git push --follow-tags',
        'git push -u origin feat',
      ]) {
        expect(blockedBy(cmd, rules), isNull, reason: cmd);
      }
      // Without the PR rules, --force-with-lease is allowed (spec sessions).
      expect(blockedBy('git push --force-with-lease', blockRules()), isNull);
    });

    test('a sessão do PR trazido leva as regras no hook PreToolUse', () async {
      final hooks = ManagedHooks(runBase: '${tmp.path}/run');
      final e = await setUpEnv(hooks: hooks);
      await publishPr(214, 'feat/duplicar-card');
      final id = await e.service.bring(
        e.ws,
        PrImportCandidate(pr: parseGhOpenPr(prJson())!, canWrite: true),
      );
      if (!await pythonAvailable()) return; // no python3: no hooks
      final cfg = File('${tmp.path}/run/$id/hooks-config.json')
          .readAsStringSync();
      expect(cfg, contains('PR trazido'));
    });
  });

  group('R10 · GitLab', () {
    test('Trazer PR fica desabilitado com o motivo', () async {
      expect(importUnavailableReason('github'), isNull);
      expect(importUnavailableReason('gitlab'), contains('GitLab'));
      expect(importUnavailableReason(null), isNotNull);
      final e = await setUpEnv(host: 'gitlab.com');
      final a = await e.service.availability(e.ws);
      expect(a.available, isFalse);
      expect(a.reason, contains('GitLab'));
      await expectLater(
        e.service.candidates(e.ws),
        throwsA(isA<PrImportException>()),
      );
      final gh = await setUpEnv();
      final ok = await gh.service.availability(gh.ws);
      expect(ok.available, isTrue);
      expect(ok.repository, 'o/r');
    });
  });

  test('forkRemoteUrl troca o dono na URL ssh e https', () {
    expect(
      forkRemoteUrl('git@github.com:o/r.git', 'bea'),
      'git@github.com:bea/r.git',
    );
    expect(
      forkRemoteUrl('https://github.com/o/r.git', 'bea'),
      'https://github.com/bea/r.git',
    );
    expect(forkRemoteUrl('git@github.com:o/r.git', ''), isNull);
  });

  test('ImportedPr ida e volta', () {
    const meta = ImportedPr(
      number: 7,
      url: 'https://github.com/o/r/pull/7',
      author: 'a',
      canPush: true,
      pushTo: 'git@github.com:a/r.git',
      pendingReplies: ['github:1'],
    );
    final back = ImportedPr.decode(meta.encode())!;
    expect(back.number, 7);
    expect(back.canPush, isTrue);
    expect(back.pushTo, 'git@github.com:a/r.git');
    expect(back.pendingReplies, ['github:1']);
    expect(back.localRef, 'refs/promptorium/pr/7');
    expect(ImportedPr.decode('x'), isNull);
  });

  group('R1 · R4 · diálogo', () {
    final ws = Workspace(
      id: 1,
      path: '/tmp/promptorium-nao-existe',
      name: 'r',
      createdAt: DateTime(2026),
    );
    List<PrImportCandidate> list() => [
      PrImportCandidate(pr: parseGhOpenPr(prJson())!, canWrite: true),
      PrImportCandidate(
        pr: parseGhOpenPr(
          prJson(
            number: 212,
            title: 'Corrige o scroll do diff lado a lado',
            author: 'bea-lima',
            head: 'fix/scroll-diff',
            fork: true,
            owner: 'bea-lima',
            checks: [
              {'name': 'ci', 'status': 'COMPLETED', 'conclusion': 'FAILURE'},
            ],
          ),
        )!,
        canWrite: true,
      ),
      PrImportCandidate(
        pr: parseGhOpenPr(
          prJson(number: 209, title: 'Guia em inglês', draft: true, checks: []),
        )!,
        canWrite: true,
      ),
      PrImportCandidate(
        pr: parseGhOpenPr(
          prJson(number: 123, title: 'SPEC-049 · Tema Vidro', head: 'spec/049'),
        )!,
        sessionId: 's49',
        canWrite: true,
      ),
    ];
    late FakeImportService fake;

    Future<ProviderContainer> open(
      WidgetTester tester, {
      int? number,
      String? unavailable,
    }) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(_Settings.new),
            prImportServiceProvider.overrideWith(
              (ref) => fake = FakeImportService(
                ref,
                list(),
                unavailable: unavailable,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () => showPrImportDialog(
                        context,
                        workspace: ws,
                        number: number,
                      ),
                      child: const Text('abrir'),
                    ),
                    SizedBox(width: 280, child: PrImportButton(workspace: ws)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final c = ProviderScope.containerOf(tester.element(find.text('abrir')));
      await tester.pump();
      if (unavailable == null) {
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
      }
      return c;
    }

    testWidgets('lista com autor, branch e checks, rascunho e "Já no app" '
        'com "Abrir no Review"', (tester) async {
      final c = await open(tester);
      expect(find.text('Trazer PR'), findsOneWidget);
      expect(find.text('Atalho para duplicar card no Quadro'), findsOneWidget);
      expect(
        find.textContaining('@bea-lima · fork · fix/scroll-diff → main'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('pr-import-checks-212')))
            .data,
        '1 check falhou',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('pr-import-checks-214')))
            .data,
        'checks ok',
      );
      expect(find.text('Rascunho'), findsOneWidget);
      expect(find.byKey(const ValueKey('pr-import-already')), findsOneWidget);
      expect(find.byKey(const ValueKey('pr-import-open-123')), findsOneWidget);
      expect(find.byKey(const ValueKey('pr-import-pick-123')), findsNothing);
      expect(find.textContaining('4 abertos'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pr-import-open-123')));
      await tester.pumpAndSettle();
      expect(c.read(selectedReviewProvider), 's49');
      expect(c.read(navigationProvider), AppSection.review);
      expect(find.byKey(const ValueKey('pr-import-dialog')), findsNothing);
    });

    testWidgets('a busca filtra por título, autor e número, e um #n fora da '
        'lista é buscado', (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('pr-import-search')),
        '@bea',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pr-import-row-212')), findsOneWidget);
      expect(find.byKey(const ValueKey('pr-import-row-214')), findsNothing);
      fake.resolved = PrImportCandidate(
        pr: parseGhOpenPr(prJson(number: 300, title: 'Fora da lista'))!,
      );
      await tester.enterText(
        find.byKey(const ValueKey('pr-import-search')),
        '#300',
      );
      await tester.pumpAndSettle();
      expect(find.text('Fora da lista'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('pr-import-search')),
        'https://github.com/x/y/pull/1',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pr-import-error')), findsOneWidget);
    });

    testWidgets('PR de fork sem permissão: aviso, Resumir por padrão e '
        '"Responder aos comentários · 3 abertos"', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('pr-import-pick-212')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pr-import-start')), findsOneWidget);
      expect(find.text('pr/212-corrige-o-scroll'), findsOneWidget);
      expect(find.byKey(const ValueKey('pr-import-no-push')), findsOneWidget);
      expect(
        find.textContaining('não permite edições de mantenedores'),
        findsOneWidget,
      );
      expect(
        find.text('Responder aos comentários · 3 abertos'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('pr-import-bring')));
      await tester.pumpAndSettle();
      expect(fake.brought.single, (212, PrStart.resumir, '', false));
    });

    testWidgets('Meu pedido exige o texto; Responder no PR vem desmarcado e '
        'segue a escolha', (tester) async {
      final c = await open(tester);
      await tester.tap(find.byKey(const ValueKey('pr-import-pick-214')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pr-import-no-push')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('pr-import-start-comentarios')),
      );
      await tester.pumpAndSettle();
      final box = find.descendant(
        of: find.byKey(const ValueKey('pr-import-reply')),
        matching: find.byIcon(Icons.check_box_outline_blank),
      );
      expect(box, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pr-import-reply')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pr-import-start-pedido')));
      await tester.pumpAndSettle();
      final bring = find.byKey(const ValueKey('pr-import-bring'));
      await tester.tap(bring);
      await tester.pump();
      expect(fake.brought, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('pr-import-request')),
        'Troque o atalho',
      );
      await tester.pump();
      await tester.tap(bring);
      await tester.pumpAndSettle();
      expect(fake.brought.single, (
        214,
        PrStart.pedido,
        'Troque o atalho',
        true,
      ));
      expect(c.read(selectedReviewProvider), 'nova');
    });

    testWidgets('aberto com um número, vai direto para "Como começar"', (
      tester,
    ) async {
      await open(tester, number: 214);
      expect(find.byKey(const ValueKey('pr-import-start')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pr-import-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pr-import-row-214')), findsOneWidget);
    });

    testWidgets('R10 · em GitLab, "Trazer PR…" aparece desabilitado com o '
        'motivo', (tester) async {
      await open(tester, unavailable: importUnavailableReason('gitlab'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('review-bring-pr-reason')),
        findsOneWidget,
      );
      expect(find.textContaining('GitLab'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('review-bring-pr')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pr-import-dialog')), findsNothing);
    });
  });
}
