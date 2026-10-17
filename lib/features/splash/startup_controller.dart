import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_cli.dart';
import '../../core/git/git_service.dart';
import '../../core/process/process_runner.dart';
import '../../data/providers.dart';
import '../../ui/shell/footer_stats.dart';
import '../board/autopilot.dart';
import '../prompt/prompt_actions.dart' show seedSavedPrompts;
import '../sessions/session_manager.dart';

/// Values produced by startup steps and consumed by later steps / the app.
class StartupContext {
  StartupContext(this.ref);

  final Ref ref;

  /// Filled by [ClaudeCliStep].
  ClaudeCliInfo? claude;
}

/// Failure of a step, with a user-facing [message].
class StartupException implements Exception {
  const StartupException(this.message, {this.details, this.hint});

  final String message;

  /// Technical detail (e.g. the OS error).
  final String? details;

  /// What the user can do about it.
  final String? hint;

  @override
  String toString() => details == null ? message : '$message — $details';
}

/// One initialization step. Throw [StartupException] to stop the sequence.
///
/// Later phases replace the stubs in [startupStepsProvider]: Fase 11 — MCP.
abstract class StartupStep {
  const StartupStep();

  /// Label shown under the progress bar while the step runs.
  String get label;

  Future<void> run(StartupContext ctx);
}

/// (a) `claude --version`.
class ClaudeCliStep extends StartupStep {
  const ClaudeCliStep();

  @override
  String get label => 'Verificando Claude Code CLI…';

  @override
  Future<void> run(StartupContext ctx) async {
    final footer = ctx.ref.read(footerStatsProvider.notifier);
    try {
      final info = await detectClaudeCli(
        run: ctx.ref.read(processRunnerProvider),
        candidates: ctx.ref.read(claudeExecutableCandidatesProvider),
      );
      ctx.claude = info;
      ctx.ref.read(resolvedClaudeCliProvider.notifier).set(info);
      footer.setCli(CliStatus.connected, version: info.version);
    } on ClaudeCliNotFound catch (e) {
      footer.setCli(CliStatus.notFound);
      throw StartupException(
        e.message,
        details: e.details,
        hint:
            'Instale o Claude Code (curl -fsSL https://claude.ai/install.sh | '
            'bash) e confira se `claude` está no PATH ou em ~/.local/bin.',
      );
    }
  }
}

/// (b) Opens `promptorium.sqlite` (runs migrations) and loads `app_settings`.
class OpenDatabaseStep extends StartupStep {
  const OpenDatabaseStep();

  @override
  String get label => 'Abrindo banco local…';

  @override
  Future<void> run(StartupContext ctx) async {
    try {
      await ctx.ref.read(appDatabaseProvider).ensureOpen();
      await ctx.ref.read(appSettingsProvider.notifier).load();
    } catch (e) {
      throw StartupException(
        'Não foi possível abrir o banco local',
        details: '$e',
        hint:
            'Confira as permissões de ~/.local/share/promptorium/'
            '${AppDatabase.fileName}.sqlite.',
      );
    }
    // First run: default saved prompts of the Prompt screen (best effort).
    try {
      await seedSavedPrompts(
        ctx.ref.read(savedPromptsRepoProvider),
        ctx.ref.read(appSettingsProvider.notifier),
      );
    } catch (e) {
      debugPrint('prompts salvos: falha ao criar os padrões — $e');
    }
  }
}

/// (c) Loads the registered workspaces and validates the active one.
class LoadWorkspacesStep extends StartupStep {
  const LoadWorkspacesStep();

  @override
  String get label => 'Carregando workspaces…';

  @override
  Future<void> run(StartupContext ctx) async {
    final list = await ctx.ref.read(workspacesRepoProvider).getAll();
    final settings = ctx.ref.read(appSettingsProvider.notifier);
    final active = settings.getInt(AppSettingKeys.activeWorkspace);
    if (active != null && list.any((w) => w.id == active)) return;
    // Stale or missing selection: fall back to the first workspace (if any).
    if (list.isEmpty) {
      await settings.remove(AppSettingKeys.activeWorkspace);
    } else {
      await settings.set(AppSettingKeys.activeWorkspace, '${list.first.id}');
    }
  }
}

/// Worktrees of the active workspace (`git worktree list`), loaded by the
/// splash ([ListWorktreesStep]); used by the Code screen (Fase 10).
class WorkspaceWorktrees extends Notifier<List<GitWorktree>> {
  @override
  List<GitWorktree> build() => const [];

  void set(List<GitWorktree> list) => state = list;
}

