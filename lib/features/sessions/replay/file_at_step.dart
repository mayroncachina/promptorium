import 'package:flutter/foundation.dart';

import '../../../core/claude/claude_event.dart' show FileChangeKind;
import '../../../core/text/line_diff.dart';
import '../../../core/text/unified_diff.dart';
import '../edit_diff.dart';
import 'replay_step.dart';

/// Where the text before the edits came from (SPEC-082 R7, P2).
enum FileBaseSource {
  /// The restore point of the start of the turn (SPEC-110 R2): the exact
  /// file before the turn, for any provider.
  restorePoint('ponto de restauração'),
  transcript('jsonl do Claude Code'),
  startSha('início da etapa'),

  /// The file as it is now with the Codex diffs undone (SPEC-095 P4).
  reverseDiff('reconstruído pelo diff'),
  baseBranch('branch base');

  const FileBaseSource(this.label);

  final String label;
}

/// Text of a file before the edit step [fromStep] (the edits from it on are
/// applied over [text]); [text] null = the file did not exist.
@immutable
class FileBase {
  const FileBase({
    required this.text,
    required this.source,
    this.fromStep = 0,
    this.detail,
  });

  final String? text;
  final FileBaseSource source;

  /// Flat position (in [flattenSteps]) of the first edit applied over it.
  final int fromStep;

  /// "a1b2c3d", "main"…
  final String? detail;

  String get label => switch (source) {
    // "ponto de restauração do turno 3 (14:30)"
    FileBaseSource.restorePoint when detail != null =>
      '${source.label} do $detail',
    _ => detail == null ? source.label : '${source.label} ($detail)',
  };

  /// Short name inside a message: "ponto do turno 3".
  String get shortLabel => switch (source) {
    FileBaseSource.restorePoint when detail != null =>
      'ponto do ${detail!.split(' (').first}',
    _ => label,
  };
}

/// A restore point the base can come from (SPEC-110 R2): the start of the
/// turn [turn], taken before the event [seq] of the session.
@immutable
class RestoreBase {
  const RestoreBase({
    required this.turn,
    required this.seq,
    required this.sha,
    this.at,
  });

  final int turn;

  /// `seq` of the message that opened the turn.
  final int seq;

  /// Commit with the whole working tree at the start of the turn.
  final String sha;
  final DateTime? at;

  String get detail =>
      'turno $turn${at == null ? '' : ' (${clock(at!.toLocal())})'}';
}

/// The file as it was right after a step (R7).
@immutable
class FileAtStep {
  const FileAtStep.ok(this.text, this.highlighted, {this.base}) : reason = null;

  const FileAtStep.failed(this.reason, {this.base})
    : text = null,
      highlighted = const {};

  /// Whole file text (null = could not be rebuilt).
  final String? text;

  /// 1-based lines written by the step.
  final Set<int> highlighted;

  /// Why it could not be rebuilt.
  final String? reason;
  final FileBase? base;

