import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/agent_trailer.dart';
import 'package:promptorium/core/git/git_service.dart';

import 'git_test_utils.dart';

void main() {
  late Directory tmp;
  late String repo;
  late GitService git;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-origins-');
    repo = await createRepo(tmp);
    git = GitService(repo, worktreesBase: '${tmp.path}/wt');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Commit with a fixed committer date and optional trailer.
  Future<void> commit(String msg, DateTime at, {String? trailer}) async {
    File('$repo/${msg.hashCode}.txt').writeAsStringSync(msg);
    await gitIn(repo, ['add', '-A']);
    final r = await Process.run(
      'git',
      [
        '-C',
        repo,
        'commit',
        '-q',
        '-m',
        msg,
        if (trailer != null) ...['--trailer', trailer],
      ],
      environment: {
        'GIT_COMMITTER_DATE': at.toIso8601String(),
        'GIT_AUTHOR_DATE': at.toIso8601String(),
      },
    );
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  test('commitAll with trailer marks the commit as app (R4)', () async {
    File('$repo/sobra.txt').writeAsStringSync('x');
    final line = agentTrailerLine(
      appTrailerModel,
      stepOrigin('SPEC-042', ['R2']),
    );
    expect(
      await git.commitAll(
        'SPEC-042 R2: arquivos restantes da etapa',
        trailer: line,
      ),
      isTrue,
    );
    expect(
      (await gitIn(repo, ['log', '-1', '--format=%B'])).trim(),
      'SPEC-042 R2: arquivos restantes da etapa\n\n'
      'Promptorium-Agente: app · SPEC-042 R2',
    );
    final o = await git.commitOrigin('HEAD');
    expect(o.kind, CommitOriginKind.app);
    expect(o.model, 'app');
    expect(o.origin, 'SPEC-042 R2');
    expect(o.trailer, line);
    // Without trailer: as before.
    File('$repo/b.txt').writeAsStringSync('y');
    await git.commitAll('sem marca');
    expect(
      (await gitIn(repo, ['log', '-1', '--format=%B'])).trim(),
      'sem marca',
    );
  });

  test(
    'commitOrigins: person, agent, app and unmarked, with since (R5)',
    () async {
      final d = DateTime.utc(2026, 11, 1);
      // The marking compares committer dates: the initial commit goes back.
      final old = d.subtract(const Duration(days: 1)).toIso8601String();
      final r = await Process.run(
        'git',
        ['-C', repo, 'commit', '-q', '--amend', '--no-edit', '--date', old],
        environment: {'GIT_COMMITTER_DATE': old},
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      await commit('antigo', d);
      await commit(
        'SPEC-042 R1: x',
        d.add(const Duration(days: 1)),
        trailer: 'Promptorium-Agente: sonnet · SPEC-042 R1',
      );
      await commit('meu', d.add(const Duration(days: 2)));
      await commit(
        'SPEC-042 R2: sobra',
        d.add(const Duration(days: 3)),
        trailer: 'Promptorium-Agente: app · SPEC-042 R2',
      );
      await commit(
        'livre',
        d.add(const Duration(days: 4)),
        trailer: 'Promptorium-Agente: gpt-5',
      );
      expect(await git.agentMarkSince('main'), d.add(const Duration(days: 1)));
      expect(await git.agentMarkCount('main'), 3);
      final log = await git.commitOrigins('main', defaultBranch: 'main');
      expect(log.since, d.add(const Duration(days: 1)));
      expect(
        [for (final c in log.commits) (c.subject, c.kind)],
        [
          ('livre', CommitOriginKind.agent),
          ('SPEC-042 R2: sobra', CommitOriginKind.app),
          ('meu', CommitOriginKind.person),
          ('SPEC-042 R1: x', CommitOriginKind.agent),
          ('antigo', CommitOriginKind.unmarked),
          ('inicial', CommitOriginKind.unmarked),
        ],
      );
      final agent = log.commits[3];
      expect(agent.model, 'sonnet');
      expect(agent.origin, 'SPEC-042 R1');
      expect(agent.author, 'Teste');
      expect(log.commits.first.origin, isNull);
      expect(log.count(CommitOriginKind.unmarked), 2);
      // A range and the single read agree.
      final range = await git.commitOrigins(
        'HEAD~2..HEAD',
        defaultBranch: 'main',
      );
      expect(range.commits.length, 2);
      expect(
        (await git.commitOrigin('HEAD~2', defaultBranch: 'main')).kind,
        CommitOriginKind.person,
      );
    },
  );

  test('never marked: everything is unmarked and since is null', () async {
    await commit('a', DateTime.utc(2026, 11, 2));
    final log = await git.commitOrigins('main');
    expect(log.since, isNull);
    expect(
      log.commits.every((c) => c.kind == CommitOriginKind.unmarked),
      isTrue,
    );
    expect(await git.agentMarkCount('main'), 0);
  });

  test('parse keeps the last value of a repeated trailer', () {
    final o = CommitOrigin.parse(
      'abc\x1fAna\x1f2026-11-08T10:00:00Z\x1fs\x1f'
      'haiku · a\x1dopus · SPEC-1 R1',
    );
    expect(o.model, 'opus');
    expect(o.origin, 'SPEC-1 R1');
    expect(o.isAgent, isTrue);
  });
}
