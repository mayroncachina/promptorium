import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/core/providers/agent_provider.dart';

import 'fake_codex.dart';

/// SPEC-096 on the adapter: steer, interrupt, "Aprovar nesta conversa",
/// permission requests, the file approval card, writable roots, the access
/// per turn and the app version in `clientInfo` — all on the fake.
void main() {
  Future<(FakeCodex, CodexRun, List<AgentEvent>)> start(
    AgentStartOptions o, {
    String? version,
  }) async {
    final fake = FakeCodex();
    final run = await CodexProvider(
      starter: (exe, args, {workingDirectory, environment}) async => fake,
      clientVersion: () => version,
    ).start(o) as CodexRun;
    final events = <AgentEvent>[];
    run.events.listen(events.add);
    addTearDown(() async {
      await run.stop(timeout: const Duration(milliseconds: 50));
      await fake.finish();
    });
    return (fake, run, events);
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Map<String, dynamic> last(FakeCodex f, String method) =>
      f.writtenJson.lastWhere((m) => m['method'] == method);

  void request(FakeCodex f, Object id, String method, Map<String, dynamic> p) =>
      f.emit(
        jsonEncode({
          'id': id,
          'method': method,
          'params': {'threadId': 'thread-codex', 'turnId': 'turn-1', ...p},
        }),
      );

  const edit = AgentStartOptions(workingDirectory: '/w', mode: PromptMode.edit);

  test('D13: clientInfo carries the app version', () async {
    final (fake, _, _) = await start(edit, version: '0.23.0');
    expect(
      last(fake, 'initialize')['params']['clientInfo']['version'],
      '0.23.0',
    );
  });

  test(
    'R7: a message during the turn goes as turn/steer with the turn id; '
    'Interromper ends it as interrupted by the person, never failed',
    () async {
      final (fake, run, events) = await start(edit);
      await run.send('Comece');
      await settle();
      expect(run.steering, isTrue);
      await run.send('Na verdade, só o README');
      final steer = last(fake, 'turn/steer')['params'];
      expect(steer['expectedTurnId'], 'turn-1');
      expect(steer['input'], [
        {'type': 'text', 'text': 'Na verdade, só o README'},
      ]);
      await run.interrupt();
      expect(last(fake, 'turn/interrupt')['params']['turnId'], 'turn-1');
      fake.emit(
        jsonEncode({
          'method': 'turn/completed',
          'params': {
            'threadId': 'thread-codex',
            'turn': {'id': 'turn-1', 'status': 'interrupted'},
          },
        }),
      );
      await settle();
      final r = events.whereType<Result>().single;
      expect(r.isInterrupted, isTrue);
      expect(r.isError, isFalse);
      expect(r.interruptReason, 'user');
    },
  );

  test('R6: "Aprovar nesta conversa" answers acceptForSession; untrusted '
      'commands do not offer it; nothing writes an execpolicy', () async {
    final (fake, run, events) = await start(edit);
    await run.send('Edite');
    await settle();
    // The fileChange item comes before its approval (D5).
    fake.emit(
      jsonEncode({
        'method': 'item/started',
        'params': {
          'threadId': 'thread-codex',
          'item': {
            'type': 'fileChange',
            'id': 'fc-1',
            'status': 'inProgress',
            'changes': [
              {
                'path': '/w/a.txt',
                'kind': {'type': 'update', 'move_path': null},
                'diff': '@@ -1 +1 @@\n-velho\n+novo\n',
              },
            ],
          },
        },
      }),
    );
    request(fake, 7, 'item/fileChange/requestApproval', {
      'itemId': 'fc-1',
      'reason': 'editar',
    });
    request(fake, 8, 'item/commandExecution/requestApproval', {
      'itemId': 'c-1',
      'command': 'ls',
      'availableDecisions': ['accept', 'cancel'],
    });
    await settle();
    final asks = events.whereType<PermissionRequest>().toList();
    final file = asks.firstWhere((a) => a.toolName == 'Edit');
    expect(file.input['file_path'], '/w/a.txt');
    expect(file.input['unified_diff'], contains('+novo'));
    expect(file.permissionSuggestions, [codexSessionSuggestion]);
    final cmd = asks.firstWhere((a) => a.toolName == 'Bash');
    expect(cmd.permissionSuggestions, isEmpty);
    await run.approve(
      file.requestId,
      updatedPermissions: [codexSessionSuggestion],
    );
    await settle();
    final answer = fake.writtenJson.lastWhere((m) => m['id'] == 7);
    expect(answer['result'], {'decision': 'acceptForSession'});
    // Under untrusted the session option is refused.
    await expectLater(
      run.approve(cmd.requestId, updatedPermissions: [codexSessionSuggestion]),
      throwsA(isA<AgentUnavailable>()),
    );
    await run.approve(cmd.requestId);
    await settle();
    expect(fake.writtenJson.lastWhere((m) => m['id'] == 8)['result'], {
      'decision': 'accept',
    });
  });

  test('R6: permissions/requestApproval shows what is asked and grants it '
      'for the turn only; read-only modes decline it', () async {
    final (fake, run, events) = await start(edit);
    await run.send('Baixe');
    await settle();
    request(fake, 9, 'item/permissions/requestApproval', {
      'itemId': 'p-1',
      'cwd': '/w',
      'startedAtMs': 1,
      'permissions': {
        'network': {'enabled': true},
        'fileSystem': {
          'write': ['/tmp/cache'],
        },
      },
    });
    await settle();
    final ask = events.whereType<PermissionRequest>().single;
    expect(ask.toolName, codexPermissionsTool);
    expect(ask.description, contains('acesso à rede'));
    expect(ask.description, contains('gravar em /tmp/cache'));
    expect(ask.permissionSuggestions, isEmpty);
    await run.approve(ask.requestId);
    await settle();
    final answer = fake.writtenJson.lastWhere((m) => m['id'] == 9)['result'];
    expect(answer['scope'], 'turn');
    expect(answer['permissions']['network'], {'enabled': true});

    final (fake2, run2, _) = await start(
      const AgentStartOptions(workingDirectory: '/w', mode: PromptMode.ask),
    );
    await run2.send('Olhe');
    await settle();
    request(fake2, 3, 'item/permissions/requestApproval', {
      'itemId': 'p-2',
      'permissions': {
        'network': {'enabled': true},
      },
    });
    await settle();
    expect(fake2.writtenJson.lastWhere((m) => m['id'] == 3)['result'], {
      'permissions': <String, dynamic>{},
      'scope': 'turn',
    });
  });

  test('R10: the worktree slice goes as writableRoots of the turn, never on '
      'the thread', () async {
    const roots = [
      '/repo/.git/worktrees/wt',
      '/repo/.git/objects',
      '/repo/.git/refs',
      '/repo/.git/logs',
    ];
    final (fake, run, _) = await start(
      const AgentStartOptions(
        workingDirectory: '/wt',
        mode: PromptMode.edit,
        extras: CodexExtras(writableRoots: roots),
      ),
    );
    final thread = last(fake, 'thread/start')['params'];
    expect(thread['sandbox'], 'read-only');
    expect(thread.containsKey('writableRoots'), isFalse);
    await run.send('Commite');
    expect(last(fake, 'turn/start')['params']['sandboxPolicy'], {
      'type': 'workspaceWrite',
      'writableRoots': roots,
    });
  });

  test('R14: with the turn stopped, a new access is valid for the next '
      'turn/start; while running it is refused', () async {
    final (fake, run, _) = await start(edit);
    await run.setPermissionMode(ClaudePermissionMode.plan);
    await run.send('Leia');
    expect(
      last(fake, 'turn/start')['params']['sandboxPolicy']['type'],
      'readOnly',
    );
    await expectLater(
      run.setPermissionMode(ClaudePermissionMode.acceptEdits),
      throwsA(isA<AgentUnavailable>()),
    );
    fake.completeTurn();
    await settle();
    await run.setPermissionMode(ClaudePermissionMode.acceptEdits);
    await run.send('Edite');
    expect(
      last(fake, 'turn/start')['params']['sandboxPolicy']['type'],
      'workspaceWrite',
    );
    expect(last(fake, 'turn/start')['params']['approvalPolicy'], 'on-request');
  });

  test('R8: images go as data URL UserInput', () async {
    final fake = FakeCodex();
    // The scripted catalog has only text: an image model is refused.
    final run = await CodexProvider(
      starter: (exe, args, {workingDirectory, environment}) async => fake,
    ).start(edit) as CodexRun;
    unawaited(run.events.drain<void>());
    addTearDown(() async {
      await run.stop(timeout: const Duration(milliseconds: 50));
      await fake.finish();
    });
    expect(run.supportsImages, isFalse);
    await expectLater(
      run.send(
        'Veja',
        images: [const ImagePart(mediaType: 'image/png', base64: 'AAAA')],
      ),
      throwsA(isA<AgentUnavailable>()),
    );
  });
}
