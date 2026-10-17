import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';

void main() {
  group('rules', () {
    final rules = blockRules(
      projectGlobs: ['npm publish*', 'docker * prune'],
      root: '/home/u/app',
      cwd: '/home/u/.promptorium/worktrees/app-x',
    );
    String? check(String cmd) => blockedBy(cmd, rules);

    test('built-in: force push, rm -rf of root / home, worktree remove', () {
      expect(check('git push --force origin main'), 'git push --force');
      expect(check('git push origin main -f'), 'git push --force');
      expect(check('git push --force-with-lease'), isNull);
      expect(check('git push origin main'), isNull);
      expect(check('rm -rf /'), isNotNull);
      expect(check('rm -rf ~'), isNotNull);
      expect(check('rm -rf ~/'), isNotNull);
      expect(check('rm -rf /*'), isNotNull);
      expect(check('rm -rf ~/projeto/build'), isNull);
      expect(check('rm -rf build/'), isNull);
      expect(check('git worktree remove ../x'), 'git worktree remove');
      expect(check('git worktree list'), isNull);
    });

    test('project globs and the repository root from a worktree', () {
      expect(check('npm publish --tag next'), 'npm publish*');
      expect(check('docker system prune'), 'docker * prune');
      expect(check('docker ps'), isNull);
      expect(check('git -C /home/u/app checkout main'), isNotNull);
      expect(check('cd /home/u/app && git status'), isNotNull);
      expect(check('cd /home/u/app-outro'), isNull);
      expect(check('git -C . status'), isNull);
      // Session in the root itself: no root rules.
      final inRoot = blockRules(root: '/r', cwd: '/r');
      expect(blockedBy('git -C /r status', inRoot), isNull);
    });
  });

  test('settings.json lists one entry per enabled hook', () {
    final j = ManagedHooks.settingsJson('python3 /h.py', {
      ManagedHook.block,
      ManagedHook.end,
    });
    final hooks = j['hooks']! as Map;
    expect(hooks.keys, ['PreToolUse', 'SessionEnd']);
    expect((hooks['PreToolUse'] as List).single['matcher'], 'Bash');
    expect(
      (hooks['SessionEnd'] as List).single.containsKey('matcher'),
      isFalse,
    );
    expect(
      (hooks['PreToolUse'] as List).single['hooks'].single['command'],
      'python3 /h.py',
    );
  });

  group('script (python3)', () {
    late Directory tmp;
    late ManagedHooks hooks;
    final hasPython = Process.runSync('which', ['python3']).exitCode == 0;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('promptorium-hooks-');
      hooks = ManagedHooks(runBase: '${tmp.path}/run');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<String> runHook(Map<String, Object?> event) async {
      final p = await Process.start('python3', [
        '${hooks.dirOf('s1')}/promptorium_hook.py',
      ]);
      p.stdin.write(jsonEncode(event));
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      expect(await p.exitCode, 0);
      return out;
    }

    test('blocks, formats, logs; the app reads the log', () async {
      final settings = await hooks.prepare(
        's1',
        enabled: ManagedHook.values.toSet(),
        rules: blockRules(projectGlobs: ['npm publish*']),
        formatCommand: 'printf formatado > {arquivo}.fmt',
      );
      expect(settings, '${tmp.path}/run/s1/settings.json');
      final cfg = jsonDecode(File(settings!).readAsStringSync()) as Map;
      expect((cfg['hooks'] as Map).keys, [
        'PreToolUse',
        'PostToolUse',
        'SessionEnd',
      ]);

      final denied = await runHook({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'git push --force origin main'},
      });
      final d = jsonDecode(denied) as Map;
      expect(d['hookSpecificOutput']['permissionDecision'], 'deny');
      expect(
        d['hookSpecificOutput']['permissionDecisionReason'],
        contains('git push --force'),
      );
      expect(
        await runHook({
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'flutter test'},
        }),
        isEmpty,
      );
      final file = File('${tmp.path}/x.dart')..writeAsStringSync('a');
      await runHook({
        'hook_event_name': 'PostToolUse',
        'tool_name': 'Write',
        'cwd': tmp.path,
        'tool_input': {'file_path': file.path},
      });
      expect(File('${file.path}.fmt').readAsStringSync(), 'formatado');
      await runHook({'hook_event_name': 'SessionEnd', 'reason': 'other'});

      final (items, offset) = await hooks.readLog('s1', 0);
      expect(items.map((a) => a.hook), [
        ManagedHook.block,
        ManagedHook.format,
        ManagedHook.end,
      ]);
      expect(items.first.text, contains('Hook bloqueou `git push --force'));
      expect(items[1].text, 'Formatado: x.dart');
      expect(items.last.text, 'Sessão encerrada (other)');
      expect((await hooks.readLog('s1', offset)).$1, isEmpty);
      await hooks.cleanup('s1');
      expect(Directory(hooks.dirOf('s1')).existsSync(), isFalse);
    }, skip: hasPython ? false : 'python3 ausente');

    test('a broken config never fails the hook', () async {
      await hooks.prepare('s1', enabled: {ManagedHook.block}, rules: const []);
      File('${hooks.dirOf('s1')}/hooks-config.json').writeAsStringSync('{');
      expect(
        await runHook({'hook_event_name': 'PreToolUse', 'tool_name': 'Bash'}),
        isEmpty,
      );
    }, skip: hasPython ? false : 'python3 ausente');

    test('nothing to do = no settings file', () async {
      expect(
        await hooks.prepare(
          's2',
          enabled: {ManagedHook.format},
          rules: const [],
        ),
        isNull,
      );
    });
  });
}
