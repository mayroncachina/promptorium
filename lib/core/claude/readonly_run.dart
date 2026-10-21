import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/agent_registry.dart';
import '../providers/provider_preferences.dart';
import '../../data/providers.dart';
import 'claude_args.dart';
import 'claude_cli.dart';
import 'claude_event.dart';
import 'claude_process.dart';
import 'run_prefs.dart';
import 'usage_tracker.dart';

/// Limit of one planner run.
const plannerTimeout = Duration(minutes: 5);

class PlannerException implements Exception {
  const PlannerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Structured answer of a `--json-schema` run. Real format (CLI 2.1.300,
/// plano Fase 8): `structured_output` plus the same JSON as a string in
/// `result`; `structured_output` is preferred, `result` is the fallback.
/// Throws [PlannerException] when the run failed.
Object? structuredOutput(Result r) {
  if (!r.isSuccess) {
    throw PlannerException(
      'O planner terminou com erro (${r.subtype.isEmpty ? 'erro' : r.subtype}).',
    );
  }
  final data = r.json['structured_output'];
  if (data != null || r.result == null) return data;
  try {
    return jsonDecode(r.result!);
  } on FormatException {
    return null;
  }
}

/// Runs one non-interactive turn of `claude -p` in [cwd] and returns its
/// `result`: permission requests are denied (read-only runs), rate limits go
/// to the usage tracker and the process is stopped afterwards. Throws
/// [PlannerException] when the CLI cannot start, exits early or times out.
///
/// Model, effort and auto-compact not set in [options] come from the planner
/// defaults of Configurações ([RunPrefs]).
Future<Result> runReadOnlyClaude(
  Ref ref, {
  required String cwd,
  required ClaudeOptions options,
  required String prompt,
  Duration timeout = plannerTimeout,
  int? workspaceId,
  String? providerId,
}) async {
  final prefs = ref.read(runPrefsProvider);
  final sourceId = options.resumeId;
  final settings = ref.read(appSettingsProvider.notifier);
  final chosen =
      providerId ??
      (sourceId == null
          ? ref.read<String>(
              defaultAgentProvider(
                workspaceId ?? ref.read(activeWorkspaceProvider)?.id,
              ),
            )
          : settings.get('agent.run.$sourceId.provider') ?? 'claude');
  final AgentRun process;
  if (options.sessionId != null) {
    await settings.set('agent.run.${options.sessionId}.provider', chosen);
  }
  try {
    if (chosen != 'claude') {
      process = await ref
          .read(agentProviderByIdProvider(chosen))
          .start(
            AgentStartOptions(
              workingDirectory: cwd,
              mode: PromptMode.ask,
              model:
                  options.model ?? providerModel(ref, chosen, RunKind.planner),
              effort:
                  options.effort ??
                  effortArg(providerEffort(ref, chosen, RunKind.planner)),
              resumeId: sourceId == null
                  ? null
                  : settings.get('agent.run.$sourceId.externalId') ?? sourceId,
              forkSession: options.forkSession,
              appendSystemPrompt: options.appendSystemPrompt,
              jsonSchema: options.jsonSchema,
              maxBudgetUsd: options.maxBudgetUsd,
              maxTurns: options.maxTurns,
              agent: options.agent,
              mcpConfigs: options.mcpConfigs,
              strictMcpConfig: true,
              mcpDisallowedTools: options.disallowedTools
                  .where(
                    (t) =>
                        !ClaudeCodeProvider.readOnlyDisallowedTools.contains(t),
                  )
                  .toList(),
            ),
          );
    } else {
      process = ClaudeRun(
        await ClaudeProcess.start(
          options.copyWith(
            // Read-only allow list, no MCP server (F12).
            tools: options.tools.isEmpty
                ? ClaudeCodeProvider.readOnlyTools
                : options.tools,
            strictMcpConfig: true,
            model: options.model ?? prefs.modelArg(RunKind.planner),
            effort: options.effort ?? effortArg(prefs.effort(RunKind.planner)),
            autocompact: options.autocompact ?? prefs.autocompact,
          ),
          workingDirectory: cwd,
          executable: ref.read(claudeExecutableProvider),
          starter: ref.read(claudeProcessStarterProvider),
        ),
      );
    }
  } catch (e) {
    throw PlannerException('Falha ao iniciar $chosen: $e');
  }
  final done = Completer<Result>();
  final logSub = process.logs.listen(
    (l) => debugPrint('planner: $l'),
    onError: (_) {},
  );
  final sub = process.events.listen(
    (e) {
      switch (e) {
        case SystemInit():
          final key = options.sessionId ?? options.resumeId;
          if (key != null && e.sessionId != null) {
            unawaited(settings.set('agent.run.$key.externalId', e.sessionId!));
          }
        case PermissionRequest():
          // Non-interactive and read-only: nothing to approve.
          process.deny(
            e.requestId,
            'O planner do Promptorium é somente leitura.',
          );
        case Result():
          if (!done.isCompleted) done.complete(e);
        case RateLimit():
          if (chosen == 'claude') ref.read(usageTrackerProvider).handle(e);
        default:
          break;
      }
    },
    onDone: () {
      if (!done.isCompleted) {
        done.completeError(
          PlannerException('O provedor $chosen encerrou antes de responder.'),
        );
      }
    },
  );
  try {
    await process.send(prompt);
    return await done.future.timeout(
      timeout,
      onTimeout: () => throw PlannerException(
        'O planner não respondeu em ${timeout.inMinutes} minutos.',
      ),
    );
  } finally {
    await process.stop(timeout: const Duration(seconds: 2));
    await sub.cancel();
    await logSub.cancel();
  }
}
