import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/agent_trailer.dart';

import 'git_test_utils.dart';

/// Runs git in [dir] with [env] added (an agent session's environment).
Future<ProcessResult> gitEnv(
  String dir,
  List<String> args, {
  Map<String, String> env = const {},
  String? stdin,
}) async {
  final p = await Process.start(
    'git',
    ['-C', dir, ...args],
    environment: {
      // The test runner itself may carry GIT_CONFIG_*; start clean.
      'GIT_CONFIG_COUNT': '0',
      ...env,
    },
  );
  if (stdin != null) p.stdin.write(stdin);
  await p.stdin.close();
  final out = await p.stdout.transform(const SystemEncoding().decoder).join();
  final err = await p.stderr.transform(const SystemEncoding().decoder).join();
  final code = await p.exitCode;
  if (code != 0) {
    throw StateError('git ${args.join(' ')} falhou ($code): $err');
  }
  return ProcessResult(p.pid, code, out, err);
}

void writeHook(String path, String body) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('#!/bin/sh\n$body\n');
  Process.runSync('chmod', ['755', path]);
}

void main() {
  late Directory tmp;
  late AgentGitHooks hooks;
  late String repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-trailer-');
    hooks = AgentGitHooks('${tmp.path}/git-hooks');
    await hooks.ensure();
    repo = await createRepo(tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, String> envOf(String model, String origin, {String? session}) =>
      hooks.environment(
        model: model,
        origin: origin,
        sessionId: session,
        inherited: const {},
      );

  Future<String> commitBody([String rev = 'HEAD']) async =>
      (await gitIn(repo, ['log', '-1', '--format=%B', rev])).trim();

  Future<void> agentCommit(
    Map<String, String> env, {
    String file = 'b.txt',
    String message = 'SPEC-042 R2: seletor',
  }) async {
    File('$repo/$file').writeAsStringSync('${DateTime.now()}\n');
    await gitEnv(repo, ['add', '-A'], env: env);
    await gitEnv(repo, ['commit', '-q', '-m', message], env: env);
  }

  group('trailer and origins', () {
    test('line by origin', () {
      expect(
        agentTrailerLine('sonnet', stepOrigin('SPEC-042', ['R2'])),
        'Promptorium-Agente: sonnet · SPEC-042 R2',
      );
      expect(stepOrigin('SPEC-042', ['R1', 'R2']), 'SPEC-042 R1, R2');
      expect(conflictOrigin('SPEC-043'), 'SPEC-043 conflito');
      expect(restackOrigin('SPEC-042'), 'SPEC-042 base');
      expect(sessionOrigin(' refatorar '), 'sessão refatorar');
      expect(agentTrailerValue('opus', promptOrigin), 'opus · Prompt');
      expect(agentModelLabel('inherit', 'claude'), 'claude');
      expect(agentModelLabel('gpt-5', 'codex'), 'gpt-5');
    });

    test('environment appends core.hooksPath after inherited entries', () {
      final env = hooks.environment(
        model: 'sonnet',
        origin: 'SPEC-042 R2',
        sessionId: 's1',
        inherited: const {'GIT_CONFIG_COUNT': '2'},
      );
      expect(env['GIT_CONFIG_COUNT'], '3');
      expect(env['GIT_CONFIG_KEY_2'], 'core.hooksPath');
      expect(env['GIT_CONFIG_VALUE_2'], hooks.dir);
      expect(env['PROMPTORIUM_GIT_CONFIG_BASE'], '2');
      expect(env['PROMPTORIUM_AGENTE'], 'sonnet');
      expect(env['PROMPTORIUM_ORIGEM'], 'SPEC-042 R2');
      expect(env['PROMPTORIUM_ORIGEM_ARQUIVO'], hooks.originFile('s1'));
    });

    test('off, without hooks or with an old git: no variables', () async {
      Future<Map<String, String>> env({
        bool enabled = true,
        AgentGitHooks? h,
        GitVersion? git = const GitVersion(2, 43),
      }) => agentCommitEnv(
        enabled: enabled,
        hooks: h,
        git: git,
        model: 'sonnet',
        origin: 'x',
        inherited: const {},
      );
      expect(await env(h: hooks), isNotEmpty);
      expect(await env(enabled: false, h: hooks), isEmpty);
      expect(await env(), isEmpty);
      expect(await env(h: hooks, git: const GitVersion(2, 31, 9)), isEmpty);
      expect(await env(h: hooks, git: null), isEmpty);
      expect(
        GitVersion.parse('git version 2.39.2.windows.1'),
        const GitVersion(2, 39, 2),
      );
      expect(
        gitSupportsAgentTrailer(GitVersion.parse('git version 2.32.0')),
        isTrue,
      );
    });

    test('ensure rewrites the folder when the version changes', () async {
      File('${hooks.dir}/pre-commit').writeAsStringSync('velho');
      File('${hooks.dir}/${AgentGitHooks.versionFile}').writeAsStringSync('0');
      await hooks.ensure();
      expect(
        File('${hooks.dir}/pre-commit').readAsStringSync(),
        AgentGitHooks.passScript,
      );
      for (final h in AgentGitHooks.standardHooks) {
        expect(File('${hooks.dir}/$h').existsSync(), isTrue, reason: h);
      }
    });
  });

  group('real git', () {
    test(
      'agent commit gets the line; amend replaces, never duplicates',
      () async {
        final env = envOf('sonnet', 'SPEC-042 R2');
        await agentCommit(env);
        expect(
          await commitBody(),
          'SPEC-042 R2: seletor\n\nPromptorium-Agente: sonnet · SPEC-042 R2',
        );
        await gitEnv(repo, [
          'commit',
          '-q',
          '--amend',
          '--no-edit',
        ], env: envOf('opus', 'SPEC-042 R3'));
        final body = await commitBody();
        expect(
          RegExp('Promptorium-Agente').allMatches(body).length,
          1,
          reason: body,
        );
        expect(body, endsWith('Promptorium-Agente: opus · SPEC-042 R3'));
        // Read back as a trailer.
        expect(
          (await gitIn(repo, [
            'log',
            '-1',
            '--format=%(trailers:key=Promptorium-Agente,valueonly)',
          ])).trim(),
          'opus · SPEC-042 R3',
        );
      },
    );

    test('a commit outside the session (terminal) has no line', () async {
      File('$repo/c.txt').writeAsStringSync('c\n');
      await gitEnv(repo, ['add', '-A']);
      await gitEnv(repo, ['commit', '-q', '-m', 'meu commit']);
      expect(await commitBody(), 'meu commit');
    });

    test(
      'the origin file of a live session wins over the environment',
      () async {
        final env = envOf('sonnet', 'SPEC-042 R2', session: 's1');
        await hooks.setOrigin('s1', 'SPEC-042 conflito');
        await agentCommit(env);
        expect(
          await commitBody(),
          endsWith('Promptorium-Agente: sonnet · SPEC-042 conflito'),
        );
        await hooks.clearOrigin('s1');
        await agentCommit(env, file: 'd.txt');
        expect(
          await commitBody(),
          endsWith('Promptorium-Agente: sonnet · SPEC-042 R2'),
        );
      },
    );

    test('.git/hooks run with the same arguments and stdin', () async {
      final log = '${tmp.path}/log';
      final h = '$repo/.git/hooks';
      writeHook('$h/pre-commit', 'echo "pre-commit \$#" >> "$log"');
      writeHook(
        '$h/prepare-commit-msg',
        'echo "prepare \$2" >> "$log"\necho "Linha do repo" >> "\$1"',
      );
      writeHook('$h/commit-msg', 'echo "commit-msg" >> "$log"');
      writeHook(
        '$h/post-checkout',
        'echo "post-checkout \$3 core=\$(git config core.hooksPath)" >> "$log"',
      );
      writeHook(
        '$h/pre-push',
        'echo "pre-push \$1 \$2" >> "$log"\ncat >> "$log"',
      );
      final env = envOf('sonnet', 'SPEC-042 R2');
      await agentCommit(env);
      final body = await commitBody();
      // The repository's prepare-commit-msg runs before the marking.
      expect(body, contains('Linha do repo'));
      expect(body, endsWith('Promptorium-Agente: sonnet · SPEC-042 R2'));
      await gitEnv(repo, ['checkout', '-q', '-b', 'outra'], env: env);
      final remote = '${tmp.path}/remote.git';
      await gitIn(tmp.path, ['init', '-q', '--bare', remote]);
      await gitIn(repo, ['remote', 'add', 'origin', remote]);
      await gitEnv(repo, ['push', '-q', 'origin', 'outra'], env: env);
      final sha = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
      final lines = File(log).readAsLinesSync();
      expect(lines, [
        'pre-commit 0',
        'prepare message',
        'commit-msg',
        // Inside the repository's hook, core.hooksPath is its own (unset).
        'post-checkout 1 core=',
        'pre-push origin $remote',
        'refs/heads/outra $sha refs/heads/outra '
            '0000000000000000000000000000000000000000',
      ]);
    });

    test('husky (core.hooksPath of the project) keeps running', () async {
      final log = '${tmp.path}/log';
      await gitIn(repo, ['config', 'core.hooksPath', '.husky']);
      writeHook(
        '$repo/.husky/pre-commit',
        'echo "husky pre-commit core=\$(git config core.hooksPath)" >> "$log"',
      );
      writeHook(
        '$repo/.husky/commit-msg',
        'grep -q "Promptorium-Agente" "\$1" && echo "husky viu a linha" >> "$log"',
      );
      // A hook in .git/hooks is ignored, as without the app.
      writeHook('$repo/.git/hooks/pre-commit', 'echo "nao" >> "$log"');
      await agentCommit(envOf('gpt-5', 'sessão refatorar'));
      expect(File(log).readAsLinesSync(), [
        'husky pre-commit core=.husky',
        'husky viu a linha',
      ]);
      expect(
        await commitBody(),
        endsWith('Promptorium-Agente: gpt-5 · sessão refatorar'),
      );
    });

    test('a failing repository hook still blocks the commit', () async {
      writeHook('$repo/.git/hooks/pre-commit', 'exit 3');
      File('$repo/e.txt').writeAsStringSync('e\n');
      final env = envOf('sonnet', 'x');
      await gitEnv(repo, ['add', '-A'], env: env);
      expect(
        () => gitEnv(repo, ['commit', '-q', '-m', 'bloqueado'], env: env),
        throwsStateError,
      );
    });

    test(
      'inherited GIT_CONFIG entries are kept for the repository hook',
      () async {
        final log = '${tmp.path}/log';
        writeHook(
          '$repo/.git/hooks/pre-commit',
          'echo "x=\$(git config promptorium.teste)" >> "$log"',
        );
        final env = {
          'GIT_CONFIG_KEY_0': 'promptorium.teste',
          'GIT_CONFIG_VALUE_0': 'herdado',
          ...hooks.environment(
            model: 'sonnet',
            origin: 'x',
            inherited: const {'GIT_CONFIG_COUNT': '1'},
          ),
        };
        await agentCommit(env);
        expect(File(log).readAsLinesSync(), ['x=herdado']);
        expect(await commitBody(), endsWith('Promptorium-Agente: sonnet · x'));
      },
    );
  });
}
