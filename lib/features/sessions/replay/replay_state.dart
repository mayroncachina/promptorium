import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../edit_diff.dart';
import '../../context/context_snapshot.dart';
import 'replay_step.dart';

/// A file in "Já leu" / "Já editou" (SPEC-082 R6).
@immutable
class ReplayFileStat {
  const ReplayFileStat({
    required this.path,
    this.reads = 0,
    this.edits = 0,
    this.added = 0,
    this.removed = 0,
    this.editedWithoutRead = false,
    this.firstEdit,
    this.via = const [],
    this.folder = false,
  });

  /// Absolute path (or as the tool gave it).
  final String path;

  /// Programs of the commands that read it, in order ("sed", "cat";
  /// SPEC-110 R1). Empty = only by the read tool.
  final List<String> via;

  /// A folder searched or listed by a command, not a file read.
  final bool folder;
  final int reads;
  final int edits;
  final int added;
  final int removed;

  /// Edited before any read of it in the session (R6).
  final bool editedWithoutRead;

  /// Index of the first edit step.
  final int? firstEdit;

  ReplayFileStat copyWith({
    int? reads,
    int? edits,
    int? added,
    int? removed,
    bool? editedWithoutRead,
    int? firstEdit,
    List<String>? via,
  }) => ReplayFileStat(
    path: path,
    via: via ?? this.via,
    folder: folder,
    reads: reads ?? this.reads,
    edits: edits ?? this.edits,
    added: added ?? this.added,
    removed: removed ?? this.removed,
    editedWithoutRead: editedWithoutRead ?? this.editedWithoutRead,
    firstEdit: firstEdit ?? this.firstEdit,
  );
}

/// What the agent had done up to a step (R6).
@immutable
class ReplayState {
  const ReplayState({
    this.read = const [],
    this.edited = const [],
    this.lastCommand,
    this.contextTokens,
    this.compactions = 0,
    this.reading,
    this.compactedSince = false,
    this.capacity,
    this.measures = false,
  });

  /// Files read up to here, in the order of the first read.
  final List<ReplayFileStat> read;

  /// Files edited up to here, in the order of the first edit.
  final List<ReplayFileStat> edited;

  /// Last `Bash` before the step (not the step itself).
  final ReplayStep? lastCommand;

  /// Context tokens of the last answer before the step.
  final int? contextTokens;

  /// Compactions up to the step.
  final int compactions;

  /// The reading of the selected point (SPEC-087 R6): never the session's
  /// current state.
  final ContextReading? reading;

  /// A compaction came after [reading] and before the step: the window is
  /// waiting for a measurement there.
  final bool compactedSince;

  /// Capacity reported for the session's model (null = unknown, no %).
  final int? capacity;

  /// The agent reports its context after each call (Codex, SPEC-110 R5):
  /// without a reading, the point is "aguardando medição", never 0.
  final bool measures;
}

/// State of the session at step [index] of the top-level [steps] (R6).
/// The reads and edits include the step itself; the last command is the
/// last one before it. [context] is `Timeline.contextTokens`.
ReplayState replayStateAt(
  List<ReplayStep> steps,
  int index, {
  List<({int items, int tokens})> context = const [],
  ContextSnapshot? ctx,
  String? root,
}) {
  if (steps.isEmpty) return const ReplayState();
  final end = index.clamp(0, steps.length - 1);
  final read = <String, ReplayFileStat>{};
  final edited = <String, ReplayFileStat>{};
  // Absolute paths of the files read (the two providers write them in
  // different ways).
  final seen = <String>{};
  ReplayStep? lastCommand;
  var compactions = 0;
  for (var i = 0; i <= end; i++) {
    final s = steps[i];
    if (s.kind == ReplayKind.run && i < end) lastCommand = s;
    if (s.mark == ReplayMarkKind.compaction) compactions++;
    if (countsReads(s)) {
      for (final r in s.reads) {
        if (r.path.isEmpty) continue;
        // A folder never hides a file of the same path.
        final key = r.isFile ? r.path : '${r.path}/';
        final old =
            read[key] ?? ReplayFileStat(path: r.path, folder: !r.isFile);
        final by = r.program;
        read[key] = old.copyWith(
          reads: old.reads + 1,
          via: by.isEmpty || old.via.contains(by) ? null : [...old.via, by],
        );
        if (r.isFile) seen.add(r.path);
      }
      continue;
    }
    final path = s.filePath;
    if (path == null) continue;
    if (s.toolName == 'Read' && s.outcome == ReplayOutcome.ok) {
      final r = read[path] ?? ReplayFileStat(path: path);
      read[path] = r.copyWith(reads: r.reads + 1);
      seen.add(absolutePath(path, root));
    } else if (s.isAppliedEdit) {
      final e = edited[path];
      if (e == null) {
        // A Write of a new file needs no read.
        final blind =
            !seen.contains(absolutePath(path, root)) &&
            !_movedSeen(s, seen, root) &&
            !createsFile(s.tool!);
        edited[path] = ReplayFileStat(
          path: path,
          edits: 1,
          added: s.added ?? 0,
          removed: s.removed ?? 0,
          editedWithoutRead: blind,
          firstEdit: s.index,
        );
      } else {
        edited[path] = e.copyWith(
          edits: e.edits + 1,
          added: e.added + (s.added ?? 0),
          removed: e.removed + (s.removed ?? 0),
        );
      }
    }
  }
  int? tokens;
  final item = steps[end].itemIndex;
  if (item >= 0) {
    for (final c in context) {
      if (c.items > item) break;
      tokens = c.tokens;
    }
  }
  // SPEC-087 R6: the reading at the step, from the history's readings;
  // a compaction after it leaves the point waiting for a measurement.
  ContextReading? reading;
  var compactedSince = false;
  if (ctx != null && item >= 0) {
    for (final r in ctx.readings) {
      if (r.itemIndex > item) break;
      reading = r;
    }
    for (final m in ctx.markers) {
      if (m.kind != ContextMarkerKind.compaction) continue;
      if (m.itemIndex <= item &&
          (reading == null ||
              m.readingsBefore > ctx.readings.indexOf(reading))) {
        compactedSince = true;
      }
    }
    // SPEC-110 R10: the conversation went back after the reading.
    var revertedAt = -1;
    for (var i = 0; i <= end; i++) {
      if (steps[i].mark == ReplayMarkKind.reverted) {
        revertedAt = steps[i].itemIndex;
      }
    }
    if (reading != null && reading.itemIndex <= revertedAt) {
      reading = null;
      compactedSince = false;
    }
    tokens = compactedSince ? null : reading?.tokens;
  }
  return ReplayState(
    read: read.values.toList(),
    edited: edited.values.toList(),
    lastCommand: lastCommand,
    contextTokens: tokens,
    compactions: compactions,
    reading: compactedSince ? null : reading,
    compactedSince: compactedSince,
    capacity: reading?.window ?? ctx?.capacity,
    measures:
        ctx?.provider == 'codex' || steps.any((s) => s.agent == 'Codex'),
  );
}

