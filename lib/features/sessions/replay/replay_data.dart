import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/transcript_reader.dart';
import '../../../core/git/diff_parser.dart';
import '../../../core/git/git_service.dart';
import '../../../core/text/line_diff.dart';
import '../../../data/providers.dart';
import '../../../core/claude/claude_event.dart' show CommandEvent;
import '../../../core/providers/agent_provider.dart' show AgentUnavailable;
import '../../../core/providers/provider_availability.dart';
import '../codex_conversations.dart';
import '../edit_diff.dart';
import '../timeline.dart';
import '../timeline_provider.dart';
import 'file_at_step.dart';
import 'replay_step.dart';

/// Steps of a timeline snapshot, computed once per snapshot (R11).
final _stepsOf = Expando<List<ReplayStep>>('replay steps');

List<ReplayStep> replayStepsOf(TimelineSnapshot snap, String? root) =>
    _stepsOf[snap] ??= replaySteps(
      snap.items,
      root: root,
      agent: snap.timeline.provider == 'codex' ? 'Codex' : 'Claude',
    );

/// Reads Claude Code transcripts (R10); replaced in tests.
final transcriptReaderProvider = Provider<TranscriptReader>(
  (ref) => TranscriptReader(),
);

/// What the replay knows of a session beyond its events: the row and the
/// commit where its step started (`spec_steps.startSha`).
@immutable
class ReplaySource {
  const ReplaySource(this.session, {this.startSha});

  final Session session;
  final String? startSha;

  String get root => session.worktreePath;
}

final replaySourceProvider = FutureProvider.family<ReplaySource?, String>((
  ref,
  sessionId,
) async {
  final s = await ref.read(sessionsRepoProvider).getById(sessionId);
  if (s == null) return null;
  String? startSha;
  if (s.specId != null) {
    final rows = await ref.read(specStepsRepoProvider).bySpec(s.specId!);
    for (final r in rows) {
      if (r.sessionId == sessionId && r.startSha != null) {
        startSha ??= r.startSha;
      }
    }
  }
  return ReplaySource(s, startSha: startSha);
});

/// `originalFile` of each edit in the transcript, read on demand (R10).
final replayOriginalsProvider =
    FutureProvider.family<Map<String, String>, String>((ref, sessionId) async {
      final src = await ref.watch(replaySourceProvider(sessionId).future);
      final ext = src?.session.externalId;
      if (src == null || ext == null || ext.isEmpty) return const {};
      try {
        return await ref
            .read(transcriptReaderProvider)
            .originalFiles(ext, cwd: src.root);
      } catch (e) {
        debugPrint('replay: transcript de $sessionId — $e');
        return const {};
      }
    });

/// The restore points "Arquivo neste ponto" can start from (SPEC-110 R2),
/// oldest first: the ones that know the message of their turn. A point
/// recorded in the middle of a turn (a message that steered it) is not the
/// start of one: the files were already half changed.
Future<List<RestoreBase>> replayPoints(Ref ref, String sessionId) async {
  final rows = await ref
      .read(restorePointsRepoProvider)
      .list(sessionId: sessionId);
  final out = [
    for (final p in rows.reversed)
      if (p.eventSeq != null)
        RestoreBase(
          turn: p.turn,
          seq: p.eventSeq!,
          sha: p.startSha,
          at: p.startedAt,
        ),
  ];
  if (out.isEmpty) return out;
  final steering = <int>{};
  String? turn;
  for (final i in ref.read(sessionTimelineProvider(sessionId)).items) {
    if (i is! UserItem) continue;
    if (i.agentTurnId != null && i.agentTurnId == turn && i.seq != null) {
      steering.add(i.seq!);
    }
    turn = i.agentTurnId;
  }
  return [
    for (final p in out)
      if (!steering.contains(p.seq)) p,
  ];
}

