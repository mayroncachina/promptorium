import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/features/board/board_screen.dart';

import '../helpers/test_db.dart';

void main() {
  test('"Ocultar concluídas" is saved in board.hideDone.<workspaceId> of the '
      'active workspace only (SPEC-019 R3, R4)', () async {
    final db = memoryDatabase();
    final a = await db
        .into(db.workspaces)
        .insertReturning(WorkspacesCompanion.insert(path: '/a', name: 'a'));
    final b = await db
        .into(db.workspaces)
        .insertReturning(WorkspacesCompanion.insert(path: '/b', name: 'b'));
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AppSettingKeys.activeWorkspace,
            value: '${a.id}',
          ),
        );
    final c = ProviderContainer(overrides: [databaseOverride(db)]);
    addTearDown(c.dispose);
    final settings = c.read(appSettingsProvider.notifier);
    await settings.load();
    c.listen(workspacesProvider, (_, _) {});
    await c.read(workspacesProvider.future);
    c.listen(boardHideDoneProvider, (_, _) {});
    final repo = AppSettingsRepo(db);

    expect(AppSettingKeys.boardHideDone(a.id), 'board.hideDone.${a.id}');
    expect(c.read(boardHideDoneProvider), isFalse);
    await c.read(boardHideDoneProvider.notifier).toggle();
    expect(c.read(boardHideDoneProvider), isTrue);
    expect(await repo.get('board.hideDone.${a.id}'), '1');
    expect(await repo.get('board.hideDone.${b.id}'), isNull);

    await settings.set(AppSettingKeys.activeWorkspace, '${b.id}');
    expect(c.read(boardHideDoneProvider), isFalse);

    await settings.set(AppSettingKeys.activeWorkspace, '${a.id}');
    expect(c.read(boardHideDoneProvider), isTrue);
    await c.read(boardHideDoneProvider.notifier).toggle();
    expect(await repo.get('board.hideDone.${a.id}'), '0');

    // A restart reads the saved value.
    await c.read(boardHideDoneProvider.notifier).set(true);
    // Same database, closed by the first container.
    final restarted = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(restarted.dispose);
    await restarted.read(appSettingsProvider.notifier).load();
    restarted.listen(workspacesProvider, (_, _) {});
    await restarted.read(workspacesProvider.future);
    expect(restarted.read(boardHideDoneProvider), isTrue);
  });
}
