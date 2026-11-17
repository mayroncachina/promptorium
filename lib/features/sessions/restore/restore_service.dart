import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_service.dart';
import '../../../data/providers.dart';
import '../../../data/repos/restore_points_repo.dart';
import 'restore_point.dart';

export '../../../data/repos/restore_points_repo.dart'
    show RestoreState, largeFilesOf;
export 'restore_point.dart';

/// Preferences of Configurações › Sessões › Pontos de restauração
/// (SPEC-084 R14), in `app_settings`.
@immutable
class RestoreSettings {
  const RestoreSettings({
    this.enabled = true,
    this.keepTurns = 20,
    this.maxDays = 14,
    this.maxFileMb = 20,
  });

  factory RestoreSettings.of(Map<String, String> s) => RestoreSettings(
    enabled: s[RestoreSettingKeys.enabled] != 'false',
    keepTurns: _int(s[RestoreSettingKeys.keepTurns], 20, min: 1),
    maxDays: _int(s[RestoreSettingKeys.maxDays], 14, min: 1),
    maxFileMb: _int(s[RestoreSettingKeys.maxFileMb], 20, min: 1),
  );

  static int _int(String? v, int fallback, {required int min}) {
    final n = int.tryParse(v ?? '');
    return n == null || n < min ? fallback : n;
  }

  /// "Gravar um ponto antes de cada turno".
  final bool enabled;

  /// "Guardar os últimos N turnos por sessão" (R13, P6).
  final int keepTurns;

  /// "Apagar pontos sem uso depois de N dias".
  final int maxDays;

  /// Untracked files bigger than this stay out of the point (R4, P9).
  final int maxFileMb;

  int get maxUntrackedBytes => maxFileMb * 1024 * 1024;
}

abstract final class RestoreSettingKeys {
  static const enabled = 'restauracao.gravar';
  static const keepTurns = 'restauracao.turnos';
  static const maxDays = 'restauracao.dias';
  static const maxFileMb = 'restauracao.limiteMb';
}

final restoreSettingsProvider = Provider<RestoreSettings>(
  (ref) => RestoreSettings.of(ref.watch(appSettingsProvider)),
);

/// How long the start of a turn waits for its point (R4). Tests lower it.
final restoreTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 5),
);

/// Outcome of the start of a turn (R4): the point, or why there is none.
@immutable
class CaptureResult {
  const CaptureResult({this.point, this.failure, this.large = const []});

  final RestorePoint? point;

  /// "passou de 5 s", "repositório sem commit"… (the timeline note).
  final String? failure;

  /// Untracked files over the limit, left out.
  final List<String> large;
}

/// What an undo or a redo did (the timeline note, R8).
@immutable
class UndoOutcome {
  const UndoOutcome({
    required this.turn,
    required this.files,
    this.commits = const [],
  });

  final int turn;
  final int files;

  /// Subjects of the commits thrown away.
  final List<String> commits;
}

class RestoreException implements Exception {
  const RestoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Space of the restore points of a workspace (R14).
@immutable
class RestoreUsage {
  const RestoreUsage({
    required this.points,
    required this.sessions,
    this.bytes,
  });

  final int points;
  final int sessions;

  /// Bytes only these refs keep (null = git could not tell).
  final int? bytes;
}

/// Restore points of the turns (SPEC-084): records them before and after
/// each turn in hidden refs (`refs/promptorium/restore/…`), works out what
/// an undo would do and does it, all or nothing.
class RestoreService {
  RestoreService(this._ref);

  final Ref _ref;

  RestorePointsRepo get _repo => _ref.read(restorePointsRepoProvider);

  GitService _git(String path) => _ref.read(gitServiceFactoryProvider)(path);

  RestoreSettings get _settings => _ref.read(restoreSettingsProvider);

  /// One operation at a time per worktree (start, end, undo).
  final Map<String, Future<void>> _chains = {};

