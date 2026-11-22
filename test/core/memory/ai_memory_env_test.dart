import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/core/memory/ai_memory_env.dart';
import 'package:promptorium/core/memory/ai_memory_state.dart';
import 'package:promptorium/core/providers/structured_run.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../features/sessions/session_test_utils.dart';
import '../../helpers/test_db.dart';
import '../git/git_test_utils.dart';

/// SPEC-098 T2 (R2, R6): the variables each kind of execution gets, and
/// nothing at all without the ai-memory binary.
void main() {
  test('R6: auxiliaries get CAPTURE_OWNER + AUTO_HANDOFF=off, step sessions '
      'only AUTO_HANDOFF=off, free sessions none', () {
    expect(aiMemoryEnvironmentFor(AiMemoryRunKind.auxiliary, installed: true), {
      'AI_MEMORY_CAPTURE_OWNER': 'promptorium',
      'AI_MEMORY_AUTO_HANDOFF': 'off',
    });
    expect(
      aiMemoryEnvironmentFor(AiMemoryRunKind.stepSession, installed: true),
      {'AI_MEMORY_AUTO_HANDOFF': 'off'},
    );
    expect(
      aiMemoryEnvironmentFor(AiMemoryRunKind.free, installed: true),
      isEmpty,
    );
    for (final k in AiMemoryRunKind.values) {
      expect(aiMemoryEnvironmentFor(k, installed: false), isEmpty);
    }
    expect(withAiMemory(null, const {}), isNull);
    expect(withAiMemory({'A': '1'}, const {}), {'A': '1'});
    expect(withAiMemory(null, const {'B': '2'}), {'B': '2'});
  });

  group('runs', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('ai-memory-env-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<Map<String, String>?> auxiliaryEnv(String? executable) async {
      final cli = FakeCli();
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          claudeProcessStarterProvider.overrideWithValue(cli.start),
          runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
          aiMemoryExecutableProvider.overrideWith((ref) async => executable),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final run = Provider(
        (ref) =>
            () => runStructured(
              ref,
              StructuredIntent(
                cwd: tmp.path,
                sessionId: 'aux-1',
                prompt: 'Leia e responda',
              ),
            ),
      );
      final done = c.read(run)();
      await until(() async => cli.args.isNotEmpty);
      cli.last.emit(
        jsonEncode({
          'type': 'result',
          'subtype': 'success',
          'result': 'ok',
          'session_id': 'aux-1',
          'total_cost_usd': 0,
        }),
      );
      await done;
      return cli.envs.single;
    }

    test('R6: an auxiliary (runStructured) runs outside the memory', () async {
      final env = await auxiliaryEnv('/opt/x/ai-memory');
      expect(env, {
        'AI_MEMORY_CAPTURE_OWNER': 'promptorium',
        'AI_MEMORY_AUTO_HANDOFF': 'off',
      });
    });

    test('R2: without the binary the auxiliary gets the same environment '
        'as before (none)', () async {
      expect(await auxiliaryEnv(null), isNull);
    });

    Future<(Map<String, String>?, Map<String, String>?)> sessionEnvs(
      String? executable,
    ) async {
      final repo = await createRepo(tmp);
      final cli = FakeCli();
      final c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
        aiMemoryExecutableProvider.overrideWith((ref) async => executable),
      ]);
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      final spec = await c
          .read(specsRepoProvider)
          .insert(
            workspaceId: ws.id,
            code: 'SPEC-001',
            title: 'Parser',
            path: 'docs/specs/SPEC-001.md',
          );
      final m = c.read(sessionManagerProvider.notifier);
      await m.create(
        NewSessionRequest(workspace: ws, title: 'Livre', prompt: 'oi'),
      );
      await m.create(
        NewSessionRequest(
          workspace: ws,
          title: 'Etapa',
          prompt: 'oi',
          specId: spec.id,
          steps: 'T1',
        ),
      );
      return (cli.envs[0], cli.envs[1]);
    }

    test('R6: a free session keeps ai-memory\'s behavior; a step session '
        'of the Quadro leaves no automatic handoff (P3)', () async {
      final (free, step) = await sessionEnvs('/opt/x/ai-memory');
      expect(free?.keys.where((k) => k.startsWith('AI_MEMORY')), isEmpty);
      expect(step?['AI_MEMORY_AUTO_HANDOFF'], 'off');
      expect(step?.containsKey('AI_MEMORY_CAPTURE_OWNER'), isFalse);
    });

    test('R2: without the binary sessions get exactly the environment of '
        'before', () async {
      final (free, step) = await sessionEnvs(null);
      expect(free?.keys.where((k) => k.startsWith('AI_MEMORY')) ?? [], isEmpty);
      expect(step?.keys.where((k) => k.startsWith('AI_MEMORY')) ?? [], isEmpty);
    });
  });
}
