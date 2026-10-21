import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/features/sessions/new_session_dialog.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

void main() {
  testWidgets('provider selection resets bypass and Codex displays YOLO', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseOverride(memoryDatabase())],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: NewSessionDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-session-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex').last);
    await tester.pumpAndSettle();
    var mode = tester.widget<DropdownButtonFormField<ClaudePermissionMode>>(
      find.byKey(const ValueKey('new-session-mode')),
    );
    expect(mode.initialValue, ClaudePermissionMode.defaultMode);
    await tester.tap(find.byKey(const ValueKey('new-session-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YOLO — sem aprovações e sem sandbox').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('codex --yolo:'), findsOneWidget);
    expect(
      find.textContaining('--dangerously-skip-permissions:'),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('new-session-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude Code').last);
    await tester.pumpAndSettle();
    mode = tester.widget<DropdownButtonFormField<ClaudePermissionMode>>(
      find.byKey(const ValueKey('new-session-mode')),
    );
    expect(mode.initialValue, ClaudePermissionMode.defaultMode);
    expect(find.textContaining('codex --yolo:'), findsNothing);
  });
}
