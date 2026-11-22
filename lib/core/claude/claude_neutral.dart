/// The one converter of Claude Code's stream-json into the neutral events
/// (SPEC-095 R8, P1). Called by the parse (`ToolUseBlock.fileChanges`,
/// `ToolUseBlock.command`, `AssistantMessage.contextUsage`,
/// `RateLimit.quota`), live and when a stored session reopens. What Claude
/// stored never changes: these events are derived, never written.
library;

import '../providers/agent_event.dart';

/// Claude tools that write files.
const claudeFileTools = {'Edit', 'Write', 'MultiEdit', 'NotebookEdit'};

/// Claude's shell tool.
const claudeCommandTool = 'Bash';

final _files = Expando<List<FileChangeEvent>>('claude file changes');
final _commands = Expando<List<CommandEvent?>>('claude command');

String? _str(Object? v) => v is String ? v : null;

/// The file change of an `Edit` / `MultiEdit` / `Write` / `NotebookEdit`
/// call (one file per call). Status [FileChangeStatus.proposed]: the result
/// decides the rest.
List<FileChangeEvent> claudeFileChanges(ToolUseBlock b) =>
    _files[b] ??= _fileChanges(b);

List<FileChangeEvent> _fileChanges(ToolUseBlock b) {
  if (!claudeFileTools.contains(b.name)) return const [];
  final i = b.input;
  final path = _str(i['file_path']) ?? _str(i['notebook_path']);
  if (path == null || path.isEmpty) return const [];
  final json = switch (b.name) {
    'Write' => FileChangeEvent.toJson(
      provider: 'claude',
      toolUseId: b.id,
      path: path,
      kind: FileChangeKind.add,
      status: FileChangeStatus.proposed,
      after: _str(i['content']),
    ),
    'MultiEdit' => FileChangeEvent.toJson(
      provider: 'claude',
      toolUseId: b.id,
      path: path,
      kind: FileChangeKind.update,
      status: FileChangeStatus.proposed,
      edits: [
        if (i['edits'] case final List edits)
          for (final e in edits)
            if (e is Map)
              {
                'old': _str(e['old_string']) ?? '',
                'new': _str(e['new_string']) ?? '',
                'all': e['replace_all'] == true,
              },
      ],
    ),
    'NotebookEdit' => FileChangeEvent.toJson(
      provider: 'claude',
      toolUseId: b.id,
      path: path,
      kind: FileChangeKind.update,
      status: FileChangeStatus.proposed,
      after: _str(i['new_source']),
    ),
    _ => FileChangeEvent.toJson(
      provider: 'claude',
      toolUseId: b.id,
      path: path,
      kind: FileChangeKind.update,
      status: FileChangeStatus.proposed,
      before: _str(i['old_string']),
      after: _str(i['new_string']),
    ),
  };
  return [AgentEvent.fromJson(json) as FileChangeEvent];
}

/// The command of a `Bash` call, running (null for other tools).
CommandEvent? claudeCommand(ToolUseBlock b) =>
    (_commands[b] ??= [_command(b)]).first;

CommandEvent? _command(ToolUseBlock b) {
  if (b.name != claudeCommandTool) return null;
  final cmd = _str(b.input['command']);
  if (cmd == null) return null;
  return AgentEvent.fromJson(
    CommandEvent.toJson(
      provider: 'claude',
      toolUseId: b.id,
      command: cmd,
      status: CommandStatus.running,
    ),
  ) as CommandEvent;
}

/// The context of a top-level call: `input + cache write + cache read` of
/// its `usage` (SPEC-087 R1). Null without usage or with zero tokens.
ContextUsageEvent? claudeContextUsage(AssistantMessage m) {
  final msg = m.json['message'];
  if (msg is! Map || msg['usage'] is! Map<String, dynamic>) return null;
  final u = Usage.fromJson(msg['usage'] as Map<String, dynamic>);
  final tokens =
      u.inputTokens + u.cacheCreationInputTokens + u.cacheReadInputTokens;
  if (tokens <= 0) return null;
  return AgentEvent.fromJson(
    ContextUsageEvent.toJson(
      provider: 'claude',
      tokens: tokens,
      input: u.inputTokens,
      cacheWrite: u.cacheCreationInputTokens,
      cacheRead: u.cacheReadInputTokens,
      model: m.model,
      messageId: m.messageId.isEmpty ? null : m.messageId,
      source: ContextUsageEvent.claudeUsage,
    ),
  ) as ContextUsageEvent;
}

/// `rate_limit_event` as a [QuotaEvent]: the 5-hour and weekly windows
/// (utilization 0–1 → percent).
QuotaEvent claudeQuota(RateLimit r) {
  double? pct(double? v) => v == null ? null : v * 100;
  return AgentEvent.fromJson(
    QuotaEvent.toJson(
      provider: 'claude',
      windows: [
        if (r.fiveHourUtilization != null || r.fiveHourResetsAt != null)
          QuotaWindow(
            id: 'five_hour',
            label: QuotaWindow.labelOf(300),
            usedPercent: pct(r.fiveHourUtilization),
            resetsAt: r.fiveHourResetsAt,
            minutes: 300,
          ),
        if (r.sevenDayUtilization != null || r.sevenDayResetsAt != null)
          QuotaWindow(
            id: 'seven_day',
            label: QuotaWindow.labelOf(10080),
            usedPercent: pct(r.sevenDayUtilization),
            resetsAt: r.sevenDayResetsAt,
            minutes: 10080,
          ),
      ],
      reached: r.status == 'rejected' ? (r.rateLimitType ?? 'limite') : null,
    ),
  ) as QuotaEvent;
}
