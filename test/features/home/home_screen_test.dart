import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/home/home_inbox.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/review/review_service.dart'
    show reviewQueueProvider;
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/ui/shell/app_shell.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/claude/claude_event_test.dart' show permissionRequestLine;
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  test('a plan ready of a conversation has no Aprovar (only the Prompt screen '
      'answers it)', () {
    PendingApproval approval(String id, String tool) => PendingApproval(
      sessionId: 'conv',
      sessionTitle: 'Conversa',
      request:
          ClaudeEvent.parseLine(
                '{"type":"control_request","request_id":"$id","request":'
                '{"subtype":"can_use_tool","tool_name":"$tool",'
                '"input":{"plan":"1. Editar"}}}',
              ).single
              as PermissionRequest,
      receivedAt: DateTime(2026, 10, 17),
    );
    final groups = buildInbox(
      sessionApprovals: const [],
      conversationApprovals: {
        7: [approval('r1', 'ExitPlanMode'), approval('r2', 'Bash')],
      },
      specs: const [],
      stepRows: const [],
      sessions: const [],
      reviewQueue: const [],
      prWatches: const {},
      isAlive: (_) => false,
    );
    final items = groups.single.items;
    final plan = items.firstWhere((i) => i.title.contains('plano pronto'));
    expect(plan.approval, isNull);
    expect(plan.conversationId, 7);
    expect(items.where((i) => i.approval != null), hasLength(1));
  });

  test('buildInbox groups by kind, urgency order, newest first', () {
    final now = DateTime(2026, 10, 17, 10);
    Session session(String id, SessionStatus st, {DateTime? ended}) => Session(
      id: id,
      workspaceId: 1,
      worktreePath: '/w/$id',
      branch: 'pr/$id',
      status: st,
      model: 'sonnet',
      title: 'Sessão $id',
      costUsd: 0,
      tokensIn: 0,
      tokensOut: 0,
      startedAt: now.subtract(const Duration(hours: 2)),
      endedAt: ended,
    );
    final groups = buildInbox(
      sessionApprovals: const [],
      conversationApprovals: const {},
      specs: const [],
      stepRows: const [],
      sessions: [
        session('a', SessionStatus.interrupted, ended: now),
        session(
          'b',
          SessionStatus.failed,
          ended: now.subtract(const Duration(minutes: 5)),
        ),
        session('c', SessionStatus.completed, ended: now),
        session('d', SessionStatus.interrupted, ended: now),
      ],
      reviewQueue: const [],
      prWatches: {
        'c': const PrWatch(
          status: PrStatus(state: 'OPEN', checks: [('analyze', 'FAILURE')]),
        ),
        'a': const PrWatch(
          status: PrStatus(state: 'OPEN', checks: [('test', 'SUCCESS')]),
        ),
      },
      isAlive: (id) => id == 'd', // resumed meanwhile: not interrupted
    );
    expect(groups.map((g) => g.kind), [
      InboxKind.prProblem,
      InboxKind.interrupted,
    ]);
    expect(groups.last.items.map((i) => i.sessionId), ['a', 'b']);
    expect(
      groups.last.items.first.title,
      'Sessão interrompida ao fechar o app',
    );
    expect(groups.last.items.last.title, 'Sessão falhou');
    expect(groups.first.items.single.title, 'CI falhou em analyze');
  });

  testWidgets('Início lists the interrupted session, counts it on the '
      'sidebar and shows a pending approval with its card', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final cli = FakeCli();
    final ws = await db
        .into(db.workspaces)
        .insertReturning(
          WorkspacesCompanion.insert(path: '/work/repo', name: 'repo'),
        );
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AppSettingKeys.activeWorkspace,
            value: '${ws.id}',
          ),
        );
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 's1',
            workspaceId: ws.id,
            worktreePath: '/work/repo',
            branch: 'pr/x',
            model: 'sonnet',
            title: const Value('SPEC-001 · R1'),
            status: const Value(SessionStatus.interrupted),
          ),
        );
    final c = ProviderContainer(
      overrides: [
        ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
        // No git in this test.
        reviewQueueProvider.overrideWith((ref, id) async => const []),
      ],
    );
    await c.read(appSettingsProvider.notifier).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.dark(), home: const AppShell()),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(Duration.zero);
    });
    await pumpFor(tester, 5);

    expect(c.read(navigationProvider), AppSection.home);
    expect(find.byKey(const ValueKey('home-inbox')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-group-interrupted')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-item-interrupted-s1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('nav-badge-home')), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.byKey(const ValueKey('home-autopilot')), findsOneWidget);
    expect(find.text('Autopilot desligado'), findsOneWidget);

    // The session asks for a permission: an approval card on Início and
    // the Sessões counter.
    await c.read(sessionManagerProvider.notifier).send('s1', 'continue');
    cli.last.emit(permissionRequestLine);
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('home-group-approval')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-badge-sessions')), findsOneWidget);
    // Resumed: no longer "interrompida".
    expect(find.byKey(const ValueKey('home-group-interrupted')), findsNothing);
    // The global overlay does not duplicate the card on Início.
    expect(find.byKey(const ValueKey('global-approvals')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-now')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-running-s1')), findsOneWidget);

    // Ctrl+K lists the approval under "Pendentes"; Ctrl+Shift+D denies the
    // oldest one from anywhere (U2).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester, 3);
    expect(
      find.byKey(const ValueKey('palette-group-Pendentes')),
      findsOneWidget,
    );
    expect(find.text('Aprovar'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFor(tester, 3);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('home-group-approval')), findsNothing);
    expect(find.byKey(const ValueKey('nav-badge-sessions')), findsNothing);
    expect(
      cli.last.writtenJson.last['response']['response']['behavior'],
      'deny',
    );
  });
}
