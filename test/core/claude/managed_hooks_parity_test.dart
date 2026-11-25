import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/secrets/secret_rules.dart';

import '../git/git_test_utils.dart';
import '../secrets/fake_secrets.dart';

/// SPEC-103 R2, R11: the same script decides the same for equivalent
/// Claude Code and Codex events, and answers in each one's format.
void main() {
  final hasPython = Process.runSync('which', ['python3']).exitCode == 0;
  late Directory tmp;
  late String repo;
  late ManagedHooks hooks;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-hook-parity-');
    repo = await createRepo(tmp);
    hooks = ManagedHooks(runBase: '${tmp.path}/run');
    await hooks.prepare(
      's1',
      enabled: ManagedHook.values.toSet(),
      rules: blockRules(projectGlobs: ['npm publish*']),
      formatCommand: 'printf ok > {arquivo}.fmt',
      secrets: {
        ...secretRulesJson(salt: 'sal', ignoredGlobs: const []),
        'tempo': 10,
      },
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Runs the script as [provider] would; returns (exit, stdout, stderr).
  Future<(int, String, String)> run(
    Map<String, Object?> event, {
    String provider = 'claude',
  }) async {
    final p = await Process.start('python3', [
      '${hooks.dirOf('s1')}/promptorium_hook.py',
      if (provider != 'claude') ...['--provedor', provider],
    ], workingDirectory: repo);
    p.stdin.add(utf8.encode(jsonEncode({...event, 'cwd': repo})));
    await p.stdin.close();
    final out = await p.stdout.transform(utf8.decoder).join();
    final err = await p.stderr.transform(utf8.decoder).join();
    return (await p.exitCode, out, err);
  }

  /// The refusal reason of a run, null when the call goes through.
  /// Claude: exit 0 + `permissionDecision: deny`. Codex: exit 2 + stderr.
  String? reasonOf((int, String, String) r, String provider) {
    final (code, out, err) = r;
    if (provider == 'claude') {
      expect(code, 0);
      if (out.trim().isEmpty) return null;
      final hso = (jsonDecode(out) as Map)['hookSpecificOutput'] as Map;
      expect(hso['permissionDecision'], 'deny');
      return hso['permissionDecisionReason'] as String;
    }
    expect(out.trim(), isEmpty, reason: 'o Codex recusa pelo stderr');
    if (code == 0) {
      expect(err.trim(), isEmpty);
      return null;
    }
    expect(code, 2);
    return err.trim();
  }

  Map<String, Object?> claudeBash(String cmd) => {
    'hook_event_name': 'PreToolUse',
    'tool_name': 'Bash',
    'tool_input': {'command': cmd},
  };

  // The Codex's shell tools: an argv with `bash -lc` and a plain `cmd`.
  List<Map<String, Object?>> codexShell(String cmd) => [
    {
      'hook_event_name': 'preToolUse',
      'tool_name': 'shell',
      'tool_input': {
        'command': ['bash', '-lc', cmd],
      },
    },
    {
      'hook_event_name': 'preToolUse',
      'tool_name': 'exec_command',
      'tool_input': {'cmd': cmd},
    },
  ];

  test('block rules: same decision and same reason in both formats', () async {
    const commands = {
      'git push --force origin spec-031': 'git push --force',
      'rm -rf ~': 'rm -rf na raiz ou na home',
      'git worktree remove ../x': 'git worktree remove',
      'npm publish --tag next': 'npm publish*',
      'flutter test test/pagamento/': null,
      'git push origin spec-031': null,
    };
    for (final MapEntry(key: cmd, value: rule) in commands.entries) {
      final claude = reasonOf(await run(claudeBash(cmd)), 'claude');
      expect(
        claude,
        rule == null
            ? isNull
            : 'Promptorium: comando bloqueado ($rule). Não tente contornar; '
                  'se for necessário, peça ao usuário.',
        reason: cmd,
      );
      for (final e in codexShell(cmd)) {
        final codex = reasonOf(await run(e, provider: 'codex'), 'codex');
        expect(codex, claude, reason: '$cmd · ${e['tool_name']}');
      }
    }
    final log = File(hooks.logOf('s1')).readAsLinesSync();
    final blocks = [
      for (final l in log)
        if ((jsonDecode(l) as Map)['evento'] == 'bloqueio')
          jsonDecode(l) as Map,
    ];
    // 4 blocking commands × (1 Claude + 2 Codex).
    expect(blocks, hasLength(12));
    expect(blocks.where((b) => b['provedor'] == 'codex'), hasLength(8));
  }, skip: hasPython ? false : 'python3 ausente');

  test('Vigia de segredos: a commit with a key is refused alike', () async {
    Directory('$repo/src/config').createSync(recursive: true);
    File('$repo/src/config/pagamento.ts')
        .writeAsStringSync("export const stripeKey = '$fakeStripe';\n");
    const cmd = 'git add -A && git commit -m "integra Stripe"';
    final claude = reasonOf(await run(claudeBash(cmd)), 'claude');
    expect(claude, startsWith('Promptorium: o Vigia de segredos bloqueou o '));
    for (final e in codexShell(cmd)) {
      expect(reasonOf(await run(e, provider: 'codex'), 'codex'), claude);
    }
    final (items, _) = await hooks.readLog('s1', 0);
    final secrets = items.where((a) => a.secrets != null).toList();
    expect(secrets.map((a) => a.provider), ['claude', 'codex', 'codex']);
    expect(secrets.map((a) => a.text).toSet(), {
      'Vigia de segredos bloqueou o commit · 1 achado',
    });
  }, skip: hasPython ? false : 'python3 ausente');

  test('formatar: the files an apply_patch added, updated or moved; a '
      'deleted one is not formatted', () async {
    for (final f in ['b.dart', 'c.dart', 'd.dart']) {
      File('$repo/lib/$f')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    File('$repo/lib/a.dart').writeAsStringSync('x');
    File('$repo/lib/e.dart').writeAsStringSync('x');
    const patch = '''*** Begin Patch
*** Add File: lib/a.dart
+void main() {}
*** Update File: lib/b.dart
@@
-x
+y
*** Delete File: lib/c.dart
*** Update File: lib/d.dart
*** Move to: lib/e.dart
@@
-x
+z
*** End Patch
''';
    final (code, out, _) = await run({
      'hook_event_name': 'postToolUse',
      'tool_name': 'apply_patch',
      'tool_input': {'command': patch},
    }, provider: 'codex');
    expect(code, 0);
    expect(out, isEmpty);
    for (final f in ['a', 'b', 'e']) {
      expect(File('$repo/lib/$f.dart.fmt').existsSync(), isTrue, reason: f);
    }
    for (final f in ['c', 'd']) {
      expect(File('$repo/lib/$f.dart.fmt').existsSync(), isFalse, reason: f);
    }
    // The Claude edit of the same kind formats its file.
    await run({
      'hook_event_name': 'PostToolUse',
      'tool_name': 'Edit',
      'tool_input': {'file_path': '$repo/lib/c.dart'},
    });
    final (items, _) = await hooks.readLog('s1', 0);
    expect(items.map((a) => (a.text, a.provider)), [
      ('Formatado: lib/a.dart', 'codex'),
      ('Formatado: lib/b.dart', 'codex'),
      ('Formatado: lib/e.dart', 'codex'),
      ('Formatado: lib/c.dart', 'claude'),
    ]);
  }, skip: hasPython ? false : 'python3 ausente');

  test('fim da sessão: SessionEnd and sessionEnd give the same card', () async {
    await run({'hook_event_name': 'SessionEnd', 'reason': 'other'});
    await run({
      'hook_event_name': 'sessionEnd',
      'reason': 'other',
    }, provider: 'codex');
    final (items, _) = await hooks.readLog('s1', 0);
    expect(items.map((a) => (a.hook, a.text, a.provider)), [
      (ManagedHook.end, 'Sessão encerrada (other)', 'claude'),
      (ManagedHook.end, 'Sessão encerrada (other)', 'codex'),
    ]);
  }, skip: hasPython ? false : 'python3 ausente');
}
