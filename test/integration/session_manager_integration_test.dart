@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/app_notifier.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/timeline_provider.dart';

import '../core/git/git_test_utils.dart';
import '../helpers/test_db.dart';

/// Real end-to-end session (plano, Fase 5): worktree created, Bash request
/// approved through the queue, result persisted. haiku, budget US$ 0.05.
///   flutter test --run-skipped -t integration test/integration
void main() {
  test('SessionManager with the real CLI', () async {
    final home = Platform.environment['HOME'] ?? '';
    final cli = await detectClaudeCli(
      run: Process.run,
      candidates: ['claude', '$home/.local/bin/claude'],
    );
    final tmp = Directory.systemTemp.createTempSync('promptorium-e2e-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = await createRepo(tmp);

    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        appNotifierProvider.overrideWithValue(const NoopAppNotifier()),
        claudeExecutableProvider.overrideWithValue(cli.executable),
        gitServiceFactoryProvider.overrideWithValue(
          (root) => GitService(root, worktreesBase: '${tmp.path}/wt'),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(sessionManagerProvider, (_, _) {});
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    final m = c.read(sessionManagerProvider.notifier);
    final sessions = c.read(sessionsRepoProvider);

    final id = await m.create(
      NewSessionRequest(
        workspace: ws,
        title: 'E2E',
        prompt:
            'Use the Bash tool to run exactly: echo promptorium-ok > out.txt '
            '. Then reply with the single word DONE.',
        model: 'haiku',
        maxBudgetUsd: 0.05,
      ),
    );
    c.listen(sessionTimelineProvider(id), (_, _) {});
    final wt = (await sessions.getById(id))!.worktreePath;
    expect(Directory(wt).existsSync(), isTrue);

    var approved = 0;
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      for (final a in c.read(sessionManagerProvider).approvals) {
        approved++;
        await m.approve(a.sessionId, a.requestId);
      }
      final s = await sessions.getById(id);
      if (s!.status == SessionStatus.completed ||
          s.status == SessionStatus.failed) {
        break;
      }
    }

    final s = (await sessions.getById(id))!;
    final types = (await sessions.events(id)).map((e) => e.type).toList();
    // ignore: avoid_print
    print(
      'status=${s.status} custo=US\$ ${s.costUsd} aprovações=$approved '
      'tokens=${s.tokensIn}/${s.tokensOut} eventos=${types.length}',
    );
    expect(s.status, SessionStatus.completed);
    expect(approved, greaterThanOrEqualTo(1));
    expect(File('$wt/out.txt').readAsStringSync().trim(), 'promptorium-ok');
    expect(types, contains('control_request'));
    expect(types.last, startsWith('result'));
    expect(s.costUsd, greaterThan(0));
    final items = c.read(sessionTimelineProvider(id)).items;
    expect(items.whereType<ToolItem>().any((t) => t.name == 'Bash'), isTrue);

    await m.stop(id);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect((await sessions.getById(id))!.status, SessionStatus.stopped);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
