import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/core/providers/claude_code_provider.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/mcp/mcp_rules.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

McpToolRule rule(String s, String t, McpRule r) =>
    McpToolRule(server: s, tool: t, rule: r);

List<String> after(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i < 0) return const [];
  final out = <String>[];
  for (var j = i + 1; j < args.length && !args[j].startsWith('--'); j++) {
    out.add(args[j]);
  }
  return out;
}

void main() {
  final rules = [
    rule('youtrack', 'search_issues', McpRule.allow),
    rule('youtrack', 'create_issue', McpRule.ask),
    rule('youtrack', 'delete_issue', McpRule.block),
    rule('claude_ai_Docs', 'read', McpRule.allow),
  ];

  test('Permitido / Bloqueado / Pedir → flags', () {
    final a = mcpRuleArgs(rules);
    expect(a.allowed, [
      'mcp__claude_ai_Docs__read',
      'mcp__youtrack__search_issues',
    ]);
    expect(a.disallowed, ['mcp__youtrack__delete_issue']);
    final ro = mcpRuleArgs(rules, ignoreAllow: true);
    expect(ro.allowed, isEmpty);
    expect(ro.disallowed, ['mcp__youtrack__delete_issue']);
  });

  test('ids de ferramenta MCP', () {
    expect(mcpServerKey('claude.ai Claude Docs'), 'claude_ai_Claude_Docs');
    expect(mcpToolId('my srv', 'x'), 'mcp__my_srv__x');
    expect(splitMcpToolId('mcp__fake-ok__echo'), (
      server: 'fake-ok',
      tool: 'echo',
    ));
    // Known server names with "__" win over the first separator.
    expect(splitMcpToolId('mcp__a__b__c', ['a__b']), (
      server: 'a__b',
      tool: 'c',
    ));
    expect(splitMcpToolId('mcp__a__b__c'), (server: 'a', tool: 'b__c'));
    expect(splitMcpToolId('Read'), isNull);
    expect(splitMcpToolId('mcp__x'), isNull);
  });

  test(
    'conversas: Perguntar/Refinar ignoram Permitido e respeitam Bloqueado',
    () {
      final a = mcpRuleArgs(rules);
      AgentStartOptions o(PromptMode m) => AgentStartOptions(
        workingDirectory: '/ws',
        mode: m,
        mcpAllowedTools: a.allowed,
        mcpDisallowedTools: a.disallowed,
      );
      final ask = ClaudeCodeProvider.optionsFor(o(PromptMode.ask)).toArgs();
      expect(ask, isNot(contains('--allowedTools')));
      expect(after(ask, '--disallowedTools'), [
        ...ClaudeCodeProvider.readOnlyDisallowedTools,
        'mcp__youtrack__delete_issue',
      ]);
      final refine = ClaudeCodeProvider.optionsFor(o(PromptMode.refine))
          .toArgs();
      expect(refine, isNot(contains('--allowedTools')));
      expect(after(refine, '--disallowedTools'), [
        'mcp__youtrack__delete_issue',
      ]);
      for (final m in [PromptMode.edit, PromptMode.plan]) {
        final args = ClaudeCodeProvider.optionsFor(o(m)).toArgs();
        expect(after(args, '--allowedTools'), a.allowed, reason: m.name);
        expect(after(args, '--disallowedTools'), a.disallowed, reason: m.name);
      }
      // No rules: nothing added.
      final none = ClaudeCodeProvider.optionsFor(
        const AgentStartOptions(workingDirectory: '/ws', mode: PromptMode.edit),
      ).toArgs();
      expect(none, isNot(contains('--allowedTools')));
      expect(none, isNot(contains('--disallowedTools')));
    },
  );

  test('sessões: create e resume aplicam as regras do banco', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-mcprules-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ws = await createRepo(tmp);
    final db = memoryDatabase();
    final cli = FakeCli();
    final c = sessionContainer(
      sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final repo = c.read(mcpToolRulesRepoProvider);
    for (final r in rules) {
      await repo.setRule(r.server, r.tool, r.rule);
    }
    final w = await c.read(workspacesRepoProvider).add(path: ws, name: 'ws');
    final manager = c.read(sessionManagerProvider.notifier);
    final id = await manager.create(
      NewSessionRequest(
        workspace: w,
        title: 'MCP',
        prompt: 'oi',
        useWorktree: false,
      ),
    );
    var args = cli.args.single;
    expect(after(args, '--allowedTools'), [
      'mcp__claude_ai_Docs__read',
      'mcp__youtrack__search_issues',
    ]);
    expect(after(args, '--disallowedTools'), ['mcp__youtrack__delete_issue']);

    // Changing a rule applies on the next (re)start.
    await repo.setRule('youtrack', 'search_issues', McpRule.block);
    await cli.last.finish(0);
    await settle();
    await manager.resume(id);
    args = cli.args.last;
    expect(after(args, '--allowedTools'), ['mcp__claude_ai_Docs__read']);
    expect(after(args, '--disallowedTools'), [
      'mcp__youtrack__delete_issue',
      'mcp__youtrack__search_issues',
    ]);
  });
}
