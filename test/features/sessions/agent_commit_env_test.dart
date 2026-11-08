import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/git/agent_trailer.dart';
import 'package:promptorium/core/providers/acp_provider.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/core/providers/agent_registry.dart'
    show codexEnabledProvider;
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

/// SPEC-048 R2 / R8: the marking variables reach only the agent sessions,
/// and only with `git: marcar-commits-de-agente` on.
void main() {
  late Directory tmp;
  late String repo;
  late AgentGitHooks hooks;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-agent-env-');
    repo = await createRepo(tmp);
    hooks = AgentGitHooks('${tmp.path}/git-hooks');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> markOn(bool on) => ProjectConfig.save(
    repo,
    ProjectConfig(git: GitConfig(markAgentCommits: on)),
  );

  test('Claude: on → model, origin and core.hooksPath; the worktree '
      'terminal never gets them; off → nothing', () async {
    final cli = FakeCli();
    final c = sessionContainer([
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      agentGitHooksProvider.overrideWithValue(hooks),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    final m = c.read(sessionManagerProvider.notifier);

    await markOn(true);
    final id = await m.create(
      NewSessionRequest(
        workspace: ws,
        title: 'Parser',
        prompt: 'oi',
        model: 'sonnet',
      ),
    );
    final env = cli.envs.single!;
    expect(env['PROMPTORIUM_AGENTE'], 'sonnet');
    expect(env['PROMPTORIUM_ORIGEM'], 'sessão Parser');
    expect(env['PROMPTORIUM_ORIGEM_ARQUIVO'], hooks.originFile(id));
    final n = env['PROMPTORIUM_GIT_CONFIG_BASE']!;
    expect(env['GIT_CONFIG_KEY_$n'], 'core.hooksPath');
    expect(env['GIT_CONFIG_VALUE_$n'], hooks.dir);
    expect(env['PROMPTORIUM_WORKTREE'], isNotNull);
    expect(File('${hooks.dir}/prepare-commit-msg').existsSync(), isTrue);
    expect(m.markedLiveSessions(repo), 1);

    // The Code terminal / session terminal environment of the worktree.
    final row = (await c.read(sessionsRepoProvider).getById(id))!;
    final terminal = c.read(worktreeEnvProvider)[row.worktreePath]!;
    expect(terminal['PROMPTORIUM_WORKTREE'], row.worktreePath);
    expect(
      terminal.keys.where(
        (k) => k.startsWith('GIT_CONFIG') || k.startsWith('PROMPTORIUM_AG'),
      ),
      isEmpty,
    );
    expect(terminal.containsKey('PROMPTORIUM_ORIGEM'), isFalse);

    // Origin of a live session: override (conflict), then the steps.
    await m.setAgentOrigin(id, conflictOrigin('SPEC-043'));
    expect(
      File(hooks.originFile(id)).readAsStringSync().trim(),
      'SPEC-043 conflito',
    );
    await m.setSteps(id, 'R2', 'Parser 2');
    expect(
      File(hooks.originFile(id)).readAsStringSync().trim(),
      'sessão Parser 2',
    );

    // R8: off applies to the next sessions; the live one keeps its marking.
    await markOn(false);
    expect(m.markedLiveSessions(repo), 1);
    await m.create(
      NewSessionRequest(workspace: ws, title: 'Outra', prompt: 'oi'),
    );
    final off = cli.envs.last!;
    expect(off.containsKey('PROMPTORIUM_AGENTE'), isFalse);
    expect(off.containsKey('GIT_CONFIG_COUNT'), isFalse);
    expect(m.markedLiveSessions(repo), 1);

    await m.stop(id);
    await until(() async => m.markedLiveSessions(repo) == 0);
    expect(File(hooks.originFile(id)).existsSync(), isFalse);
  });

  test('Codex: the marking goes in the App Server environment', () async {
    final envs = <Map<String, String>?>[];
    final c = sessionContainer([
      codexEnabledProvider.overrideWithValue(true),
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: FakeCli(),
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      agentGitHooksProvider.overrideWithValue(hooks),
      codexProcessStarterProvider.overrideWithValue((
        exe,
        args, {
        workingDirectory,
        environment,
      }) async {
        envs.add(environment);
        return FakeCodex();
      }),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(ws.id), 'codex');
    final m = c.read(sessionManagerProvider.notifier);
    await markOn(true);
    await m.create(
      NewSessionRequest(workspace: ws, title: 'Livre', prompt: 'oi'),
    );
    await settle();
    expect(envs.single!['PROMPTORIUM_AGENTE'], 'codex');
    expect(envs.single!['PROMPTORIUM_ORIGEM'], 'sessão Livre');
    expect(envs.single!['GIT_CONFIG_COUNT'], isNotNull);

    await markOn(false);
    await m.create(
      NewSessionRequest(workspace: ws, title: 'Sem', prompt: 'oi'),
    );
    await settle();
    expect(envs.last!.containsKey('PROMPTORIUM_AGENTE'), isFalse);
  });

  test('ACP: the environment of the options reaches the process', () async {
    Map<String, String>? got;
    final provider = AcpProvider(
      id: 'acp-x',
      displayName: 'X',
      command: ['x', '--acp'],
      starter: (exe, args, {workingDirectory, environment}) async {
        got = environment;
        throw const ProcessException('x', [], 'sem processo');
      },
    );
    final env = hooks.environment(
      model: 'gemini',
      origin: 'sessão y',
      inherited: const {},
    );
    await expectLater(
      provider.start(
        AgentStartOptions(
          workingDirectory: '/w',
          mode: PromptMode.edit,
          environment: env,
        ),
      ),
      throwsA(isA<AgentUnavailable>()),
    );
    expect(got, env);
  });
}
