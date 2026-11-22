import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/codex/codex_hooks.dart';

import 'fake_codex.dart';

/// SPEC-103 R3–R5: the Codex adapter of the app's hooks.
void main() {
  final hooks = ManagedHooks(runBase: '/r/run');
  ManagedHookPlan plan([Set<ManagedHook>? on]) => hooks.plan(
    's1',
    enabled: on ?? ManagedHook.values.toSet(),
    rules: builtinBlockRules,
    formatCommand: 'dart format {arquivo}',
    secrets: const {'regras': <Object?>[]},
  );
  final command = hooks.commandOf(plan(), provider: 'codex');

  // The `hooks/list` entry SPEC-093 recorded (hooks-por_c.jsonl).
  final recorded = readCodexTranscript(
    'test/fixtures/codex/0.170/hooks-por_c.jsonl',
  );
  final recordedResult =
      recorded
              .firstWhere((l) => l.dir == 'recv' && l.msg['id'] == 2)
              .msg['result']
          as Map<String, dynamic>;
  final recordedHook =
      ((recordedResult['data'] as List).first as Map)['hooks'][0]
          as Map<String, dynamic>;

  Map<String, dynamic> listed(
    Map<String, ({bool enabled, String trust})> events, {
    String source = 'sessionFlags',
    List<Object?> warnings = const [],
    List<Object?> errors = const [],
  }) => {
    'data': [
      {
        'cwd': '/r/wt',
        'hooks': [
          for (final MapEntry(:key, :value) in events.entries)
            {
              ...recordedHook,
              'eventName': key,
              'command': command,
              'source': source,
              'enabled': value.enabled,
              'trustStatus': value.trust,
            },
        ],
        'warnings': warnings,
        'errors': errors,
      },
    ],
  };

  group('overrides (R3)', () {
    test('one -c per event, in the shape the 0.170 lists', () {
      final o = codexHookOverrides(plan(), command);
      const handler =
          '{type="command",command="python3 \'/r/run/s1/promptorium_hook.py\' '
          '--provedor codex"}';
      expect(o, {
        'hooks.PreToolUse': '[{matcher="*",hooks=[$handler]}]',
        'hooks.PostToolUse': '[{matcher="*",hooks=[$handler]}]',
        'hooks.SessionEnd': '[{hooks=[$handler]}]',
      });
    });

    test('only the events of the hooks that are on; nothing when all are '
        'off', () {
      expect(codexHookOverrides(plan({ManagedHook.end}), command).keys, [
        'hooks.SessionEnd',
      ]);
      expect(codexHookOverrides(plan({}), command), isEmpty);
    });

    test('quotes and backslashes are escaped as TOML', () {
      final o = codexHookOverrides(plan({ManagedHook.end}), r'a "b" \c');
      expect(o['hooks.SessionEnd'], contains(r'command="a \"b\" \\c"'));
    });

    test('never --trust, never ~/.codex, never CODEX_HOME (R3, R4)', () {
      final all = codexHookOverrides(
        plan(),
        command,
      ).entries.expand((e) => ['-c', '${e.key}=${e.value}']).join(' ');
      expect(all, isNot(contains('--trust')));
      expect(all, isNot(contains('bypass')));
      expect(all, isNot(contains('.codex')));
      expect(all, isNot(contains('CODEX_HOME')));
      expect(all, isNot(contains('trusted_hash')));
    });
  });

  group('hooks/list (R5)', () {
    test('the recorded 0.170 answer: listed but untrusted = só pós-turno', () {
      final s = codexHookStatus(
        plan({ManagedHook.block}),
        command: recordedHook['command'] as String,
        result: recordedResult,
      );
      expect(s.mode, CodexHookMode.postTurn);
      expect(s.active, isEmpty);
      expect(s.inactive, {ManagedHook.block});
      expect(s.reason, codexUntrustedReason);
      expect(s.whenOf(ManagedHook.block), HookWhen.afterTurn);
      expect(s.whenOf(ManagedHook.block, yolo: true), HookWhen.unavailable);
    });

    test('every event listed, on and trusted = nativos', () {
      final s = codexHookStatus(
        plan(),
        command: command,
        result: listed({
          'preToolUse': (enabled: true, trust: 'trusted'),
          'postToolUse': (enabled: true, trust: 'managed'),
          'sessionEnd': (enabled: true, trust: 'trusted'),
        }),
      );
      expect(s.mode, CodexHookMode.native);
      expect(s.active, ManagedHook.values.toSet());
      expect(s.reason, isNull);
      expect(s.whenOf(ManagedHook.block, yolo: true), HookWhen.beforeTool);
    });

    test('one hook inactive = parciais, with the inactive ones', () {
      final s = codexHookStatus(
        plan(),
        command: command,
        result: listed({
          'preToolUse': (enabled: true, trust: 'trusted'),
          'postToolUse': (enabled: true, trust: 'untrusted'),
          'sessionEnd': (enabled: false, trust: 'trusted'),
        }),
      );
      expect(s.mode, CodexHookMode.partial);
      expect(s.active, {ManagedHook.block, ManagedHook.secrets});
      expect(s.inactive, {ManagedHook.format, ManagedHook.end});
      expect(s.tooltip, contains('Formatar ao editar'));
    });

    test('the state never comes from what was sent: a hook of another '
        'origin or command does not count', () {
      final s = codexHookStatus(
        plan({ManagedHook.block}),
        command: command,
        result: listed({
          'preToolUse': (enabled: true, trust: 'trusted'),
        }, source: 'user'),
      );
      expect(s.mode, CodexHookMode.postTurn);
      expect(s.reason, 'O Codex não listou os hooks do app.');
      expect(
        codexHookStatus(
          plan({ManagedHook.block}),
          command: 'python3 outro.py',
          result: listed({'preToolUse': (enabled: true, trust: 'trusted')}),
        ).mode,
        CodexHookMode.postTurn,
      );
    });

    test('an error of hooks/list = só pós-turno; errors and warnings go to '
        'the tooltip', () {
      final s = codexHookStatus(
        plan(),
        command: command,
        error: 'Codex: timeout',
      );
      expect(s.mode, CodexHookMode.postTurn);
      expect(s.problems, ['hooks/list falhou: Codex: timeout']);
      final w = codexHookStatus(
        plan({ManagedHook.end}),
        command: command,
        result: listed(
          {'sessionEnd': (enabled: true, trust: 'trusted')},
          warnings: [
            {'message': 'hook lento'},
          ],
          errors: ['config inválida'],
        ),
      );
      expect(w.mode, CodexHookMode.native);
      expect(w.problems, ['Aviso: hook lento', 'Erro: config inválida']);
      expect(w.tooltip, contains('Aviso: hook lento'));
    });

    test('all hooks off = desligados', () {
      expect(
        codexHookStatus(plan({}), command: command).mode,
        CodexHookMode.off,
      );
    });
  });
}
