import '../../../core/claude/claude_event.dart'
    show CommandAction, CommandEvent, FileChangeKind;
import '../edit_diff.dart';
import '../timeline.dart';

/// Kind of a replay step (SPEC-082 R2).
enum ReplayKind {
  read('Ler', 'L'),
  edit('Editar', 'E'),
  run('Rodar', 'R'),
  web('Web', 'W'),
  subagent('Subagente', 'S'),
  plan('Plano', 'P'),
  other('Outra', 'O'),
  user('Você', 'V'),
  assistant('Claude', 'C'),
  thinking('Raciocínio', 'P'),
  mark('Aviso', '!');

  const ReplayKind(this.label, this.letter);

  final String label;

  /// Letter of the badge (the color is never the only sign, R3).
  final String letter;

  bool get isTool => index <= other.index;
  bool get isTalk => this == user || this == assistant || this == thinking;
}

/// Lane of the scrubber where a step is drawn (R3). Marks are flags above
/// the lanes.
enum ReplayLane {
  read('Ler'),
  edit('Editar'),
  run('Rodar'),
  talk('Conversa');

  const ReplayLane(this.label);

  final String label;
}

/// What came of a step (R2).
enum ReplayOutcome {
  ok,
  error,
  denied,

  /// "sem resposta": a tool call that never got a result.
  pending,
}

/// App notices that are marks (R2).
enum ReplayMarkKind {
  info,
  error,
  gatePassed,
  gateFailed,
  compaction,
  resume,

  /// A turn stopped before its end (Codex `interrupted`, SPEC-110 R1).
  interrupted,

  /// The agent's conversation went back (SPEC-110 R10).
  reverted;

  /// Drawn as a flag above the lanes (R3).
  bool get isFlag =>
      this == gatePassed ||
      this == gateFailed ||
      this == compaction ||
      this == resume ||
      this == interrupted ||
      this == reverted;
}

/// One read, search or listing made by a command (SPEC-110 R1).
class CommandRead {
  const CommandRead({
    required this.type,
    required this.path,
    this.query,
    this.command = '',
  });

  /// [CommandAction.read], `search` or `listFiles`.
  final String type;

  /// Absolute path of the file or folder ('' = not told).
  final String path;

  /// Text of a search.
  final String? query;

  /// The part of the command that does it.
  final String command;

  bool get isFile => type == CommandAction.read;

  /// "sed", "rg", "cat": the program that read it.
  String get program {
    final first = command.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? '' : baseName(first);
  }

  /// "sed -n", "cat" (the list of steps).
  String get via => program == 'sed' && RegExp(r'\s-n\b').hasMatch(command)
      ? 'sed -n'
      : program;

  /// "1–80" of `sed -n 1,80p` (null = the whole file or unknown).
  String? get range {
    if (program != 'sed') return null;
    final m = RegExp(r'(\d+),(\d+)p').firstMatch(command);
    return m == null ? null : '${m.group(1)}–${m.group(2)}';
  }

  /// What the step shows: `tabela.dart 1–80`, `"calcularFrete" lib/`.
  String label(String? root) {
    final rel = path.isEmpty ? '.' : relativePath(path, root);
    return switch (type) {
      CommandAction.read => [baseName(path), ?range].join(' '),
      CommandAction.search => '"${query ?? ''}" $rel',
      _ => rel,
    };
  }
}

/// Reads of a command, with absolute paths.
List<CommandRead> commandReadsOf(CommandEvent? e, {String? root}) {
  if (e == null) return const [];
  final cwd = e.cwd ?? root;
  String abs(String? p) {
    if (p == null || p.isEmpty) return '';
    final a = absolutePath(p, cwd);
    return a.length > 1 && a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  }

  if (e.actions.isEmpty) {
    return [
      for (final p in e.reads)
        CommandRead(type: CommandAction.read, path: abs(p)),
    ];
  }
  return [
    for (final a in e.actions)
      CommandRead(
        type: a.type,
        path: abs(a.path),
        query: a.query,
        command: a.command ?? '',
      ),
  ];
}

/// One step of the replay: a tool call, a message of the conversation or a
/// mark of the app (R2).
class ReplayStep {
  ReplayStep({
    required this.index,
    required this.kind,
    required this.item,
    required this.turn,
    required this.target,
    this.at,
    this.duration,
    this.outcome = ReplayOutcome.ok,
    this.mark,
    this.added,
    this.removed,
    this.itemIndex = -1,
    this.children = const [],
    this.parent,
    this.reads = const [],
    this.agent = 'Claude',
  });

