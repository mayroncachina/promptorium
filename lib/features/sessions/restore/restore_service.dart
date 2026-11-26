import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/codex/codex_neutral.dart' show codexTurnStartedSubtype;
import '../../../core/codex/codex_thread_ops.dart';
import '../../../core/git/git_service.dart';
import '../../../core/providers/capabilities.dart';
import '../../../data/providers.dart';
import '../../../data/repos/restore_points_repo.dart';
import '../codex_conversations.dart';
import '../conversation_events.dart';
import '../session_manager.dart';
import '../timeline.dart' show AppEventTypes;
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
    this.conversation,
    this.restored,
  });

  final int turn;
  final int files;

  /// Subjects of the commits thrown away.
  final List<String> commits;

  /// What came of the agent's conversation in an undo (SPEC-110 R8); null =
  /// it was not asked to go back.
  final ConversationRevert? conversation;

  /// Redo (R9): the copy was adopted (true) or the conversation did not come
  /// back (false); null = it had not gone back.
  final bool? restored;
}

/// The Codex turn a restore point opened (SPEC-110 R6, P1); without one,
/// only the files can be undone.
@immutable
class AgentTurn {
  const AgentTurn(String this.id) : reason = null;

  const AgentTurn.unknown(String this.reason) : id = null;

  final String? id;
  final String? reason;
}

/// Text of the timeline after an undo: "Turno 4 desfeito: 41 arquivos,
/// 1 commit (wip)." (SPEC-084 R8).
String undoneNote(UndoOutcome o) {
  final commits = o.commits.isEmpty ? '' : ', ${commitsLabel(o.commits)}';
  return 'Turno ${o.turn} desfeito: ${filesLabel(o.files)}$commits.';
}

