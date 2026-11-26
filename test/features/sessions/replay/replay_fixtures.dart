import 'dart:convert';

import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/codex/codex_neutral.dart';
import 'package:promptorium/features/sessions/timeline.dart';

/// Builds a session timeline for the replay tests: each call adds one
/// stored event, one second after the previous one (unless [gap] says
/// otherwise).
class TimelineBuilder {
  TimelineBuilder({DateTime? start})
    : now = start ?? DateTime(2026, 11, 16, 14, 0);

  final Timeline t = Timeline();
  DateTime now;
  var _ids = 0;

  /// Rows as `session_events` keeps them.
  final List<({String json, DateTime at})> rows = [];

  void _add(
    Map<String, dynamic> j, {
    Duration gap = const Duration(seconds: 1),
  }) {
    now = now.add(gap);
    final json = jsonEncode(j);
    rows.add((json: json, at: now));
    t.applyStored(json, at: now, seq: rows.length);
  }

  void user(String text, {Duration gap = const Duration(seconds: 1)}) {
    now = now.add(gap);
    final j = AppEventTypes.userMessage(text, now);
    final json = jsonEncode(j);
    rows.add((json: json, at: now));
    t.applyStored(json, at: now, seq: rows.length);
  }

  void say(String text, {int? contextTokens, String? parent}) => _add({
    'type': 'assistant',
    'message': {
      'content': [
        {'type': 'text', 'text': text},
      ],
      if (contextTokens != null)
        'usage': {
          'input_tokens': contextTokens,
          'output_tokens': 10,
          'cache_read_input_tokens': 0,
          'cache_creation_input_tokens': 0,
        },
    },
    'parent_tool_use_id': parent,
  });

  void think(String text) => _add({
    'type': 'assistant',
    'message': {
      'content': [
        {'type': 'thinking', 'thinking': text},
      ],
    },
    'parent_tool_use_id': null,
  });

  /// A tool call; returns its id. [result] null = no answer yet.
  String tool(
    String name,
    Map<String, dynamic> input, {
    String? result = 'ok',
    bool error = false,
    String? parent,
    Duration took = const Duration(seconds: 1),
    String? id,
  }) {
    final toolId = id ?? 'toolu_${++_ids}';
    _add({
      'type': 'assistant',
      'message': {
        'content': [
          {'type': 'tool_use', 'id': toolId, 'name': name, 'input': input},
        ],
      },
      'parent_tool_use_id': parent,
    });
    if (result != null) {
      _add({
        'type': 'user',
        'message': {
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': toolId,
              'content': result,
              'is_error': error,
            },
          ],
        },
        'parent_tool_use_id': parent,
      }, gap: took);
    }
    return toolId;
  }

  String read(String path, {String result = '1\tline'}) =>
      tool('Read', {'file_path': path}, result: result);

  String edit(
    String path,
    String old,
    String neu, {
    bool error = false,
    String? parent,
  }) => tool(
    'Edit',
    {'file_path': path, 'old_string': old, 'new_string': neu},
    error: error,
    parent: parent,
  );

  String write(String path, String content) =>
      tool('Write', {'file_path': path, 'content': content});

  String bash(
    String command, {
    String result = 'ok',
    bool error = false,
    Duration took = const Duration(seconds: 1),
  }) => tool(
    'Bash',
    {'command': command},
    result: result,
    error: error,
    took: took,
  );

  void denied(String id) => _add(AppEventTypes.deniedMessageEvent(id, at: now));

  void note(String text, {bool error = false}) {
    now = now.add(const Duration(seconds: 1));
    final j = AppEventTypes.noteMessage(text, error: error, at: now);
    final json = jsonEncode(j);
    rows.add((json: json, at: now));
    t.applyStored(json, at: now, seq: rows.length);
  }

  void compact() => _add({'type': 'system', 'subtype': 'compact_boundary'});

  void pause(Duration d) => now = now.add(d);

  // --- Codex (SPEC-110) -------------------------------------------------------

  String? turnId;

  Map<String, dynamic> _codex(Map<String, dynamic> j) => {
    ...j,
    'provider': 'codex',
    'session_id': 'thread-1',
    'turn_id': ?turnId,
  };

  /// `seq` of the last row.
  int get seq => rows.length;

  /// A `turn/started`, after its message.
  void turn(String id) {
    turnId = id;
    _add(_codex({'type': 'system', 'subtype': codexTurnStartedSubtype}));
  }

  void endTurn({String status = 'success'}) {
    _add(
      _codex({
        'type': 'result',
        'subtype': status,
        'is_error': status == 'error_during_execution',
        'num_turns': 1,
        'result': '',
      }),
    );
    turnId = null;
  }

  /// A `commandExecution` item of the App Server, started and completed.
  String command(
    String id,
    String command,
    List<Map<String, dynamic>> actions, {
    String? output = 'ok',
    int exit = 0,
    String status = 'completed',
    String cwd = '/w',
  }) {
    final item = {
      'id': id,
      'type': 'commandExecution',
      'command': command,
      'cwd': cwd,
      'commandActions': actions,
    };
    _add(_codex(codexCommand({...item, 'status': 'inProgress'})));
    _add(
      _codex(
        codexCommand({
          ...item,
          'status': status,
          'aggregatedOutput': output,
          'exitCode': exit,
          'durationMs': 1000,
        }),
      ),
    );
    return id;
  }

  /// A `fileChange` item: one event per change.
  String patch(
    String id,
    List<Map<String, dynamic>> changes, {
    String status = 'completed',
  }) {
    for (var i = 0; i < changes.length; i++) {
      final f = codexFileChange(
        changes[i],
        toolUseId: id,
        index: i,
        status: status,
      );
      _add(_codex({...f.json, 'diff': ?f.diff}));
    }
    return id;
  }

  void codexEvent(Map<String, dynamic> j) => _add(_codex(j));

  List<TimelineItem> get items => t.items;
}

Map<String, dynamic> readAction(String path, {String? command}) => {
  'type': 'read',
  'command': command ?? 'cat $path',
  'name': path.split('/').last,
  'path': path,
};

Map<String, dynamic> update(String path, String diff, {String? move}) => {
  'path': path,
  'kind': {'type': 'update', 'move_path': ?move},
  'diff': diff,
};

ClaudeEvent ev(Map<String, dynamic> j) => ClaudeEvent.fromJson(j);