  Future<T> _serial<T>(String key, Future<T> Function() job) {
    final prev = _chains[key] ?? Future<void>.value();
    final next = prev.then((_) => job());
    _chains[key] = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  /// Files saved by the person through Código (R7), by owner, with when.
  final Map<String, List<(String, DateTime)>> _userEdits = {};

  /// The checkpoint of a spec step just recorded (R17): the first turn of
  /// the step reuses it instead of writing the same tree again.
  final Map<String, (String head, String sha, DateTime at)> _offered = {};

  /// Folders already told they are not a git repository.
  final Set<String> _noGitNoted = {};

  /// SPEC-035 checkpoint of a step in [worktree]: [head] and the tree
  /// ([sha], or [head] when clean).
  void offerCheckpoint(String worktree, String head, String? sha) =>
      _offered[worktree] = (head, sha ?? head, DateTime.now());

  /// The person saved [path] through Código while [owner] works (R7).
  void noteUserEdit(String owner, String path, {DateTime? at}) {
    final list = _userEdits.putIfAbsent(owner, () => []);
    list.add((path, at ?? DateTime.now()));
    if (list.length > 500) list.removeRange(0, list.length - 500);
  }

  static bool isGitDir(String path) =>
      FileSystemEntity.typeSync('$path/.git') != FileSystemEntityType.notFound;

  // --- recording -------------------------------------------------------------

  /// Start of a turn (R1–R4): the point with HEAD, branch and the whole
  /// working tree, within the timeout. Never throws: a failure comes back in
  /// [CaptureResult.failure] and the turn goes on.
  Future<CaptureResult> start({
    required int workspaceId,
    required String worktree,
    String? sessionId,
    int? conversationId,
    String prompt = '',
  }) async {
    final settings = _settings;
    if (!settings.enabled) return const CaptureResult();
    if (!isGitDir(worktree)) {
      if (_noGitNoted.add(worktree)) {
        return CaptureResult(
          failure: '${_folder(worktree)} não é um repositório git',
        );
      }
      return const CaptureResult();
    }
    var cancelled = false;
    final timeout = _ref.read(restoreTimeoutProvider);
    try {
      return await _serial(
        worktree,
        () => _start(
          settings: settings,
          workspaceId: workspaceId,
          worktree: worktree,
          sessionId: sessionId,
          conversationId: conversationId,
          prompt: prompt,
          cancelled: () => cancelled,
        ),
      ).timeout(timeout);
    } on TimeoutException {
      cancelled = true;
      return CaptureResult(failure: 'passou de ${timeout.inSeconds} s');
    } on GitException catch (e) {
      return CaptureResult(failure: _reason(e));
    } catch (e) {
      return CaptureResult(failure: '$e');
    }
  }

  Future<CaptureResult> _start({
    required RestoreSettings settings,
    required int workspaceId,
    required String worktree,
    required String? sessionId,
    required int? conversationId,
    required String prompt,
    required bool Function() cancelled,
  }) async {
    final git = _git(worktree);
    final owner = restoreOwnerKey(
      sessionId: sessionId,
      conversationId: conversationId,
    );
    final state = await _reuseOrCapture(git, worktree, settings);
    if (cancelled()) return const CaptureResult();
    final turn = await _repo.nextTurn(
      sessionId: sessionId,
      conversationId: conversationId,
    );
    await git.updateRef(restoreRef(owner, turn, RestoreRefs.start), state.sha);
    final now = DateTime.now();
    // A new turn: the "Refazer" of an undone one goes away (R11).
    await _repo.dropRedo(sessionId: sessionId, conversationId: conversationId);
    final point = await _repo.insert(
      RestorePointsCompanion.insert(
        workspaceId: workspaceId,
        sessionId: Value(sessionId),
        conversationId: Value(conversationId),
        worktreePath: worktree,
        turn: turn,
        prompt: Value(_cut(prompt)),
        startedAt: now,
        startBranch: Value(state.branch),
        startHead: state.head,
        startSha: state.sha,
        files: Value(state.files),
        bytes: Value(state.bytes),
        largeFiles: Value(jsonEncode(state.large)),
        usedAt: Value(now),
      ),
    );
    await _keepLast(
      git,
      owner,
      sessionId: sessionId,
      conversationId: conversationId,
      keep: settings.keepTurns,
    );
    return CaptureResult(point: point, large: state.large);
  }

  Future<TreeState> _reuseOrCapture(
    GitService git,
    String worktree,
    RestoreSettings settings,
  ) async {
    final offered = _offered.remove(worktree);
    if (offered != null &&
        DateTime.now().difference(offered.$3) < const Duration(seconds: 30)) {
      final head = await git.headSha();
      if (head == offered.$1) {
        return TreeState(
          head: head!,
          branch: await git.currentBranch(),
          sha: offered.$2,
          files: offered.$2 == head ? 0 : (await git.status()).length,
        );
      }
    }
    return git.captureState(maxUntrackedBytes: settings.maxUntrackedBytes);
  }

  /// The message that opened the turn reached the timeline (R10).
  Future<void> attachSeq(int pointId, int seq) =>
      _repo.update(pointId, RestorePointsCompanion(eventSeq: Value(seq)));

  /// End of the turn (R1): the `result`, or the process died. Errors only
  /// log.
  Future<void> end({String? sessionId, int? conversationId}) async {
    final points = await _repo.list(
      sessionId: sessionId,
      conversationId: conversationId,
    );
    final p = points.firstOrNull;
    if (p == null || p.endedAt != null) return;
    try {
      await _serial(p.worktreePath, () async {
        final cur = await _repo.byId(p.id);
        if (cur != null && cur.endedAt == null) await _end(cur);
      }).timeout(_ref.read(restoreTimeoutProvider) * 2);
    } catch (e) {
      debugPrint('ponto de restauração (fim do turno ${p.turn}): $e');
    }
  }

  Future<void> _end(RestorePoint p) async {
    final git = _git(p.worktreePath);
    final state = await git.captureState(
      maxUntrackedBytes: _settings.maxUntrackedBytes,
    );
    final owner = _ownerOf(p);
    await git.updateRef(restoreRef(owner, p.turn, RestoreRefs.end), state.sha);
    final changes = await git.treeChanges(p.startSha, state.sha);
    final commits = await _commitCount(git, p.startHead, state.head);
    final large = {...largeFilesOf(p), ...state.large}.toList();
    final now = DateTime.now();
    await _repo.update(
      p.id,
      RestorePointsCompanion(
        endedAt: Value(now),
        endBranch: Value(state.branch),
        endHead: Value(state.head),
        endSha: Value(state.sha),
        changedFiles: Value(changes.length),
        commits: Value(commits),
        largeFiles: Value(jsonEncode(large)),
        usedAt: Value(now),
      ),
    );
  }

  Future<int> _commitCount(GitService git, String base, String head) async {
    if (base == head) return 0;
    try {
      return (await git.commitsBetween(base, head)).length;
    } on GitException {
      return 0;
    }
  }

  // --- plan ------------------------------------------------------------------

  /// The newest point of the owner from [p] on that was not undone: its end
  /// is the end of what an undo of [p] takes back (R9 sums the turns).
  Future<(List<RestorePoint>, RestorePoint)> _range(RestorePoint p) async {
    final all = await _repo.list(
      sessionId: p.sessionId,
      conversationId: p.conversationId,
    );
    final from = [
      for (final x in all)
        if (x.turn >= p.turn) x,
    ];
    final latest =
        from.where((x) => x.state != RestoreState.undone).firstOrNull ?? p;
    return (from, latest);
  }

  /// What undoing [p] (and every turn after it) would do (R6, R7, R12,
  /// R16). [otherLive]: other live sessions in the same folder (id →
  /// title).
  Future<UndoPlan> plan(
    RestorePoint p, {
    Map<String, String> otherLive = const {},
  }) => _serial(p.worktreePath, () async {
    final git = _git(p.worktreePath);
    final (range, latest) = await _range(p);
    final now = await git.captureState(
      maxUntrackedBytes: _settings.maxUntrackedBytes,
    );
    final endSha = latest.endSha ?? now.sha;
    final turn = await git.treeChanges(p.startSha, endSha);
    final after = endSha == now.sha
        ? const <TreeChange>[]
        : await git.treeChanges(endSha, now.sha);
    // The database keeps whole seconds: the end second counts whole.
    final until = (latest.endedAt ?? DateTime.now()).add(
      const Duration(seconds: 1),
    );
    final during = <String>{
      for (final (path, at)
          in _userEdits[_ownerOf(p)] ?? const <(String, DateTime)>[])
        if (!at.isBefore(p.startedAt) && !at.isAfter(until)) path,
    };
    final commits = await _safe(
      () => git.commitsBetween(p.startHead, now.head),
      const <GitLogEntry>[],
    );
    final pushed = commits.isEmpty
        ? (commits: <String>{}, remotes: <String>[])
        : await _safe(() => git.pushedCommits(p.startHead, now.head), (
            commits: <String>{},
            remotes: <String>[],
          ));
    final kept = p.startSha == p.startHead
        ? const <String>[]
        : [
            for (final c in await git.treeChanges(p.startHead, p.startSha))
              c.path,
          ];
    return buildUndoPlan(
      turn: turn,
      after: after,
      editedDuring: during,
      editedAt: _mtimes(p.worktreePath, after),
      commits: commits,
      pushed: pushed.commits,
      remotes: pushed.remotes,
      kept: kept,
      ignored: await _safe(
        () => git.ignoredChangedSince(p.startedAt),
        const <String>[],
      ),
      large: {for (final x in range) ...largeFilesOf(x)}.toList(),
      others: await _others(p, otherLive),
      startBranch: p.startBranch,
      currentBranch: now.branch,
      startHead: p.startHead,
    );
  });

  /// What "Refazer" of [p] would do: the same rules, from the state right
  /// after the undo back to "antes de desfazer" (R11).
  Future<UndoPlan> redoPlan(RestorePoint p) =>
      _serial(p.worktreePath, () async {
        final undoSha = p.undoSha, undoneSha = p.undoneSha;
        if (undoSha == null || undoneSha == null) {
          throw const RestoreException('Este turno não pode ser refeito.');
        }
        final git = _git(p.worktreePath);
        final now = await git.captureState(
          maxUntrackedBytes: _settings.maxUntrackedBytes,
        );
        final turn = await git.treeChanges(undoneSha, undoSha);
        final after = undoneSha == now.sha
            ? const <TreeChange>[]
            : await git.treeChanges(undoneSha, now.sha);
        final commits = await _safe(
          () => git.commitsBetween(now.head, p.undoHead ?? now.head),
          const <GitLogEntry>[],
        );
        return buildUndoPlan(
          turn: turn,
          after: after,
          editedAt: _mtimes(p.worktreePath, after),
          commits: commits,
          startBranch: p.undoBranch,
          currentBranch: now.branch,
          startHead: p.undoHead ?? now.head,
        );
      });

  Future<Map<String, Set<String>>> _others(
    RestorePoint p,
    Map<String, String> otherLive,
  ) async {
    if (otherLive.isEmpty) return const {};
    final out = <String, Set<String>>{};
    final git = _git(p.worktreePath);
    for (final MapEntry(key: id, value: title) in otherLive.entries) {
      final points = await _repo.list(sessionId: id);
      final files = <String>{};
      for (final x in points) {
        if (x.worktreePath != p.worktreePath) continue;
        if ((x.endedAt ?? DateTime.now()).isBefore(p.startedAt)) continue;
        final end = x.endSha;
        if (end == null) continue;
        files.addAll(
          (await _safe(
            () => git.treeChanges(x.startSha, end),
            const <TreeChange>[],
          )).map((c) => c.path),
        );
      }
      out[title] = files;
    }
    return out;
  }

  static Map<String, DateTime> _mtimes(String root, List<TreeChange> list) => {
    for (final c in list)
      if (File('$root/${c.path}').existsSync())
        c.path: File('$root/${c.path}').lastModifiedSync(),
  };

  // --- undo / redo -----------------------------------------------------------

  /// Undoes [p] and every turn after it (R8): records "antes de desfazer",
  /// moves the branch back to the start HEAD (unless [filesOnly], R12) and
  /// puts back only [paths]. A failure halfway goes back to "antes de
  /// desfazer" and throws [RestoreException].
  Future<UndoOutcome> undo(
    RestorePoint p,
    Set<String> paths, {
    bool filesOnly = false,
  }) => _serial(p.worktreePath, () async {
    final git = _git(p.worktreePath);
    final owner = _ownerOf(p);
    final (range, _) = await _range(p);
    final before = await git.captureState(
      maxUntrackedBytes: _settings.maxUntrackedBytes,
    );
    await git.updateRef(
      restoreRef(owner, p.turn, RestoreRefs.beforeUndo),
      before.sha,
    );
    final commits = filesOnly
        ? const <GitLogEntry>[]
        : await _safe(
            () => git.commitsBetween(p.startHead, before.head),
            const <GitLogEntry>[],
          );
    final moveHead =
        !filesOnly &&
        (before.head != p.startHead || before.branch != p.startBranch);
    await _apply(
      git,
      before: before,
      head: moveHead ? (p.startHead, p.startBranch) : null,
      source: p.startSha,
      paths: paths,
    );
    final after = await git.captureState(
      maxUntrackedBytes: _settings.maxUntrackedBytes,
    );
    await git.updateRef(
      restoreRef(owner, p.turn, RestoreRefs.undone),
      after.sha,
    );
    final now = DateTime.now();
    await _repo.update(
      p.id,
      RestorePointsCompanion(
        state: const Value(RestoreState.undone),
        undoBranch: Value(before.branch),
        undoHead: Value(before.head),
        undoSha: Value(before.sha),
        undoneHead: Value(after.head),
        undoneSha: Value(after.sha),
        usedAt: Value(now),
      ),
    );
    for (final x in range) {
      if (x.id == p.id || x.state == RestoreState.undone) continue;
      await _repo.update(
        x.id,
        RestorePointsCompanion(
          state: const Value(RestoreState.undone),
          usedAt: Value(now),
        ),
      );
    }
    return UndoOutcome(
      turn: p.turn,
      files: paths.length,
      commits: [for (final c in commits) c.subject],
    );
  });

  /// "Refazer" (R11): back to "antes de desfazer" with the same rules
  /// (only [paths]; the branch goes back to where it was).
  Future<UndoOutcome> redo(RestorePoint p, Set<String> paths) => _serial(
    p.worktreePath,
    () async {
      final undoSha = p.undoSha, undoHead = p.undoHead;
      if (undoSha == null || undoHead == null || p.undoneSha == null) {
        throw const RestoreException('Este turno não pode ser refeito.');
      }
      final git = _git(p.worktreePath);
      final before = await git.captureState(
        maxUntrackedBytes: _settings.maxUntrackedBytes,
      );
      final moveHead = before.head != undoHead || before.branch != p.undoBranch;
      await _apply(
        git,
        before: before,
        head: moveHead ? (undoHead, p.undoBranch) : null,
        source: undoSha,
        paths: paths,
      );
      final (range, _) = await _range(p);
      final now = DateTime.now();
      for (final x in range) {
        if (x.state != RestoreState.undone) continue;
        await _repo.update(
          x.id,
          RestorePointsCompanion(
            state: const Value(RestoreState.redone),
            undoneSha: const Value(null),
            undoneHead: const Value(null),
            usedAt: Value(now),
          ),
        );
      }
      return UndoOutcome(turn: p.turn, files: paths.length);
    },
  );

  /// Test hook: fails [_apply] after the HEAD moved (R8 "nunca fica meio
  /// desfeito").
  @visibleForTesting
  static bool failAfterMoveForTest = false;

  Future<void> _apply(
    GitService git, {
    required TreeState before,
    required (String, String?)? head,
    required String source,
    required Set<String> paths,
  }) async {
    try {
      if (head != null) await git.moveHead(head.$1, branch: head.$2);
      if (failAfterMoveForTest) throw const GitException('falha simulada');
      await git.restorePaths(source, paths);
    } catch (e) {
      try {
        await _rollback(git, before);
      } catch (e2) {
        debugPrint('ponto de restauração: volta ao estado anterior — $e2');
      }
      throw RestoreException(
        'Não deu para desfazer: ${e is GitException ? _reason(e) : e}. '
        'Os arquivos voltaram ao estado de antes.',
      );
    }
  }

  /// Puts the worktree back as it was in [target] ("antes de desfazer").
  Future<void> _rollback(GitService git, TreeState target) async {
    await git.moveHead(target.head, branch: target.branch);
    final now = await git.captureState();
    final changed = await git.treeChanges(target.sha, now.sha);
    await git.restorePaths(target.sha, [for (final c in changed) c.path]);
  }

  /// Diff of [path] from tree-ish [a] to [b] (the "Ver diff", P7).
  Future<String> diff(String worktree, String a, String b, String path) => _git(
    worktree,
  ).git(['--literal-pathspecs', 'diff', '--no-renames', a, b, '--', path]);

  // --- retention -------------------------------------------------------------

  Future<void> _keepLast(
    GitService git,
    String owner, {
    String? sessionId,
    int? conversationId,
    required int keep,
  }) async {
    final all = await _repo.list(
      sessionId: sessionId,
      conversationId: conversationId,
    );
    if (all.length <= keep) return;
    final old = all.sublist(keep);
    await _drop(git, old);
  }

  Future<void> _drop(GitService git, List<RestorePoint> points) async {
    if (points.isEmpty) return;
    await git.deleteRefList([
      for (final p in points)
        for (final s in RestoreRefs.all) restoreRef(_ownerOf(p), p.turn, s),
    ]);
    await _repo.deleteIds([for (final p in points) p.id]);
  }

  Future<GitService?> _rootGit(int workspaceId, String fallback) async {
    final ws = await _ref.read(workspacesRepoProvider).getById(workspaceId);
    final path = ws?.path ?? fallback;
    return isGitDir(path) ? _git(path) : null;
  }

  /// Every point of the worktree at [path] (it is going away, R13).
  Future<void> dropWorktree(String path) async {
    final points = [
      for (final p in await _repo.all())
        if (p.worktreePath == path) p,
    ];
    if (points.isEmpty) return;
    final git = await _rootGit(points.first.workspaceId, path);
    if (git == null) {
      await _repo.deleteIds([for (final p in points) p.id]);
      return;
    }
    await _drop(git, points);
  }

  /// Every point of a session (merged, discarded or deleted, R13).
  Future<void> dropSession(String sessionId) async {
    final points = await _repo.list(sessionId: sessionId);
    if (points.isEmpty) return;
    final git = await _rootGit(
      points.first.workspaceId,
      points.first.worktreePath,
    );
    if (git == null) {
      await _repo.deleteIds([for (final p in points) p.id]);
      return;
    }
    await _drop(git, points);
  }

  /// "Apagar todos os pontos deste workspace…" (R14).
  Future<int> dropWorkspace(Workspace ws) async {
    final points = await _repo.byWorkspace(ws.id);
    await _repo.deleteIds([for (final p in points) p.id]);
    if (isGitDir(ws.path)) await _git(ws.path).deleteRefs(restoreRefsPrefix);
    return points.length;
  }

  /// Opening the app (R13): points of merged sessions, of worktrees that
  /// are gone and unused for more than the configured days go away, and
  /// so do the refs no row knows (session deleted).
  Future<void> prune({DateTime? now}) async {
    final days = _settings.maxDays;
    final limit = (now ?? DateTime.now()).subtract(Duration(days: days));
    final sessions = _ref.read(sessionsRepoProvider);
    final all = await _repo.all();
    final drop = <RestorePoint>[];
    for (final p in all) {
      var gone =
          p.usedAt.isBefore(limit) || !Directory(p.worktreePath).existsSync();
      if (!gone && p.sessionId != null) {
        final s = await sessions.getById(p.sessionId!);
        gone = s == null || s.status == SessionStatus.merged;
      }
      if (gone) drop.add(p);
    }
    final byWs = <int, List<RestorePoint>>{};
    for (final p in drop) {
      byWs.putIfAbsent(p.workspaceId, () => []).add(p);
    }
    for (final MapEntry(key: ws, value: list) in byWs.entries) {
      final git = await _rootGit(ws, list.first.worktreePath);
      if (git == null) {
        await _repo.deleteIds([for (final p in list) p.id]);
      } else {
        await _safe(() => _drop(git, list), null);
      }
    }
    // Refs without a row.
    final kept = await _repo.all();
    for (final ws in await _ref.read(workspacesRepoProvider).getAll()) {
      if (!isGitDir(ws.path)) continue;
      final git = _git(ws.path);
      final known = <String>{
        for (final p in kept)
          if (p.workspaceId == ws.id)
            for (final s in RestoreRefs.all) restoreRef(_ownerOf(p), p.turn, s),
      };
      final refs = await _safe(
        () => git.refsUnder(restoreRefsPrefix),
        const <String, String>{},
      );
      final orphan = [
        for (final r in refs.keys)
          if (!known.contains(r)) r,
      ];
      if (orphan.isNotEmpty) await _safe(() => git.deleteRefList(orphan), null);
    }
  }

  /// Points and space of [ws] (R14).
  Future<RestoreUsage> usage(Workspace ws) async {
    final points = await _repo.byWorkspace(ws.id);
    final owners = {for (final p in points) _ownerOf(p)};
    final bytes = isGitDir(ws.path)
        ? await _git(ws.path).diskUsageOnly(restoreRefsPrefix)
        : null;
    return RestoreUsage(
      points: points.length,
      sessions: owners.length,
      bytes: bytes,
    );
  }

  // --- helpers ---------------------------------------------------------------

  static String _ownerOf(RestorePoint p) =>
      restoreOwnerKey(sessionId: p.sessionId, conversationId: p.conversationId);

  static String _cut(String s) {
    final line = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return line.length <= 120 ? line : '${line.substring(0, 119)}…';
  }

  static String _folder(String path) =>
      path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? path;

  static String _reason(GitException e) {
    final err = '${e.stderr}\n${e.stdout}'.toLowerCase();
    if (e.message.contains('sem commit')) return 'repositório sem commit';
    if (err.contains('index.lock')) return 'o índice do git está travado';
    if (err.contains('no space')) return 'disco cheio';
    if (err.contains('not a git repository')) return 'não é um repositório git';
    return e.message;
  }

  static Future<T> _safe<T>(Future<T> Function() job, T fallback) async {
    try {
      return await job();
    } catch (e) {
      debugPrint('ponto de restauração: $e');
      return fallback;
    }
  }
}

final restoreServiceProvider = Provider<RestoreService>(RestoreService.new);

/// Points of a session, newest turn first (the panel, the timeline and the
/// header button).
final sessionRestorePointsProvider =
    StreamProvider.family<List<RestorePoint>, String>(
      (ref, sessionId) =>
          ref.watch(restorePointsRepoProvider).watch(sessionId: sessionId),
    );
