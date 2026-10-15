import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_root.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/ui/shell/app_shell.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/shell/side_bar.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../helpers/test_db.dart';

/// Shell inside a container whose settings were loaded (like the splash does).
Future<ProviderContainer> pumpLoadedShell(
  WidgetTester tester,
  AppDatabase db, {
  Future<String> Function(String)? resolver,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [
      // Not closed by the container: the same database is reopened later.
      appDatabaseProvider.overrideWithValue(db),
      if (resolver != null) gitRootResolverProvider.overrideWithValue(resolver),
    ],
  );
  await c.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: AppTheme.dark(), home: const AppShell()),
    ),
  );
  return c;
}

Future<void> unmount(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  // Drift cancels stream queries with a zero-duration timer.
  await tester.pump(Duration.zero);
}

Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

bool active(WidgetTester tester, AppSection s) =>
    tester.widget<SideBarItem>(find.byKey(ValueKey('nav-${s.name}'))).active;

void main() {
  testWidgets('zoom per editor and last screen persist across restarts', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);

    var c = await pumpLoadedShell(tester, db);
    await ctrl(tester, LogicalKeyboardKey.digit7); // Código
    await ctrl(tester, LogicalKeyboardKey.equal);
    await ctrl(tester, LogicalKeyboardKey.equal);
    await ctrl(tester, LogicalKeyboardKey.digit3); // Specs
    await ctrl(tester, LogicalKeyboardKey.minus);
    expect(find.text('90%'), findsOneWidget);
    await unmount(tester, c);

    final saved = await AppSettingsRepo(db).getAll();
    expect(saved[AppSettingKeys.lastSection], 'specs');
    expect(saved[AppSettingKeys.editorZoom('code')], '120');
    expect(saved[AppSettingKeys.editorZoom('specs')], '90');

    // "Reopen the app".
    c = await pumpLoadedShell(tester, db);
    expect(active(tester, AppSection.specs), isTrue);
    expect(find.text('90%'), findsOneWidget);
    await ctrl(tester, LogicalKeyboardKey.digit7);
    expect(find.text('120%'), findsOneWidget);
    await unmount(tester, c);
  });

  testWidgets('workspace selector lists, adds (validated) and selects', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final asked = <String>[];
    Future<String> resolver(String folder) async {
      asked.add(folder);
      return switch (folder) {
        '/missing' => throw const InvalidWorkspaceFolder('A pasta não existe.'),
        '/plain' => throw const InvalidWorkspaceFolder(
          'A pasta não é um repositório git.',
        ),
        _ => '/home/x/proj', // e.g. a subfolder resolves to the repo root
      };
    }

    final other = await WorkspacesRepoHelper.add(db, '/srv/other');
    final c = await pumpLoadedShell(tester, db, resolver: resolver);
    await tester.pumpAndSettle();
    expect(find.text('Selecionar…'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('title-workspace')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-picker')), findsOneWidget);
    expect(find.text('/srv/other'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workspace-add')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('workspace-path-field'));
    final confirm = find.byKey(const ValueKey('workspace-add-confirm'));

    await tester.enterText(field, '/missing');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('A pasta não existe.'), findsOneWidget);

    await tester.enterText(field, '/plain');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('A pasta não é um repositório git.'), findsOneWidget);

    await tester.enterText(field, '/home/x/proj/lib');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(asked, ['/missing', '/plain', '/home/x/proj/lib']);
    expect(find.byKey(const ValueKey('workspace-picker')), findsNothing);
    expect(workspaceName(tester), 'proj');
    final added = await WorkspacesRepoHelper.byPath(db, '/home/x/proj');
    expect(
      await AppSettingsRepo(db).get(AppSettingKeys.activeWorkspace),
      '${added!.id}',
    );

    // Switch to the other workspace from the list.
    await tester.tap(find.byKey(const ValueKey('title-workspace')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('workspace-item-${other.id}')));
    await tester.pumpAndSettle();
    expect(workspaceName(tester), 'other');
    expect(c.read(activeWorkspaceProvider)?.id, other.id);

    // Remove the active one: selection cleared.
    await tester.tap(find.byKey(const ValueKey('title-workspace')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('workspace-remove-${other.id}')));
    await tester.pumpAndSettle();
    expect(find.text('/srv/other'), findsNothing);
    expect(c.read(activeWorkspaceProvider), isNull);
    await unmount(tester, c);
  });
}

String? workspaceName(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('title-workspace-name')))
    .data;

/// Small helpers to avoid importing the repo in every assertion.
abstract final class WorkspacesRepoHelper {
  static Future<Workspace> add(AppDatabase db, String path) => db
      .into(db.workspaces)
      .insertReturning(
        WorkspacesCompanion.insert(path: path, name: path.split('/').last),
      );

  static Future<Workspace?> byPath(AppDatabase db, String path) => (db.select(
    db.workspaces,
  )..where((w) => w.path.equals(path))).getSingleOrNull();
}
