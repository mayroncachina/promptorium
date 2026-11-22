import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

/// SPEC-096 R10a (decision 15): without the OS sandbox the Codex never runs
/// in the project root nor without full access; the Prompt refuses it.
void main() {
  test('no sandbox: root and non-YOLO refused (no worktree left behind), '
      'YOLO in a worktree runs, the Prompt refuses', () async {
    final tmp = Directory.systemTemp.createTempSync('codex-nosb-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final root = await createRepo(tmp);
    final servers = <FakeCodex>[];
    final c = sessionContainer([
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: FakeCli(),
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      providerAvailabilityProvider.overrideWith(
        (ref, id) async => ProviderAvailability(
          ProviderStatus.ready,
          'ok',
          sandboxWarning: id == 'codex' ? 'bwrap: uid map' : null,
        ),
      ),
      codexProcessStarterProvider.overrideWithValue((
        exe,
        args, {
        workingDirectory,
        environment,
      }) async {
        final f = FakeCodex();
        servers.add(f);
        return f;
      }),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    await c.read(providerAvailabilityProvider('codex').future);
    final ws = await c.read(workspacesRepoProvider).add(path: root, name: 'r');
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(ws.id), 'codex');
    final m = c.read(sessionManagerProvider.notifier);
    NewSessionRequest req(bool wt, ClaudePermissionMode mode) =>
        NewSessionRequest(
          workspace: ws,
          title: 'S',
          prompt: 'Olá',
          useWorktree: wt,
          permissionMode: mode,
        );
    await expectLater(
      m.create(req(true, ClaudePermissionMode.acceptEdits)),
      throwsA(
        isA<SessionException>().having(
          (e) => e.message,
          'message',
          contains('Sandbox do Codex indisponível'),
        ),
      ),
    );
    await expectLater(
      m.create(req(false, ClaudePermissionMode.acceptEdits)),
      throwsA(isA<SessionException>()),
    );
    expect(servers, isEmpty);
    final wts = await gitIn(root, ['worktree', 'list']);
    expect(wts.trim().split('\n'), hasLength(1));
    final id = await m.create(req(true, ClaudePermissionMode.skipPermissions));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(servers, hasLength(1));
    expect(
      servers.single.writtenJson.lastWhere(
        (x) => x['method'] == 'turn/start',
      )['params']['sandboxPolicy']['type'],
      'dangerFullAccess',
    );
    expect((await c.read(sessionsRepoProvider).getById(id))!.provider, 'codex');
    await expectLater(
      c
          .read(conversationManagerProvider.notifier)
          .create(workspace: ws, text: 'Oi', providerId: 'codex'),
      throwsA(isA<ConversationException>()),
    );
    await m.shutdown();
  });
}
