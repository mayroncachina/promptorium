import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';

import '../../core/codex/fake_codex.dart';
import '../../helpers/test_db.dart';
import 'prompt_test_utils.dart';

/// SPEC-096 T2 on the Prompt: a Codex conversation through the real
/// [ConversationManager] and the App Server fake (no paid turn).
void main() {
  late ProviderContainer c;
  late Workspace ws;
  late List<FakeCodex> servers;

  setUp(() async {
    servers = [];
    final db = memoryDatabase();
    c = ProviderContainer(
      overrides: [
        databaseOverride(db),
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
      ],
    );
    c.listen(conversationManagerProvider, (_, _) {});
    ws = await addWorkspace(db, '/work/repo');
    await c.read(appSettingsProvider.notifier).load();
  });

  tearDown(() async {
    await c.read(conversationManagerProvider.notifier).shutdown();
    for (final s in servers) {
      await s.finish();
    }
    c.dispose();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  Map<String, dynamic> lastTurn(FakeCodex f) =>
      f.writtenJson.lastWhere((m) => m['method'] == 'turn/start')['params'];

  void fileApproval(FakeCodex f, Object id) {
    f.emit(
      jsonEncode({
        'method': 'item/started',
        'params': {
          'threadId': 'thread-codex',
          'item': {
            'type': 'fileChange',
            'id': 'fc-$id',
            'status': 'inProgress',
            'changes': [
              {
                'path': '/work/repo/a.txt',
                'kind': {'type': 'update', 'move_path': null},
                'diff': '@@ -1 +1 @@\n-a\n+b\n',
              },
            ],
          },
        },
      }),
    );
    f.emit(
      jsonEncode({
        'id': id,
        'method': 'item/fileChange/requestApproval',
        'params': {
          'threadId': 'thread-codex',
          'turnId': 'turn-1',
          'itemId': 'fc-$id',
        },
      }),
    );
  }

  test(
    'R4–R6: Perguntar runs read-only (the sandbox declines writes); '
    'Editar asks, and "Aprovar nesta conversa" answers acceptForSession',
    () async {
      final m = c.read(conversationManagerProvider.notifier);
      final id = await m.create(
        workspace: ws,
        text: 'Explique o ledger',
        providerId: 'codex',
        mode: PromptMode.ask,
      );
      await settle();
      final f = servers.single;
      expect(lastTurn(f)['sandboxPolicy'], {'type': 'readOnly'});
      expect(lastTurn(f)['approvalPolicy'], 'never');
      // A write asked in Perguntar is declined without a card.
      fileApproval(f, 1);
      await settle();
      expect(c.read(conversationManagerProvider).approvalsOf(id), isEmpty);
      expect(f.writtenJson.lastWhere((x) => x['id'] == 1)['result'], {
        'decision': 'decline',
      });
      f.completeTurn();
      await settle();

      // Editar: the next message restarts the process in the new mode.
      await m.setMode(id, PromptMode.edit);
      await m.send(id, 'Agora edite');
      await settle();
      final g = servers.last;
      expect(
        g.writtenJson.where((x) => x['method'] == 'thread/resume'),
        hasLength(1),
      );
      expect(lastTurn(g)['sandboxPolicy']['type'], 'workspaceWrite');
      fileApproval(g, 2);
      await settle();
      final a = c.read(conversationManagerProvider).approvalsOf(id).single;
      expect(a.request.permissionSuggestions, [codexSessionSuggestion]);
      await m.approve(id, a.requestId, always: true);
      await settle();
      expect(g.writtenJson.lastWhere((x) => x['id'] == 2)['result'], {
        'decision': 'acceptForSession',
      });
    },
  );

  test('R7: a message with the turn running directs it (turn/steer) and '
      'Interromper keeps the process, with the turn interrupted', () async {
    final m = c.read(conversationManagerProvider.notifier);
    final id = await m.create(
      workspace: ws,
      text: 'Comece',
      providerId: 'codex',
      mode: PromptMode.edit,
    );
    await settle();
    final f = servers.single;
    await m.send(id, 'Só o README');
    expect(
      f.writtenJson.lastWhere(
        (x) => x['method'] == 'turn/steer',
      )['params']['expectedTurnId'],
      'turn-1',
    );
    expect(
      f.writtenJson.where((x) => x['method'] == 'turn/start'),
      hasLength(1),
    );
    await m.interrupt(id);
    expect(f.writtenJson.any((x) => x['method'] == 'turn/interrupt'), isTrue);
    expect(m.isAlive(id), isTrue);
    expect(servers, hasLength(1));
  });

  test('R5: "Executar plano" opens a turn in Editar with the plan', () async {
    final m = c.read(conversationManagerProvider.notifier);
    final id = await m.create(
      workspace: ws,
      text: 'Planeje',
      providerId: 'codex',
      mode: PromptMode.plan,
    );
    await settle();
    servers.single.completeTurn();
    await settle();
    await m.executePlan(id, '1. Criar a.txt');
    await settle();
    final conv = await c.read(conversationsRepoProvider).getById(id);
    expect(conv!.mode, 'edit');
    final turn = lastTurn(servers.last);
    expect(turn['sandboxPolicy']['type'], 'workspaceWrite');
    expect(turn['input'].first['text'], planExecutionMessage('1. Criar a.txt'));
    expect(
      ProviderCapabilities.codex.supports(ProviderCapability.planMode),
      isFalse,
    );
  });
}