  bool get ok => text != null;
}

/// Edit steps of [path] (subagents included), in order, with their flat
/// position. A moved file (Codex `move_path`) keeps the edits it had under
/// the old name.
List<ReplayStep> editsOf(List<ReplayStep> steps, String path, {String? root}) {
  var key = absolutePath(path, root);
  final out = <ReplayStep>[];
  for (final s in flattenSteps(steps).toList().reversed) {
    final p = s.filePath;
    if (s.kind != ReplayKind.edit || p == null) continue;
    if (absolutePath(p, root) != key) continue;
    out.add(s);
    final from = s.tool?.change?.fromPath;
    if (from != null && editApplied(s.tool!)) key = absolutePath(from, root);
  }
  return out.reversed.toList();
}

/// Rebuilds [path] right after the edit [target], applying [edits] (from
/// [editsOf]) in order over [base] (R7). Only applied edits count; the base
/// covers the edits before `base.fromStep`.
FileAtStep fileAtStep({
  required FileBase? base,
  required List<ReplayStep> edits,
  required ReplayStep target,
}) {
  final stop = edits.indexOf(target);
  if (stop < 0) {
    return FileAtStep.failed('Este passo não edita o arquivo.', base: base);
  }
  final from = (base?.fromStep ?? 0).clamp(0, stop);
  String? text = base?.text;
  var known = base != null;
  String? before;
  for (var i = from; i <= stop; i++) {
    final s = edits[i];
    final t = s.tool!;
    if (!editApplied(t)) {
      if (i == stop) {
        return FileAtStep.failed(
          s.outcome == ReplayOutcome.denied
              ? 'A edição deste passo foi negada: o arquivo não mudou.'
              : 'A edição deste passo não foi aplicada.',
          base: base,
        );
      }
      continue;
    }
    if (!known && !createsFile(t)) {
      if (t.change != null) {
        return FileAtStep.failed(
          'Conteúdo anterior indisponível: o diff do Codex não se aplica ao '
          'contrário sobre o arquivo do passo seguinte, e a sessão não tem '
          'commit de início nem branch base com o arquivo.',
          base: base,
        );
      }
      return FileAtStep.failed(
        'Não há conteúdo anterior: o Claude Code não tem mais a transcrição '
        'desta sessão e ela não tem commit de início nem branch base com o '
        'arquivo.',
        base: base,
      );
    }
    if (known && text == null && !createsFile(t)) {
      return FileAtStep.failed(
        'O arquivo não existe na base (${base?.label ?? ''}) e o passo '
        '${s.index + 1} o edita.',
        base: base,
      );
    }
    before = text;
    final after = applyToolEdit(t, text);
    if (after == null) {
      if (t.change != null) {
        return FileAtStep.failed(_diffFailure(s, text, base), base: base);
      }
      return FileAtStep.failed(
        'A edição do passo ${_stepLabel(s)} não se aplica: o trecho antigo '
        'não está no arquivo (outro comando pode tê-lo mudado).',
        base: base,
      );
    }
    text = after;
    known = true;
  }
  return FileAtStep.ok(text!, _addedLines(before ?? '', text), base: base);
}

/// Why the diff of [s] does not apply over [text] (SPEC-110 R2).
String _diffFailure(ReplayStep s, String? text, FileBase? base) {
  final change = s.tool!.change!;
  final no = _stepLabel(s);
  if (change.isCut) {
    return 'O diff do passo $no foi cortado ao ser guardado '
        '(${change.cutLabel}): não dá para aplicar. O diff do passo '
        'continua abaixo.';
  }
  final where = base == null ? '' : ' (${base.shortLabel})';
  final line = applyHunks(text, parseHunks(change.unifiedDiff ?? '')).line;
  final why = line == null ? '' : ': a linha $line já era diferente';
  return 'O diff do passo $no não se aplica sobre a base$where$why. O diff '
      'do passo continua abaixo.';
}

String _stepLabel(ReplayStep s) => s.parent == null
    ? '${s.index + 1}'
    : '${s.parent!.index + 1}.${s.index + 1}';

/// 1-based lines of [after] added relative to [before].
Set<int> _addedLines(String before, String after) {
  final out = <int>{};
  var line = 0;
  for (final d in lineDiff(before, after)) {
    switch (d.op) {
      case DiffOp.same:
        line++;
      case DiffOp.add:
        out.add(++line);
      case DiffOp.del:
        break;
    }
  }
  return out;
}

/// Lines of the new text of an edit.
Iterable<String> _newLines(ReplayStep s) sync* {
  final input = s.tool?.input ?? const {};
  Iterable<String> split(Object? v) =>
      v is String ? v.split('\n') : const <String>[];
  final diff = s.tool?.change?.unifiedDiff;
  if (diff != null) {
    for (final h in parseHunks(diff)) {
      for (final l in h.lines) {
        if (l.op == DiffOp.add) yield l.text;
      }
    }
    return;
  }
  switch (s.toolName) {
    case 'Edit':
      yield* split(input['new_string']);
    case 'Write':
      yield* split(input['content']);
    case 'MultiEdit':
      final edits = input['edits'];
      if (edits is List) {
        for (final e in edits) {
          if (e is Map) yield* split(e['new_string']);
        }
      }
    case 'NotebookEdit':
      yield* split(input['new_source']);
  }
}

/// Who wrote a line of the final diff (R8, P5).
@immutable
class WhoWrote {
  const WhoWrote({this.edit, this.command});

  /// The last applied edit whose new text has the line.
  final ReplayStep? edit;

  /// No edit wrote it: the command it most likely came from (null = none).
  final ReplayStep? command;

