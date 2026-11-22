import 'package:flutter/foundation.dart';

import '../../../core/claude/claude_event.dart' show FileChangeKind;
import '../../../core/text/line_diff.dart';
import '../../../core/text/unified_diff.dart';
import '../edit_diff.dart';
import 'replay_step.dart';

/// Where the text before the edits came from (SPEC-082 R7, P2).
enum FileBaseSource {
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

  String get label =>
      detail == null ? source.label : '${source.label} ($detail)';
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
/// position.
List<ReplayStep> editsOf(List<ReplayStep> steps, String path, {String? root}) {
  final key = absolutePath(path, root);
  return [
    for (final s in flattenSteps(steps))
      if (s.kind == ReplayKind.edit &&
          s.filePath != null &&
          absolutePath(s.filePath!, root) == key)
        s,
  ];
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
  return WhoWrote(command: _likelyCommand(steps, path));
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

/// Looks up the base text of a file for "Arquivo neste ponto" (P2): the
/// `originalFile` of the transcript, then the commit where the step
/// started, then the session's base branch.
class FileBaseResolver {
  FileBaseResolver({
    required this.originalFiles,
    required this.showAt,
    this.startSha,
    this.baseRef,
    this.baseBranch,
    this.root,
    this.readFile,
  });

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
    // 1. Transcript: the latest edit up to the target with its originalFile
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
    // 2. Codex (SPEC-095 P4): the file now with the diffs from the last
    // edit back to the target undone.
    final reversed = await _reverse(path, edits, stop);
    if (reversed != null) return reversed;
    final rel = relativePath(absolutePath(path, root), root);
    if (rel.startsWith('/')) return null;
    // 2. The commit where the step started.
    if (startSha != null) {
      final text = await showAt(startSha!, rel);
      return FileBase(
        text: text,
        source: FileBaseSource.startSha,
        detail: _short(startSha!),
      );
    }
    // 3. The base branch.
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
