import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/git/git_root.dart';
import '../core/git/repo_setup.dart';
import '../core/process/process_runner.dart';
import 'db/app_database.dart';
import 'repos/agent_settings_repo.dart';
import 'repos/app_settings_repo.dart';
import 'repos/conversations_repo.dart';
import 'repos/mcp_tool_rules_repo.dart';
import 'repos/project_plans_repo.dart';
import 'repos/saved_prompts_repo.dart';
import 'repos/sessions_repo.dart';
import 'repos/spec_steps_repo.dart';
import 'repos/specs_repo.dart';
import 'repos/tasks_repo.dart';
import 'repos/workspaces_repo.dart';

export 'db/app_database.dart';
export 'repos/app_settings_repo.dart' show AppSettingKeys;

/// The app database. Tests override it with
/// `AppDatabase(NativeDatabase.memory())`.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

// --- repositories -----------------------------------------------------------

final workspacesRepoProvider = Provider(
  (ref) => WorkspacesRepo(ref.watch(appDatabaseProvider)),
);
final specsRepoProvider = Provider(
  (ref) => SpecsRepo(ref.watch(appDatabaseProvider)),
);
final specStepsRepoProvider = Provider(
  (ref) => SpecStepsRepo(ref.watch(appDatabaseProvider)),
);
final tasksRepoProvider = Provider(
  (ref) => TasksRepo(ref.watch(appDatabaseProvider)),
);
final sessionsRepoProvider = Provider(
  (ref) => SessionsRepo(ref.watch(appDatabaseProvider)),
);
final conversationsRepoProvider = Provider(
  (ref) => ConversationsRepo(ref.watch(appDatabaseProvider)),
);
final savedPromptsRepoProvider = Provider(
  (ref) => SavedPromptsRepo(ref.watch(appDatabaseProvider)),
);
final agentSettingsRepoProvider = Provider(
  (ref) => AgentSettingsRepo(ref.watch(appDatabaseProvider)),
);
final mcpToolRulesRepoProvider = Provider(
  (ref) => McpToolRulesRepo(ref.watch(appDatabaseProvider)),
);
final appSettingsRepoProvider = Provider(
  (ref) => AppSettingsRepo(ref.watch(appDatabaseProvider)),
);
final projectPlansRepoProvider = Provider(
  (ref) => ProjectPlansRepo(ref.watch(appDatabaseProvider)),
);

// --- lists used by the screens ----------------------------------------------

final workspacesProvider = StreamProvider<List<Workspace>>(
  (ref) => ref.watch(workspacesRepoProvider).watchAll(),
);

final specsProvider = StreamProvider.family<List<Spec>, int>(
  (ref, workspaceId) =>
      ref.watch(specsRepoProvider).watchByWorkspace(workspaceId),
);

final tasksProvider = StreamProvider.family<List<Task>, int>(
  (ref, workspaceId) =>
      ref.watch(tasksRepoProvider).watchByWorkspace(workspaceId),
);

/// Planning draft of a workspace (null = never planned).
final projectPlanProvider = StreamProvider.family<ProjectPlan?, int>(
  (ref, workspaceId) => ref.watch(projectPlansRepoProvider).watch(workspaceId),
);

final sessionsProvider = StreamProvider.family<List<Session>, int>(
  (ref, workspaceId) =>
      ref.watch(sessionsRepoProvider).watchByWorkspace(workspaceId),
);

final sessionEventsProvider = StreamProvider.family<List<SessionEvent>, String>(
  (ref, sessionId) => ref.watch(sessionsRepoProvider).watchEvents(sessionId),
);

final conversationsProvider = StreamProvider.family<List<Conversation>, int>(
  (ref, workspaceId) =>
      ref.watch(conversationsRepoProvider).watchByWorkspace(workspaceId),
);

/// Auto-dispose: only the Prompt screen listens (no drift stream left open
/// after leaving it).
final savedPromptsProvider = StreamProvider.autoDispose<List<SavedPrompt>>(
  (ref) => ref.watch(savedPromptsRepoProvider).watchAll(),
);

final agentSettingsProvider = StreamProvider<List<AgentSetting>>(
  (ref) => ref.watch(agentSettingsRepoProvider).watchAll(),
);

final mcpToolRulesProvider = StreamProvider.family<List<McpToolRule>, String>(
  (ref, server) => ref.watch(mcpToolRulesRepoProvider).watchForServer(server),
);

// --- preferences ------------------------------------------------------------