  bool get fromCommand => edit == null;
}

/// The edit of [path] whose new text contains [line] (the last one, when
/// several do); otherwise "veio de um comando", with the most likely `Bash`
/// (P5). Blank lines are nobody's.
WhoWrote? whoWroteLine(
  List<ReplayStep> steps,
  String path,
  String line, {
  String? root,
}) {
  final wanted = line.trim();
  if (wanted.isEmpty) return null;
  final edits = editsOf(steps, path, root: root);
  for (final s in edits.reversed) {
    if (!s.isAppliedEdit) continue;
    if (_newLines(s).any((l) => l.trim() == wanted)) return WhoWrote(edit: s);
  }
  return WhoWrote(
    command: flattenSteps(steps).any((s) => s.tool?.isNeutral ?? false)
        ? _commandBefore(steps, edits, wanted)
        : _likelyCommand(steps, path),
  );
}

/// Codex (SPEC-110 R3): the last command (Rodar) before the line shows up —
/// an edit whose diff already has it as context (or removes it) came after.
/// No such edit: the last command of the session.
ReplayStep? _commandBefore(
  List<ReplayStep> steps,
  List<ReplayStep> edits,
  String wanted,
) {
  ReplayStep? showsUp;
  for (final s in edits) {
    final diff = s.tool?.change?.unifiedDiff;
    if (diff == null) continue;
    if (parseHunks(diff)
        .any((h) => h.oldLines.any((l) => l.trim() == wanted))) {
      showsUp = s;
      break;
    }
  }
  ReplayStep? last;
  for (final s in flattenSteps(steps)) {
    if (identical(s, showsUp)) break;
    if (s.kind == ReplayKind.run && s.outcome != ReplayOutcome.denied) last = s;
  }
  return last;
}

final _rewriters = RegExp(
  r'\b(format|fix|build_runner|codegen|generate|sed|perl|prettier|eslint|'
  r'black|ruff|gofmt|rustfmt)\b',
);

ReplayStep? _likelyCommand(List<ReplayStep> steps, String path) {
  final runs = [
    for (final s in flattenSteps(steps))
      if (s.kind == ReplayKind.run && s.outcome != ReplayOutcome.denied) s,
  ];
  if (runs.isEmpty) return null;
  final name = baseName(path);
  for (final s in runs.reversed) {
    if (s.target.contains(name)) return s;
  }
  for (final s in runs.reversed) {
    if (_rewriters.hasMatch(s.target)) return s;
  }
  return runs.last;
}

/// Looks up the base text of a file for "Arquivo neste ponto" (P2, SPEC-110
/// R2): the restore point of the start of the turn, the `originalFile` of
/// the transcript (Claude), the commit where the step started, then the
/// session's base branch.
class FileBaseResolver {
  FileBaseResolver({
    required this.originalFiles,
    required this.showAt,
    this.startSha,
    this.baseRef,
    this.baseBranch,
    this.root,
    this.readFile,
    this.points,
  });

  /// Restore points of the session, oldest first (SPEC-110 R2).
  final Future<List<RestoreBase>> Function()? points;

  /// The file as it is now (absolute path; null when missing), for the
  /// Codex diffs undone (P4).
  final Future<String?> Function(String path)? readFile;

  /// `tool_use_id` → `originalFile` from the transcript (loaded on demand;
  /// empty when there is none).
  final Future<Map<String, String>> Function() originalFiles;

  /// `git show <rev>:<path>` (null when the file is not there or git
  /// fails).
  final Future<String?> Function(String rev, String path) showAt;

  /// `spec_steps.startSha` of the session.
  final String? startSha;

  /// Commit of the base branch to use (merge-base), null = [baseBranch].
  final Future<String?> Function()? baseRef;
  final String? baseBranch;

  /// Worktree path (git paths are relative to it).
  final String? root;

