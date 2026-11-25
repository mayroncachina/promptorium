import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/codex/codex_probe.dart';
import 'package:promptorium/core/providers/agent_registry.dart'
    show providerFlowsProvider, ProviderFlows, AppFlow;
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/agents/agent_repository.dart';
import 'package:promptorium/features/agents/codex_agent.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

/// SPEC-106 T2: a Codex session with a `.claude/agents` agent — the
/// payload of `thread/start` and `turn/start`, and the record of the run.
void main() {
  test('R1–R4, R11, R12: instructions, model, effort and sandbox of the '
      'agent; the record survives a later edit of the .md; nothing in '
      '~/.codex', () async {
    final tmp = Directory.systemTemp.createTempSync('codex-agent-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final home = Directory('${tmp.path}/home')..createSync();
    final root = await createRepo(tmp);
    final agents = Directory('$root/.claude/agents')
      ..createSync(recursive: true);
    final md = File('${agents.path}/leitor.md')
      ..writeAsStringSync(
        '---\nname: leitor\ndescription: Lê o código\nmodel: sonnet\n'
        'effort: high\ntools: Read, Grep, Glob\nmaxTurns: 12\n'
        'mcpServers:\n  - github\n---\nLeia antes de responder.\n',
      );
    final servers = <FakeCodex>[];
    final argsSeen = <List<String>>[];
    const models = [
      {
        'id': 'gpt-a',
        'supportedReasoningEfforts': [
          {'reasoningEffort': 'low'},
        ],
        'inputModalities': ['text'],
      },
      {
        'id': 'gpt-b',
        'supportedReasoningEfforts': [
          {'reasoningEffort': 'low'},
          {'reasoningEffort': 'high'},
        ],
        'inputModalities': ['text'],
      },
    ];
    final c = sessionContainer([
      providerFlowsProvider.overrideWithValue(
        ProviderFlows.defaults.copyWith('codex', {...AppFlow.values}),
      ),
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: FakeCli(),
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      agentHomeProvider.overrideWithValue(home.path),
      providerAvailabilityProvider.overrideWith(
        (ref, id) async =>
            const ProviderAvailability(ProviderStatus.ready, 'ok'),
      ),
      codexProcessStarterProvider.overrideWithValue((
        exe,
        args, {
        workingDirectory,
        environment,
      }) async {
        argsSeen.add(args);
        final fake = FakeCodex(models: models);
        servers.add(fake);
        return fake;
      }),
    ]);
    addTearDown(c.dispose);
    final settings = c.read(appSettingsProvider.notifier);
    await settings.load();
    await settings.set(
      codexModelsCacheKey,
      CodexModelsCache(
        version: '0.170.0',
        readAt: DateTime(2026, 11, 22),
        models: const [
          CodexModelInfo('gpt-a', ['low'], ['text']),
          CodexModelInfo('gpt-b', ['low', 'high'], ['text']),
        ],
      ).encode(),
    );
    await settings.set(codexAgentModelKey('sonnet'), 'gpt-b');
    final ws = await c.read(workspacesRepoProvider).add(path: root, name: 'r');
    await settings.set(providerPreferenceKey(ws.id), 'codex');
    final m = c.read(sessionManagerProvider.notifier);
    final id = await m.create(
      NewSessionRequest(
        workspace: ws,
        title: 'Agente',
        prompt: 'Explique o projeto',
        agent: 'leitor',
        model: 'gpt-a',
        permissionMode: ClaudePermissionMode.acceptEdits,
      ),
    );
    await settle();
    final fake = servers.single;
    final thread = fake.writtenJson.lastWhere(
      (x) => x['method'] == 'thread/start',
    )['params'];
    // R1: the agent's body under its header.
    expect(thread['developerInstructions'], startsWith('# Agente `leitor`'));
    expect(
      thread['developerInstructions'],
      contains('Leia antes de responder.'),
    );
    // R2: sonnet → gpt-b through the table; R3: high is in gpt-b's list.
    expect(thread['model'], 'gpt-b');
    final turn = fake.writtenJson.lastWhere(
      (x) => x['method'] == 'turn/start',
    )['params'];
    expect(turn['effort'], 'high');
    // R4: read-only agent in Editar = read-only.
    expect(turn['sandboxPolicy'], {'type': 'readOnly'});
    // R12: no profile, nothing global.
    expect(argsSeen.single, isNot(contains('-p')));
    expect(argsSeen.single, isNot(contains('--profile')));
    expect(Directory('${home.path}/.codex').existsSync(), isFalse);

    // R11: the run record.
    final events = await c.read(sessionsRepoProvider).events(id);
    final run = events
        .map((e) => jsonDecode(e.json) as Map<String, dynamic>)
        .lastWhere((j) => j['type'] == 'promptorium_run');
    expect(run['agent']['name'], 'leitor');
    expect(run['agent']['model'], 'gpt-b');
    expect(run['agent']['effort'], 'high');
    expect(run['agent']['sandbox'], 'read-only');
    expect(run['agent']['ignored'], ['maxTurns', 'mcpServers']);

    // The .md changes later: the session still shows what ran.
    md.writeAsStringSync(
      '---\nname: leitor\ndescription: x\nmodel: opus\n---\nOutro.\n',
    );
    final saved = (await c.read(sessionsRepoProvider).getById(id))!;
    expect(sessionAgentLabel(saved), 'leitor · adaptado');
    expect(sessionAgentRecord(saved)!.model, 'gpt-b');
    expect(saved.agentName, 'leitor');
    fake.completeTurn();
    await settle();
    await m.shutdown();
  });
}
