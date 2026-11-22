import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/agent_registry.dart';
import '../providers/structured_run.dart';
import 'claude_args.dart';
import 'claude_cli.dart';
import 'claude_event.dart';
import 'run_extensions.dart';
import 'claude_process.dart';
import 'run_prefs.dart';

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

/// The Claude adapter of [runStructured] (SPEC-100 R1, R2): the options of
/// one non-interactive `claude -p` turn for [intent].
///
/// Read-only as before: the read tools only (`--tools`), the read-only
/// `--disallowedTools`, no MCP server (F12) and permission requests denied.
/// Runs given their own [ClaudeStructuredExtras.tools] and `allowedTools`
/// (the prototype screens, SPEC-022 R2) may write where those rules allow.
///
/// Model, effort and auto-compact not set in the extras come from the
/// kind's defaults of Configurações ([RunPrefs]); the profile "rápido" is
/// Haiku · low (R4).
Future<ClaudeOptions> claudeStructuredOptions(
  Ref ref,
  StructuredIntent intent,
) async {
  final prefs = ref.read(runPrefsProvider);
  final e = intent.claude;
  final fast = intent.profile == StructuredProfile.fast;
  return ClaudeOptions(
    sessionId: intent.sessionId,
    resumeId: intent.resumeId,
    forkSession: intent.forkSession,
    permissionMode: ClaudePermissionMode.defaultMode,
    tools: e.tools.isEmpty ? ClaudeCodeProvider.readOnlyTools : e.tools,
    allowedTools: e.allowedTools,
    disallowedTools:
        e.disallowedTools ?? ClaudeCodeProvider.readOnlyDisallowedTools,
    appendSystemPrompt: intent.instructions,
    jsonSchema: intent.schema == null ? null : jsonEncode(intent.schema),
    maxBudgetUsd: e.maxBudgetUsd,
    maxTurns: e.maxTurns,
    agent: e.agent,
    includePartialMessages: false,
    strictMcpConfig: true,
    settingsFile: e.settingsFile ?? await runSettingsFile(ref),
    model: e.model ?? (fast ? 'haiku' : prefs.modelArg(intent.kind)),
    effort: e.effort ?? (fast ? 'low' : effortArg(prefs.effort(intent.kind))),
    autocompact: prefs.autocompact,
  );
}

/// Starts the Claude Code round of [intent].
Future<StructuredStart> startClaudeStructured(
  Ref ref,
  StructuredIntent intent,
) async {
  final options = await claudeStructuredOptions(ref, intent);
  final run = ClaudeRun(
    await ClaudeProcess.start(
      options,
      workingDirectory: intent.cwd,
      executable: ref.read(claudeExecutableProvider),
      starter: ref.read(claudeProcessStarterProvider),
    ),
  );
  return (run: run as AgentRun, model: options.model);
}