FileBaseResolver _resolver(Ref ref, ReplaySource src) {
  final git = ref.read(gitServiceFactoryProvider)(src.root);
  final base = src.session.baseBranch;
  return FileBaseResolver(
    originalFiles: () =>
        ref.read(replayOriginalsProvider(src.session.id).future),
    showAt: (rev, path) async {
      try {
        return await git.show(rev, path);
      } on GitException {
        return null;
      }
    },
    startSha: src.startSha,
    baseBranch: base,
    baseRef: base == null
        ? null
        : () async {
            try {
              return await git.mergeBase(base, 'HEAD');
            } on GitException {
              return null;
            }
          },
    root: src.root,
    points: () => replayPoints(ref, src.session.id),
    readFile: (path) async {
      final f = File(path);
      return await f.exists() ? await f.readAsString() : null;
    },
  );
}

/// The output of a command was cut, or kept apart by the agent (SPEC-110
/// R4).
bool replayOutputMissing(CommandEvent c) =>
    c.provider == 'codex' &&
    c.done &&
    (c.outputCutLines > 0 || c.output == null);

/// Why the whole output of [s] cannot be fetched (null = it can).
String? replayFetchBlock(ReplayStep s, ProviderAvailability? codex) {
  if (s.agentTurnId == null) {
    return 'O turno deste comando não foi identificado.';
  }
  if (codex == null) return 'Verificando o Codex…';
  if (codex.status == ProviderStatus.missing) {
    return 'O Codex não está instalado.';
  }
  return codex.available ? null : codex.message;
}

/// "Buscar a saída completa" (SPEC-110 R4): one read by RPC, when asked.
Future<String> fetchReplayOutput(
  WidgetRef ref,
  String sessionId,
  ReplayStep step,
) async {
  final turnId = step.agentTurnId;
  final tool = step.tool;
  if (turnId == null || tool == null) {
    throw const AgentUnavailable('O turno deste comando não foi identificado.');
  }
  final s = await ref.read(sessionsRepoProvider).getById(sessionId);
  if (s == null) throw const AgentUnavailable('Sessão não encontrada.');
  return ref
      .read(codexConversationsProvider)
      .itemOutput(
        s,
        turnId: turnId,
        itemId: tool.id,
        // A turn that left the conversation is still in the copy.
        copies: ref
            .read(sessionTimelineProvider(sessionId))
            .timeline
            .conversationCopies,
      );
}

/// The file of an edit step right after it (R7). Key: session id and the
/// edit's `tool_use_id`.
final replayFileAtProvider =
    FutureProvider.family<FileAtStep, (String, String)>((ref, key) async {
      final (sessionId, toolId) = key;
      final src = await ref.watch(replaySourceProvider(sessionId).future);
      if (src == null) return const FileAtStep.failed('Sessão não encontrada.');
      final steps = replayStepsOf(
        ref.read(sessionTimelineProvider(sessionId)),
        src.root,
      );
      final target = flattenSteps(steps)
          .where((s) => s.tool?.id == toolId)
          .firstOrNull;
      final path = target?.filePath;
      if (target == null || path == null) {
        return const FileAtStep.failed('Este passo não edita um arquivo.');
      }
      final edits = editsOf(steps, path, root: src.root);
      final base = await _resolver(ref, src).resolve(path, edits, target);
      return fileAtStep(base: base, edits: edits, target: target);
    });

/// A file in "Resultado" (R8).
@immutable
class ReplayResultFile {
  const ReplayResultFile(this.path, {this.added = 0, this.removed = 0});

  /// Absolute path.
  final String path;
  final int added;
  final int removed;
}

/// Files the session changed with its applied edits, with the +/−
/// accumulated (R8).
List<ReplayResultFile> replayResultFiles(List<ReplayStep> steps, String? root) {
  final out = <String, (int, int)>{};
  for (final s in flattenSteps(steps)) {
    if (!s.isAppliedEdit || s.filePath == null) continue;
    final key = absolutePath(s.filePath!, root);
    final (a, r) = out[key] ?? (0, 0);
    out[key] = (a + (s.added ?? 0), r + (s.removed ?? 0));
  }
  return [
    for (final e in out.entries)
      ReplayResultFile(e.key, added: e.value.$1, removed: e.value.$2),
  ];
}

