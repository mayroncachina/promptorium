part of 'agent_event.dart';

// --- neutral events (SPEC-095) ----------------------------------------------
//
// Where the providers' concepts do not match the stream-json of Claude Code
// (files, commands, context, quota), both speak these types. The Codex
// adapter emits them as app events (`{"type":"promptorium_…","v":1,…}`, P2);
// Claude's tool calls are converted on read by `claude_neutral.dart` (P1)
// and nothing Claude stored changes (R8, R11).

/// `type` of each neutral event, as stored in `session_events` (R11, P2).
abstract final class NeutralEventTypes {
  static const fileChange = 'promptorium_file_change';
  static const command = 'promptorium_command';
  static const contextUsage = 'promptorium_context_usage';
  static const compaction = 'promptorium_compaction';
  static const quota = 'promptorium_quota';
  static const otherItem = 'promptorium_other_item';

  /// Version of the stored shape.
  static const version = 1;

  static const all = {
    fileChange,
    command,
    contextUsage,
    compaction,
    quota,
    otherItem,
  };
}

/// Limit of a diff or a command output stored in one event (P3): 2.000
/// lines or 256 KB, whichever comes first.
abstract final class NeutralLimits {
  static const maxLines = 2000;
  static const maxBytes = 256 * 1024;

  /// [text] cut to the limits, and how many lines were left out.
  static ({String text, int cut}) cut(String text) {
    final lines = text.split('\n');
    // A trailing newline leaves an empty last element: not a line.
    final total = lines.length - (text.endsWith('\n') ? 1 : 0);
    var bytes = 0;
    var kept = 0;
    for (; kept < total && kept < maxLines; kept++) {
      final size = utf8.encode(lines[kept]).length + 1;
      if (bytes + size > maxBytes) break;
      bytes += size;
    }
    if (kept >= total) return (text: text, cut: 0);
    return (text: '${lines.take(kept).join('\n')}\n', cut: total - kept);
  }

  /// "diff cortado: 1.234 linhas" (R12).
  static String cutLabel(int lines, {String what = 'diff'}) =>
      '$what cortado: ${_thousands(lines)} ${lines == 1 ? 'linha' : 'linhas'}';

