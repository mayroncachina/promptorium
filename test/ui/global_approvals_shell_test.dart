import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/ui/shell/app_shell.dart';
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
  for (final section in [
    AppSection.tasks,
    AppSection.specs,
    AppSection.review,
    AppSection.code,
    AppSection.agents,
  ]) {
    testWidgets('inside the real shell, the approval shows over '
        '${section.label}', (tester) async {
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
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 's1',
              workspaceId: ws.id,
              worktreePath: '/work/repo',
              branch: 'pr/x',
              model: 'sonnet',
              title: const Value.absentIfNull('SPEC-001 · R1'),
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
          child: MaterialApp(theme: AppTheme.dark(), home: const AppShell()),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await tester.pump(Duration.zero);
      });

      c.read(navigationProvider.notifier).go(section);
      await pumpFor(tester, 3);
      await c.read(sessionManagerProvider.notifier).send('s1', 'continue');
      cli.last.emit(permissionRequestLine);
      await pumpFor(tester);
      expect(
        find.byKey(const ValueKey('global-approvals')),
        findsOneWidget,
        reason: 'on ${section.label}',
      );
      expect(find.byKey(const ValueKey('approve-req-1')), findsOneWidget);
    });
  }
}