/// Reads final repository changes only when the Result side tab is opened.
/// Bash-only edits and generated, untracked files belong here too (R8).
final replayResultFilesProvider =
    FutureProvider.family<List<ReplayResultFile>, String>((ref, id) async {
      final src = await ref.watch(replaySourceProvider(id).future);
      if (src == null) return const [];
      final steps = replayStepsOf(
        ref.read(sessionTimelineProvider(id)),
        src.root,
      );
      final fallback = replayResultFiles(steps, src.root);
      final git = ref.read(gitServiceFactoryProvider)(src.root);
      try {
        final base =
            src.startSha ??
            (src.session.baseBranch == null
                ? null
                : await git.mergeBase(src.session.baseBranch!, 'HEAD'));
        if (base == null) return fallback;
        final files = DiffParser.parse(await git.diff(base: base));
        final result = <String, ReplayResultFile>{
          for (final file in files)
            absolutePath(file.path, src.root): ReplayResultFile(
              absolutePath(file.path, src.root),
              added: file.isBinary
                  ? -1
                  : file.hunks.fold(0, (n, h) => n + h.additions),
              removed: file.isBinary
                  ? -1
                  : file.hunks.fold(0, (n, h) => n + h.deletions),
            ),
        };
        for (final entry in await git.status()) {
          if (!entry.isUntracked) continue;
          final path = absolutePath(entry.path, src.root);
          final text = await _untrackedText(src.root, path);
          result[path] = ReplayResultFile(
            path,
            added: text == null ? -1 : _fileLines(text).length,
            removed: text == null ? -1 : 0,
          );
        }
        return result.values.toList()..sort((a, b) => a.path.compareTo(b.path));
      } on GitException {
        // The worktree can already have been removed after merge.
        return fallback;
      } on FileSystemException {
        return fallback;
      }
    });