  static String _thousands(int n) {
    final s = '$n';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// What happened to the file (R1).
enum FileChangeKind {
  add,
  update,
  delete,
  move;

  static FileChangeKind parse(Object? v) => switch (v) {
    'add' => add,
    'delete' => delete,
    'move' => move,
    _ => update,
  };
}

/// Where a change stands (R1): proposed (waiting or running), applied,
/// declined by the person, failed.
enum FileChangeStatus {
  proposed,
  applied,
  declined,
  failed;

  static FileChangeStatus parse(Object? v) => switch (v) {
    'applied' => applied,
    'declined' => declined,
    'failed' => failed,
    _ => proposed,
  };
}

/// Where a command stands (R2).
enum CommandStatus {
  running,
  completed,
  failed,
  declined;

  static CommandStatus parse(Object? v) => switch (v) {
    'completed' => completed,
    'failed' => failed,
    'declined' => declined,
    _ => running,
  };
}

/// Common header of a stored neutral event.
Map<String, dynamic> _neutral(String type, String provider) => {
  'type': type,
  'v': NeutralEventTypes.version,
  'provider': provider,
};

/// One file changed by the agent (R1). Codex: one per item of
/// `fileChange.changes[]`; Claude: `Edit`, `MultiEdit`, `Write`,
/// `NotebookEdit` seen through `claude_neutral.dart`.
class FileChangeEvent extends AgentEvent {
  // A private field cannot be a named initializing formal.
  // ignore: prefer_initializing_formals
  FileChangeEvent._(super.json, {String? fullDiff}) : _fullDiff = fullDiff;

  /// A live change: [json] is what gets stored (its diff cut to the limit,
  /// R12) and [fullDiff] the whole diff, kept in memory while the session
  /// lives.
  factory FileChangeEvent.live(Map<String, dynamic> json, String? fullDiff) =>
      FileChangeEvent._(json, fullDiff: fullDiff);

  /// The stored shape. [diff] is cut here (R12) unless [cut] is false.
  static Map<String, dynamic> toJson({
    required String provider,
    required String toolUseId,
    required String path,
    required FileChangeKind kind,
    required FileChangeStatus status,
    int index = 0,
    String? fromPath,
    String? diff,
    String? before,
    String? after,
    List<Map<String, dynamic>>? edits,
    bool cut = true,
  }) {
    var stored = diff;
    var cutLines = 0;
    if (diff != null && cut) {
      final c = NeutralLimits.cut(diff);
      stored = c.text;
      cutLines = c.cut;
    }
    return {
      ..._neutral(NeutralEventTypes.fileChange, provider),
      'tool_use_id': toolUseId,
      'index': index,
      'path': path,
      'kind': kind.name,
      'from_path': ?fromPath,
      'diff': ?stored,
      if (cutLines > 0) 'diff_cut': cutLines,
      'before': ?before,
      'after': ?after,
      'edits': ?edits,
      'status': status.name,
    };
  }

  final String? _fullDiff;

  String get path => _str(json['path']) ?? '';
  FileChangeKind get kind => FileChangeKind.parse(json['kind']);

  /// Origin of a [FileChangeKind.move].
  String? get fromPath => _str(json['from_path']);

  /// Unified diff (hunks `@@ -a,b +c,d @@`); the whole one while live.
  String? get unifiedDiff => _fullDiff ?? _str(json['diff']);

  /// Lines left out of the stored diff (R12; 0 = whole).
  int get diffCutLines => _int(json['diff_cut']) ?? 0;

  /// The diff at hand is the cut one (reopened session).
  bool get isCut => diffCutLines > 0 && _fullDiff == null;

  /// "diff cortado: N linhas" when [isCut].
  String? get cutLabel => isCut ? NeutralLimits.cutLabel(diffCutLines) : null;

  /// Text before / after, when known: the whole file (a new or deleted
  /// file) or, for a Claude `Edit`, the replaced fragment.
  String? get before => _str(json['before']);
  String? get after => _str(json['after']);

  /// Claude `MultiEdit`: `{old, new, all}` fragments in order.
  List<Map<String, dynamic>> get edits => [
    for (final e in _list(json['edits']))
      if (e is Map<String, dynamic>) e,
  ];

  String get toolUseId => _str(json['tool_use_id']) ?? '';

  /// Position inside its item (Codex items change several files).
  int get index => _int(json['index']) ?? 0;
  FileChangeStatus get status => FileChangeStatus.parse(json['status']);
  String get provider => _str(json['provider']) ?? 'claude';

  /// The same change with another status (not stored).
  FileChangeEvent withStatus(FileChangeStatus s) => s == status
      ? this
      : FileChangeEvent._({...json, 'status': s.name}, fullDiff: _fullDiff);

  /// Lines added / removed by the diff (null without one).
  (int, int)? get stats {
    final d = unifiedDiff;
    if (d == null) return null;
    var a = 0, r = 0;
    for (final l in d.split('\n')) {
      if (l.startsWith('+++') || l.startsWith('---')) continue;
      if (l.startsWith('+')) a++;
      if (l.startsWith('-')) r++;
    }
    return (a, r);
  }
}

/// One shell command (R2). Codex: `commandExecution`; Claude: `Bash` plus
/// its `tool_result`.
class CommandEvent extends AgentEvent {
  CommandEvent._(super.json);

  static Map<String, dynamic> toJson({
    required String provider,
    required String toolUseId,
    required String command,
    required CommandStatus status,
    String? cwd,
    int? exitCode,
    String? output,
    int? durationMs,
    List<String> reads = const [],
    List<CommandAction> actions = const [],
    int unknownActions = 0,
  }) {
    String? stored = output;
    var cutLines = 0;
    if (output != null) {
      final c = NeutralLimits.cut(output);
      stored = c.text;
      cutLines = c.cut;
    }
    return {
      ..._neutral(NeutralEventTypes.command, provider),
      'tool_use_id': toolUseId,
      'command': command,
      'cwd': ?cwd,
      'exit_code': ?exitCode,
      'output': ?stored,
      if (cutLines > 0) 'output_cut': cutLines,
      'duration_ms': ?durationMs,
      if (reads.isNotEmpty) 'reads': reads,
      if (actions.isNotEmpty) 'actions': [for (final a in actions) a.toJson()],
      if (unknownActions > 0) 'unknown_actions': unknownActions,
      'status': status.name,
    };
  }

  String get toolUseId => _str(json['tool_use_id']) ?? '';

  /// The command as run (Codex wraps it in `zsh -lc '…'`).
  String get command => _str(json['command']) ?? '';
  String? get cwd => _str(json['cwd']);
  int? get exitCode => _int(json['exit_code']);
  String? get output => _str(json['output']);
  int get outputCutLines => _int(json['output_cut']) ?? 0;
  int? get durationMs => _int(json['duration_ms']);
  CommandStatus get status => CommandStatus.parse(json['status']);
  String get provider => _str(json['provider']) ?? 'claude';

  /// Files the command reads (Codex `commandActions` of type `read`).
  List<String> get reads => _strings(json['reads']);

  /// What the agent says the command does (Codex `commandActions` of a
  /// known type: `read`, `search`, `listFiles`; SPEC-107 R11, P4).
  List<CommandAction> get actions => [
    for (final a in json['actions'] as List? ?? const [])
      ?CommandAction.fromJson(a),
  ];

  /// Actions the agent could not classify (Codex `unknown`, SPEC-110 R1):
  /// with any, the command is not only a read.
  int get unknownActions => _int(json['unknown_actions']) ?? 0;

  /// Every action of the command is a read, a search or a listing.
  bool get onlyReads => unknownActions == 0 && actions.isNotEmpty;

  bool get done => status != CommandStatus.running;

  bool get failed =>
      status == CommandStatus.failed ||
      status == CommandStatus.declined ||
      (exitCode != null && exitCode != 0);

  /// The command without the login shell around it: `ls`, not
  /// `/usr/bin/zsh -lc ls`.
  String get displayCommand {
    final m = RegExp(r'^(?:\S*/)?(?:ba|z|da|k)?sh\s+-l?c\s+([\s\S]+)$')
        .firstMatch(command.trim());
    if (m == null) return command;
    var c = m.group(1)!.trim();
    if (c.length >= 2 &&
        ((c.startsWith("'") && c.endsWith("'")) ||
            (c.startsWith('"') && c.endsWith('"')))) {
      c = c.substring(1, c.length - 1);
    }
    return c;
  }

  /// This command finished with [output] (a Claude `tool_result`). The exit
  /// code comes from "Exit code N" when the agent wrote one.
  CommandEvent completedWith({required String output, required bool isError}) {
    final code = RegExp(r'[Ee]xit code (\d+)').firstMatch(output);
    return CommandEvent._(
      toJson(
        provider: provider,
        toolUseId: toolUseId,
        command: command,
        cwd: cwd,
        status: isError ? CommandStatus.failed : CommandStatus.completed,
        exitCode: isError
            ? (code == null ? null : int.parse(code.group(1)!))
            : 0,
        output: output,
        durationMs: durationMs,
        reads: reads,
        actions: actions,
        unknownActions: unknownActions,
      ),
    );
  }
}

/// One classified action of a command (Codex `commandActions`, SPEC-107
/// R11): only the known types; `unknown` never becomes one (P4).
class CommandAction {
  const CommandAction({
    required this.type,
    this.path,
    this.query,
    this.command,
  });

  static const read = 'read';
  static const search = 'search';
  static const listFiles = 'listFiles';
  static const known = {read, search, listFiles};

  /// `read`, `search` or `listFiles`.
  final String type;
  final String? path;

  /// The searched text (`search`).
  final String? query;

  /// The part of the command that does it (`sed -n 1,80p a.dart`).
  final String? command;

  static CommandAction? fromJson(Object? j) {
    if (j is! Map) return null;
    final type = _str(j['type']);
    if (type == null || !known.contains(type)) return null;
    final path = _str(j['path']);
    if (type == read && (path == null || path.isEmpty)) return null;
    return CommandAction(
      type: type,
      path: path,
      query: _str(j['query']),
      command: _str(j['command']),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'path': ?path,
    'query': ?query,
    'command': ?command,
  };
}

/// The context of one top-level model call, as the agent measured it (R3).
class ContextUsageEvent extends AgentEvent {
  ContextUsageEvent._(super.json);

  /// Where a reading comes from (`ContextReading.source`).
  static const claudeUsage = 'claude-usage';
  static const codexTokenUsage = 'codex-tokenUsage';

  static Map<String, dynamic> toJson({
    required String provider,
    required int tokens,
    required String source,
    int input = 0,
    int cacheWrite = 0,
    int cacheRead = 0,
    int output = 0,
    int? window,
    String? model,
    String? messageId,
    String? turnId,
    DateTime? at,
  }) => {
    ..._neutral(NeutralEventTypes.contextUsage, provider),
    'tokens': tokens,
    'input': input,
    'cache_write': cacheWrite,
    'cache_read': cacheRead,
    if (output > 0) 'output': output,
    'turn_id': ?turnId,
    'window': ?window,
    'model': ?model,
    'message_id': ?messageId,
    'source': source,
    'at': (at ?? DateTime.now()).toIso8601String(),
  };

  int get tokens => _int(json['tokens']) ?? 0;
  int get input => _int(json['input']) ?? 0;
  int get cacheWrite => _int(json['cache_write']) ?? 0;
  int get cacheRead => _int(json['cache_read']) ?? 0;

  /// Output of the call, part of the Codex `last.totalTokens` (SPEC-107
  /// R3): the context the next call reads back. Claude: 0.
  int get output => _int(json['output']) ?? 0;

  /// The agent's turn id (Codex `turnId`, SPEC-107 R4).
  String? get turnId => _str(json['turn_id']);

  /// Capacity of the model's window (Codex `modelContextWindow`).
  int? get window => _int(json['window']);
  String? get model => _str(json['model']);
  String? get messageId => _str(json['message_id']);
  String get source => _str(json['source']) ?? claudeUsage;
  DateTime? get at => DateTime.tryParse('${json['at']}');
  String get provider => _str(json['provider']) ?? 'claude';
}

enum CompactionEventPhase {
  started,
  completed,
  failed;

  static CompactionEventPhase parse(Object? v) => switch (v) {
    'started' => started,
    'failed' => failed,
    _ => completed,
  };
}

/// A compaction of the context (R3, R4).
class CompactionEvent extends AgentEvent {
  CompactionEvent._(super.json);

  static Map<String, dynamic> toJson({
    required String provider,
    required CompactionEventPhase phase,
    String trigger = 'auto',
    int? preTokens,
    int? postTokens,
    String? key,
    String? error,
    DateTime? at,
  }) => {
    ..._neutral(NeutralEventTypes.compaction, provider),
    'phase': phase.name,
    'trigger': trigger,
    'pre_tokens': ?preTokens,
    'post_tokens': ?postTokens,
    'key': ?key,
    'error': ?error,
    'at': (at ?? DateTime.now()).toIso8601String(),
  };

  CompactionEventPhase get phase => CompactionEventPhase.parse(json['phase']);

  /// `auto` or `manual`.
  String get trigger => _str(json['trigger']) ?? 'auto';
  int? get preTokens => _int(json['pre_tokens']);
  int? get postTokens => _int(json['post_tokens']);

  /// Deduplication key (the Codex item id).
  String? get key => _str(json['key']);
  String? get error => _str(json['error']);
  String get provider => _str(json['provider']) ?? 'claude';
}

/// One window of a plan limit (R5).
class QuotaWindow {
  const QuotaWindow({
    required this.id,
    required this.label,
    this.usedPercent,
    this.resetsAt,
    this.minutes,
  });

  final String id;

  /// "5 h", "semana"…
  final String label;

  /// 0–100.
  final double? usedPercent;
  final DateTime? resetsAt;
  final int? minutes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'used_percent': ?usedPercent,
    'resets_at': ?resetsAt?.toUtc().toIso8601String(),
    'minutes': ?minutes,
  };

  static QuotaWindow? fromJson(Object? j) {
    if (j is! Map) return null;
    return QuotaWindow(
      id: '${j['id'] ?? ''}',
      label: '${j['label'] ?? ''}',
      usedPercent: _double(j['used_percent']),
      resetsAt: DateTime.tryParse('${j['resets_at']}'),
      minutes: _int(j['minutes']),
    );
  }

  /// "5 h", "semana", "90 min".
  static String labelOf(int? minutes) => switch (minutes) {
    null => 'janela',
    10080 => 'semana',
    final m when m % 1440 == 0 => '${m ~/ 1440} d',
    final m when m % 60 == 0 => '${m ~/ 60} h',
    final m => '$m min',
  };
}

/// Plan usage of the account (R5). Only passed on, never stored (P5).
class QuotaEvent extends AgentEvent {
  QuotaEvent._(super.json);

  static Map<String, dynamic> toJson({
    required String provider,
    required List<QuotaWindow> windows,
    String? plan,
    String? reached,
    DateTime? at,
  }) => {
    ..._neutral(NeutralEventTypes.quota, provider),
    'windows': [for (final w in windows) w.toJson()],
    'plan': ?plan,
    'reached': ?reached,
    'at': (at ?? DateTime.now()).toIso8601String(),
  };

  List<QuotaWindow> get windows => [
    for (final w in _list(json['windows'])) ?QuotaWindow.fromJson(w),
  ];
  String? get plan => _str(json['plan']);

  /// Kind of limit reached (null = none).
  String? get reached => _str(json['reached']);
  DateTime? get at => DateTime.tryParse('${json['at']}');
  String get provider => _str(json['provider']) ?? 'claude';
}

/// An item of the agent the app does not translate (R6): shown collapsed,
/// never dropped.
class OtherItemEvent extends AgentEvent {
  OtherItemEvent._(super.json);

  static Map<String, dynamic> toJson({
    required String provider,
    required String itemType,
    required String summary,
    String? toolUseId,
    String? text,
  }) => {
    ..._neutral(NeutralEventTypes.otherItem, provider),
    'item_type': itemType,
    'summary': summary,
    'text': ?text,
    'tool_use_id': ?toolUseId,
  };

  String get itemType => _str(json['item_type']) ?? '';
  String get summary => _str(json['summary']) ?? '';

  /// The whole text, where the item is one (a plan, SPEC-110 R1).
  String? get text => _str(json['text']);

  /// A plan of the agent: the `plan` item or `turn/plan/updated`.
  bool get isPlan => itemType == 'plan' || itemType == 'turnPlan';
  String get toolUseId => _str(json['tool_use_id']) ?? '';
  String get provider => _str(json['provider']) ?? 'claude';
}

AgentEvent? _parseNeutral(Map<String, dynamic> j) => switch (j['type']) {
  NeutralEventTypes.fileChange => FileChangeEvent._(j),
  NeutralEventTypes.command => CommandEvent._(j),
  NeutralEventTypes.contextUsage => ContextUsageEvent._(j),
  NeutralEventTypes.compaction => CompactionEvent._(j),
  NeutralEventTypes.quota => QuotaEvent._(j),
  NeutralEventTypes.otherItem => OtherItemEvent._(j),
  _ => null,
};

/// Whether [e] goes to `session_events`: live text deltas and the plan
/// quota (P5) are not stored.
bool isStoredEvent(AgentEvent e) =>
    e is! StreamDelta && e is! StreamOther && e is! QuotaEvent;
