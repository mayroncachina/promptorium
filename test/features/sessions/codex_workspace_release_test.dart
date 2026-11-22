import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/sessions/codex_workspace_release.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

/// SPEC-096 R15: leaving a workspace ends its idle Codex processes; a turn
/// on its way and the processes of other workspaces keep running.
void main() {
  test(
    'switching workspaces ends the idle Codex processes of the one left',
    () async {
      final tmp = Directory.systemTemp.createTempSync('codex-ws-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final a = await createRepo(tmp, name: 'a');
      final b = await createRepo(tmp, name: 'b');
      final servers = <FakeCodex>[];
      final c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
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
          final f = FakeCodex(threadId: 'thread-${servers.length}');
          servers.add(f);
          return f;
        }),
      ]);
      addTearDown(c.dispose);
      c.listen(codexWorkspaceReleaseProvider, (_, _) {});
      c.listen(conversationManagerProvider, (_, _) {});
      await c.read(appSettingsProvider.notifier).load();
      final wsA = await c.read(workspacesRepoProvider).add(path: a, name: 'a');
      final wsB = await c.read(workspacesRepoProvider).add(path: b, name: 'b');
      await c.read(workspaceActionsProvider).select(wsA.id);
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 60));
      void done(FakeCodex f) => f.emit(
        jsonEncode({
          'method': 'turn/completed',
          'params': {
            'threadId': f.threadId,
            'turn': {'id': 'turn-1', 'status': 'completed'},
          },
        }),
      );
      final m = c.read(sessionManagerProvider.notifier);
      NewSessionRequest req(Workspace ws, String t) => NewSessionRequest(
        workspace: ws,
        provider: 'codex',
        title: t,
        prompt: 'Olá',
        permissionMode: ClaudePermissionMode.acceptEdits,
      );
      final idle = await m.create(req(wsA, 'parada'));
      await settle();
      done(servers.last);
      final busy = await m.create(req(wsA, 'rodando'));
      final other = await m.create(req(wsB, 'outro'));
      await settle();
      done(servers.last);
      final conv = c.read(conversationManagerProvider.notifier);
      final convId = await conv.create(
        workspace: wsA,
        text: 'Oi',
        providerId: 'codex',
      );
      await settle();
      done(servers.last);
      await settle();
      expect(m.isAlive(idle) && m.isAlive(busy) && m.isAlive(other), isTrue);
      expect(conv.isAlive(convId), isTrue);
      await c.read(workspaceActionsProvider).select(wsB.id);
      await settle();
      await settle();
      expect(m.isAlive(idle), isFalse, reason: 'ociosa do workspace deixado');
      expect(m.isAlive(busy), isTrue, reason: 'turno em andamento continua');
      expect(m.isAlive(other), isTrue, reason: 'outro workspace intacto');
      expect(conv.isAlive(convId), isFalse);
      await m.shutdown();
      await conv.shutdown();
    },
  );
}