final workspaceWorktreesProvider =
    NotifierProvider<WorkspaceWorktrees, List<GitWorktree>>(
      WorkspaceWorktrees.new,
    );

/// (c') `git worktree list` of the active workspace. Never fails the startup.
class ListWorktreesStep extends StartupStep {
  const ListWorktreesStep();

  @override
  String get label => 'Listando worktrees…';

  @override
  Future<void> run(StartupContext ctx) async {
    final id = ctx.ref
        .read(appSettingsProvider.notifier)
        .getInt(AppSettingKeys.activeWorkspace);
    if (id == null) return;
    final ws = await ctx.ref.read(workspacesRepoProvider).getById(id);
    if (ws == null) return;
    try {
      final list = await ctx.ref
          .read(gitServiceFactoryProvider)(ws.path)
          .listWorktrees();
      ctx.ref.read(workspaceWorktreesProvider.notifier).set(list);
    } catch (e) {
      debugPrint('worktrees de ${ws.path}: $e');
    }
  }
}

/// (e) Sessions left running when the app closed become `interrupted`
/// (they show "Retomar", which uses `--resume`).
class RestoreSessionsStep extends StartupStep {
  const RestoreSessionsStep();

  @override
  String get label => 'Restaurando sessões…';

  @override
  Future<void> run(StartupContext ctx) async {
    final n = await ctx.ref.read(sessionsRepoProvider).markLiveAsInterrupted();
    if (n > 0) debugPrint('$n sessão(ões) marcada(s) como interrompida(s)');
    // Notices not delivered before closing; the autopilot that was on
    // resumes (not awaited: it may start sessions).
    await ctx.ref.read(sessionManagerProvider.notifier).restoreNotices();
    unawaited(
      ctx.ref.read(autopilotProvider.notifier).restore().catchError((Object e) {
        debugPrint('autopilot não retomado — $e');
      }),
    );
  }
}

/// Placeholder for steps implemented in later phases.
class StubStep extends StartupStep {
  const StubStep(this.label);

  @override
  final String label;

  @override
  Future<void> run(StartupContext ctx) async {}
}

/// Ordered startup steps. Override in tests or replace stubs in later phases.
final startupStepsProvider = Provider<List<StartupStep>>(
  (ref) => const [
    ClaudeCliStep(),
    OpenDatabaseStep(),
    LoadWorkspacesStep(),
    ListWorktreesStep(),
    // Stub on purpose: `claude mcp list` starts every server (slow); the MCP
    // screen runs it lazily per workspace (DT-48).
    StubStep('Conectando servidores MCP…'),
    RestoreSessionsStep(),
  ],
);

enum StartupStatus { idle, running, failed, done }

@immutable
class StartupState {
  const StartupState({
    this.status = StartupStatus.idle,
    this.completed = 0,
    this.total = 0,
    this.label = '',
    this.error,
    this.claude,
  });

  final StartupStatus status;

  /// Steps finished successfully.
  final int completed;
  final int total;

  /// Current step label, "Pronto" when done, error message when failed.
  final String label;
  final StartupException? error;
  final ClaudeCliInfo? claude;

  double get progress => total == 0 ? 0 : completed / total;
}

class StartupController extends Notifier<StartupState> {
  @override
  StartupState build() => const StartupState();

  /// Runs every step in sequence. Calling it again after a failure retries
  /// from the start; calls while running are ignored.
  Future<void> run() async {
    if (state.status == StartupStatus.running) return;
    final steps = ref.read(startupStepsProvider);
    final ctx = StartupContext(ref);
    state = StartupState(
      status: StartupStatus.running,
      total: steps.length,
      label: steps.isEmpty ? '' : steps.first.label,
    );
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      state = StartupState(
        status: StartupStatus.running,
        completed: i,
        total: steps.length,
        label: step.label,
        claude: ctx.claude,
      );
      try {
        await step.run(ctx);
      } on StartupException catch (e) {
        state = StartupState(
          status: StartupStatus.failed,
          completed: i,
          total: steps.length,
          label: e.message,
          error: e,
          claude: ctx.claude,
        );
        return;
      } catch (e) {
        final err = StartupException('Falha em "${step.label}"', details: '$e');
        state = StartupState(
          status: StartupStatus.failed,
          completed: i,
          total: steps.length,
          label: err.message,
          error: err,
          claude: ctx.claude,
        );
        return;
      }
    }
    state = StartupState(
      status: StartupStatus.done,
      completed: steps.length,
      total: steps.length,
      label: 'Pronto',
      claude: ctx.claude,
    );
  }
}

final startupControllerProvider =
    NotifierProvider<StartupController, StartupState>(StartupController.new);
