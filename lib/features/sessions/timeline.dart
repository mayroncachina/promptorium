import 'dart:convert';

import '../../core/claude/claude_event.dart';

/// Event types written by the app itself into `session_events` (they never
/// come from the CLI; `ClaudeEvent.fromJson` turns them into [UnknownEvent]).
abstract final class AppEventTypes {
  /// Message typed by the user: `{"type":"promptorium_user","text":…}`.
  /// The CLI does not echo stdin messages (no `--replay-user-messages`).
  static const user = 'promptorium_user';

  /// Lifecycle note: `{"type":"promptorium_note","level":"info|error","text":…}`.
  static const note = 'promptorium_note';

  /// Stdout line that was not a JSON object: `{"type":"invalid_line","raw":…}`.
  static const invalidLine = 'invalid_line';

  static Map<String, dynamic> userMessage(String text, DateTime at) => {
    'type': user,
    'text': text,
    'at': at.toIso8601String(),
  };

  static Map<String, dynamic> noteMessage(
    String text, {
    bool error = false,
    DateTime? at,
  }) => {
    'type': note,
    'level': error ? 'error' : 'info',
    'text': text,
    'at': (at ?? DateTime.now()).toIso8601String(),
  };
}

/// `session_events.type` for an event: `type` or `type/subtype`.
String eventTypeKey(ClaudeEvent e) {
  if (e is UnknownEvent && e.raw != null) return AppEventTypes.invalidLine;
  final t = e.type;
  final sub = e.json['subtype'];
  return sub is String && sub.isNotEmpty ? '$t/$sub' : t;
}

/// JSON stored for an event (the raw line, or a wrapper for invalid lines).
String eventJson(ClaudeEvent e) => e is UnknownEvent && e.raw != null
    ? jsonEncode({'type': AppEventTypes.invalidLine, 'raw': e.raw})
    : jsonEncode(e.json);

// --- items -------------------------------------------------------------------

sealed class TimelineItem {
  TimelineItem({this.at, this.parentToolUseId});

  final DateTime? at;

  /// Non-null ⇒ produced inside a subagent (nested under its Task card).
  final String? parentToolUseId;
}

class UserItem extends TimelineItem {
  UserItem(this.text, {super.at});

  final String text;
}

/// Claude's text; [live] while it is still streaming (`text_delta`).
class AssistantTextItem extends TimelineItem {
  AssistantTextItem(
    this.text, {
    this.live = false,
    super.at,
    super.parentToolUseId,
  });

  String text;
  bool live;
}

/// A `tool_use` block and (once it arrives) its `tool_result`.
class ToolItem extends TimelineItem {
  ToolItem({
    required this.id,
    required this.name,
    required this.input,
    super.at,
    super.parentToolUseId,
  });

  final String id;
  final String name;
  final Map<String, dynamic> input;
  String? result;
  bool isError = false;

  /// Subagent messages (`parent_tool_use_id == id`).
  final List<TimelineItem> children = [];

  bool get done => result != null;

  /// Task / Agent tool: runs a subagent.
  bool get isSubagent => isSubagentTool(name);

  static bool isSubagentTool(String name) => name == 'Task' || name == 'Agent';
}

enum NoticeLevel { info, success, error }

/// Small status line (session start, end of turn, errors, app notes).
class NoticeItem extends TimelineItem {
  NoticeItem(this.text, {this.level = NoticeLevel.info, super.at});

  final String text;
  final NoticeLevel level;
}

// --- reducer -----------------------------------------------------------------

/// Builds the timeline of one session from its events, in order.
///
/// Mutable on purpose (deltas arrive many times per second); the provider
/// wraps it in a new snapshot after each change.
class Timeline {
  final List<TimelineItem> items = [];
  final Map<String, ToolItem> _tools = {};
  final Map<String?, AssistantTextItem> _live = {};
  bool _sawInit = false;

  /// Model reported by the first `system/init`.
  String? model;

  /// Number of events applied (persisted or live).
  int applied = 0;

  ToolItem? tool(String id) => _tools[id];

  List<TimelineItem> _target(String? parent) {
    if (parent == null) return items;
    return _tools[parent]?.children ?? items;
  }

  /// Applies one stored row (`session_events.json`).
  void applyStored(String json, {DateTime? at}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    for (final e in ClaudeEvent.expand(decoded)) {
      apply(e, at: at);
    }
  }

