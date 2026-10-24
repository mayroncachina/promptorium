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

  /// After the gate, the next step goes to the same session while its
  /// context is below this many thousand tokens (`0` = off; SPEC-017 R4).
  static const continueContextTokens = 'board.continueContextTokens';

  /// Plugins (`nome@marketplace`) and MCP servers (names) turned off in the
  /// app's runs, as JSON lists (SPEC-017 R2).
  static const disabledPlugins = 'agent.disabledPlugins';
  static const disabledMcpServers = 'agent.disabledMcpServers';

  /// Plugins and MCP servers seen in the last `system/init` (JSON).
  static const knownExtensions = 'agent.knownExtensions';

  /// Minutes without activity before an idle session's process is closed
  /// (`0` = never). The session stays and "Retomar" starts it again.
  static const idleMinutes = 'claude.idleMinutes';

  /// `--autocompact` of every run (`auto` or `100k`–`1M`).
  static const autocompact = 'claude.autocompact';

  /// Quadro: "Ocultar concluídas" of a workspace (`1` / `0`; SPEC-019 R3).
  static String boardHideDone(int workspaceId) => 'board.hideDone.$workspaceId';

  /// Worktree selected in the Code screen for a workspace (path).
  static String codeWorktree(int workspaceId) => 'code.worktree.$workspaceId';

  /// ACP agents of the Prompt screen: `nome = comando` per line (F18).
  static const acpAgents = 'acp.agents';

  /// Shortcut layout the user was told about (`AppSection.shortcutsVersion`).
  static const shortcutsVersion = 'ui.shortcutsVersion';

  /// '1' once the default saved prompts were inserted (Fase 6).
  static const savedPromptsSeeded = 'prompts.seeded';

  /// Labels of the last commands run from the palette, newest first, one
  /// per line (UX v2, U2).
  static const paletteRecent = 'ui.paletteRecent';
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
