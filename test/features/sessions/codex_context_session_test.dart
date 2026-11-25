import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/agent_registry.dart'
    show providerFlowsProvider, ProviderFlows, AppFlow;
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/context/context_snapshot.dart';
import 'package:promptorium/features/context/context_tracker.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../../core/codex/codex_replay.dart';
import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

/// SPEC-107 R6, R8 in a real Codex session over the `contexto` transcript
/// of SPEC-093: the Codex threshold preference reaches `thread/start` and
/// the panel; "Compactar agora" sends `thread/compact/start` once and the
/// compaction is not a work turn.
void main() {
  test(
    'Codex threshold sent; Compactar agora by thread/compact/start',
    () async {
      final tmp = Directory.systemTemp.createTempSync('codex-context-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final root = await createRepo(tmp);
      final servers = <FakeCodex>[];
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
        codexProcessStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
        }) async {
          final fake = FakeCodex.replay(
            readCodexTranscript('$codexFixtures/contexto.jsonl'),
            fallback: codexHandshake(),
          );
          servers.add(fake);
          return fake;
        }),
      ]);
      addTearDown(c.dispose);
      final settings = c.read(appSettingsProvider.notifier);
      await settings.load();
      // P1: the Codex has its own threshold; Claude's stays as it was.
      await settings.set(AppSettingKeys.codexAutocompact, '300k');
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: root, name: 'r');
      await settings.set(providerPreferenceKey(ws.id), 'codex');
      final m = c.read(sessionManagerProvider.notifier);
      final id = await m.create(
        NewSessionRequest(
          workspace: ws,
          title: 'Contexto',
          prompt: 'Olá',
          permissionMode: ClaudePermissionMode.skipPermissions,
        ),
      );
      await until(() async {
        final s = await c.read(sessionsRepoProvider).getById(id);
        return s?.status.name == 'completed';
      });
      final f = servers.lastWhere(
        (s) => s.writtenAll.any((x) => x['method'] == 'thread/start'),
      );
      final start = f.writtenAll.firstWhere(
        (x) => x['method'] == 'thread/start',
      );
      expect(start['params']['config'], {
        'model_auto_compact_token_limit': 300000,
      });
      expect(c.read(appSettingsProvider)[AppSettingKeys.autocompact], isNull);
      final runRow = (await c.read(sessionsRepoProvider).events(id))
          .firstWhere((r) => r.type == ContextEventTypes.run);
      expect(jsonDecode(runRow.json)['autocompact'], '300k');

      await m.compactNow(id);
      await until(
        () async => !(c.read(sessionManagerProvider).live[id]?.busy ?? true),
      );
      final compacts = [
        for (final x in f.writtenAll)
          if (x['method'] == 'thread/compact/start') x,
      ];
      expect(compacts, hasLength(1));
      expect(compacts.single['params'].keys, ['threadId']);
      // The compaction rows reopen as one marker, pending a new reading.
      final rows = await c.read(sessionsRepoProvider).events(id);
      final t = Timeline();
      for (final r in rows) {
        t.applyStored(r.json);
      }
      final s = t.context.snapshot;
      expect(s.threshold, 300000);
      expect(s.thresholdSource, ContextThresholdSource.sent);
      expect(s.lastCompaction!.trigger, 'manual');
      expect(s.lastCompaction!.postTokens, 15663);
      expect(s.pendingAfterCompaction, isTrue);
      // A compaction is not a work turn.
      expect(s.turn, 1);
      expect(
        rows
            .where((r) => r.type == 'promptorium_note')
            .map((r) => jsonDecode(r.json)['text']),
        contains('Compactação pedida pelo app (thread/compact/start).'),
      );
      await m.shutdown();
    },
  );
}
