import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/secrets/secret_rules.dart';

import '../git/git_test_utils.dart';
import '../secrets/fake_secrets.dart';

/// SPEC-085 R1, R16: the Vigia de segredos branch of the app's hook.
void main() {
  late Directory tmp;
  late String repo;
  late ManagedHooks hooks;
  late String settings;

  Future<void> prepare({double timeout = 10, bool on = true}) async {
    settings = (await hooks.prepare(
      's1',
      enabled: {ManagedHook.block, ManagedHook.secrets},
      rules: builtinBlockRules,
      secrets: {
        ...secretRulesJson(salt: 'sal', ignoredGlobs: ['test/fixtures/**']),
        'tempo': timeout,
        'ligado': on,
      },
    ))!;
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-hook-secrets-');
    repo = await createRepo(tmp);
    hooks = ManagedHooks(runBase: '${tmp.path}/run');
    await prepare();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Runs the hook for a Bash [command] in [cwd]; returns its stdout.
  Future<String> run(String command, {String? cwd}) async {
    final p = await Process.start('python3', [
      '${hooks.dirOf('s1')}/promptorium_hook.py',
    ], workingDirectory: cwd ?? repo);
    p.stdin.add(
      utf8.encode(
        jsonEncode({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': command},
          'cwd': cwd ?? repo,
        }),
      ),
    );
    await p.stdin.close();
    final out = await p.stdout.transform(utf8.decoder).join();
    await p.stderr.drain<void>();
    expect(await p.exitCode, 0);
    return out;
  }

  String log() {
    final f = File(hooks.logOf('s1'));
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  test('settings route PreToolUse on Bash to the script', () {
    final j = jsonDecode(File(settings).readAsStringSync()) as Map;
    expect((j['hooks'] as Map).keys, contains('PreToolUse'));
    final cfg = jsonDecode(
      File('${hooks.dirOf('s1')}/hooks-config.json').readAsStringSync(),
    ) as Map;
    expect(cfg['segredos'], hooks.secretsOf('s1'));
    expect(File(hooks.secretsOf('s1')).existsSync(), isTrue);
  });

  test('git add -A && git commit with an untracked .env and a key is '
      'denied; the log and the reason only have masked values', () async {
    File('$repo/.env').writeAsStringSync('DATABASE_URL=postgres://a:b@c/d\n');
    Directory('$repo/src/config').createSync(recursive: true);
    File('$repo/src/config/pagamento.ts')
        .writeAsStringSync("// x\nexport const stripeKey = '$fakeStripe';\n");
    final out = await run('git add -A && git commit -m "SPEC-031 R2: Stripe"');
    final j = jsonDecode(out) as Map;
    final hso = j['hookSpecificOutput'] as Map;
    expect(hso['permissionDecision'], 'deny');
    final reason = hso['permissionDecisionReason'] as String;
    expect(
      reason,
      'Promptorium: o Vigia de segredos bloqueou o commit: 2 achados '
      '(arquivo .env; Stripe live key em src/config/pagamento.ts:2). Não '
      'tente contornar nem mudar o comando; espere o usuário decidir.',
    );
    final line = log().trim().split('\n').last;
    final a = HookActivity.fromLogLine(line)!;
    expect(a.hook, ManagedHook.secrets);
    expect(a.text, 'Vigia de segredos bloqueou o commit · 2 achados');
    expect(a.secrets!['achados'], hasLength(2));
    for (final s in [out, log()]) {
      expect(s.contains(fakeStripe), isFalse);
      expect(s.contains(fakeStripe.substring(8, 30)), isFalse);
      expect(s.contains('postgres://a:b'), isFalse);
    }
    expect(log(), contains('sk_live_••••••••(107)'));
  });

  test('git push with the secret in an earlier commit not sent yet is '
      'denied; gh pr create too', () async {
    final bare = '${tmp.path}/remote.git';
    await Process.run('git', ['init', '-q', '--bare', bare]);
    await gitIn(repo, ['remote', 'add', 'origin', bare]);
    await gitIn(repo, ['push', '-q', '-u', 'origin', 'main']);
    File('$repo/k.py').writeAsStringSync('KEY = "$fakeGithub"\n');
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'chave']);
    File('$repo/k.py').writeAsStringSync('KEY = None\n');
    await gitIn(repo, ['commit', '-qam', 'tira a chave']);
    final push = jsonDecode(await run('git push origin main')) as Map;
    expect(
      (push['hookSpecificOutput'] as Map)['permissionDecisionReason'],
      contains('bloqueou o push: 1 achado (GitHub token em k.py:1)'),
    );
    final pr = jsonDecode(await run('gh pr create --fill --base main')) as Map;
    expect(
      (pr['hookSpecificOutput'] as Map)['permissionDecisionReason'],
      contains('bloqueou o PR'),
    );
  });

  test('git -C <dir> commit from another folder is checked', () async {
    File('$repo/id_rsa').writeAsStringSync('x\n');
    final out = await run('git -C $repo commit -am x', cwd: tmp.path);
    expect(out, contains('deny'));
    final cd = await run('cd repo && git commit -m x', cwd: tmp.path);
    expect(cd, contains('deny'));
  });

  test('a command without commit, push or PR passes; a clean commit '
      'passes; ignored paths pass', () async {
    File('$repo/.env').writeAsStringSync('A=1\n');
    expect(await run('ls -la && cat .env'), isEmpty);
    File('$repo/.env').deleteSync();
    File('$repo/b.txt').writeAsStringSync('ok\n');
    expect(await run('git add -A && git commit -m ok'), isEmpty);
    Directory('$repo/test/fixtures').createSync(recursive: true);
    File('$repo/test/fixtures/w.json')
        .writeAsStringSync('{"t": "$fakeGithub"}\n');
    expect(await run('git add -A && git commit -m ok'), isEmpty);
  });

  test('the old rules still win (git push --force)', () async {
    final out = await run('git push --force');
    expect(out, contains('comando bloqueado (git push --force)'));
  });

  test('timeout lets the command through and is logged (R16)', () async {
    await prepare(timeout: 0);
    File('$repo/.env').writeAsStringSync('A=1\n');
    expect(await run('git add -A && git commit -m x'), isEmpty);
    final a = HookActivity.fromLogLine(log().trim().split('\n').last)!;
    expect(a.timedOut, isTrue);
    expect(a.text, 'Vigia de segredos: tempo esgotado, commit não conferido');
  });

  test('the vigia off lets everything through', () async {
    await prepare(on: false);
    File('$repo/.env').writeAsStringSync('A=1\n');
    expect(await run('git add -A && git commit -m x'), isEmpty);
  });

  test('a waiver lets the commit through and is logged (R11, R12)', () async {
    File('$repo/.env').writeAsStringSync('A=1\n');
    await hooks.writeSecrets('s1', {
      ...secretRulesJson(
        salt: 'sal',
        waivers: const [
          SecretWaiverRef(
            id: 9,
            rule: 'env-file',
            path: '.env',
            fingerprint: '',
            byValue: false,
          ),
        ],
      ),
    });
    expect(await run('git add -A && git commit -m x'), isEmpty);
    final a = HookActivity.fromLogLine(log().trim().split('\n').last)!;
    expect(a.waived, [9]);
  });

  test('a typical commit (200 files, ~1 MB) is checked fast (R16)', () async {
    for (var i = 0; i < 200; i++) {
      File('$repo/f$i.txt').writeAsStringSync(
        '${List.filled(100, 'const valor$i = "${fakeChars(40, seed: i)}";').join('\n')}\n',
      );
    }
    final sw = Stopwatch()..start();
    await run('git add -A && git commit -m grande');
    // 1 s on this machine; the GitHub runners are about 2× slower.
    expect(sw.elapsedMilliseconds, lessThan(4000));
  });
}
