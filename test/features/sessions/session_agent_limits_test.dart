import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/agents/agent_repository.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

/// DT-23: the agent's budget (`agent_settings`) and `maxTurns` (frontmatter)
/// become `--max-budget-usd` / `--max-turns`, also on `--resume`.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('promptorium-limits-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  List<String> valueOf(List<String> args, String flag) {
    final i = args.indexOf(flag);
    return i < 0 ? const [] : [args[i + 1]];
  }

  test('create / resume with an agent pass its budget and max turns', () async {
    final home = '${tmp.path}/home';
    final ws = await createRepo(tmp);
    File('$home/.claude/agents/implementer.md')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '---\nname: implementer\ndescription: global\nmaxTurns: 3\n---\n',
      );
    // The project agent overrides the global one (its settings win).
    File('$ws/.claude/agents/implementer.md')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '---\nname: implementer\ndescription: projeto\nmaxTurns: 9\n---\n',
      );
    final db = memoryDatabase();
    final cli = FakeCli();
    final c = sessionContainer([
      ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
      agentHomeProvider.overrideWithValue(home),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final settings = c.read(agentSettingsRepoProvider);
    await settings.upsert(
      const AgentSetting(
        agentName: 'implementer',
        scope: AgentScope.global,
        budgetUsd: 9.99,
        mcpServers: [],
      ),
    );
    await settings.upsert(
      const AgentSetting(
        agentName: 'implementer',
        scope: AgentScope.project,
        budgetUsd: 2.5,
        mcpServers: [],
      ),
    );
    final w = await c.read(workspacesRepoProvider).add(path: ws, name: 'ws');
    final manager = c.read(sessionManagerProvider.notifier);
    final id = await manager.create(
      NewSessionRequest(
        workspace: w,
        title: 'Com agente',
        prompt: 'oi',
        agent: 'implementer',
        useWorktree: false,
      ),
    );
    var args = cli.args.single;
    expect(valueOf(args, '--agent'), ['implementer']);
    expect(valueOf(args, '--max-budget-usd'), ['2.5']);
    expect(valueOf(args, '--max-turns'), ['9']);

    // Resume (process gone) reapplies the limits.
    await cli.last.finish(0);
    await settle();
    expect(manager.isAlive(id), isFalse);
    await manager.resume(id);
    args = cli.args.last;
    expect(args, containsAllInOrder(['--resume', id]));
    expect(valueOf(args, '--max-budget-usd'), ['2.5']);
    expect(valueOf(args, '--max-turns'), ['9']);

    // An explicit budget of the request wins; no agent ⇒ no limits.
    await manager.create(
      NewSessionRequest(
        workspace: w,
        title: 'Explícito',
        prompt: 'oi',
        agent: 'implementer',
        maxBudgetUsd: 1,
        useWorktree: false,
      ),
    );
    expect(valueOf(cli.args.last, '--max-budget-usd'), ['1']);
    await manager.create(
      NewSessionRequest(
        workspace: w,
        title: 'Sem agente',
        prompt: 'oi',
        useWorktree: false,
      ),
    );
    expect(cli.args.last, isNot(contains('--max-budget-usd')));
    expect(cli.args.last, isNot(contains('--max-turns')));
  });
}