/// Whether the reads of a command count in "Já leu" (SPEC-110 R1): a read
/// that worked, or the reads of a command that also does something else
/// (whose exit code is about the rest). Denied or unfinished: no.
bool countsReads(ReplayStep s) =>
    s.reads.isNotEmpty &&
    (s.outcome == ReplayOutcome.ok ||
        (s.kind == ReplayKind.run && s.outcome == ReplayOutcome.error));

/// A moved file read under its old name.
bool _movedSeen(ReplayStep s, Set<String> seen, String? root) {
  final from = s.tool?.change?.fromPath;
  return from != null && seen.contains(absolutePath(from, root));
}

/// Step filters above the list (R9).
enum ReplayFilter {
  all('Tudo'),
  edits('Edições'),
  commands('Comandos'),
  reads('Leituras'),
  errors('Erros');

  const ReplayFilter(this.label);

  final String label;

  bool matches(ReplayStep s) => switch (this) {
    ReplayFilter.all => true,
    ReplayFilter.edits => s.kind == ReplayKind.edit,
    ReplayFilter.commands => s.kind == ReplayKind.run,
    ReplayFilter.reads => s.kind == ReplayKind.read,
    ReplayFilter.errors => s.isProblem,
  };
}

/// Whether [s] passes the [filter], the search [query] (file or command)
/// and the chosen [file] (R8, R9).
bool replayStepVisible(
  ReplayStep s, {
  ReplayFilter filter = ReplayFilter.all,
  String query = '',
  String? file,
  String? root,
}) {
  if (!filter.matches(s)) return false;
  if (file != null && !stepTouches(s, file, root: root)) return false;
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return s.target.toLowerCase().contains(q) ||
      (s.filePath?.toLowerCase().contains(q) ?? false);
}

/// Where the cursor of one session's replay is (R4: kept while the app
/// runs, so going back to the tab goes back to the same step).
@immutable
class ReplayCursor {
  const ReplayCursor({
    this.index,
    this.child,
    this.openSubagent,
    this.filter = ReplayFilter.all,
    this.query = '',
    this.file,
  });

  /// Top-level step (null = the last one).
  final int? index;

  /// Step inside the open subagent (P7), null = the subagent step itself.
  final int? child;

  /// Top-level index of the subagent shown in its own lane.
  final int? openSubagent;
  final ReplayFilter filter;
  final String query;

  /// File chosen in "Resultado" (R8).
  final String? file;

  ReplayCursor copyWith({
    int? Function()? index,
    int? Function()? child,
    int? Function()? openSubagent,
    ReplayFilter? filter,
    String? query,
    String? Function()? file,
  }) => ReplayCursor(
    index: index == null ? this.index : index(),
    child: child == null ? this.child : child(),
    openSubagent: openSubagent == null ? this.openSubagent : openSubagent(),
    filter: filter ?? this.filter,
    query: query ?? this.query,
    file: file == null ? this.file : file(),
  );
}

class ReplayCursorController extends Notifier<ReplayCursor> {
  ReplayCursorController(this.sessionId);

  final String sessionId;

  @override
  ReplayCursor build() => const ReplayCursor();

  void set(ReplayCursor c) => state = c;

  /// Back to the last step, no filter (the entries of R12).
  void reset() => state = const ReplayCursor();
}

final replayCursorProvider =
    NotifierProvider.family<ReplayCursorController, ReplayCursor, String>(
      ReplayCursorController.new,
    );

/// Path key used to compare files across tools (absolute under [root]).
String fileKey(String path, String? root) => absolutePath(path, root);