/// In-memory copy of `app_settings`, loaded by the splash ([load]) so that
/// notifiers can read preferences synchronously in `build`. Writes go to the
/// database in the background.
class AppSettingsController extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  AppSettingsRepo get _repo => ref.read(appSettingsRepoProvider);

  Future<void> load() async => state = await _repo.getAll();

  String? get(String key) => state[key];

  int? getInt(String key) => int.tryParse(state[key] ?? '');

  Future<void> set(String key, String value) {
    if (state[key] == value) return Future.value();
    state = {...state, key: value};
    return _persist(() => _repo.set(key, value));
  }

  Future<void> remove(String key) {
    if (!state.containsKey(key)) return Future.value();
    state = {...state}..remove(key);
    return _persist(() => _repo.remove(key));
  }

  Future<void> _persist(Future<Object?> Function() write) async {
    try {
      await write();
    } catch (e, st) {
      debugPrint('app_settings: falha ao gravar — $e\n$st');
    }
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, Map<String, String>>(
      AppSettingsController.new,
    );

// --- active workspace -------------------------------------------------------

/// Workspace stored in `app_settings` (null = none selected / not loaded).
final activeWorkspaceProvider = Provider<Workspace?>((ref) {
  final id = int.tryParse(
    ref.watch(appSettingsProvider)[AppSettingKeys.activeWorkspace] ?? '',
  );
  if (id == null) return null;
  final list = ref.watch(workspacesProvider).value ?? const <Workspace>[];
  for (final w in list) {
    if (w.id == id) return w;
  }
  return null;
});

/// Validates a folder and returns its git root (see [resolveGitRoot]).
/// Overridden in widget tests, where real file system futures do not run.
final gitRootResolverProvider = Provider<Future<String> Function(String)>(
  (ref) =>
      (folder) => resolveGitRoot(folder, run: ref.read(processRunnerProvider)),
);

/// Opens the native folder chooser; returns null when cancelled.
/// Overridden in widget tests, where platform channels do not answer.
final directoryPickerProvider =
    Provider<Future<String?> Function({String? initialDirectory})>(
      (ref) =>
          ({initialDirectory}) => getDirectoryPath(
            initialDirectory: initialDirectory,
            confirmButtonText: 'Selecionar',
          ),
    );

/// Opens the native file chooser (several files); empty when cancelled.
/// Overridden in widget tests, where platform channels do not answer.
final filePickerProvider =
    Provider<Future<List<String>> Function({String? initialDirectory})>(
      (ref) =>
          ({initialDirectory}) async => [
            for (final f in await openFiles(
              initialDirectory: initialDirectory,
              confirmButtonText: 'Anexar',
            ))
              f.path,
          ],
    );

/// Select / add / remove workspaces (title bar selector).
class WorkspaceActions {
  WorkspaceActions(this._ref);

  final Ref _ref;

  Future<void> select(int id) => _ref
      .read(appSettingsProvider.notifier)
      .set(AppSettingKeys.activeWorkspace, '$id');

  /// Validates [folder] (exists + git repository), registers its repository
  /// root and makes it active. Throws [InvalidWorkspaceFolder].
  Future<Workspace> addFolder(String folder) async {
    final root = await _ref.read(gitRootResolverProvider)(folder);
    final ws = await _ref
        .read(workspacesRepoProvider)
        .add(path: root, name: folderName(root));
    await select(ws.id);
    return ws;
  }

  /// `git init` in [folder] (see [RepoSetup.init]), then adds it.
  Future<Workspace> initFolder(
    String folder, {
    bool commitFiles = true,
    String? remoteUrl,
  }) async {
    await _ref
        .read(repoSetupProvider)
        .init(folder, commitFiles: commitFiles, remoteUrl: remoteUrl);
    return addFolder(folder);
  }

  /// `git clone` [url] into [folder] (see [RepoSetup.clone]), then adds the
  /// clone.
  Future<Workspace> cloneInto(String folder, String url) async =>
      addFolder(await _ref.read(repoSetupProvider).clone(folder, url));

  /// Unregisters the workspace (data rows cascade; files are untouched).
  Future<void> remove(int id) async {
    final settings = _ref.read(appSettingsProvider.notifier);
    if (settings.getInt(AppSettingKeys.activeWorkspace) == id) {
      await settings.remove(AppSettingKeys.activeWorkspace);
    }
    await _ref.read(workspacesRepoProvider).delete(id);
  }
}

final workspaceActionsProvider = Provider(WorkspaceActions.new);
