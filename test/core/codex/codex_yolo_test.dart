import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_command.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/core/providers/permission_policy.dart';

import 'fake_codex.dart';

void main() {
  test('interactive create/resume/fork use YOLO and no Claude arguments', () {
    for (final args in [
      codexCommandArgs(permissionMode: ClaudePermissionMode.skipPermissions),
      codexCommandArgs(
        threadId: 'thread',
        permissionMode: ClaudePermissionMode.skipPermissions,
      ),
      codexCommandArgs(
        threadId: 'thread',
        fork: true,
        permissionMode: ClaudePermissionMode.skipPermissions,
      ),
    ]) {
      expect(args, contains('--yolo'));
      expect(args, isNot(contains('--permission-mode')));
      expect(args, isNot(contains('--dangerously-skip-permissions')));
      expect(args, isNot(contains('--sandbox')));
    }
    expect(
      const ClaudeOptions(permissionMode: ClaudePermissionMode.skipPermissions)
          .toArgs(),
      contains('--dangerously-skip-permissions'),
    );
    expect(codexCommandArgs(threadId: 't'), isNot(contains('--yolo')));
    expect(
      codexCommandArgs(
        threadId: 't',
        permissionMode: ClaudePermissionMode.plan,
      ),
      contains('read-only'),
    );
  });

  test('unsupported command fails its parser probe before execution', () async {
    await expectLater(
      validateCodexCommand('codex', ['resume', 't', '--yolo'], (
        exe,
        args,
      ) async {
        expect(args.last, '--help');
        return ProcessResult(1, 2, '', 'unsupported');
      }),
      throwsA(isA<AgentUnavailable>()),
    );
  });

  test('YOLO label follows the provider; read-only policy wins', () {
    expect(
      permissionModeLabel(
        ClaudePermissionMode.skipPermissions,
        provider: 'codex',
      ),
      contains('YOLO'),
    );
    expect(
      permissionModeLabel(ClaudePermissionMode.skipPermissions),
      isNot(contains('YOLO')),
    );
    expect(
      codexPermissionPolicy(
        ClaudePermissionMode.skipPermissions,
        readOnly: true,
      ).sandbox,
      'read-only',
    );
  });

  for (final operation in ['start', 'resume', 'fork']) {
    test('App Server $operation and turns retain YOLO policies', () async {
      final fake = FakeCodex();
      final run =
          await CodexProvider(
            starter: (exe, args, {workingDirectory, environment}) async {
              expect(args, ['app-server']);
              return fake;
            },
          ).start(
            AgentStartOptions(
              workingDirectory: '/w',
              mode: PromptMode.edit,
              resumeId: operation == 'start' ? null : 'parent-thread',
              forkSession: operation == 'fork',
              permissionMode: ClaudePermissionMode.skipPermissions,
            ),
          );
      run.events.listen((_) {});
      addTearDown(run.stop);
      final thread = fake.writtenJson.singleWhere(
        (m) => m['method'] == 'thread/$operation',
      );
      expect(thread['params']['approvalPolicy'], 'never');
      expect(thread['params']['sandbox'], 'danger-full-access');
      await run.send('Execute');
      final turn = fake.writtenJson.last;
      expect(turn['params']['approvalPolicy'], 'never');
      expect(turn['params']['sandboxPolicy'], {'type': 'dangerFullAccess'});
    });
  }

  test('server that does not apply YOLO is rejected and stopped', () async {
    final fake = FakeCodex(rejectYolo: true);
    await expectLater(
      CodexProvider(
        starter: (exe, args, {workingDirectory, environment}) async => fake,
      ).start(
        const AgentStartOptions(
          workingDirectory: '/w',
          mode: PromptMode.edit,
          permissionMode: ClaudePermissionMode.skipPermissions,
        ),
      ),
      throwsA(isA<AgentUnavailable>()),
    );
    expect(fake.signals, contains(ProcessSignal.sigterm));
  });

  for (final mode in [PromptMode.ask, PromptMode.plan, PromptMode.edit]) {
    test('$mode never acquires YOLO implicitly', () async {
      final fake = FakeCodex();
      final run = await CodexProvider(
        starter: (exe, args, {workingDirectory, environment}) async => fake,
      ).start(AgentStartOptions(workingDirectory: '/w', mode: mode));
      run.events.listen((_) {});
      addTearDown(run.stop);
      final thread = fake.writtenJson.last['params'];
      expect(
        thread['sandbox'],
        mode == PromptMode.edit ? 'workspace-write' : 'read-only',
      );
      await run.send('Olá');
      expect(
        fake.writtenJson.last['params']['sandboxPolicy']['type'],
        isNot('dangerFullAccess'),
      );
    });
  }
}