  void apply(ClaudeEvent e, {DateTime? at}) {
    applied++;
    final now = at ?? DateTime.now();
    switch (e) {
      case SystemInit():
        model ??= e.model.isEmpty ? null : e.model;
        if (!_sawInit) {
          _sawInit = true;
          final mode = e.permissionMode.isEmpty ? '' : ' · ${e.permissionMode}';
          items.add(NoticeItem('Sessão iniciada · ${e.model}$mode', at: now));
        }
      case StreamDelta(kind: StreamDeltaKind.text):
        final live = _live[e.parentToolUseId];
        if (live != null) {
          live.text += e.text;
        } else {
          final item = AssistantTextItem(
            e.text,
            live: true,
            at: now,
            parentToolUseId: e.parentToolUseId,
          );
          _live[e.parentToolUseId] = item;
          _target(e.parentToolUseId).add(item);
        }
      case AssistantMessage():
        for (final b in e.blocks) {
          switch (b) {
            case TextBlock(:final text):
              final live = _live.remove(e.parentToolUseId);
              if (live != null) {
                live
                  ..text = text
                  ..live = false;
              } else if (text.trim().isNotEmpty) {
                _target(e.parentToolUseId).add(
                  AssistantTextItem(
                    text,
                    at: now,
                    parentToolUseId: e.parentToolUseId,
                  ),
                );
              }
            case ToolUseBlock():
              _finishLive(e.parentToolUseId);
              final t = ToolItem(
                id: b.id,
                name: b.name,
                input: b.input,
                at: now,
                parentToolUseId: e.parentToolUseId,
              );
              _tools[b.id] = t;
              _target(e.parentToolUseId).add(t);
            case ThinkingBlock() || OtherBlock():
              break;
          }
        }
      case ToolResult():
        final t = _tools[e.toolUseId];
        if (t != null) {
          t
            ..result = e.content
            ..isError = e.isError;
        } else if (e.isError) {
          items.add(NoticeItem(e.content, level: NoticeLevel.error, at: now));
        }
      case Result():
        _live.keys.toList().forEach(_finishLive);
        items.add(_resultNotice(e, now));
      case SystemOther(subtype: 'api_retry'):
        items.add(NoticeItem('Falha na API; tentando novamente…', at: now));
      case UnknownEvent():
        _applyApp(e.json, now);
      default:
        break;
    }
  }

  void _finishLive(String? parent) {
    final live = _live.remove(parent);
    if (live != null) live.live = false;
  }

  void _applyApp(Map<String, dynamic> j, DateTime now) {
    final at = DateTime.tryParse('${j['at']}')?.toLocal() ?? now;
    switch (j['type']) {
      case AppEventTypes.user:
        items.add(UserItem('${j['text'] ?? ''}', at: at));
      case AppEventTypes.note:
        items.add(
          NoticeItem(
            '${j['text'] ?? ''}',
            level: j['level'] == 'error' ? NoticeLevel.error : NoticeLevel.info,
            at: at,
          ),
        );
    }
  }

  static NoticeItem _resultNotice(Result r, DateTime at) {
    final secs = (r.durationMs / 1000).toStringAsFixed(1).replaceAll('.', ',');
    final turns = r.numTurns == 1 ? '1 turno' : '${r.numTurns} turnos';
    final denials = r.permissionDenials.isEmpty
        ? ''
        : ' · ${r.permissionDenials.length} permissão(ões) negada(s)';
    if (r.isSuccess) {
      return NoticeItem(
        'Concluído · $turns · ${secs}s$denials',
        level: NoticeLevel.success,
        at: at,
      );
    }
    final why = switch (r.subtype) {
      'error_max_turns' => 'limite de turnos atingido',
      'error_max_budget_usd' => 'orçamento esgotado',
      'error_during_execution' => 'erro durante a execução',
      _ => r.subtype.isEmpty ? 'erro' : r.subtype,
    };
    return NoticeItem(
      'Falhou · $why · $turns$denials',
      level: NoticeLevel.error,
      at: at,
    );
  }
}

// --- presentation helpers (pure, shared by the timeline and approvals) -------

/// Main argument of a tool call (file path, command, pattern…).
String toolTarget(String name, Map<String, dynamic> input, {String? root}) {
  String rel(String p) {
    if (root != null && root.isNotEmpty && p.startsWith('$root/')) {
      return p.substring(root.length + 1);
    }
    return p;
  }

  for (final k in const ['file_path', 'notebook_path', 'path']) {
    final v = input[k];
    if (v is String && v.isNotEmpty) {
      final pattern = input['pattern'];
      return pattern is String && k == 'path'
          ? '$pattern  em ${rel(v)}'
          : rel(v);
    }
  }
  for (final k in const [
    'command',
    'pattern',
    'url',
    'query',
    'description',
    'prompt',
    'skill',
  ]) {
    final v = input[k];
    if (v is String && v.isNotEmpty) return _oneLine(v);
  }
  for (final v in input.values) {
    if (v is String && v.isNotEmpty) return _oneLine(v);
  }
  return input.isEmpty ? '' : _oneLine(jsonEncode(input));
}

String _oneLine(String s) {
  final line = s.trim().split('\n').first;
  return line.length > 200 ? '${line.substring(0, 200)}…' : line;
}

int _lines(Object? v) =>
    v is String && v.isNotEmpty ? '\n'.allMatches(v.trimRight()).length + 1 : 0;

/// Lines added / removed by an Edit / Write / MultiEdit input.
(int, int)? editStats(String name, Map<String, dynamic> input) {
  switch (name) {
    case 'Edit':
      return (_lines(input['new_string']), _lines(input['old_string']));
    case 'Write':
      return (_lines(input['content']), 0);
    case 'MultiEdit':
      var a = 0, d = 0;
      final edits = input['edits'];
      if (edits is List) {
        for (final e in edits) {
          if (e is Map) {
            a += _lines(e['new_string']);
            d += _lines(e['old_string']);
          }
        }
      }
      return (a, d);
  }
  return null;
}

/// Short summary of a finished tool result ("82 linhas", "ok", "erro").
String resultSummary(ToolItem t) {
  if (!t.done) return '';
  if (t.isError) return 'erro';
  final n = _lines(t.result);
  return switch (t.name) {
    'Read' => n == 1 ? '1 linha' : '$n linhas',
    'Glob' ||
    'Grep' => n == 0 ? 'nada' : (n == 1 ? '1 resultado' : '$n resultados'),
    _ => 'ok',
  };
}
