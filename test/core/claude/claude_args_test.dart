import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';

void main() {
  const base = [
    '-p',
    '--input-format',
    'stream-json',
    '--output-format',
    'stream-json',
    '--verbose',
    '--permission-prompt-tool',
    'stdio',
  ];

  test('minimal options = base flags + partial messages', () {
    expect(const ClaudeOptions().toArgs(), [
      ...base,
      '--include-partial-messages',
    ]);
    expect(const ClaudeOptions(includePartialMessages: false).toArgs(), base);
  });

  test('new session with every option', () {
    const o = ClaudeOptions(
      sessionId: '6f1c1f0e-0000-4000-8000-000000000001',
      model: 'sonnet',
      permissionMode: ClaudePermissionMode.acceptEdits,
      allowedTools: ['Read', 'Bash(git *)'],
      disallowedTools: ['mcp__srv__drop'],
      appendSystemPrompt: 'Responda em português.',
      mcpConfigs: ['/tmp/a.json', '{"mcpServers":{}}'],
      strictMcpConfig: true,
      agentsJson: '{"planner":{"description":"p","prompt":"x"}}',
      maxBudgetUsd: 0.5,
      maxTurns: 12,
    );
    expect(o.toArgs(), [
      ...base,
      '--include-partial-messages',
      '--session-id',
      '6f1c1f0e-0000-4000-8000-000000000001',
      '--model',
      'sonnet',
      '--permission-mode',
      'acceptEdits',
      '--append-system-prompt',
      'Responda em português.',
      '--mcp-config',
      '/tmp/a.json',
      '--mcp-config',
      '{"mcpServers":{}}',
      '--strict-mcp-config',
      '--agents',
      '{"planner":{"description":"p","prompt":"x"}}',
      '--max-budget-usd',
      '0.5',
      '--max-turns',
      '12',
      '--allowedTools',
      'Read',
      'Bash(git *)',
      '--disallowedTools',
      'mcp__srv__drop',
    ]);
  });

  test('resume + fork, default permission mode, integer budget', () {
    const o = ClaudeOptions(
      resumeId: 'abc',
      forkSession: true,
      permissionMode: ClaudePermissionMode.defaultMode,
      maxBudgetUsd: 2,
      includePartialMessages: false,
    );
    expect(o.toArgs(), [
      ...base,
      '--resume',
      'abc',
      '--fork-session',
      '--permission-mode',
      'default',
      '--max-budget-usd',
      '2',
    ]);
    expect(o.copyWith(model: 'haiku').toArgs(), contains('haiku'));
  });

  test('fork with a chosen id and --agent', () {
    const o = ClaudeOptions(
      resumeId: 'abc',
      forkSession: true,
      sessionId: 'new-id',
      agent: 'implementer',
      includePartialMessages: false,
    );
    expect(o.toArgs(), [
      ...base,
      '--session-id',
      'new-id',
      '--resume',
      'abc',
      '--fork-session',
      '--agent',
      'implementer',
    ]);
  });

  test('effort and auto-compact', () {
    const o = ClaudeOptions(
      model: 'sonnet',
      effort: 'medium',
      autocompact: '200k',
      includePartialMessages: false,
    );
    expect(o.toArgs(), [
      ...base,
      '--model',
      'sonnet',
      '--effort',
      'medium',
      '--autocompact',
      '200k',
    ]);
    // Empty = CLI default (no flag).
    expect(
      const ClaudeOptions(effort: '', autocompact: '').toArgs(),
      isNot(anyOf(contains('--effort'), contains('--autocompact'))),
    );
    expect(o.copyWith(effort: 'low').toArgs(), contains('low'));
  });

  test('rejects contradictory options and never bypasses permissions', () {
    expect(
      () => const ClaudeOptions(sessionId: 'a', resumeId: 'b').toArgs(),
      throwsArgumentError,
    );
    expect(
      () => const ClaudeOptions(forkSession: true).toArgs(),
      throwsArgumentError,
    );
    expect(
      () => const ClaudeOptions(maxTurns: 0).toArgs(),
      throwsArgumentError,
    );
    expect(ClaudePermissionMode.fromCli('plan'), ClaudePermissionMode.plan);
    // Only the opt-in mode skips permissions; no other mode or default does.
    expect(const ClaudeOptions().toArgs().join(' '), isNot(contains('danger')));
    for (final m in ClaudePermissionMode.values) {
      if (m == ClaudePermissionMode.skipPermissions) continue;
      final args = ClaudeOptions(permissionMode: m).toArgs().join(' ');
      expect(args, isNot(contains('bypass')));
      expect(args, isNot(contains('dangerously')));
    }
  });

  test(
    'skipPermissions (the user\'s opt-in) is --dangerously-skip-permissions '
    'without --permission-mode, and round-trips through the stored value',
    () {
      final args = const ClaudeOptions(
        permissionMode: ClaudePermissionMode.skipPermissions,
      ).toArgs();
      expect(args, contains('--dangerously-skip-permissions'));
      expect(args, isNot(contains('--permission-mode')));
      expect(args, isNot(contains('bypassPermissions')));
      expect(
        ClaudePermissionMode.fromCli(
          ClaudePermissionMode.skipPermissions.cliValue,
        ),
        ClaudePermissionMode.skipPermissions,
      );
    },
  );
}
