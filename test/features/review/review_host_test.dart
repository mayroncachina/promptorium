import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/issues/issue_availability.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/review/review_host.dart';

import '../../core/git/fake_issues.dart';

void main() {
  test(
    'detects HTTPS, SSH and scp remotes; custom hosts require configuration',
    () {
      expect(
        detectReviewHost('git@github.com:o/r.git', const ProjectConfig()),
        'github',
      );
      expect(
        detectReviewHost('https://gitlab.com/o/r.git', const ProjectConfig()),
        'gitlab',
      );
      expect(
        detectReviewHost(
          'ssh://git@git.exemplo.com/o/r.git',
          const ProjectConfig(),
        ),
        isNull,
      );
      expect(
        detectReviewHost(
          'ssh://git@git.exemplo.com/o/r.git',
          const ProjectConfig(host: 'git.exemplo.com', hostType: 'gitlab'),
        ),
        'gitlab',
      );
      expect(
        detectReviewHost('/tmp/remote.git', const ProjectConfig()),
        isNull,
      );
    },
  );
  test(
    'invalid glab token is unavailable even if auth status exits zero',
    () async {
      final host = GitlabHost(
        (exe, args, {workingDirectory}) async => ProcessResult(
          1,
          0,
          exe == 'which' ? '/usr/bin/glab' : '',
          exe == 'glab' ? 'Invalid token provided' : '',
        ),
      );
      final result = await host.availability('/tmp', 'gitlab.com');
      expect(result.available, isFalse);
      expect(result.reason, contains('glab auth login'));
    },
  );
  test('resolves explicit/upstream remote and refuses ambiguous or local destinations', () {
    expect(chooseReviewRemote(['origin', 'fork']), isNull);
    expect(chooseReviewRemote(['origin', 'fork'], upstream: 'fork'), 'fork');
    expect(
      chooseReviewRemote(
        ['origin', 'fork'],
        explicit: 'origin',
        upstream: 'fork',
      ),
      'origin',
    );
    expect(chooseReviewRemote(['origin'], explicit: 'missing'), isNull);
    expect(remoteHost('file:///tmp/repo.git'), isNull);
    expect(remoteHost('C:\\repo\\x.git'), isNull);
    expect(
      detectReviewHost(
        'ssh://git@enterprise.example/o/r.git',
        const ProjectConfig(host: 'enterprise.example', hostType: 'github'),
      ),
      'github',
    );
    expect(
      detectReviewHost(
        'ssh://git@other.example/o/r.git',
        const ProjectConfig(host: 'enterprise.example', hostType: 'github'),
      ),
      isNull,
    );
  });

  test('Github probes only gh and authenticates the effective host', () async {
    final calls = <(String, List<String>)>[];
    final host = GithubHost((exe, args, {workingDirectory}) async {
      calls.add((exe, args));
      return ProcessResult(1, 0, exe == 'which' ? '/bin/gh' : '', '');
    });
    expect(
      (await host.availability('/repo', 'enterprise.example')).available,
      isTrue,
    );
    expect(calls.map((c) => c.$1), ['which', 'gh']);
    expect(calls[0].$2, ['gh']);
    expect(calls[1].$2, ['auth', 'status', '--hostname', 'enterprise.example']);
  });

  test('missing CLI offers install; network and compatibility do not become login errors', () async {
    final missing = await GithubHost(
      (exe, args, {workingDirectory}) async => ProcessResult(1, 1, '', ''),
    ).availability('/repo', 'github.com');
    expect(missing.problem, HostProblem.missing);
    expect(missing.installUrl, contains('github.com/cli/cli'));
    for (final fixture in [
      ('network timeout', HostProblem.network),
      ('unknown flag: --hostname', HostProblem.incompatible),
    ]) {
      final result = await GithubHost(
        (exe, args, {workingDirectory}) async => ProcessResult(
          1,
          exe == 'which' ? 0 : 1,
          exe == 'which' ? '/bin/gh' : '',
          fixture.$1,
        ),
      ).availability('/repo', 'github.com');
      expect(result.problem, fixture.$2);
      expect(result.reason, isNot(contains('auth login')));
    }
    final gitlab = await GitlabHost(
      (exe, args, {workingDirectory}) async =>
          ProcessResult(1, 0, '/bin/glab', ''),
    ).availability('/repo', 'gitlab.com');
    expect(gitlab.available, isFalse);
    expect(gitlab.problem, HostProblem.unsupported);
    expect(gitlab.reason, contains('DT-55'));
  });

  test('remote kinds: hosted, local path and invalid URL are told apart', () {
    for (final url in [
      'https://github.com/o/r.git',
      'ssh://git@gitlab.com/o/r.git',
      'git@github.com:o/r.git',
    ]) {
      expect(remoteKind(url), RemoteKind.hosted, reason: url);
    }
    for (final url in [
      '/srv/git/r.git',
      './r',
      '../r',
      '~/r.git',
      'file:///srv/r.git',
      r'C:\repos\r',
    ]) {
      expect(remoteKind(url), RemoteKind.local, reason: url);
    }
    for (final url in ['nao é url', 'https://', 'github.com', '']) {
      expect(remoteKind(url), RemoteKind.invalid, reason: url);
    }
  });

  group('issues (SPEC-074 R2): the same diagnosis, no session needed', () {
    late Directory root;
    setUp(() async {
      root = Directory.systemTemp.createTempSync('issue-avail-');
      await Process.run('git', [
        'init',
        '-q',
        '-b',
        'main',
      ], workingDirectory: root.path);
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<void> remote(String name, String url) => Process.run('git', [
      'remote',
      'add',
      name,
      url,
    ], workingDirectory: root.path);

    Future<IssueAvailability> check(
      FakeIssuesGh fake, {
      ProjectConfig config = const ProjectConfig(),
    }) => issueAvailability(
      root: root.path,
      git: GitService(root.path),
      gh: GhCli(fake.call, cwd: root.path),
      config: config,
    );

    test(
      'available: the repository, its default branch and the account',
      () async {
        await remote('origin', 'git@github.com:ana-souza/loja-da-ana.git');
        final a = await check(FakeIssuesGh(defaultBranch: 'main'));
        expect(a.available, isTrue);
        expect(a.repo, 'ana-souza/loja-da-ana');
        expect(a.defaultBranch, 'main');
        expect(a.account, 'ana-souza');
        expect(
          a.issueUrl(226),
          'https://github.com/ana-souza/loja-da-ana/issues/226',
        );
      },
    );

    test('each reason turns the buttons off with its own text', () async {
      // No remote.
      var a = await check(FakeIssuesGh());
      expect((a.available, a.problem), (false, IssueProblem.noRemote));
      expect(a.reason, contains('não tem remote'));

      // A local remote.
      await remote('origin', '/srv/git/loja.git');
      a = await check(FakeIssuesGh());
      expect(a.problem, IssueProblem.localRemote);
      expect(a.reason, contains('caminho local'));

      // GitLab.
      await Process.run('git', [
        'remote',
        'set-url',
        'origin',
        'git@gitlab.com:ana/loja.git',
      ], workingDirectory: root.path);
      a = await check(FakeIssuesGh());
      expect(a.problem, IssueProblem.gitlab);
      expect(a.reason, contains('só para GitHub'));
      expect(a.title, 'Issues do GitLab ainda não');

      // Another host.
      await Process.run('git', [
        'remote',
        'set-url',
        'origin',
        'git@git.exemplo.com:ana/loja.git',
      ], workingDirectory: root.path);
      a = await check(FakeIssuesGh());
      expect(a.problem, IssueProblem.otherHost);

      await Process.run('git', [
        'remote',
        'set-url',
        'origin',
        'https://github.com/ana-souza/loja-da-ana.git',
      ], workingDirectory: root.path);
      // gh missing: with the link to install it.
      a = await check(FakeIssuesGh(hasGh: false));
      expect(a.problem, IssueProblem.ghMissing);
      expect(a.installUrl, contains('cli/cli'));
      expect(a.title, 'O GitHub CLI (gh) não está instalado');

      // gh without login.
      a = await check(FakeIssuesGh(authed: false));
      expect(a.problem, IssueProblem.ghLoggedOut);
      expect(a.reason, contains('gh auth login'));

      // The issues are off in the repository.
      a = await check(FakeIssuesGh(issuesEnabled: false));
      expect(a.problem, IssueProblem.issuesDisabled);
      expect(a.reason, contains('desligadas em ana-souza/loja-da-ana'));
      expect(a.repo, 'ana-souza/loja-da-ana');
    });

    test('several remotes: origin, unless the branch tracks another', () async {
      await remote('origin', 'git@github.com:ana-souza/loja-da-ana.git');
      await remote('fork', 'git@github.com:lucas/loja-da-ana.git');
      final a = await check(FakeIssuesGh());
      expect(a.remote, 'origin');
      expect(githubRepoOf('https://github.com/o/r.git'), 'o/r');
      expect(githubRepoOf('/srv/r'), isNull);
    });
  });
}
