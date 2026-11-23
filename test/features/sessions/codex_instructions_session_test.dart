import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/agent_registry.dart'
    show providerFlowsProvider, ProviderFlows, AppFlow;
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/core/providers/workspace_assets.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

/// SPEC-104 R1/R2 end to end on a temporary repository: a Codex session in
/// a project with only a CLAUDE.md loads it (the proof is in the run event)
/// and nothing is created or changed in the repository.
void main() {
  test('R1: a Codex session in a CLAUDE.md-only project records the '
      'instructionSources and leaves git status clean', () async {
    final tmp = Directory.systemTemp.createTempSync('codex-instr-session-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final root = await createRepo(tmp);
    File('$root/CLAUDE.md').writeAsStringSync('# regras\n- nunca use print\n');
    Directory('$root/.claude/skills/gerar-release').createSync(recursive: true);
    File('$root/.claude/skills/gerar-release/SKILL.md')
        .writeAsStringSync('---\nname: gerar-release\ndescription: x\n---\n');
    await gitIn(root, ['add', '.']);
    await gitIn(root, ['commit', '-q', '-m', 'regras']);
    final servers = <FakeCodex>[];
    final argsSeen = <List<String>>[];
    final db = memoryDatabase();
    final c = sessionContainer([
      providerFlowsProvider.overrideWithValue(
        ProviderFlows.defaults.copyWith('codex', {...AppFlow.values}),
      ),
      ...sessionOverrides(
        db: db,
        cli: FakeCli(),
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
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
        final fake = FakeCodex()
          ..instructionSources = ['$workingDirectory/CLAUDE.md'];
        servers.add(fake);
        return fake;
      }),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: root, name: 'r');
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(ws.id), 'codex');
    final m = c.read(sessionManagerProvider.notifier);
    final id = await m.create(
      NewSessionRequest(workspace: ws, title: 'Corrigir cache', prompt: 'Olá'),
    );
    await settle();
    expect(
      argsSeen.single,
      containsAllInOrder([
        '-c',
        'project_doc_fallback_filenames=["CLAUDE.md"]',
      ]),
    );
    final roots =
        servers.single.writtenJson.singleWhere(
              (x) => x['method'] == 'skills/extraRoots/set',
            )['params']['extraRoots']
            as List;
    expect(roots.first, endsWith('/.claude/skills'));
    final events = await c.read(sessionsRepoProvider).events(id);
    final run = events.singleWhere((e) => e.type == 'promptorium_run');
    expect(jsonDecode(run.json)['instructionSources'], ['CLAUDE.md']);
    // The proof the Instruções tab reads (R2).
    final proof = await c.read(instructionsProofProvider(ws.id).future);
    expect(proof, isNotNull);
    expect(proof!.loaded('CLAUDE.md'), isTrue);
    expect(proof.where, 'sessão “Corrigir cache”');
    servers.single.completeTurn();
    await settle();
    await m.shutdown();
    // Nothing created or changed in the repository nor in the worktree.
    expect(await gitIn(root, ['status', '--porcelain']), isEmpty);
    final session = (await c.read(sessionsRepoProvider).getById(id))!;
    expect(
      await gitIn(session.worktreePath, ['status', '--porcelain']),
      isEmpty,
    );
    expect(File('$root/AGENTS.md').existsSync(), isFalse);
  });
}
