import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/ui/shell/global_approvals.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../core/claude/claude_event_test.dart' show permissionRequestLine;
import '../features/sessions/session_test_utils.dart';
import '../helpers/test_db.dart';

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('a pending approval is answerable from another screen and '
      'hidden where it is already shown', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
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
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 's1',
            workspaceId: ws.id,
            worktreePath: '/work/repo',
            branch: 'pr/x',
            model: 'sonnet',
            title: const Value.absentIfNull('Shell da IDE'),
            status: const Value(SessionStatus.interrupted),
          ),
        );
    final c = ProviderContainer(
      overrides: sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
    );
    await c.read(appSettingsProvider.notifier).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: GlobalApprovals()),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(Duration.zero);
    });

    // The user is on Specs, not on the session.
    c.read(navigationProvider.notifier).go(AppSection.specs);
    await c.read(sessionManagerProvider.notifier).send('s1', 'continue');
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('global-approvals')), findsNothing);

    cli.last.emit(permissionRequestLine);
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('global-approvals')), findsOneWidget);
    expect(find.text('Shell da IDE · quer executar'), findsOneWidget);

    // On Sessões with that session selected, the session panel shows it.
    c.read(navigationProvider.notifier).go(AppSection.sessions);
    c.read(selectedSessionProvider.notifier).select('s1');
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('global-approvals')), findsNothing);

    // Another session selected: back in the corner; answer it from there.
    c.read(selectedSessionProvider.notifier).select('outra');
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('approve-req-1')));
    await pumpFor(tester);
    final resp = cli.last.writtenJson.last;
    expect(resp['type'], 'control_response');
    expect(resp['response']['request_id'], 'req-1');
    expect(resp['response']['response']['behavior'], 'allow');
    expect(find.byKey(const ValueKey('global-approvals')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