List<String> _fileLines(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// Read only repository-local, small text files. A symlink outside the
/// worktree is never followed for the generated-file preview.
Future<String?> _untrackedText(String root, String path) async {
  final file = File(path);
  try {
    final realRoot = await Directory(root).resolveSymbolicLinks();
    final real = await file.resolveSymbolicLinks();
    if (!p.isWithin(realRoot, real) || await file.length() > 2 * 1024 * 1024) {
      return null;
    }
    final bytes = await file.readAsBytes();
    if (bytes.contains(0)) return null;
    return utf8.decode(bytes);
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// One line of the final diff (R8).
typedef ReplayDiffRow = ({DiffOp op, String text, int? oldNo, int? newNo});

/// The final diff of a file: the end of the session against the base.
@immutable
class ReplayFinalDiff {
  const ReplayFinalDiff({this.rows = const [], this.against, this.error});

  final List<ReplayDiffRow> rows;

  /// "contra o início da etapa (a1b2c3d)".
  final String? against;
  final String? error;

  int get added => rows.where((r) => r.op == DiffOp.add).length;
  int get removed => rows.where((r) => r.op == DiffOp.del).length;
}

/// Final diff of [path] in the session (R8): `git diff <base> -- path` in
/// the worktree, base = the commit where the step started or the
/// merge-base with the base branch; without git, the base text with the
/// session's edits applied.
final replayFinalDiffProvider =
    FutureProvider.family<ReplayFinalDiff, (String, String)>((ref, key) async {
      final (sessionId, path) = key;
      final src = await ref.watch(replaySourceProvider(sessionId).future);
      if (src == null) return const ReplayFinalDiff(error: 'Sem sessão.');
      final root = src.root;
      final rel = relativePath(path, root);
      final git = ref.read(gitServiceFactoryProvider)(root);
      String? rev = src.startSha;
      String? against = rev == null
          ? null
          : 'contra o início da etapa (${rev.substring(0, rev.length.clamp(0, 7))})';
      final base = src.session.baseBranch;
      if (rev == null && base != null) {
        try {
          rev = await git.mergeBase(base, 'HEAD');
        } on GitException {
          rev = null;
        }
        if (rev != null) against = 'contra $base';
      }
      if (rev != null && !rel.startsWith('/')) {
        try {
          final files = DiffParser.parse(
            await git.diff(base: rev, path: rel, context: 3),
          );
          final rows = <ReplayDiffRow>[];
          for (final f in files) {
            for (final h in f.hunks) {
              for (final l in h.lines) {
                rows.add((
                  op: switch (l.kind) {
                    DiffLineKind.add => DiffOp.add,
                    DiffLineKind.del => DiffOp.del,
                    _ => DiffOp.same,
                  },
                  text: l.text,
                  oldNo: l.oldNo,
                  newNo: l.newNo,
                ));
              }
            }
          }
          if (rows.isNotEmpty) {
            return ReplayFinalDiff(rows: rows, against: against);
          }
        } on GitException {
          // Falls back to the session's edits.
        }
      }
      // A command can create a new file that has not been added to git.
      if (!rel.startsWith('/') && p.isWithin(root, path)) {
        try {
          final status = await git.status();
          if (status.any(
            (e) => e.isUntracked && absolutePath(e.path, root) == path,
          )) {
            final text = await _untrackedText(root, path);
            if (text == null) {
              return const ReplayFinalDiff(
                error: 'Arquivo binário, grande demais ou fora da worktree.',
              );
            }
            final lines = _fileLines(text);
            return ReplayFinalDiff(
              against: 'arquivo novo, gerado na worktree',
              rows: [
                for (var i = 0; i < lines.length; i++)
                  (op: DiffOp.add, text: lines[i], oldNo: null, newNo: i + 1),
              ],
            );
          }
        } on GitException {
          // The worktree may no longer exist.
        }
      }
      // Without git: the base of the first edit plus every applied edit.
      final steps = replayStepsOf(
        ref.read(sessionTimelineProvider(sessionId)),
        root,
      );
      final edits = editsOf(steps, path, root: root);
      final applied = edits.where((s) => s.isAppliedEdit).toList();
      if (applied.isEmpty) {
        return const ReplayFinalDiff(error: 'Nenhuma edição aplicada.');
      }
      final first = await _resolver(ref, src).resolve(path, edits, edits.first);
      final at = fileAtStep(base: first, edits: edits, target: applied.last);
      if (!at.ok) return ReplayFinalDiff(error: at.reason);
      final before = first?.text ?? '';
      final rows = <ReplayDiffRow>[];
      var o = 1, n = 1;
      for (final d in lineDiff(before, at.text!)) {
        switch (d.op) {
          case DiffOp.same:
            rows.add((op: d.op, text: d.text, oldNo: o++, newNo: n++));
          case DiffOp.del:
            rows.add((op: d.op, text: d.text, oldNo: o++, newNo: null));
          case DiffOp.add:
            rows.add((op: d.op, text: d.text, oldNo: null, newNo: n++));
        }
      }
      return ReplayFinalDiff(
        rows: _trim(rows),
        against: 'contra ${first?.label ?? 'o arquivo vazio'}',
      );
    });

/// Keeps changed rows with 3 lines of context around them.
List<ReplayDiffRow> _trim(List<ReplayDiffRow> rows) {
  final keep = List<bool>.filled(rows.length, false);
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].op == DiffOp.same) continue;
    for (var j = i - 3; j <= i + 3; j++) {
      if (j >= 0 && j < rows.length) keep[j] = true;
    }
  }
  return [
    for (var i = 0; i < rows.length; i++)
      if (keep[i]) rows[i],
  ];
}