/// What the agent hears after a redo (with the next message).
String redoNotice(int turn) =>
    'O usuário refez o turno $turn; os arquivos voltaram ao estado de depois '
    'do turno. Releia antes de alterar.';

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

  SessionManager get _manager => _ref.read(sessionManagerProvider.notifier);

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
    final timeout = _ref.read(restoreTimeoutProvider);
    // The limit counts from here (the wait for the previous end of turn
    // included); once the tree is captured in time the point is written
    // whole, so a late answer never leaves a point the turn did not get.
    final deadline = DateTime.now().add(timeout);
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
          deadline: deadline,
        ),
      );
    } on TimeoutException {
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
    required DateTime deadline,
  }) async {
    final git = _git(worktree);
    final owner = restoreOwnerKey(
      sessionId: sessionId,
      conversationId: conversationId,
    );
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) throw TimeoutException(null);
    // Past the limit the capture goes on alone and its commit is dropped
    // (no ref keeps it).
    final state = await _reuseOrCapture(git, worktree, settings).timeout(left);
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
  ///
  /// [beforeEnd] runs in the restore queue of the worktree right before the
  /// end is captured (and alone when there is no open point): the commit the
  /// app makes at the end of a Codex turn (SPEC-096 R10) must land before
  /// the capture, or the point reads the old HEAD with a clean tree and says
  /// "nada mudou" while the undo leaves the turn's files behind.
  Future<void> end({
    String? sessionId,
    int? conversationId,
    Future<void> Function()? beforeEnd,
  }) async {
    final points = await _repo.list(
      sessionId: sessionId,
      conversationId: conversationId,
    );
    final p = points.firstOrNull;
    if (p == null || p.endedAt != null) {
      await _runBeforeEnd(beforeEnd);
      return;
    }
    try {
      await _serial(p.worktreePath, () async {
        await _runBeforeEnd(beforeEnd);
        final cur = await _repo.byId(p.id);
        if (cur != null && cur.endedAt == null) await _end(cur);
      }).timeout(_ref.read(restoreTimeoutProvider) * 2);
    } catch (e) {
      debugPrint('ponto de restauração (fim do turno ${p.turn}): $e');
    }
  }

  Future<void> _runBeforeEnd(Future<void> Function()? job) async {
    if (job == null) return;
    try {
      await job();
    } catch (e) {
      debugPrint('ponto de restauração (antes do fim do turno): $e');
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
      conversation: await _safe(() => _conversationPlan(p, range), null),
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
          conversation: await _safe(() => _redoConversationPlan(p), null),
        );
      });

  // --- the agent's conversation (SPEC-110) -------------------------------------

  /// The Codex turn [p] opened (R6): the `turn/started` that follows its
  /// message in `session_events`, up to the next message. A message that
  /// steered a running turn opened none.
  Future<AgentTurn> agentTurnOf(RestorePoint p) async {
    const none = AgentTurn.unknown(
      'O turno do Codex deste ponto não foi identificado: só os arquivos '
      'voltam.',
    );
    final sid = p.sessionId, seq = p.eventSeq;
    if (sid == null || seq == null) return none;
    final sessions = _ref.read(sessionsRepoProvider);
    String? other;
    var from = seq;
    scan:
    while (true) {
      final rows = await sessions.eventsAfter(sid, from);
      for (final e in rows) {
        from = e.seq;
        if (e.type == AppEventTypes.user) break scan;
        if (!e.json.contains('"turn_id"')) {
          // The process died before the turn and was started again.
          if (e.type == AppEventTypes.note &&
              e.json.contains('Sessão retomada')) {
            break scan;
          }
          continue;
        }
        final id = _turnIdOf(e.json);
        if (id == null) continue;
        if (e.type == 'system/$codexTurnStartedSubtype') return AgentTurn(id);
        other ??= id;
      }
      if (rows.length < 200) break;
    }
    if (other == null) return none;
    // Sessions from before the `turn_started` event: an id already seen
    // before the message is of a turn that was running.
    final before = await sessions.lastEventBefore(sid, seq, '"turn_id"');
    if (before != null && _turnIdOf(before.json) == other) {
      return const AgentTurn.unknown(
        'Este ponto foi gravado no meio de um turno do Codex: só os arquivos '
        'voltam.',
      );
    }
    return AgentTurn(other);
  }

  static String? _turnIdOf(String json) {
    try {
      final j = jsonDecode(json);
      final id = j is Map && j['provider'] == 'codex' ? j['turn_id'] : null;
      return id is String && id.isNotEmpty ? id : null;
    } on FormatException {
      return null;
    }
  }

  static int _lastTurn(RestorePoint p, List<RestorePoint> range) {
    var last = p.turn;
    for (final x in range) {
      if (x.state != RestoreState.undone && x.turn > last) last = x.turn;
    }
    return last;
  }

  /// The "Conversa do agente" of the undo window (R7).
  Future<ConversationPlan?> _conversationPlan(
    RestorePoint p,
    List<RestorePoint> range,
  ) async {
    if (p.sessionId == null) return null;
    final s = await _ref.read(sessionsRepoProvider).getById(p.sessionId!);
    if (s == null) return null;
    final caps = capabilitiesFor(s.provider);
    final last = _lastTurn(p, range);
    ConversationPlan plan({String? id, String? reason, bool only = false}) =>
        ConversationPlan(
          provider: s.provider,
          agent: caps.displayName,
          firstTurn: p.turn,
          lastTurn: last,
          beforeTurnId: id,
          reason: reason,
          onlyCodex: only,
        );
    if (!caps.supports(ProviderCapability.revertConversation)) {
      return plan(
        reason: caps.reasonFor(ProviderCapability.revertConversation),
        only: true,
      );
    }
    if ((s.externalId ?? '').isEmpty) {
      return plan(reason: 'A sessão ainda não tem uma conversa do Codex.');
    }
    final turn = await agentTurnOf(p);
    return plan(id: turn.id, reason: turn.reason);
  }

  Future<ConversationPlan?> _redoConversationPlan(RestorePoint p) async {
    final r = await activeRevert(p);
    if (r == null) return null;
    return ConversationPlan(
      provider: 'codex',
      agent: capabilitiesFor('codex').displayName,
      firstTurn: r.turn,
      lastTurn: r.lastTurn,
      copyAt: r.copyId == null ? null : r.copyAt,
      reason: r.copyId == null
          ? 'Não há cópia da conversa: só os arquivos voltam, e o agente '
                'recebe o aviso.'
          : null,
    );
  }

  /// The revert of the conversation made with the undo of [p] and not
  /// restored since (R9).
  Future<ConversationRevert?> activeRevert(RestorePoint p) async {
    if (p.sessionId == null) return null;
    final rows = await _ref.read(sessionsRepoProvider).eventsOfTypes({
      AgentConversationEvents.reverted,
      AgentConversationEvents.restored,
    }, sessionId: p.sessionId);
    ConversationRevert? found;
    for (final e in rows) {
      final Object? j;
      try {
        j = jsonDecode(e.json);
      } on FormatException {
        continue;
      }
      if (j is! Map) continue;
      if (j['type'] == AgentConversationEvents.restored) {
        if (found != null && j['revert'] == found.key) found = null;
        continue;
      }
      final r = ConversationRevert.fromJson(j);
      if (r != null && r.pointId == p.id) found = r;
    }
    return found;
  }

  /// Steps 2 and 3 of R8, after the files: the copy, then the revert. Never
  /// throws: a failure comes in [ConversationRevert.error] and changes
  /// nothing else — the files stay undone and the session keeps its thread,
  /// which is whole until `thread/revert` answers. Only inside
  /// [SessionManager.holdConversation].
  Future<ConversationRevert?> _revertConversation(
    RestorePoint p, {
    required int lastTurn,
    required int files,
    required List<String> commits,
    String? copyId,
    DateTime? copiedAt,
  }) async {
    final s = await _ref.read(sessionsRepoProvider).getById(p.sessionId ?? '');
    if (s == null) return null;
    final turn = await agentTurnOf(p);
    final thread = s.externalId ?? '';
    var copy = copyId;
    String? copyError;
    String? error = turn.reason;
    if (error == null && thread.isEmpty) {
      error = 'a sessão não tem uma conversa do Codex';
    }
    if (error == null) {
      try {
        await _ref.read(codexConversationsProvider).run(s, (
          ops, {
          required live,
        }) async {
          // `thread/revert` wants the thread loaded; no turn starts.
          if (!live) await ops.resume(thread, cwd: s.worktreePath);
          if (copy == null) {
            try {
              copy = await ops.fork(thread, cwd: s.worktreePath);
            } catch (e) {
              // R9: without a copy, "Refazer" brings back only the files.
              copyError = codexThreadFailure(e);
            }
          }
          await ops.revert(thread, turn.id!);
        }, loadsThread: true);
      } catch (e) {
        error = codexThreadFailure(e);
      }
    }
    final out = ConversationRevert(
      key: 'cr-${DateTime.now().microsecondsSinceEpoch}',
      pointId: p.id,
      turn: p.turn,
      lastTurn: lastTurn,
      beforeTurnId: turn.id ?? '',
      threadId: thread,
      at: DateTime.now(),
      fromSeq: p.eventSeq,
      copyId: copy,
      copiedAt: copyId == null ? null : copiedAt,
      copyError: copyError,
      error: error,
      files: files,
      commits: commits,
    );
    if (out.ok) {
      _manager.conversationReverted(s.id);
      await _safe(() => _manager.appEvent(s.id, out.toJson()), null);
    }
    return out;
  }

  /// R9: the session goes on in the copy. False when it could not (the
  /// thread of the session stays the one it has).
  Future<bool> _restoreConversation(
    RestorePoint p,
    ConversationRevert r, {
    required int files,
  }) async {
    final s = await _ref.read(sessionsRepoProvider).getById(p.sessionId ?? '');
    final copy = r.copyId;
    if (s == null || copy == null) return false;
    try {
      // The idle process ends first: it writes the old thread and may have
      // the copy open (it made it).
      await _manager.release(s.id);
      // What the next message will do. A copy that does not resume (gone,
      // archived) never becomes the conversation of the session.
      await _ref
          .read(codexConversationsProvider)
          .runShort(
            (ops) => ops.resume(copy, cwd: s.worktreePath),
            cwd: s.worktreePath,
            loadsThread: true,
          );
      await _ref.read(sessionsRepoProvider).setExternalId(s.id, copy);
    } catch (e) {
      await _safe(
        () => _manager.note(
          s.id,
          'A conversa do Codex não voltou: ${codexThreadFailure(e)}. Só os '
          'arquivos foram refeitos e o agente recebe o aviso.',
          error: true,
        ),
        null,
      );
      return false;
    }
    await _safe(
      () => _manager.appEvent(
        s.id,
        conversationRestoredEvent(
          revert: r,
          previousThread: s.externalId ?? '',
          files: files,
        ),
      ),
      null,
    );
    return true;
  }

  /// "Desfazer" of a session, whole (R8): the files, the conversation when
  /// asked, the timeline and what the agent hears.
  Future<UndoOutcome> undoTurn(
    RestorePoint p,
    Set<String> paths, {
    bool filesOnly = false,
    bool revertConversation = false,
  }) async {
    final out = await undo(
      p,
      paths,
      filesOnly: filesOnly,
      revertConversation: revertConversation,
    );
    final sid = p.sessionId;
    if (sid == null) return out;
    final c = out.conversation;
    // It went back: the note is its event, and the agent no longer knows
    // the turn.
    if (c != null && c.ok) return out;
    await _manager.note(sid, undoneNote(out));
    if (c != null) await _manager.appEvent(sid, c.toJson());
    await _manager.queueNotice(sid, SessionManager.undoNotice(out.turn));
    return out;
  }

  /// "Refazer" of a session, whole (R9).
  Future<UndoOutcome> redoTurn(RestorePoint p, Set<String> paths) async {
    final out = await redo(p, paths);
    final sid = p.sessionId;
    // With the conversation back, its event is the note.
    if (sid == null || out.restored == true) return out;
    final lost = out.restored == false
        ? ' Sem a cópia, a conversa do Codex não volta.'
        : '';
    await _manager.note(
      sid,
      'Turno ${out.turn} refeito: ${filesLabel(out.files)}.$lost',
    );
    await _manager.queueNotice(sid, redoNotice(out.turn));
    return out;
  }

  /// "Tentar voltar a conversa" after a failure (R8): only the conversation,
  /// while no turn started since the undo.
  Future<ConversationRevert> retryConversation(
    String sessionId,
    ConversationRevert failed,
  ) async {
    final p = await _repo.byId(failed.pointId);
    if (p == null ||
        p.state != RestoreState.undone ||
        p.undoneSha == null ||
        await activeRevert(p) != null) {
      throw const RestoreException(
        'A conversa só volta enquanto nenhum turno novo começou.',
      );
    }
    final out = await _manager.holdConversation(
      sessionId,
      () => _serial(
        p.worktreePath,
        () => _revertConversation(
          p,
          lastTurn: failed.lastTurn,
          files: failed.files,
          commits: failed.commits,
          copyId: failed.copyId,
          copiedAt: failed.copyAt,
        ),
      ),
    );
    if (out == null) throw const RestoreException('Sessão não encontrada.');
    if (out.ok) {
      await _manager.cancelNotice(
        sessionId,
        SessionManager.undoNotice(failed.turn),
      );
    } else {
      await _manager.appEvent(sessionId, out.toJson());
    }
    return out;
  }

  /// The copies nobody can adopt any more are archived in the Codex
  /// (`thread/archive`, R9): a new turn took "Refazer" away, or the point is
  /// gone. Never the conversation of a session, nor a copy once adopted.
  Future<void> archiveOrphanCopies() async {
    final sessions = _ref.read(sessionsRepoProvider);
    final rows = await sessions.eventsOfTypes(AgentConversationEvents.all);
    final copies = <String, (String, ConversationRevert)>{};
    final done = <String>{};
    for (final e in rows) {
      final Object? j;
      try {
        j = jsonDecode(e.json);
      } on FormatException {
        continue;
      }
      if (j is! Map) continue;
      final copy = j['copy_id'];
      if (j['type'] == AgentConversationEvents.restored ||
          j['type'] == AgentConversationEvents.archived) {
        if (copy is String) done.add(copy);
        continue;
      }
      final r = ConversationRevert.fromJson(j);
      if (r?.copyId case final id?) copies[id] = (e.sessionId, r!);
    }
    final orphans = <String, String>{};
    for (final MapEntry(key: id, value: (sid, r)) in copies.entries) {
      if (done.contains(id) || await sessions.hasExternalId(id)) continue;
      final p = await _repo.byId(r.pointId);
      final redoable =
          p != null && p.state == RestoreState.undone && p.undoneSha != null;
      if (!redoable) orphans[id] = sid;
    }
    if (orphans.isEmpty) return;
    await _ref.read(codexConversationsProvider).runShort((ops) async {
      for (final MapEntry(key: id, value: sid) in orphans.entries) {
        try {
          await ops.archive(id);
        } catch (e) {
          final text = '$e'.toLowerCase();
          final gone =
              text.contains('no rollout found') ||
              text.contains('thread not found') ||
              text.contains('archived');
          if (!gone) {
            debugPrint('cópia $id da conversa não arquivada — $e');
            continue;
          }
        }
        await sessions.appendEvent(
          sid,
          type: AgentConversationEvents.archived,
          json: jsonEncode({
            'type': AgentConversationEvents.archived,
            'v': 1,
            'copy_id': id,
            'at': DateTime.now().toIso8601String(),
          }),
        );
      }
    });
  }

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
  ///
  /// [revertConversation] (SPEC-110 R8): only after the files are undone,
  /// the agent's conversation goes back too; no turn of the session starts
  /// meanwhile, and its failure never touches the files.
  Future<UndoOutcome> undo(
    RestorePoint p,
    Set<String> paths, {
    bool filesOnly = false,
    bool revertConversation = false,
  }) {
    final sid = p.sessionId;
    Future<UndoOutcome> job() => _undo(
      p,
      paths,
      filesOnly: filesOnly,
      revertConversation: revertConversation && sid != null,
    );
    return revertConversation && sid != null
        ? _manager.holdConversation(sid, job)
        : job();
  }

  Future<UndoOutcome> _undo(
    RestorePoint p,
    Set<String> paths, {
    required bool filesOnly,
    required bool revertConversation,
  }) => _serial(p.worktreePath, () async {
    final git = _git(p.worktreePath);
    final owner = _ownerOf(p);
    final (range, _) = await _range(p);
    final lastTurn = _lastTurn(p, range);
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
    final subjects = [for (final c in commits) c.subject];
    return UndoOutcome(
      turn: p.turn,
      files: paths.length,
      commits: subjects,
      conversation: revertConversation
          ? await _safe<ConversationRevert?>(
              () => _revertConversation(
                p,
                lastTurn: lastTurn,
                files: paths.length,
                commits: subjects,
              ),
              null,
            )
          : null,
    );
  });

  /// "Refazer" (R11): back to "antes de desfazer" with the same rules
  /// (only [paths]; the branch goes back to where it was). With the
  /// conversation reverted, the session goes on in its copy (SPEC-110 R9),
  /// also only after the files.
  Future<UndoOutcome> redo(RestorePoint p, Set<String> paths) async {
    final revert = await _safe(() => activeRevert(p), null);
    Future<UndoOutcome> job() => _redo(p, paths, revert);
    return revert?.copyId == null
        ? job()
        : _manager.holdConversation(p.sessionId!, job);
  }

  Future<UndoOutcome> _redo(
    RestorePoint p,
    Set<String> paths,
    ConversationRevert? revert,
  ) => _serial(p.worktreePath, () async {
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
    return UndoOutcome(
      turn: p.turn,
      files: paths.length,
      restored: revert == null
          ? null
          : await _safe(
              () => _restoreConversation(p, revert, files: paths.length),
              false,
            ),
    );
  });

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
    // SPEC-110 R9: the copies of the conversations go with the points.
    await _safe(archiveOrphanCopies, null);
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
