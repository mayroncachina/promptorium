import 'dart:convert' show jsonDecode, jsonEncode;

/// One NDJSON line of `claude -p --output-format stream-json --verbose`
/// (plano, Fase 0.2).
///
/// [AgentEvent.fromJson] never throws: unknown `type`s become
/// [UnknownEvent] and unknown `system` subtypes become [SystemOther]
/// (anti-padrão 0.5: ignorar o que não conhecer).
sealed class AgentEvent {
  const AgentEvent(this.json);

  /// The decoded line, as received (kept for persistence in `session_events`).
  final Map<String, dynamic> json;

  /// Top-level `type` of the line (`system`, `assistant`, …).
  String get type => _str(json['type']) ?? '';

  /// `session_id` (present on almost every line).
  String? get sessionId => _str(json['session_id']);

  /// Parses one decoded line. Never throws.
  factory AgentEvent.fromJson(Map<String, dynamic> json) {
    try {
      return _parse(json);
    } catch (_) {
      return UnknownEvent(json);
    }
  }

  /// Like [fromJson], but a `user` line with several `tool_result` blocks
  /// yields one [ToolResult] per block. Never throws.
  static List<AgentEvent> expand(Map<String, dynamic> json) {
    try {
      if (json['type'] == 'user') {
        final results = ToolResult._all(json);
        if (results.isNotEmpty) return results;
      }
    } catch (_) {
      // fall through to fromJson
    }
    return [AgentEvent.fromJson(json)];
  }

  /// Decodes one stdout line. Invalid JSON / non-object lines become
  /// [UnknownEvent] with [UnknownEvent.raw] set. Never throws.
  static List<AgentEvent> parseLine(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return [UnknownEvent(const {}, raw: line)];
    }
    if (decoded is! Map<String, dynamic>) {
      return [UnknownEvent(const {}, raw: line)];
    }
    return expand(decoded);
  }

  static AgentEvent _parse(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'system':
        return switch (j['subtype']) {
          'init' => SystemInit._(j),
          'status' => SystemStatus._(j),
          _ => SystemOther(j),
        };
      case 'stream_event':
        final event = _map(j['event']);
        if (event['type'] == 'content_block_delta') {
          final delta = _map(event['delta']);
          final kind = switch (delta['type']) {
            'text_delta' => StreamDeltaKind.text,
            'thinking_delta' => StreamDeltaKind.thinking,
            _ => null,
          };
          if (kind != null) return StreamDelta._(j, kind, event, delta);
        }
        return StreamOther._(j, event);
      case 'assistant':
        return AssistantMessage._(j);
      case 'user':
        final results = ToolResult._all(j);
        return results.isEmpty ? UnknownEvent(j) : results.first;
      case 'rate_limit_event':
        return RateLimit._(j);
      case 'control_request':
        final req = _map(j['request']);
        if (req['subtype'] == 'can_use_tool' && j['request_id'] is String) {
          return PermissionRequest._(j, req);
        }
        return UnknownEvent(j);
      case 'control_cancel_request':
        final id = _str(j['request_id']);
        return id == null ? UnknownEvent(j) : ControlCancel._(j, id);
      case 'result':
        return Result._(j);
      default:
        return UnknownEvent(j);
    }
  }
}

// --- system ----------------------------------------------------------------

class McpServerStatus {
  const McpServerStatus({required this.name, required this.status});

  final String name;

  /// `connected`, `pending`, `failed`, `needs-auth`, …
  final String status;

  bool get isConnected => status == 'connected';

  bool get isFailed => status == 'failed';
}

/// `system/init`: first line of every turn.
class SystemInit extends AgentEvent {
  SystemInit._(super.json)
    : model = _str(json['model']) ?? '',
      tools = _strings(json['tools']),
      mcpServers = [
        for (final s in _list(json['mcp_servers']))
          if (s is Map && s['name'] is String)
            McpServerStatus(
              name: s['name'] as String,
              status: _str(s['status']) ?? 'unknown',
            ),
      ],
      agents = _strings(json['agents']),
      skills = _strings(json['skills']),
      permissionMode = _str(json['permissionMode']) ?? '',
      cwd = _str(json['cwd']) ?? '',
      claudeCodeVersion = _str(json['claude_code_version']);

  final String model;
  final List<String> tools;
  final List<McpServerStatus> mcpServers;
  final List<String> agents;

  /// Skill names the session can load (user, project, plugins, built-in).
  final List<String> skills;
  final String permissionMode;
  final String cwd;
  final String? claudeCodeVersion;
}

/// `system/status` (e.g. `status: requesting`).
class SystemStatus extends AgentEvent {
  SystemStatus._(super.json) : status = _str(json['status']);

  final String? status;

  String get subtype => 'status';
}

/// Any other `system` subtype (`hook_*`, `api_retry`, `permission_denied`…).
class SystemOther extends AgentEvent {
  const SystemOther(super.json);

  String get subtype => _str(json['subtype']) ?? '';
}

