import 'dart:convert';

import '../../core/claude/claude_event.dart';
import '../../core/claude/claude_args.dart';
import '../../core/claude/managed_hooks.dart' show secretBlockTitle;
import '../../core/providers/permission_policy.dart';
import '../../core/secrets/secret_scanner.dart';
import '../context/context_tracker.dart';

/// Event types written by the app itself into `session_events` (they never
/// come from the CLI; `ClaudeEvent.fromJson` turns them into [UnknownEvent]).
abstract final class AppEventTypes {
  /// Message typed by the user: `{"type":"promptorium_user","text":…}`.
  /// The CLI does not echo stdin messages (no `--replay-user-messages`).
  static const user = 'promptorium_user';

  /// Lifecycle note: `{"type":"promptorium_note","level":"info|error","text":…}`.
  static const note = 'promptorium_note';

  /// Approval denied in the app: `{"type":"promptorium_denied",
  /// "tool_use_id":…}` (SPEC-026 R4). Marks the tool card as denied.
  static const denied = 'promptorium_denied';

  /// Message sent to the agent when a tool call is denied in the app.
  static const deniedMessage = 'O usuário negou esta ação no Promptorium.';

  static Map<String, dynamic> deniedMessageEvent(
    String toolUseId, {
    DateTime? at,
  }) => {
    'type': denied,
    'tool_use_id': toolUseId,
    'at': (at ?? DateTime.now()).toIso8601String(),
  };

  /// A comparison of two answers (SPEC-079): `{"type":"promptorium_compare",
  /// "status":"open|chosen","prompt":…,"sides":[…]}`. Open, it shows
  /// nothing here (the Prompt shows the columns); chosen, the prompt and
  /// the folded card ([CompareItem]).
  static const compare = 'promptorium_compare';

  /// The Vigia de segredos blocked a commit, push or PR (SPEC-085 R7):
  /// `{"type":"promptorium_secrets","block":…,"action":"commit|push|pr",
  /// "command":…,"findings":[…],"partial":bool}`. The findings are already
  /// masked ([SecretFinding.toJson]); the value is never stored.
  static const secrets = 'promptorium_secrets';

  /// A finding of a block was handled (R9, R11): `{"type":
  /// "promptorium_secret_resolved","block":…,"finding":`fingerprint`,
  /// "path":…,"how":"removido|ignorado|pedido","text":…}`.
  static const secretResolved = 'promptorium_secret_resolved';

  static Map<String, dynamic> secretsEvent({
    required String block,
    required String action,
    String? command,
    required List<Map<String, Object?>> findings,
    bool partial = false,
    DateTime? at,
    String? provider,
  }) => {
    'type': secrets,
    'provider': ?provider,
    'block': block,
    'action': action,
    'command': ?command,
    'findings': findings,
    'partial': partial,
    'at': (at ?? DateTime.now()).toIso8601String(),
  };

