import '../db/app_database.dart';

/// Keys stored in `app_settings`.
abstract final class AppSettingKeys {
  /// Glass effects of the Vidro theme, `false` to turn them off (SPEC-049 R6).
  static const glassEffects = 'aparencia.vidro';

  /// Shake of the cards that need the person, `false` to turn it off
  /// (SPEC-054 R7).
  static const attentionShake = 'aparencia.tremor';

  /// Right panel of the Prompt collapsed in its strip (`1` / `0`;
  /// SPEC-056 R8).
  static const promptPanelCollapsed = 'prompt.painelRecolhido';

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

  /// "Escrever o Plano em seguida" of "Nova spec" (`0` = off; SPEC-039 R7).
  static const specPlanNext = 'specs.planNext';

  /// Quadro: a spec with at most this many steps runs in one session.
  static const singleSessionSteps = 'board.singleSessionSteps';

  /// After the gate, the next step goes to the same session while its
  /// context is below this many thousand tokens (`0` = off; SPEC-017 R4).
  static const continueContextTokens = 'board.continueContextTokens';

  /// Plugins (`nome@marketplace`) and MCP servers (names) turned off in the
  /// app's runs, as JSON lists (SPEC-017 R2).
  static const disabledPlugins = 'agent.disabledPlugins';
  static const disabledMcpServers = 'agent.disabledMcpServers';

  /// Promptorium MCP server of the app's runs, `0` to turn it off
  /// (SPEC-052 R10; on by default, P2).
  static const mcpServer = 'mcp.servidor';

  /// Specs one run may create through the server (SPEC-052 R9; default 10).
  static const mcpCreationLimit = 'mcp.limiteCriacoes';

  /// Plugins and MCP servers seen in the last `system/init` (JSON).
  static const knownExtensions = 'agent.knownExtensions';

  /// Minutes without activity before an idle session's process is closed
  /// (`0` = never). The session stays and "Retomar" starts it again.
  static const idleMinutes = 'claude.idleMinutes';

  /// `--autocompact` of every run (`auto` or `100k`–`1M`).
  static const autocompact = 'claude.autocompact';

  /// Quadro: "Ocultar concluídas" of a workspace (`1` / `0`; SPEC-019 R3).
  static String boardHideDone(int workspaceId) => 'board.hideDone.$workspaceId';

  /// Quadro: the Bandeja is open (`1` / `0`; SPEC-068 R7).
  static String boardTrayOpen(int workspaceId) => 'board.trayOpen.$workspaceId';

  /// Sprint chosen on the Quadro (SPEC-042 R2).
  static String boardSprint(int workspaceId) => 'board.sprint.$workspaceId';

  /// Quadro: the folder of the Foco view is collapsed (`1` / `0`; SPEC-036 R5).
  static String boardFolderCollapsed(int workspaceId) =>
      'board.folderCollapsed.$workspaceId';

  /// Worktree selected in the Code screen for a workspace (path).
  static String codeWorktree(int workspaceId) => 'code.worktree.$workspaceId';

  /// ACP agents of the Prompt screen: `nome = comando` per line (F18).
  static const acpAgents = 'acp.agents';

  /// Shortcut layout the user was told about (`AppSection.shortcutsVersion`).
  static const shortcutsVersion = 'ui.shortcutsVersion';

  /// Rule of a `StepKind` of the Orquestrador: model alias and `--effort`
  /// (SPEC-035 R2, R6).
  static String orchestratorModel(String kind) => 'orchestrator.model.$kind';
  static String orchestratorEffort(String kind) => 'orchestrator.effort.$kind';

  /// "Abrir Executar em Automático" (`1` / `0`).
  static const orchestratorAutoByDefault = 'orchestrator.autoByDefault';

  /// "Escaladas por etapa" (`0`–`2`).
  static const orchestratorEscalations = 'orchestrator.escalations';

  /// "Perguntar antes de escalar para Opus" (`1` / `0`).
  static const orchestratorAskBeforeOpus = 'orchestrator.askBeforeOpus';

  /// "Classificar as etapas com": model alias (`haiku` / `sonnet`).
  static const orchestratorClassifierModel = 'orchestrator.classifierModel';

  /// Model and effort of the line "Revisão" of the plan of a spec run in
  /// Automático (`sonnet|medium`, SPEC-035 R4, R8).
  static String orchestratorReviewOf(int specId) =>
      'orchestrator.review.$specId';

  /// "Ignorar" of the suggestion of the Histórico for a `StepKind`
  /// (SPEC-035 R18): ISO time of the newest escalation seen then.
  static String orchestratorHistoryIgnored(String kind) =>
      'orchestrator.historyIgnored.$kind';

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
