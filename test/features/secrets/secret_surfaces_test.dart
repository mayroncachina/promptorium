import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/secrets/secret_rules.dart';
import 'package:promptorium/core/secrets/secret_scanner.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/home/home_inbox.dart';
import 'package:promptorium/features/secrets/secret_blocks.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

/// SPEC-085 R2, R5, R7: "Segredo encontrado" in Início, Atividades and the
/// end-of-turn check of a session without the hook.
void main() {
  const finding = SecretFinding(
    path: '.env',
    ruleId: 'env-file',
    ruleName: 'arquivo de ambiente',
    kind: SecretRuleKind.file,
    masked: 'A',
    fingerprint: 'f',
  );
  final pending = PendingSecret(
    key: sessionSecretKey('s1'),
    workspaceId: 1,
    sessionId: 's1',
    title: 'Sessão s1',
    findings: const [finding, finding],
    at: DateTime(2026, 11, 17),
  );

  test('the inbox has the group "Segredo encontrado" right after the '
      'approvals', () {
    final groups = buildInbox(
      sessionApprovals: const [],
      conversationApprovals: const {},
      specs: const [],
      stepRows: const [],
      sessions: const [],
      reviewQueue: const [],
      prWatches: const {},
      isAlive: (_) => false,
      secrets: [pending],
    );
    final g = groups.single;
    expect(g.kind, InboxKind.secret);
    expect(g.title, 'Segredo encontrado');
    expect(g.items.single.detail, 'commit bloqueado · 2 achados');
    expect(g.items.single.sessionId, 's1');
  });

  test('Atividades shows it as needing you', () {
    final items = buildActivities(
      [const ActivityWorkspace(id: 1, name: 'loja-api')],
      ActivityLive(secrets: {pending.key: pending}),
      now: DateTime(2026, 11, 17),
    );
    final a = items.single;
    expect(a.id, 'secret:session:s1');
    expect(a.needsYou, isTrue);
    expect(a.status, 'Segredo encontrado');
    expect(a.pose, ActivityPose.wave);
    expect(a.subtitle, 'commit bloqueado · 2 achados');
  });

  test('a session without the hook has the turn\'s commits checked at the '
      'end of the turn (R2)', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-r2-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = await createRepo(tmp);
    SessionManager.secretTurnCheckWithoutHooks = true;
    addTearDown(() => SessionManager.secretTurnCheckWithoutHooks = false);
    final cli = FakeCli();
    // No managed hooks in tests: like a Codex session or no python3.
    final c = sessionContainer(
      sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
      ),
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    final id = await c
        .read(sessionManagerProvider.notifier)
        .create(
          NewSessionRequest(
            workspace: ws,
            title: 'Sem hook',
            prompt: 'oi',
            useWorktree: false,
          ),
        );
    // The agent committed a .env during the turn.
    File('$repo/.env').writeAsStringSync('TOKEN=1\n');
    await gitIn(repo, ['add', '.env']);
    await gitIn(repo, ['commit', '-qm', 'env']);
    cli.last.emit(
      jsonEncode({
        'type': 'result',
        'subtype': 'success',
        'is_error': false,
        'duration_ms': 10,
        'num_turns': 1,
        'result': 'pronto',
        'total_cost_usd': 0,
        'usage': {'input_tokens': 1, 'output_tokens': 1},
        'session_id': id,
      }),
    );
    await until(
      () async =>
          (await c.read(sessionsRepoProvider).events(id))
              .any((e) => e.type == AppEventTypes.secrets),
    );
    final events = await c.read(sessionsRepoProvider).events(id);
    expect(
      events.any(
        (e) => e.json.contains(
          'Vigia de segredos sem hook nesta sessão (sem python3)',
        ),
      ),
      isTrue,
    );
    expect(c.read(secretBlocksProvider)[sessionSecretKey(id)], isNotNull);
  });
}