  static Map<String, dynamic> secretResolvedEvent({
    required String block,
    required String finding,
    required String path,
    required String how,
    String? text,
    DateTime? at,
  }) => {
    'type': secretResolved,
    'block': block,
    'finding': finding,
    'path': path,
    'how': how,
    'text': ?text,
    'at': (at ?? DateTime.now()).toIso8601String(),
  };

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
    String? provider,
  }) => {
    'type': note,
    'level': error ? 'error' : 'info',
    'text': text,
    // SPEC-103 P4: the hook cards of a Codex session carry its badge.
    'provider': ?provider,
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

/// Claude's reasoning (`thinking` block / `thinking_delta`), shown
/// collapsed (UX v2, U3; DT-20). [live] while it streams.
class ThinkingItem extends TimelineItem {
  ThinkingItem(this.text, {this.live = false, super.at, super.parentToolUseId});

  String text;
  bool live;
}

/// Names of the cards built from neutral events (SPEC-095): what the card
/// shows where a Claude card shows the tool name.
abstract final class NeutralToolNames {
  static const file = 'arquivo';
  static const command = 'comando';
  static const other = 'outro';
}

/// A `tool_use` block and (once it arrives) its `tool_result`; or a card of
/// a neutral event (a file, a command, an item without translation).
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

  /// The user denied the call in the app (SPEC-026 R4): not applied.
  bool denied = false;

  /// Subagent messages (`parent_tool_use_id == id`).
  final List<TimelineItem> children = [];

  /// When the result arrived (subagent duration).
  DateTime? doneAt;

  bool get done => result != null;

  /// Tool calls made by the subagent (nested, any depth).
  int get childToolCount => _countTools(children);

  static int _countTools(List<TimelineItem> items) {
    var n = 0;
    for (final i in items) {
      if (i is ToolItem) n += 1 + _countTools(i.children);
    }
    return n;
  }

  /// Task / Agent tool: runs a subagent.
  bool get isSubagent => isSubagentTool(name);

  // --- neutral view (SPEC-095 R9) -------------------------------------------

  /// The file change behind a neutral card (Codex); null for a Claude call,
  /// whose block brings its own ([fileChanges]).
  FileChangeEvent? change;

  /// The command behind a neutral card (Codex).
  CommandEvent? commandEvent;

  /// An item the app does not translate (R6): shown collapsed.
  OtherItemEvent? other;

  late final ToolUseBlock _block = ToolUseBlock(
    id: id,
    name: name,
    input: input,
  );

  /// Status of this call as a change: from the event, or from the result.
  FileChangeStatus get _status => denied
      ? FileChangeStatus.declined
      : isError
      ? FileChangeStatus.failed
      : done
      ? FileChangeStatus.applied
      : FileChangeStatus.proposed;

  /// The files this card changes, in the neutral vocabulary (both
  /// providers).
  List<FileChangeEvent> get fileChanges {
    final c = change;
    if (c != null) {
      return [denied ? c.withStatus(FileChangeStatus.declined) : c];
    }
    if (commandEvent == null && other == null) {
      return [for (final f in _block.fileChanges) f.withStatus(_status)];
    }
    return const [];
  }

  /// The command of this card (both providers), completed by its result.
  CommandEvent? get command {
    final c = commandEvent;
    if (c != null) return c;
    if (other != null || change != null) return null;
    final start = _block.command;
    if (start == null || result == null) return start;
    return start.completedWith(output: result!, isError: isError);
  }

  /// A card that changes files / runs a command.
  bool get isFileChange => fileChanges.isNotEmpty;
  bool get isCommand => command != null;

  /// A card built from a neutral event (not a Claude tool call).
  bool get isNeutral => change != null || commandEvent != null || other != null;

  /// The file this card reads or changes (null = none).
  String? get filePath {
    final c = change;
    if (c != null) return c.path;
    final p = input['file_path'] ?? input['notebook_path'];
    return p is String && p.isNotEmpty ? p : null;
  }

  /// Lines added / removed (an edit), null when unknown.
  (int, int)? get stats => change?.stats ?? editStats(name, input);

  static bool isSubagentTool(String name) => name == 'Task' || name == 'Agent';
}

enum NoticeLevel { info, success, error }

/// Small status line (session start, end of turn, errors, app notes).
class NoticeItem extends TimelineItem {
  NoticeItem(
    this.text, {
    this.level = NoticeLevel.info,
    this.provider,
    super.at,
  });

  final String text;
  final NoticeLevel level;

  /// SPEC-103 P4: `codex` on the hook cards of a Codex session (badge).
  final String? provider;
}

/// A chosen comparison (SPEC-079 R11): the folded card with both sides.
/// A [NoticeItem] for every view that does not know it (replay…).
class CompareItem extends NoticeItem {
  CompareItem(this.data, super.text, {super.at});

  /// The stored event (`CompareRun.fromJson`).
  final Map<String, dynamic> data;
}

/// The card of a commit, push or PR blocked by the Vigia de segredos
/// (SPEC-085 R7). A [NoticeItem] for every reader that does not know it
/// (replay, search): its text is the title.
class SecretBlockItem extends NoticeItem {
  SecretBlockItem({
    required this.block,
    required this.action,
    required this.findings,
    this.command,
    this.partial = false,
    super.provider,
    super.at,
  }) : super(
         secretBlockTitle(action, findings.length),
         level: NoticeLevel.error,
       );