  /// Position in its list (0-based; the UI shows `index + 1`).
  final int index;
  final ReplayKind kind;

  /// The timeline item it comes from.
  final TimelineItem item;

  /// 1-based turn (a turn starts at each message of the person or the app).
  final int turn;

  /// File, pattern, command or the first line of the text.
  final String target;
  final DateTime? at;
  final Duration? duration;
  final ReplayOutcome outcome;
  final ReplayMarkKind? mark;

  /// Lines added / removed by an edit.
  final int? added;
  final int? removed;

  /// Position of [item] in the top-level timeline items (-1 = nested).
  final int itemIndex;

  /// Steps of a subagent (P7: collapsed into this one step).
  final List<ReplayStep> children;

  /// The subagent step this one belongs to (null = top level).
  final ReplayStep? parent;

  ToolItem? get tool => item is ToolItem ? item as ToolItem : null;

  String? get toolName => tool?.name;

  /// What a command read (Codex, SPEC-110 R1): the step is **Ler** when the
  /// command only reads, **Rodar** with these listed when it does more.
  final List<CommandRead> reads;

  /// Who answers in this session ("Claude", "Codex").
  final String agent;

  /// Id of the agent's turn (Codex `turn/started`); null = unknown.
  String? get agentTurnId => (parent ?? this).item.agentTurnId;

  /// It left the agent's conversation (SPEC-110 R10).
  RevertMark? get reverted => (parent ?? this).item.reverted;

  /// What the step does, in words: the tool name, or the verb of a neutral
  /// card ("Ler", "Buscar", "Editar", "Rodar").
  String get verb {
    final t = tool;
    if (t == null) {
      return kind == ReplayKind.assistant ? agent : kind.label;
    }
    if (!t.isNeutral) return t.name;
    if (kind == ReplayKind.read && reads.isNotEmpty) {
      return switch (reads.first.type) {
        CommandAction.read => 'Ler',
        CommandAction.search => 'Buscar',
        _ => 'Listar',
      };
    }
    return kind.label;
  }

  /// "criado", "apagado", "movido" of a neutral file change ("alterado" is
  /// the usual case).
  String? get changeLabel => switch (tool?.change?.kind) {
    FileChangeKind.add => 'criado',
    FileChangeKind.update => 'alterado',
    FileChangeKind.delete => 'apagado',
    FileChangeKind.move => 'movido',
    null => null,
  };

  /// "sed -n" of a read made by a command (null otherwise).
  String? get via =>
      kind == ReplayKind.read && reads.isNotEmpty ? reads.first.via : null;

  /// Absolute or relative path of the file it reads or edits.
  String? get filePath =>
      tool?.filePath ??
      (kind == ReplayKind.read && reads.length == 1 && reads.first.isFile
          ? reads.first.path
          : null);

  ReplayLane? get lane => switch (kind) {
    ReplayKind.read || ReplayKind.web || ReplayKind.subagent => ReplayLane.read,
    ReplayKind.edit => ReplayLane.edit,
    ReplayKind.run || ReplayKind.other => ReplayLane.run,
    ReplayKind.plan ||
    ReplayKind.user ||
    ReplayKind.assistant ||
    ReplayKind.thinking => ReplayLane.talk,
    ReplayKind.mark => null,
  };

  /// Error, denied, failed gate or an error notice ("próximo erro", R4).
  bool get isProblem =>
      outcome == ReplayOutcome.error ||
      outcome == ReplayOutcome.denied ||
      mark == ReplayMarkKind.gateFailed ||
      mark == ReplayMarkKind.error;

  /// Edit applied to the file (finished, no error, not denied).
  bool get isAppliedEdit {
    final t = tool;
    return kind == ReplayKind.edit && t != null && editApplied(t);
  }

  /// "+6 −2" of an edit.
  String get statsLabel => added == null ? '' : '+$added −${removed ?? 0}';
}

/// Kind of a card (R2): the neutral events by what they are (SPEC-095
/// R9), a Claude call by its tool.
ReplayKind replayKindOfTool(ToolItem t) {
  if (t.change != null) return ReplayKind.edit;
  // SPEC-110 R1: a command that only reads, searches or lists is a read.
  if (t.commandEvent case final c?) {
    return c.onlyReads ? ReplayKind.read : ReplayKind.run;
  }
  if (t.other case final o?) {
    return o.isPlan ? ReplayKind.plan : ReplayKind.other;
  }
  return replayKindOf(t.name);
}

