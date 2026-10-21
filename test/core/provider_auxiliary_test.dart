import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/readonly_run.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';

import 'codex/fake_codex.dart';
import '../helpers/test_db.dart';
import '../features/sessions/session_test_utils.dart' show settle;

final run = Provider(
  (ref) =>
      (ClaudeOptions options) => runReadOnlyClaude(
        ref,
        cwd: '/work',
        workspaceId: 12,
        options: options,
        prompt: 'Leia e responda',
      ),
);

void main() {
  test('auxiliary starts with project default and keeps its saved provider on resume', () async {
    final servers = <FakeCodex>[];
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        codexProcessStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
        }) async {
          final server = FakeCodex(threadId: 'external-planner');
          servers.add(server);
          return server;
        }),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(12), 'codex');
    var response = c.read(run)(const ClaudeOptions(sessionId: 'planner-local'));
    await settle();
    expect(
      servers.single.writtenJson.any((r) => r['method'] == 'turn/start'),
      isTrue,
    );
    servers.single.completeTurn();
    final result = await response;
    expect(result.json['provider'], 'codex');
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(12), 'claude');
    response = c.read(run)(const ClaudeOptions(resumeId: 'planner-local'));
    await settle();
    final resume = servers.last.writtenJson.singleWhere(
      (r) => r['method'] == 'thread/resume',
    );
    expect(resume['params']['threadId'], 'external-planner');
    expect(resume['params']['sandbox'], 'read-only');
    servers.last.completeTurn();
    expect((await response).isSuccess, isTrue);
  });
}