  final String block;

  /// `commit`, `push` or `pr`.
  final String action;
  final String? command;
  final List<SecretFinding> findings;
  final bool partial;

  /// How each finding was handled, by `path\u0000fingerprint`.
  final Map<String, String> resolved = {};

  static String keyOf(SecretFinding f) => '${f.path}\u0000${f.fingerprint}';

  String? resolution(SecretFinding f) => resolved[keyOf(f)];

  List<SecretFinding> get open => [
    for (final f in findings)
      if (!resolved.containsKey(keyOf(f))) f,
  ];

  bool get done => open.isEmpty;
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
  final Map<String?, ThinkingItem> _liveThinking = {};
  bool _sawInit = false;
  final Set<String> _deniedIds = {};

  /// Neutral cards by the id of their item (a Codex item changes several
  /// files: one card per file, R1).
  final Map<String, List<ToolItem>> _groups = {};
  final Map<String, SecretBlockItem> _secretBlocks = {};

  /// A block of the Vigia de segredos by its id (SPEC-085).
  SecretBlockItem? secretBlock(String id) => _secretBlocks[id];

  /// Model reported by the first `system/init`.
  String? model;

  /// Number of events applied (persisted or live).
  int applied = 0;

  /// Context tokens of each top-level answer (SPEC-082 R6): `items` is the
  /// length of [items] once the answer was applied.
  final List<({int items, int tokens})> contextTokens = [];

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
      apply(e, at: at, stored: true);
    }
  }

  /// Context window of this history (SPEC-087).
  final ContextTracker context = ContextTracker();

  /// [stored] = rebuilt from a persisted row (not a live reading).
  void apply(ClaudeEvent e, {DateTime? at, bool stored = false}) {
    applied++;
    final now = at ?? DateTime.now();
    _applyItems(e, now);
    context.apply(e, at: now, itemIndex: items.length, live: !stored);
  }

  void _applyItems(ClaudeEvent e, DateTime now) {
    switch (e) {
      case SystemInit():
        model ??= e.model.isEmpty ? null : e.model;
        if (!_sawInit) {
          _sawInit = true;
          final stored = e.json['permission_label'];
          final label = e.json['provider'] == 'codex'
              ? stored is String && stored.isNotEmpty
                    ? stored
                    : permissionModeLabel(
                        ClaudePermissionMode.fromCli(e.permissionMode),
                        provider: 'codex',
                      )
              : e.permissionMode;
          final mode = label.isEmpty ? '' : ' · $label';
          items.add(NoticeItem('Sessão iniciada · ${e.model}$mode', at: now));
        }
      case StreamDelta(kind: StreamDeltaKind.thinking):
        final live = _liveThinking[e.parentToolUseId];
        if (live != null) {
          live.text += e.text;
        } else {
          final item = ThinkingItem(
            e.text,
            live: true,
            at: now,
            parentToolUseId: e.parentToolUseId,
          );
          _liveThinking[e.parentToolUseId] = item;
          _target(e.parentToolUseId).add(item);
        }
      case StreamDelta(kind: StreamDeltaKind.text):
        _finishThinking(e.parentToolUseId);
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
              _finishThinking(e.parentToolUseId);
              final t = ToolItem(
                id: b.id,
                name: b.name,
                input: b.input,
                at: now,
                parentToolUseId: e.parentToolUseId,
              );
              if (_deniedIds.contains(b.id)) t.denied = true;
              _tools[b.id] = t;
              _target(e.parentToolUseId).add(t);
            case ThinkingBlock(:final thinking):
              final live = _liveThinking.remove(e.parentToolUseId);
              if (live != null) {
                live
                  ..text = thinking.isEmpty ? live.text : thinking
                  ..live = false;
              } else if (thinking.trim().isNotEmpty) {
                _target(e.parentToolUseId).add(
                  ThinkingItem(
                    thinking,
                    at: now,
                    parentToolUseId: e.parentToolUseId,
                  ),
                );
              }
            case OtherBlock():
              break;
          }
        }
        _recordContext(e);
      case ToolResult():
        final t = _tools[e.toolUseId];
        if (t != null) {
          t
            ..result = e.content
            ..isError = e.isError
            ..doneAt = now;
          if (e.isError && e.content.contains(AppEventTypes.deniedMessage)) {
            t.denied = true;
          }
        } else if (e.isError) {
          items.add(NoticeItem(e.content, level: NoticeLevel.error, at: now));
        }
      case Result():
        _live.keys.toList().forEach(_finishLive);
        _liveThinking.keys.toList().forEach(_finishThinking);
        items.add(_resultNotice(e, now));
      case SystemOther(subtype: 'api_retry'):
        items.add(NoticeItem('Falha na API; tentando novamente…', at: now));
      case SystemOther(subtype: 'compact_boundary'):
        items.add(NoticeItem(compactionNotice, at: now));
      case FileChangeEvent():
        _applyFile(e, now);
      case CommandEvent():
        _applyCommand(e, now);
      case OtherItemEvent():
        _applyOther(e, now);
      case CompactionEvent(phase: CompactionEventPhase.completed):
        items.add(NoticeItem(compactionNotice, at: now));
      case ContextUsageEvent(:final tokens):
        contextTokens.add((items: items.length, tokens: tokens));
      case UnknownEvent():
        _applyApp(e.json, now);
      default:
        break;
    }
  }

  /// The card of [id] (a neutral event), created at the end when new.
  ToolItem _neutral(
    String id,
    String group,
    String name,
    Map<String, dynamic> input,
    DateTime now,
  ) {
    final old = _tools[id];
    if (old != null) return old;
    _finishLive(null);
    _finishThinking(null);
    final t = ToolItem(id: id, name: name, input: input, at: now);
    if (_deniedIds.contains(group)) t.denied = true;
    _tools[id] = t;
    _groups.putIfAbsent(group, () => []).add(t);
    items.add(t);
    return t;
  }

  /// One card per file (R1, R9). Later events of the same file update it.
  void _applyFile(FileChangeEvent e, DateTime now) {
    final id = e.index == 0 ? e.toolUseId : '${e.toolUseId}#${e.index}';
    final t = _neutral(id, e.toolUseId, NeutralToolNames.file, {
      'path': e.path,
    }, now);
    t.change = e;
    switch (e.status) {
      case FileChangeStatus.proposed:
        break;
      case FileChangeStatus.applied:
        t
          ..result = ''
          ..isError = false
          ..doneAt = now;
      case FileChangeStatus.failed:
        t
          ..result = ''
          ..isError = true
          ..doneAt = now;
      case FileChangeStatus.declined:
        t
          ..result = ''
          ..denied = true
          ..doneAt = now;
    }
  }

  void _applyCommand(CommandEvent e, DateTime now) {
    final t = _neutral(e.toolUseId, e.toolUseId, NeutralToolNames.command, {
      'command': e.displayCommand,
      'cwd': ?e.cwd,
    }, now);
    t.commandEvent = e;
    if (!e.done) return;
    t
      ..result = e.output ?? ''
      ..isError = e.failed
      ..doneAt = now;
    if (e.status == CommandStatus.declined) t.denied = true;
  }

  /// R6: collapsed, with the type and the one-line summary.
  void _applyOther(OtherItemEvent e, DateTime now) {
    final id = e.toolUseId.isEmpty ? 'other-${items.length}' : e.toolUseId;
    final summary = e.summary.isEmpty ? '' : ' · "${e.summary}"';
    final t = _neutral(id, id, NeutralToolNames.other, {
      'description': '${e.itemType}$summary',
    }, now);
    t
      ..other = e
      ..result = e.summary
      ..doneAt = now;
  }

  /// Notice of a `system/compact_boundary` (SPEC-082 R2).
  static const compactionNotice = 'Contexto compactado';

  void _recordContext(AssistantMessage e) {
    if (e.parentToolUseId != null) return;
    if (e.json['message'] case {'usage': final Map<String, dynamic> u}) {
      final usage = Usage.fromJson(u);
      final ctx =
          usage.inputTokens +
          usage.cacheReadInputTokens +
          usage.cacheCreationInputTokens;
      if (ctx > 0) contextTokens.add((items: items.length, tokens: ctx));
    }
  }

  void _finishLive(String? parent) {
    final live = _live.remove(parent);
    if (live != null) live.live = false;
  }

  void _finishThinking(String? parent) {
    final live = _liveThinking.remove(parent);
    if (live != null) live.live = false;
  }

  void _applyApp(Map<String, dynamic> j, DateTime now) {
    final at = DateTime.tryParse('${j['at']}')?.toLocal() ?? now;
    switch (j['type']) {
      case AppEventTypes.user:
        items.add(UserItem('${j['text'] ?? ''}', at: at));
      case AppEventTypes.denied:
        final id = j['tool_use_id'];
        if (id is String) _deniedIds.add(id);
        _tools[id]?.denied = true;
        for (final t in _groups[id] ?? const <ToolItem>[]) {
          t.denied = true;
        }
      case AppEventTypes.compare when j['status'] == 'chosen':
        _applyCompare(j, at);
      case AppEventTypes.note:
        items.add(
          NoticeItem(
            '${j['text'] ?? ''}',
            level: j['level'] == 'error' ? NoticeLevel.error : NoticeLevel.info,
            provider: j['provider'] as String?,
            at: at,
          ),
        );
      case AppEventTypes.secrets:
        final block = '${j['block'] ?? ''}';
        final item = SecretBlockItem(
          block: block,
          action: '${j['action'] ?? 'commit'}',
          command: j['command'] as String?,
          partial: j['partial'] == true,
          provider: j['provider'] as String?,
          findings: [
            if (j['findings'] case final List l)
              for (final f in l) ?SecretFinding.fromJson(f),
          ],
          at: at,
        );
        _secretBlocks[block] = item;
        items.add(item);
      case AppEventTypes.secretResolved:
        final b = _secretBlocks['${j['block']}'];
        final how = '${j['how'] ?? ''}';
        b?.resolved['${j['path']}\u0000${j['finding']}'] = how;
        final text = j['text'];
        if (text is String && text.isNotEmpty) {
          items.add(NoticeItem(text, at: at));
        }
    }
  }

  /// The prompt, the card and the note of the chosen side (SPEC-079 R11).
  void _applyCompare(Map<String, dynamic> j, DateTime at) {
    final sides = [
      for (final s in (j['sides'] as List?) ?? const [])
        if (s is Map) s,
    ];
    String label(Map s) {
      final m = '${s['model'] ?? ''}';
      final model = m.isEmpty || m == 'inherit'
          ? 'Padrão'
          : m[0].toUpperCase() + m.substring(1);
      final mode = switch (s['mode']) {
        'plan' => 'Planejar',
        'edit' => 'Editar',
        _ => 'Perguntar',
      };
      return '$model · $mode';
    }

    final chosen = sides.where((s) => s['letter'] == j['chosen']).firstOrNull;
    final other = sides.where((s) => s['letter'] != j['chosen']).firstOrNull;
    items
      ..add(UserItem('${j['prompt'] ?? ''}', at: at))
      ..add(
        CompareItem(
          j,
          other == null
              ? 'Comparação'
              : 'Comparação: ${label(other)} (não escolhida)',
          at: at,
        ),
      );
    if (chosen != null) {
      items.add(
        NoticeItem(
          'escolhida entre ${sides.length} · ${label(chosen)}',
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
    // SPEC-096 R7: an interrupted turn is not a failure.
    if (r.isInterrupted) {
      return NoticeItem(
        r.interruptReason == 'user'
            ? 'Interrompido por você · dá para continuar'
            : 'Interrompido · dá para continuar',
        level: NoticeLevel.info,
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
