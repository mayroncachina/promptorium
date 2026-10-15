import '../db/app_database.dart';

/// Keys stored in `app_settings`.
abstract final class AppSettingKeys {
  /// Id of the active workspace (int).
  static const activeWorkspace = 'workspace.active';

  /// `AppSection.name` of the last visible screen.
  static const lastSection = 'ui.lastSection';

  /// Zoom percent of one editor ('specs', 'code').
  static String editorZoom(String editor) => 'editor.zoom.$editor';

  /// Token usage of one day (`yyyy-mm-dd`, JSON; see `UsageTracker`).
  static String usage(String day) => 'usage.$day';

  /// Worktree selected in the Code screen for a workspace (path).
  static String codeWorktree(int workspaceId) => 'code.worktree.$workspaceId';

  /// '1' once the default saved prompts were inserted (Fase 6).
  static const savedPromptsSeeded = 'prompts.seeded';
}

class AppSettingsRepo {
  AppSettingsRepo(this._db);

  final AppDatabase _db;

  $AppSettingsTable get _t => _db.appSettings;

  Future<Map<String, String>> getAll() async => {
    for (final row in await _db.select(_t).get()) row.key: row.value,
  };

  Stream<Map<String, String>> watchAll() => _db
      .select(_t)
      .watch()
      .map((rows) => {for (final r in rows) r.key: r.value});

  Future<String?> get(String key) async => (await (_db.select(
    _t,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watch(String key) => (_db.select(
    _t,
  )..where((s) => s.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<void> set(String key, String value) => _db
      .into(_t)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );

  Future<int> remove(String key) =>
      (_db.delete(_t)..where((s) => s.key.equals(key))).go();

  Future<int?> getInt(String key) async => int.tryParse(await get(key) ?? '');

  Future<void> setInt(String key, int value) => set(key, '$value');
}
