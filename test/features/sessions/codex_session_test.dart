import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../core/codex/fake_codex.dart';
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'session_test_utils.dart';

void main() {
  test(
    'Codex YOLO persists, resumes its external thread, forks and leaves YOLO',
    () async {
      final tmp = Directory.systemTemp.createTempSync('codex-session-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final root = await createRepo(tmp);
      final servers = <FakeCodex>[];
      final claude = FakeCli();
      final c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: claude,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
        codexProcessStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
        }) async {
          final fake = FakeCodex(threadId: 'external-${servers.length}');
          servers.add(fake);
          expect(args, ['app-server']);
          return fake;
        }),
      ]);
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: root, name: 'r');
      await c
          .read(appSettingsProvider.notifier)
          .set(providerPreferenceKey(ws.id), 'codex');
      var m = c.read(sessionManagerProvider.notifier);
      final id = await m.create(
        NewSessionRequest(
          workspace: ws,
          title: 'YOLO',
          prompt: 'Olá',
          permissionMode: ClaudePermissionMode.skipPermissions,
        ),
      );
      await settle();
      var saved = (await c.read(sessionsRepoProvider).getById(id))!;
      expect(saved.provider, 'codex');
      expect(saved.externalId, 'external-0');
      expect(saved.permissionMode, 'bypassPermissions');
      expect(
        jsonDecode(saved.runConfig!)['permissionMode'],
        'bypassPermissions',
      );
      expect(saved.effort, 'default');
      await expectLater(
        m.setPermissionMode(id, ClaudePermissionMode.plan),
        throwsA(isA<SessionException>()),
      );
      expect(
        (await c.read(sessionsRepoProvider).getById(id))!.permissionMode,
        'bypassPermissions',
      );
      servers.last.completeTurn();
      await settle();
      await c
          .read(appSettingsProvider.notifier)
          .set(providerPreferenceKey(ws.id), 'claude');
      await m.release(id);
      c.invalidate(sessionManagerProvider);
      await settle();
      m = c.read(sessionManagerProvider.notifier);
      await m.resume(id);
      expect(
        servers.last.writtenJson.singleWhere(
          (x) => x['method'] == 'thread/resume',
        )['params']['threadId'],
        'external-0',
      );
      expect(
        servers.last.writtenJson.last['params']['sandbox'],
        'danger-full-access',
      );
      await settle();
      final child = await m.fork(id, prompt: 'Continue');
      await settle();
      final fork = (await c.read(sessionsRepoProvider).getById(child))!;
      expect(fork.provider, 'codex');
      expect(fork.permissionMode, 'bypassPermissions');
      expect(fork.externalId, 'external-2');
      expect(
        servers.last.writtenJson.singleWhere(
          (x) => x['method'] == 'thread/fork',
        )['params']['threadId'],
        'external-1',
      );
      await m.setPermissionMode(id, ClaudePermissionMode.plan);
      await m.resume(id);
      expect(servers.last.writtenJson.last['params']['sandbox'], 'read-only');
      expect(claude.processes, isEmpty);
      await m.shutdown();
    },
  );

  test('YOLO is refused in workspace root before starting Codex', () async {
    final tmp = Directory.systemTemp.createTempSync('codex-root-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final root = await createRepo(tmp);
    final c = sessionContainer(
      sessionOverrides(
        db: memoryDatabase(),
        cli: FakeCli(),
        notifier: FakeNotifier(),
      ),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: root, name: 'r');
    await expectLater(
      c
          .read(sessionManagerProvider.notifier)
          .create(
            NewSessionRequest(
              workspace: ws,
              title: 'YOLO',
              prompt: 'Olá',
              provider: 'codex',
              useWorktree: false,
              permissionMode: ClaudePermissionMode.skipPermissions,
            ),
          ),
      throwsA(isA<SessionException>()),
    );
  });
  test('spec starts with project default and its next run retains the saved provider', () async {
    final tmp = Directory.systemTemp.createTempSync('codex-spec-default-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final root = await createRepo(tmp);
    Directory('$root/specs').createSync();
    File('$root/specs/SPEC-001-test.md').writeAsStringSync(
      '---\nid: SPEC-001\nstatus: aprovada\n---\n\n# Teste\n\n## Requisitos\n\n- R1 · Ler\n',
    );
    final claude = FakeCli();
    final servers = <FakeCodex>[];
    final c = sessionContainer([
      ...sessionOverrides(
        db: memoryDatabase(),
        cli: claude,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
      codexProcessStarterProvider.overrideWithValue((
        exe,
        args, {
        workingDirectory,
        environment,
      }) async {
        final server = FakeCodex();
        servers.add(server);
        return server;
      }),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: root, name: 'r');
    await c.read(specServiceProvider).sync(ws);
    final spec = (await c
        .read(specsRepoProvider)
        .getByCode(ws.id, 'SPEC-001'))!;
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(ws.id), 'codex');
    final first = await c.read(specRunnerProvider).runNext(spec.id);
    expect(
      (await c.read(sessionsRepoProvider).getById(first))!.provider,
      'codex',
    );
    await c.read(sessionManagerProvider.notifier).stop(first);
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(ws.id), 'claude');
    final next = await c.read(specRunnerProvider).runNext(spec.id);
    expect(
      (await c.read(sessionsRepoProvider).getById(next))!.provider,
      'codex',
    );
    expect(claude.processes, isEmpty);
    await c.read(sessionManagerProvider.notifier).shutdown();
  });
}
