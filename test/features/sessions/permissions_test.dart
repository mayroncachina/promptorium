import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/core/providers/claude_code_provider.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/mcp/mcp_config.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

void main() {
  test('--tools allow list; Perguntar is read-only with no MCP server', () {
    expect(
      const ClaudeOptions(
        tools: ['Read', 'Grep'],
        includePartialMessages: false,
      ).toArgs(),
      containsAllInOrder(['--tools', 'Read,Grep']),
    );
    final ask = ClaudeCodeProvider.optionsFor(
      const AgentStartOptions(
        workingDirectory: '/w',
        mode: PromptMode.ask,
        mcpAllowedTools: ['mcp__a__b'],
      ),
    );
    expect(ask.tools, ClaudeCodeProvider.readOnlyTools);
    expect(ask.strictMcpConfig, isTrue);
    expect(ask.allowedTools, isEmpty);
    final edit = ClaudeCodeProvider.optionsFor(
      const AgentStartOptions(workingDirectory: '/w', mode: PromptMode.edit),
    );
    expect(edit.tools, isEmpty);
    expect(edit.strictMcpConfig, isFalse);
  });

  test('server arguments: only known flags and package names stay', () {
    expect(
      maskArgs([
        '-y',
        '@modelcontextprotocol/server-github',
        '--token',
        'ghp_abc',
        '--config=/home/u/c.json',
        '--port',
        '8080',
        'sk1234567890abcdefghijklmnop',
        'API_KEY=xyz',
      ]),
      [
        '-y',
        '@modelcontextprotocol/server-github',
        '--token',
        mcpMask,
        '--config=$mcpMask',
        '--port',
        '8080',
        mcpMask,
        mcpMask,
      ],
    );
  });

  group('"Sem perguntar" only in a worktree; live mode switch', () {
    late Directory tmp;
    late String repo;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-perm-');
      repo = await createRepo(tmp);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('refused in the root; a root session resumes in default; the mode '
        'of a live session changes with a control_request', () async {
      final cli = FakeCli();
      final c = sessionContainer(
        sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      final m = c.read(sessionManagerProvider.notifier);
      await expectLater(
        m.create(
          NewSessionRequest(
            workspace: ws,
            title: 'Raiz',
            prompt: 'oi',
            useWorktree: false,
            permissionMode: ClaudePermissionMode.skipPermissions,
          ),
        ),
        throwsA(isA<SessionException>()),
      );
      expect(cli.processes, isEmpty);

      final root = await m.create(
        NewSessionRequest(
          workspace: ws,
          title: 'Raiz',
          prompt: 'oi',
          useWorktree: false,
        ),
      );
      await expectLater(
        m.setPermissionMode(root, ClaudePermissionMode.skipPermissions),
        throwsA(isA<SessionException>()),
      );
      await m.setPermissionMode(root, ClaudePermissionMode.acceptEdits);
      await settle();
      final control = cli.last.writtenJson.last;
      expect(control['type'], 'control_request');
      expect(control['request'], {
        'subtype': 'set_permission_mode',
        'mode': 'acceptEdits',
      });
      expect(
        skipOnlyInWorktree(
          ClaudePermissionMode.skipPermissions,
          worktree: repo,
          root: repo,
        ),
        ClaudePermissionMode.defaultMode,
      );
      expect(
        skipOnlyInWorktree(
          ClaudePermissionMode.skipPermissions,
          worktree: '$repo-wt',
          root: repo,
        ),
        ClaudePermissionMode.skipPermissions,
      );

      // In a worktree it is accepted.
      await m.create(
        NewSessionRequest(
          workspace: ws,
          title: 'Isolada',
          prompt: 'oi',
          permissionMode: ClaudePermissionMode.skipPermissions,
        ),
      );
      expect(cli.args.last, contains('--dangerously-skip-permissions'));
    });
  });
}
