import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/code/code_model.dart';
import 'package:promptorium/features/code/code_screen.dart';
import 'package:promptorium/features/code/worktree_terminal.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/ui/shell/editor_zoom.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import '../specs/specs_screen_test.dart' show settleIo;

void main() {
  late Directory tmp;
  late String repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-code-ui-');
    repo = await createRepo(tmp);
    Directory('$repo/lib').createSync();
    File('$repo/lib/main.dart').writeAsStringSync('void main() {}\n');
    File('$repo/.gitignore').writeAsStringSync('ignorado.txt\n');
    File('$repo/ignorado.txt').writeAsStringSync('x');
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'lib']);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(ProviderContainer, Workspace)> pump(
    WidgetTester tester, {
    bool withSession = false,
  }) async {
    // Shell: sidebar 56px, title bar + footer ≈ 72px of a 1100×700 window.
    tester.view.physicalSize = const Size(1044, 628);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final c = ProviderContainer(
      overrides: [
        ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
        codeTerminalAutoStartProvider.overrideWithValue(false),
        currentBranchProvider.overrideWith((ref, root) async => 'main'),
        gitWorktreesProvider.overrideWith(
          (ref, root) async => [GitWorktree(path: repo, branch: 'main')],
        ),
      ],
    );
    c.listen(sessionManagerProvider, (_, _) {});
    late Workspace ws;
    await tester.runAsync(() async {
      ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'repo');
      await c
          .read(appSettingsRepoProvider)
          .set(AppSettingKeys.activeWorkspace, '${ws.id}');
      await c.read(appSettingsProvider.notifier).load();
      if (withSession) {
        await c
            .read(sessionManagerProvider.notifier)
            .create(
              NewSessionRequest(
                workspace: ws,
                title: 'Shell da IDE',
                prompt: 'Trabalhe.',
                useWorktree: false,
              ),
            );
        await settle();
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: CodeScreen()),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(Duration.zero);
    });
    await settleIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('code-tree-lib')).evaluate().isNotEmpty,
    );
    return (c, ws);
  }

  testWidgets('fits 1100×700; tree respects .gitignore; open, zoom "code" '
      'independent of "specs"', (tester) async {
    final (c, _) = await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('code-tree-a.txt')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-tree-.gitignore')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-tree-ignorado.txt')), findsNothing);
    expect(find.text('Nenhum arquivo aberto'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('code-tree-lib')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('code-tree-lib/main.dart')));
    await settleIo(
      tester,
      until: () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(
      find.byKey(const ValueKey('code-tab-lib/main.dart')),
      findsOneWidget,
    );
    final status = tester.widget<Text>(
      find.byKey(const ValueKey('code-status-position')),
    );
    expect(status.data, 'Ln 1, Col 1  ·  Dart  ·  UTF-8  ·  LF');
    expect(tester.takeException(), isNull);

    double fontSize() =>
        tester.widget<CodeEditor>(find.byType(CodeEditor)).style!.fontSize!;
    expect(fontSize(), 13);
    c.read(editorZoomProvider('code').notifier).zoomIn();
    await tester.pump();
    expect(fontSize(), closeTo(14.3, 0.001));
    expect(c.read(editorZoomProvider('specs')), 100);
    c.read(editorZoomProvider('specs').notifier).zoomOut();
    await tester.pump();
    expect(fontSize(), closeTo(14.3, 0.001));
    expect(c.read(editorZoomProvider('code')), 110);

    // Ctrl+P: "Ir para arquivo".
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byKey(const ValueKey('code-goto-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('code-goto-field')),
      'atx',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('code-goto-a.txt')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('code-goto-a.txt')));
    await settleIo(
      tester,
      until: () =>
          find.byKey(const ValueKey('code-tab-a.txt')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('code-tab-a.txt')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('banner when an active session works in the worktree', (
    tester,
  ) async {
    await pump(tester, withSession: true);
    expect(find.byKey(const ValueKey('code-agent-banner')), findsOneWidget);
    expect(find.textContaining('Shell da IDE'), findsWidgets);
    expect(find.byKey(const ValueKey('code-pause-agent')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
