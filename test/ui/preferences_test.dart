import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_root.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/git/repo_setup.dart';
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
  String? Function(String root)? branchOf,
  Future<String?> Function({String? initialDirectory})? directoryPicker,
  RepoSetup? repoSetup,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [
      // Not closed by the container: the same database is reopened later.
      appDatabaseProvider.overrideWithValue(db),
      if (resolver != null) gitRootResolverProvider.overrideWithValue(resolver),
      if (directoryPicker != null)
        directoryPickerProvider.overrideWithValue(directoryPicker),
      if (repoSetup != null) repoSetupProvider.overrideWithValue(repoSetup),
      // No real git under FakeAsync.
      currentBranchProvider.overrideWith(
        (ref, root) async => branchOf?.call(root),
      ),
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
    final c = await pumpLoadedShell(
      tester,
      db,
      resolver: resolver,
      branchOf: (root) => root == '/srv/other' ? 'feat/login' : null,
    );
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
    expect(find.byKey(const ValueKey('title-workspace-branch')), findsNothing);
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
    expect(
      find.byKey(const ValueKey('title-workspace-branch')),
      findsOneWidget,
    );
    expect(find.text('feat/login'), findsOneWidget);
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

  testWidgets('workspace selector adds a folder chosen in the file picker', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final starts = <String?>[];
    String? answer;
    Future<String?> picker({String? initialDirectory}) async {
      starts.add(initialDirectory);
      return answer;
    }

    final c = await pumpLoadedShell(
      tester,
      db,
      resolver: (folder) async => '/home/x/proj',
      directoryPicker: picker,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('title-workspace')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-add')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('workspace-path-field'));
    final browse = find.byKey(const ValueKey('workspace-browse'));

    // Cancelled: nothing added, the form stays open with the typed path,
    // and the chooser starts at that path when it exists.
    await tester.enterText(field, '/');
    await tester.tap(browse);
    await tester.pumpAndSettle();
    expect(starts, ['/']);
    expect(find.byKey(const ValueKey('workspace-picker')), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, '/');
    expect(await WorkspacesRepoHelper.byPath(db, '/home/x/proj'), isNull);

    // Chosen: added and selected right away.
    answer = '/home/x/proj/lib';
    await tester.tap(browse);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-picker')), findsNothing);
    expect(workspaceName(tester), 'proj');
    expect(await WorkspacesRepoHelper.byPath(db, '/home/x/proj'), isNotNull);
    await unmount(tester, c);
  });

  testWidgets('a non-git folder offers git init, init + remote and clone', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final repos = <String>{'/home/x/repo'};
    Future<String> resolver(String folder) async =>
        repos.contains(folder) ? folder : throw NotAGitRepository(folder);
    final setup = _FakeRepoSetup(repos);

    final c = await pumpLoadedShell(
      tester,
      db,
      resolver: resolver,
      repoSetup: setup,
    );
    await tester.pumpAndSettle();
    Future<void> submit(String path) async {
      await tester.tap(find.byKey(const ValueKey('title-workspace')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workspace-path-field')),
        path,
      );
      await tester.tap(find.byKey(const ValueKey('workspace-add-confirm')));
      await tester.pumpAndSettle();
    }

    final confirm = find.byKey(const ValueKey('workspace-setup-confirm'));
    final url = find.byKey(const ValueKey('workspace-setup-url'));

    // Plain folder: the choices replace the form; "Voltar" returns to it.
    await submit('/home/x/plain');
    expect(find.byKey(const ValueKey('workspace-setup')), findsOneWidget);
    expect(find.text('/home/x/plain'), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-setup')), findsNothing);
    expect(find.byKey(const ValueKey('workspace-path-field')), findsOneWidget);

    // Init + remote: the URL is required; the files box goes to git init.
    await tester.tap(find.byKey(const ValueKey('workspace-add-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-setup-remote')));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Informe a URL do repositório.'), findsOneWidget);
    expect(setup.calls, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey('workspace-setup-commit-files')),
    );
    await tester.enterText(url, 'git@host:org/plain.git');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(setup.calls, [
      'init /home/x/plain files=false remote=git@host:org/plain.git',
    ]);
    expect(find.byKey(const ValueKey('workspace-picker')), findsNothing);
    expect(workspaceName(tester), 'plain');

    // Clone into a non-empty folder: subfolder shown, git errors surfaced.
    await submit('/home/x/busy');
    await tester.tap(find.byKey(const ValueKey('workspace-setup-clone')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-setup-commit-files')),
      findsNothing,
    );
    await tester.enterText(url, 'https://host/org/fail.git');
    await tester.pump();
    expect(find.text('Destino: /home/x/busy/fail'), findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text("fatal: repository 'x' not found"), findsOneWidget);

    await tester.enterText(url, 'https://host/org/app.git');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(setup.calls.last, 'clone /home/x/busy https://host/org/app.git');
    expect(workspaceName(tester), 'app');
    expect(
      await WorkspacesRepoHelper.byPath(db, '/home/x/busy/app'),
      isNotNull,
    );
    await unmount(tester, c);
  });

  testWidgets('"Novo projeto…" in the workspace selector opens the dialog', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final c = await pumpLoadedShell(tester, db);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('title-workspace')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-new-project')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-picker')), findsNothing);
    expect(find.byKey(const ValueKey('new-project-dialog')), findsOneWidget);
    final create = find.byKey(const ValueKey('new-project-create'));
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('new-project-parent')),
      '/srv',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-project-name')),
      'receitas',
    );
    await tester.pump();
    expect(find.text('Será criada: /srv/receitas'), findsOneWidget);
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('new-project-remote')));
    await tester.pump();
    await tester.tap(create);
    await tester.pump();
    expect(find.text('Informe a URL do repositório remoto.'), findsOneWidget);
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

/// Records init / clone and turns the folder into a "repository" for the
/// fake resolver. URLs containing `fail` fail like git does.
class _FakeRepoSetup extends RepoSetup {
  _FakeRepoSetup(this.repos);

  final Set<String> repos;
  final calls = <String>[];

  @override
  bool isEmptyFolder(String folder) => false;

  @override
  Future<void> init(
    String folder, {
    bool commitFiles = true,
    String? remoteUrl,
  }) async {
    calls.add('init $folder files=$commitFiles remote=$remoteUrl');
    repos.add(folder);
  }

  @override
  Future<String> clone(String folder, String url) async {
    if (url.contains('fail')) {
      throw const GitException(
        'git clone falhou',
        stderr: "fatal: repository 'x' not found\n",
      );
    }
    calls.add('clone $folder $url');
    final dest = RepoSetup.cloneDestination(folder, url, folderEmpty: false);
    repos.add(dest);
    return dest;
  }
}
