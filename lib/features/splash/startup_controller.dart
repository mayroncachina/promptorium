import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_cli.dart';
import '../../core/process/process_runner.dart';
import '../../ui/shell/footer_stats.dart';

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
/// Later phases replace the stubs in [startupStepsProvider]:
/// Fase 3 — banco + workspaces; Fase 5 — sessões; Fase 11 — MCP.
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
      footer.setCli(CliStatus.connected, version: info.version);
    } on ClaudeCliNotFound catch (e) {
      footer.setCli(CliStatus.notFound);
      throw StartupException(
        e.message,
        details: e.details,
        hint:
            'Instale o Claude Code e confira se `claude` está no PATH '
            'ou em ~/.local/bin.',
      );
    }
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
    StubStep('Abrindo banco local…'), // TODO(Fase 3): drift
    StubStep('Carregando workspaces e worktrees…'), // TODO(Fase 3)
    StubStep('Conectando servidores MCP…'), // TODO(Fase 11): claude mcp list
    StubStep('Restaurando sessões…'), // TODO(Fase 5)
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