  /// Base for the edits of [path] up to [target] ([edits] from [editsOf]).
  /// Null when nothing has the file.
  Future<FileBase?> resolve(
    String path,
    List<ReplayStep> edits,
    ReplayStep target,
  ) async {
    final stop = edits.indexOf(target);
    if (stop < 0) return null;
    // 1. The restore point of the start of the turn (SPEC-110 R2, P6).
    final point = await _fromPoint(path, edits, stop);
    if (point != null) {
      // Claude: a command that rewrote the file inside the turn (a
      // formatter) breaks the sequence; the `originalFile` of the edit
      // itself is exact there.
      if (edits[stop].tool?.change != null ||
          fileAtStep(base: point, edits: edits, target: target).ok) {
        return point;
      }
    }
    // 2. Transcript: the latest edit up to the target with its originalFile
    // (exact even when a command changed the file in between).
    Map<String, String> originals;
    try {
      originals = await originalFiles();
    } catch (_) {
      originals = const {};
    }
    for (var i = stop; i >= 0; i--) {
      final id = edits[i].tool?.id;
      final text = id == null ? null : originals[id];
      if (text != null) {
        return FileBase(
          text: text,
          source: FileBaseSource.transcript,
          fromStep: i,
        );
      }
    }
    if (point != null) return point;
    // Codex (SPEC-095 P4), without a point: the file now with the diffs from the last
    // edit back to the target undone.
    final reversed = await _reverse(path, edits, stop);
    if (reversed != null) return reversed;
    final rel = relativePath(absolutePath(path, root), root);
    if (rel.startsWith('/')) return null;
    // 3. The commit where the step started.
    if (startSha != null) {
      final text = await showAt(startSha!, rel);
      return FileBase(
        text: text,
        source: FileBaseSource.startSha,
        detail: _short(startSha!),
      );
    }
    // 4. The base branch.
    if (baseBranch != null) {
      final rev = await baseRef?.call() ?? baseBranch!;
      final text = await showAt(rev, rel);
      return FileBase(
        text: text,
        source: FileBaseSource.baseBranch,
        detail: baseBranch,
      );
    }
    return null;
  }
}

extension on FileBaseResolver {
  /// The file in the newest point taken before edit [stop] (its turn's
  /// start), with the edits of the file from that point on to apply. Null
  /// without a point, or when the point does not have the file and the
  /// first edit does not create it (ignored by git, too big: left out).
  Future<FileBase?> _fromPoint(
    String path,
    List<ReplayStep> edits,
    int stop,
  ) async {
    final load = points;
    if (load == null) return null;
    int? seqOf(ReplayStep s) => (s.parent ?? s).item.seq;
    final seq = seqOf(edits[stop]);
    if (seq == null) return null;
    final List<RestoreBase> all;
    try {
      all = await load();
    } catch (_) {
      return null;
    }
    RestoreBase? point;
    for (final p in all) {
      if (p.seq < seq && (point == null || p.seq > point.seq)) point = p;
    }
    if (point == null) return null;
    var from = stop;
    while (from > 0 && (seqOf(edits[from - 1]) ?? -1) > point.seq) {
      from--;
    }
    // The name the file had at the point (it may have been moved since).
    final first = edits[from];
    final name = first.tool?.change?.fromPath ?? first.filePath ?? path;
    final rel = relativePath(absolutePath(name, root), root);
    if (rel.startsWith('/')) return null;
    String? text;
    try {
      text = await showAt(point.sha, rel);
    } catch (_) {
      return null;
    }
    if (text == null && !createsFile(first.tool!)) return null;
    return FileBase(
      text: text,
      source: FileBaseSource.restorePoint,
      detail: point.detail,
      fromStep: from,
    );
  }

  /// The text before edit [stop] rebuilt from the current file, when every
  /// edit of the file from it on is a Codex diff that undoes cleanly.
  Future<FileBase?> _reverse(
    String path,
    List<ReplayStep> edits,
    int stop,
  ) async {
    final read = readFile;
    if (read == null) return null;
    final later = edits.sublist(stop);
    if (later.any((s) => s.tool?.change == null)) return null;
    String? text;
    try {
      text = await read(absolutePath(path, root));
    } catch (_) {
      return null;
    }
    for (final s in later.reversed) {
      final t = s.tool!;
      if (!editApplied(t)) continue;
      final c = t.change!;
      if (c.kind == FileChangeKind.add) {
        text = null; // the file did not exist before it
        continue;
      }
      final diff = c.unifiedDiff;
      if (text == null || diff == null || c.isCut) return null;
      text = reverseUnifiedDiff(text, diff);
      if (text == null) return null;
    }
    return FileBase(
      text: text,
      source: FileBaseSource.reverseDiff,
      fromStep: stop,
    );
  }
}

String _short(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;
