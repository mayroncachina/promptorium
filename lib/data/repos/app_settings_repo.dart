import '../db/app_database.dart';

/// Keys stored in `app_settings`.
abstract final class AppSettingKeys {
  /// Id of the active workspace (int).
  static const activeWorkspace = 'workspace.active';

  /// `AppSection.name` of the last visible screen.
  static const lastSection = 'ui.lastSection';

  /// Zoom percent of one editor ('specs', 'code').
  static String editorZoom(String editor) => 'editor.zoom.$editor';

  /// Last `rate_limit_event` (raw JSON): the footer shows the plan usage
  /// right after a restart (see `RateLimitController`).
  static const lastRateLimit = 'usage.rateLimit';

  /// Default model of a `RunKind` (`session`, `conversation`, `planner`).
  static String runModel(String kind) => 'claude.model.$kind';

  /// Default `--effort` of a `RunKind` (`default` = CLI default).
  static String runEffort(String kind) => 'claude.effort.$kind';

  /// Quadro: a spec with at most this many steps runs in one session.
  static const singleSessionSteps = 'board.singleSessionSteps';

  /// Minutes without activity before an idle session's process is closed
  /// (`0` = never). The session stays and "Retomar" starts it again.
  static const idleMinutes = 'claude.idleMinutes';

  /// `--autocompact` of every run (`auto` or `100k`–`1M`).
  static const autocompact = 'claude.autocompact';

  /// Worktree selected in the Code screen for a workspace (path).
  static String codeWorktree(int workspaceId) => 'code.worktree.$workspaceId';

  /// ACP agents of the Prompt screen: `nome = comando` per line (F18).
  static const acpAgents = 'acp.agents';

  /// Shortcut layout the user was told about (`AppSection.shortcutsVersion`).
  static const shortcutsVersion = 'ui.shortcutsVersion';

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