/// Kind of the tool [name] (R2).
ReplayKind replayKindOf(String name) => switch (name) {
  'Read' || 'Grep' || 'Glob' || 'LS' => ReplayKind.read,
  'Edit' || 'MultiEdit' || 'Write' || 'NotebookEdit' => ReplayKind.edit,
  'Bash' => ReplayKind.run,
  'WebFetch' || 'WebSearch' => ReplayKind.web,
  'Task' || 'Agent' => ReplayKind.subagent,
  'TodoWrite' || 'ExitPlanMode' => ReplayKind.plan,
  _ => ReplayKind.other,
};

/// Kind of mark of an app notice.
ReplayMarkKind replayMarkOf(NoticeItem n) {
  if (n is ConversationItem && n.data.ok) return ReplayMarkKind.reverted;
  final t = n.text;
  if (t.startsWith('Verificação aprovada')) return ReplayMarkKind.gatePassed;
  if (t.startsWith('Verificação falhou')) return ReplayMarkKind.gateFailed;
  if (t == Timeline.compactionNotice) return ReplayMarkKind.compaction;
  if (t.startsWith('Sessão retomada')) return ReplayMarkKind.resume;
  if (t.startsWith('Interrompido')) return ReplayMarkKind.interrupted;
  return n.level == NoticeLevel.error
      ? ReplayMarkKind.error
      : ReplayMarkKind.info;
}

String _firstLine(String s) {
  final line = s.trim().split('\n').first.trim();
  return line.length > 160 ? '${line.substring(0, 160)}…' : line;
}

/// Steps of a session timeline, in order (R2). Pure: computed once per
/// timeline snapshot. [root] makes the targets relative to the worktree;
/// [agent] names who answers.
///
/// SPEC-110 R1: a Codex turn starts at its `turn/started`; a message sent
/// during the turn (`turn/steer`) does not start another one.
List<ReplayStep> replaySteps(
  List<TimelineItem> items, {
  String? root,
  String agent = 'Claude',
}) {
  var turn = 0;
  var sawUser = false;
  String? turnId;
  return _steps(
    items,
    root: root,
    agent: agent,
    parent: null,
    turnOf: (item) {
      if (item is UserItem) {
        final id = item.agentTurnId;
        if (id == null || id != turnId) turn++;
        turnId = id;
        sawUser = true;
      }
      return sawUser ? turn : 1;
    },
  );
}

List<ReplayStep> _steps(
  List<TimelineItem> items, {
  required String? root,
  required String agent,
  required ReplayStep? parent,
  required int Function(TimelineItem) turnOf,
}) {
  final out = <ReplayStep>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final turn = parent?.turn ?? turnOf(item);
    final step = _stepOf(
      item,
      index: out.length,
      turn: turn,
      root: root,
      agent: agent,
      itemIndex: parent == null ? i : -1,
      parent: parent,
      next: () => i + 1 < items.length ? items[i + 1].at : null,
    );
    if (step == null) continue;
    out.add(step);
  }
  return out;
}