// --- streaming ---------------------------------------------------------------

enum StreamDeltaKind { text, thinking }

/// `stream_event` with a `text_delta` / `thinking_delta` (live text).
class StreamDelta extends AgentEvent {
  StreamDelta._(
    super.json,
    this.kind,
    Map<String, dynamic> event,
    Map<String, dynamic> delta,
  ) : index = _int(event['index']) ?? 0,
      text =
          _str(
            kind == StreamDeltaKind.text ? delta['text'] : delta['thinking'],
          ) ??
          '',
      parentToolUseId = _str(json['parent_tool_use_id']);

  final StreamDeltaKind kind;

  /// Content block index inside the message.
  final int index;
  final String text;

  /// Non-null ⇒ the delta belongs to a subagent.
  final String? parentToolUseId;
}

/// Any other `stream_event` (message_start, content_block_start/stop,
/// signature_delta, message_delta, message_stop…).
class StreamOther extends AgentEvent {
  StreamOther._(super.json, Map<String, dynamic> event)
    : eventType = _str(event['type']) ?? '',
      index = _int(event['index']),
      parentToolUseId = _str(json['parent_tool_use_id']);

  final String eventType;
  final int? index;
  final String? parentToolUseId;
}

// --- messages ----------------------------------------------------------------

sealed class ContentBlock {
  const ContentBlock();
}

class TextBlock extends ContentBlock {
  const TextBlock(this.text);

  final String text;
}

class ThinkingBlock extends ContentBlock {
  const ThinkingBlock(this.thinking);

  final String thinking;
}

class ToolUseBlock extends ContentBlock {
  const ToolUseBlock({
    required this.id,
    required this.name,
    required this.input,
  });

  final String id;
  final String name;
  final Map<String, dynamic> input;
}

/// Block type the app does not know (kept raw).
class OtherBlock extends ContentBlock {
  const OtherBlock(this.json);

  final Map<String, dynamic> json;

  String get type => _str(json['type']) ?? '';
}

/// `assistant`: the CLI emits one line per content block, all with the same
/// `message.id`.
class AssistantMessage extends AgentEvent {
  AssistantMessage._(super.json)
    : messageId = _str(_map(json['message'])['id']) ?? '',
      model = _str(_map(json['message'])['model']),
      blocks = [
        for (final b in _list(_map(json['message'])['content']))
          if (b is Map<String, dynamic>) _block(b),
      ],
      parentToolUseId = _str(json['parent_tool_use_id']);

  final String messageId;
  final String? model;
  final List<ContentBlock> blocks;

  /// Non-null ⇒ message of a subagent.
  final String? parentToolUseId;

  static ContentBlock _block(Map<String, dynamic> b) => switch (b['type']) {
    'text' => TextBlock(_str(b['text']) ?? ''),
    'thinking' => ThinkingBlock(_str(b['thinking']) ?? ''),
    'tool_use' => ToolUseBlock(
      id: _str(b['id']) ?? '',
      name: _str(b['name']) ?? '',
      input: _map(b['input']),
    ),
    _ => OtherBlock(b),
  };
}

/// `user` line carrying a `tool_result` block.
class ToolResult extends AgentEvent {
  ToolResult._(super.json, Map<String, dynamic> block)
    : toolUseId = _str(block['tool_use_id']) ?? '',
      content = _resultText(block['content']),
      isError = block['is_error'] == true,
      parentToolUseId = _str(json['parent_tool_use_id']);

  final String toolUseId;

  /// Text content (text parts joined with newlines; images omitted).
  final String content;
  final bool isError;

  /// Non-null ⇒ result inside a subagent.
  final String? parentToolUseId;

  static List<ToolResult> _all(Map<String, dynamic> j) {
    final content = _map(j['message'])['content'];
    if (content is! List) return const [];
    return [
      for (final b in content)
        if (b is Map<String, dynamic> && b['type'] == 'tool_result')
          ToolResult._(j, b),
    ];
  }

  static String _resultText(Object? c) {
    if (c is String) return c;
    if (c is List) {
      return [
        for (final p in c)
          if (p is Map && p['type'] == 'text' && p['text'] is String)
            p['text'] as String,
      ].join('\n');
    }
    return c == null ? '' : jsonEncode(c);
  }
}

// --- rate limit --------------------------------------------------------------

/// `rate_limit_event` (plan usage, shown in the footer).
class RateLimit extends AgentEvent {
  RateLimit._(super.json)
    : status = _str(_info(json)['status']),
      rateLimitType = _str(_info(json)['rateLimitType']),
      resetsAt = _epoch(_info(json)['resetsAt']),
      isUsingOverage = _info(json)['isUsingOverage'] == true,
      fiveHourUtilization = _double(_window(json, 'five_hour')['utilization']),
      fiveHourResetsAt = _epoch(_window(json, 'five_hour')['resetsAt']),
      sevenDayUtilization = _double(_window(json, 'seven_day')['utilization']),
      sevenDayResetsAt = _epoch(_window(json, 'seven_day')['resetsAt']);

