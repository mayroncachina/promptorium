import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/review/review_host.dart';

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
}
