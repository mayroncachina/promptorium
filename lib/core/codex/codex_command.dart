import '../claude/claude_args.dart';
import '../process/process_runner.dart';
import '../providers/agent_provider.dart';
import '../providers/permission_policy.dart';

/// Interactive commands only. App Server permissions travel over RPC.
List<String> codexCommandArgs({
  String? threadId,
  bool fork = false,
  String? model,
  String? effort,
  ClaudePermissionMode? permissionMode,
}) {
  if (fork && (threadId == null || threadId.isEmpty)) {
    throw const AgentUnavailable('Codex: fork exige a thread de origem.');
  }
  if (permissionMode == ClaudePermissionMode.auto) {
    throw const AgentUnavailable(
      'Codex: aprovação automática Claude não tem equivalente validado.',
    );
  }
  final policy = codexCliPolicy(codexAccessFor(permissionMode));
  return [
    if (threadId != null) ...[fork ? 'fork' : 'resume', threadId],
    if (permissionMode == ClaudePermissionMode.skipPermissions)
      '--yolo'
    else ...[
      '--sandbox',
      policy.sandbox,
      '--ask-for-approval',
      policy.approval,
    ],
    if (model != null && model.isNotEmpty && model != 'inherit') ...[
      '--model',
      model,
    ],
    if (effort != null && effort.isNotEmpty && effort != 'default') ...[
      '-c',
      'model_reasoning_effort="$effort"',
    ],
  ];
}

/// Probe the actual subcommand parser without starting a model execution.
Future<void> validateCodexCommand(
  String executable,
  List<String> args,
  ProcessRunner run,
) async {
  const limit = Duration(seconds: 10);
  final probe = [...args, '--help'];
  // The real runner gets a limit that also ends the process (SPEC-071 R16);
  // an injected one (tests) is only timed.
  final result = identical(run, defaultProcessRunner)
      ? await runKillingOnTimeout(executable, probe, timeout: limit)
      : await run(executable, probe).timeout(limit);
  if (result.exitCode != 0) {
    throw const AgentUnavailable(
      'O Codex instalado não suporta o comando ou modo selecionado. Atualize o CLI antes de executar.',
    );
  }
}