  /// `allowed`, `allowed_warning`, `rejected`…
  final String? status;
  final String? rateLimitType;
  final DateTime? resetsAt;
  final bool isUsingOverage;

  /// 0–1.
  final double? fiveHourUtilization;
  final DateTime? fiveHourResetsAt;

  /// 0–1.
  final double? sevenDayUtilization;
  final DateTime? sevenDayResetsAt;

  static Map<String, dynamic> _info(Map<String, dynamic> j) =>
      _map(j['rate_limit_info']);

  static Map<String, dynamic> _window(Map<String, dynamic> j, String name) =>
      _map(_map(_info(j)['unifiedWindows'])[name]);
}

// --- permissions -------------------------------------------------------------

/// `control_request` / `can_use_tool` (plano, Fase 0.3). Answer with
/// `AgentRun.approve` / `deny`.
class PermissionRequest extends AgentEvent {
  PermissionRequest._(super.json, Map<String, dynamic> req)
    : requestId = json['request_id'] as String,
      toolName = _str(req['tool_name']) ?? '',
      displayName = _str(req['display_name']),
      input = _map(req['input']),
      description = _str(req['description']),
      permissionSuggestions = [
        for (final s in _list(req['permission_suggestions']))
          if (s is Map<String, dynamic>) s,
      ],
      decisionReason = _text(req['decision_reason']),
      toolUseId = _str(req['tool_use_id']);

  final String requestId;
  final String toolName;
  final String? displayName;
  final Map<String, dynamic> input;
  final String? description;

  /// Raw suggestions; "Sempre permitir" sends one back as `updatedPermissions`.
  final List<Map<String, dynamic>> permissionSuggestions;
  final String? decisionReason;
  final String? toolUseId;
}

/// `control_cancel_request`: the CLI no longer waits for [requestId].
class ControlCancel extends AgentEvent {
  const ControlCancel._(super.json, this.requestId);

  final String requestId;
}

// --- result ------------------------------------------------------------------

class Usage {
  const Usage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheCreationInputTokens = 0,
    this.cacheReadInputTokens = 0,
  });

  factory Usage.fromJson(Map<String, dynamic> j) => Usage(
    inputTokens: _int(j['input_tokens']) ?? 0,
    outputTokens: _int(j['output_tokens']) ?? 0,
    cacheCreationInputTokens: _int(j['cache_creation_input_tokens']) ?? 0,
    cacheReadInputTokens: _int(j['cache_read_input_tokens']) ?? 0,
  );

  final int inputTokens;
  final int outputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;

  int get total =>
      inputTokens +
      outputTokens +
      cacheCreationInputTokens +
      cacheReadInputTokens;

  Usage operator +(Usage o) => Usage(
    inputTokens: inputTokens + o.inputTokens,
    outputTokens: outputTokens + o.outputTokens,
    cacheCreationInputTokens:
        cacheCreationInputTokens + o.cacheCreationInputTokens,
    cacheReadInputTokens: cacheReadInputTokens + o.cacheReadInputTokens,
  );
}

/// `result`: end of a turn.
class Result extends AgentEvent {
  Result._(super.json)
    : subtype = _str(json['subtype']) ?? '',
      isError = json['is_error'] == true,
      totalCostUsd = _double(json['total_cost_usd']) ?? 0,
      usage = Usage.fromJson(_map(json['usage'])),
      numTurns = _int(json['num_turns']) ?? 0,
      durationMs = _int(json['duration_ms']) ?? 0,
      permissionDenials = [
        for (final d in _list(json['permission_denials']))
          if (d is Map<String, dynamic>) d,
      ],
      result = _str(json['result']);

  /// `success`, `error_max_turns`, `error_max_budget_usd`,
  /// `error_during_execution`, …
  final String subtype;
  final bool isError;
  final double totalCostUsd;
  final Usage usage;
  final int numTurns;
  final int durationMs;
  final List<Map<String, dynamic>> permissionDenials;

  /// Final text (only on success).
  final String? result;

  bool get isSuccess => subtype == 'success' && !isError;
}

/// Anything not recognised (or an invalid line, see [raw]).
class UnknownEvent extends AgentEvent {
  const UnknownEvent(super.json, {this.raw});

  /// The original line when it was not a JSON object.
  final String? raw;
}

// --- tolerant readers --------------------------------------------------------

String? _str(Object? v) => v is String ? v : null;

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

double? _double(Object? v) => v is num ? v.toDouble() : null;

Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : const {};

List<Object?> _list(Object? v) => v is List ? v : const [];

List<String> _strings(Object? v) => [
  for (final s in _list(v))
    if (s is String) s,
];

String? _text(Object? v) =>
    v == null ? null : (v is String ? v : jsonEncode(v));

DateTime? _epoch(Object? v) => v is num
    ? DateTime.fromMillisecondsSinceEpoch((v * 1000).round(), isUtc: true)
    : null;