ReplayStep? _stepOf(
  TimelineItem item, {
  required int index,
  required int turn,
  required String? root,
  required String agent,
  required int itemIndex,
  required ReplayStep? parent,
  required DateTime? Function() next,
}) {
  Duration? until(DateTime? end) {
    final at = item.at;
    if (at == null || end == null) return null;
    final d = end.difference(at);
    return d.isNegative ? Duration.zero : d;
  }

  switch (item) {
    case ToolItem():
      final kind = replayKindOfTool(item);
      final outcome = item.denied
          ? ReplayOutcome.denied
          : item.isError
          ? ReplayOutcome.error
          : item.done
          ? ReplayOutcome.ok
          : ReplayOutcome.pending;
      final stats = item.stats;
      final children = <ReplayStep>[];
      final reads = commandReadsOf(item.commandEvent, root: root);
      final step = ReplayStep(
        index: index,
        kind: kind,
        item: item,
        turn: turn,
        agent: agent,
        reads: reads,
        target: kind == ReplayKind.read && reads.isNotEmpty
            ? reads.map((r) => r.label(root)).join(', ')
            : toolTarget(item.name, item.input, root: root),
        at: item.at,
        duration: until(item.doneAt ?? next()),
        outcome: outcome,
        added: stats?.$1,
        removed: stats?.$2,
        itemIndex: itemIndex,
        children: children,
        parent: parent,
      );
      if (item.children.isNotEmpty) {
        children.addAll(
          _steps(
            item.children,
            root: root,
            agent: agent,
            parent: step,
            turnOf: (_) => turn,
          ),
        );
      }
      return step;
    case UserItem():
      return ReplayStep(
        index: index,
        kind: ReplayKind.user,
        item: item,
        turn: turn,
        target: _firstLine(item.text),
        at: item.at,
        duration: until(next()),
        itemIndex: itemIndex,
        parent: parent,
      );
    case AssistantTextItem():
      return ReplayStep(
        index: index,
        kind: ReplayKind.assistant,
        item: item,
        turn: turn,
        agent: agent,
        target: _firstLine(item.text),
        at: item.at,
        duration: until(next()),
        itemIndex: itemIndex,
        parent: parent,
      );
    case ThinkingItem():
      return ReplayStep(
        index: index,
        kind: ReplayKind.thinking,
        item: item,
        turn: turn,
        target: _firstLine(item.text),
        at: item.at,
        duration: until(next()),
        itemIndex: itemIndex,
        parent: parent,
      );
    case NoticeItem():
      final mark = replayMarkOf(item);
      return ReplayStep(
        index: index,
        kind: ReplayKind.mark,
        item: item,
        turn: turn,
        target: mark == ReplayMarkKind.reverted
            ? 'Conversa revertida para antes do turno '
                  '${(item as ConversationItem).data.turn}'
            : _firstLine(item.text),
        at: item.at,
        outcome:
            mark == ReplayMarkKind.error || mark == ReplayMarkKind.gateFailed
            ? ReplayOutcome.error
            : ReplayOutcome.ok,
        mark: mark,
        itemIndex: itemIndex,
        parent: parent,
      );
  }
}

/// Every step, subagent steps right after their subagent, in order.
Iterable<ReplayStep> flattenSteps(List<ReplayStep> steps) sync* {
  for (final s in steps) {
    yield s;
    yield* flattenSteps(s.children);
  }
}

/// Turn starts: turn number → the user step that opened it (null when the
/// turn has no message, e.g. steps before the first one).
Map<int, ReplayStep?> turnStarts(List<ReplayStep> steps) {
  final out = <int, ReplayStep?>{};
  for (final s in steps) {
    if (s.kind == ReplayKind.user && !out.containsKey(s.turn)) {
      out[s.turn] = s;
    } else {
      out.putIfAbsent(s.turn, () => null);
    }
  }
  return out;
}

/// Whether [step] (or a step of its subagent) reads or edits [path].
bool stepTouches(ReplayStep step, String path, {String? root}) {
  final key = absolutePath(path, root);
  final p = step.filePath;
  if (p != null && absolutePath(p, root) == key) return true;
  if (step.reads.any((r) => r.isFile && r.path == key)) return true;
  return step.children.any((c) => stepTouches(c, path, root: root));
}

/// Path of [path] relative to [root], for display.
String relativePath(String path, String? root) {
  if (root != null && root.isNotEmpty && path.startsWith('$root/')) {
    return path.substring(root.length + 1);
  }
  return path;
}

/// Last segment of a path.
String baseName(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

/// Long pauses between consecutive steps (P4): index of the step after the
/// pause → its length. [min] is the shortest pause cut.
Map<int, Duration> longPauses(
  List<ReplayStep> steps, {
  Duration min = const Duration(minutes: 10),
}) {
  final out = <int, Duration>{};
  for (var i = 1; i < steps.length; i++) {
    final a = steps[i - 1], b = steps[i];
    final end = a.at == null
        ? null
        : (a.duration == null ? a.at : a.at!.add(a.duration!));
    if (end == null || b.at == null) continue;
    final gap = b.at!.difference(end);
    if (gap >= min) out[i] = gap;
  }
  return out;
}

/// "2 h", "45 min", "12 s".
String shortDuration(Duration d) {
  if (d.inHours >= 1) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

/// "14:32".
String clock(DateTime? at) {
  if (at == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.hour)}:${two(at.minute)}';
}
