import 'dart:async';
import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/claude_cli.dart';
import '../../core/claude/claude_event.dart';
import '../../core/claude/claude_process.dart';
import '../../core/claude/managed_hooks.dart';
import '../../core/claude/run_extensions.dart';
import '../../core/claude/run_prefs.dart';
import '../../core/claude/usage_tracker.dart';
import '../../core/providers/agent_registry.dart';
import '../../core/providers/permission_policy.dart';
import '../../core/providers/provider_preferences.dart';
import '../../core/git/git_service.dart';
import '../../core/git/worktree_setup.dart';
import '../../core/process/shell_runner.dart';
import '../../data/providers.dart';
import '../../data/repos/durable_state_repo.dart';
import '../../data/repos/sessions_repo.dart';
import '../../ui/shell/navigation.dart';
import '../agents/agent_repository.dart';
import '../board/spec_runner.dart';
import '../mcp/mcp_rules.dart';
import '../project/project_config.dart';
import '../tasks/task_rules.dart';
import 'app_notifier.dart';
import 'session_changes.dart';
import 'timeline.dart';
import 'timeline_provider.dart';

export '../../core/claude/claude_cli.dart' show claudeProcessStarterProvider;

/// Generates session ids (`--session-id`, UUID v4).
final sessionIdGeneratorProvider = Provider<String Function()>(
  (ref) => const Uuid().v4,
);

/// Models offered by the "Nova sessão" dialog (plano 0.2). `inherit` = do not
/// pass `--model` (CLI / agent default).
const sessionModels = ['inherit', 'opus', 'sonnet', 'haiku', 'fable'];

/// Input of [SessionManager.create].
@immutable
class NewSessionRequest {
  const NewSessionRequest({
    required this.workspace,
    required this.title,
    required this.prompt,
    this.agent,
    this.model = 'inherit',
    this.provider,
    this.effort,
    this.permissionMode = ClaudePermissionMode.defaultMode,
    this.useWorktree = true,
    this.taskId,
    this.maxBudgetUsd,
    this.resumeFrom,
    this.origin,
    this.specId,
    this.steps,
    this.worktreePath,
    this.branch,
    this.baseBranch,
    this.environment,
    this.duelId,
  });

  final Workspace workspace;
  final String title;
  final String prompt;

  /// Subagent name passed as `--agent` (null = none).
  final String? agent;
  final String model;
  final String? provider;

  /// `--effort` (one of `effortChoices`); null = the session default of
  /// Configurações ([RunPrefs]).
  final String? effort;
  final ClaudePermissionMode permissionMode;

  /// false = run in the workspace root (no `git worktree add`).
  final bool useWorktree;
  final int? taskId;

  /// `--max-budget-usd`; null = the agent's budget (`agent_settings`), if
  /// any. Resumes reapply the agent's budget (DT-23).
  final double? maxBudgetUsd;

  /// Claude session to carry over (`--resume ID --fork-session
  /// --session-id NEW`): "Continuar como sessão" of the Prompt screen.
  final String? resumeFrom;

  /// Note shown at the top of the timeline (e.g. where the context came from).
  final String? origin;

  /// Spec (card) and steps (`R2` / `R1,R2`) the session works on
  /// (`SpecRunner`).
  final int? specId;
  final String? steps;

  /// Existing worktree to run in (the spec's), with its [branch] and the
  /// [baseBranch] it came from. Null = [useWorktree] decides.
  final String? worktreePath;
  final String? branch;
  final String? baseBranch;

  /// Extra variables of the process (`PROMPTORIUM_*`); null = computed.
  final Map<String, String>? environment;

  /// Best-of-N attempt (`spec_duels.id`) the session runs.
  final int? duelId;
}

/// A `can_use_tool` request waiting for the user (approvals queue).
@immutable
class PendingApproval {
  const PendingApproval({
    required this.sessionId,
    required this.sessionTitle,
    required this.request,
    required this.receivedAt,
  });

  final String sessionId;
  final String sessionTitle;
  final PermissionRequest request;
  final DateTime receivedAt;

  String get requestId => request.requestId;
}

/// Runtime state of a session with a live process.
@immutable
class LiveSession {
  const LiveSession({
    this.alive = true,
    this.approvals = const [],
    this.subagentsRunning = 0,
    this.busySince,
  });

  final bool alive;
  final List<PendingApproval> approvals;

  /// Task / Agent tool calls without a result yet.
  final int subagentsRunning;

  /// When the running turn started (null = idle: waiting for the user).
  final DateTime? busySince;

  bool get busy => busySince != null;
}

@immutable
class SessionManagerState {
  const SessionManagerState({this.live = const {}, this.lastInit});

  /// Sessions whose `claude -p` process is running (by session id).
  final Map<String, LiveSession> live;

  /// Last `system/init` of any session (MCP servers in the footer).
  final SystemInit? lastInit;

  bool isAlive(String id) => live[id]?.alive ?? false;

  /// Approvals of every session, oldest first.
  List<PendingApproval> get approvals =>
      [for (final s in live.values) ...s.approvals]
        ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

  int get subagentsRunning =>
      live.values.fold(0, (n, s) => n + s.subagentsRunning);
}

/// Thrown for user-facing failures (shown in dialogs / snackbars).
class SessionException implements Exception {
  const SessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Mutable bookkeeping of one running process.
class _Proc {
  _Proc(
    this.process,
    this.title,
    this.lastCost, {
    this.skipPermissions = false,
  });

  final ManagedAgentRun process;
  String title;

  /// Started with `--dangerously-skip-permissions` (a start flag: a live
  /// switch to another mode does not undo it).
  final bool skipPermissions;

  /// Highest cumulative `total_cost_usd` seen (the session cost).
  double lastCost;
  final List<PermissionRequest> pending = [];
  final DateTime started = DateTime.now();
  final Map<String, DateTime> pendingAt = {};
  final Set<String> subagents = {};
  bool stopping = false;

  /// Last CLI event or message sent (idle sessions are closed).
  DateTime lastActivity = DateTime.now();

  /// Context of the last top-level answer (input + cache read + cache
  /// write): what the next call sends again (SPEC-017 R4).
  int? contextTokens;

  /// A message was sent and its `result` has not arrived yet (turn running).
  bool busy = false;

  /// When [busy] became true.
  DateTime? busySince;

  /// Set by [SessionManager.release]: the exit records nothing.
  bool released = false;

  /// Completed once [SessionManager._onExit] ran.
  final Completer<void> exited = Completer<void>();
  Future<void> queue = Future.value();
  Map<String, dynamic>? lastJson;
  int? lastSeq;

  /// Bytes of the hooks log already shown.
  int hookOffset = 0;
  StreamSubscription<ClaudeEvent>? sub;
  StreamSubscription<String>? logSub;
}

/// Creates sessions and owns one [ClaudeProcess] per live session
/// (plano, Fase 5). Every CLI event is persisted in `session_events`
/// (except `stream_event` deltas, which only feed the live timeline) and
/// updates the session status / cost / tokens.
class SessionManager extends Notifier<SessionManagerState> {
  final Map<String, _Proc> _procs = {};

  /// In-flight [resume] calls (two quick sends must not start two processes).
  final Map<String, Future<void>> _resuming = {};

  /// Removal of the hook files of a process that ended, by session id; a
  /// quick resume waits for it before writing the new ones.
  final Map<String, Future<void>> _hookCleanups = {};

  /// Notices of manual edits (Código, Fase 10) not delivered yet, by
  /// session id; mirrored in `pending_notices` (schema v9) so closing the
  /// app does not lose them. A live process gets them right away, even in
  /// the middle of a turn (verified on CLI 2.1.302: the message joins the
  /// running turn — docs/pesquisa/hooks-settings-stream-json.md §3); with an
  /// approval pending they wait for the turn's `result`; without a process
  /// (e.g. "Pausar agente") they go with the next message.
  final Map<String, List<String>> _notices = {};

  /// Screen that was open when each session was created (Tarefas, Projeto,
  /// Skills…): clicking its "concluída / falhou" notification goes back
  /// there. Kept for the app session only (default: Sessões).
  final Map<String, AppSection> _origins = {};

  /// Set by [shutdown]: exits are not recorded (the next launch marks the
  /// sessions as interrupted) and no new process starts.
  bool _shuttingDown = false;

  @override
  SessionManagerState build() {
    ref.onDispose(() {
      for (final p in _procs.values) {
        p.stopping = true;
        p.process.stop(timeout: const Duration(seconds: 2));
      }
    });
    return const SessionManagerState();
  }

  // --- public API ------------------------------------------------------------

  /// Creates the worktree (optional), the `sessions` row and the process, then
  /// sends [NewSessionRequest.prompt]. Returns the session id.
  Future<String> create(NewSessionRequest r) async {
    final provider =
        r.provider ?? ref.read<String>(defaultAgentProvider(r.workspace.id));
    final title = r.title.trim();
    final prompt = r.prompt.trim();
    if (title.isEmpty) throw const SessionException('Informe um título.');
    if (prompt.isEmpty) {
      throw const SessionException('Informe o prompt inicial.');
    }
    final id = ref.read(sessionIdGeneratorProvider)();
    _origins[id] = ref.read(navigationProvider);
    final ws = r.workspace;
    final git = ref.read(gitServiceFactoryProvider)(ws.path);
    String path = ws.path, branch;
    String? base;
    try {
      if (r.worktreePath != null) {
        path = r.worktreePath!;
        branch = r.branch ?? await git.currentBranch() ?? 'HEAD';
        base = r.baseBranch;
      } else if (r.useWorktree) {
        // The worktree starts at the root's HEAD: that branch is the merge
        // target of the Review (Fase 9).
        base = await git.currentBranch();
        final wt = await git.addWorktree(sessionSlug(title, id));
        path = wt.path;
        branch = wt.branch;
        await _setupWorktree(ws.path, wt);
      } else {
        branch = await git.currentBranch() ?? 'HEAD';
      }
    } on GitException catch (e) {
      throw SessionException('Falha ao criar o worktree: $e');
    }
    if (r.permissionMode == ClaudePermissionMode.skipPermissions &&
        path == ws.path) {
      throw const SessionException(
        '"Sem perguntar" só roda em worktree isolado: marque "Criar '
        'worktree isolado" ou escolha outro modo.',
      );
    }
    final effort =
        r.effort ??
        (provider == 'claude'
            ? ref.read(runPrefsProvider).effort(RunKind.session)
            : 'default');
    await _repo.insert(
      id: id,
      workspaceId: ws.id,
      worktreePath: path,
      branch: branch,
      model: r.model,
      provider: provider,
      externalId: provider == 'claude' ? id : null,
      effort: effort,
      agentName: r.agent,
      title: title,
      permissionMode: r.permissionMode.cliValue,
      taskId: r.taskId,
      specId: r.specId,
      steps: r.steps,
      baseBranch: base,
      duelId: r.duelId,
    );
    if (r.origin != null) await _note(id, r.origin!);
    final limits = await _agentLimits(r.agent, ws.path);
    final mcp = await _mcpRules();
    final env =
        r.environment ?? worktreeEnvironment(root: ws.path, worktree: path);
    await _start(
      id,
      ClaudeOptions(
        sessionId: id,
        resumeId: r.resumeFrom,
        forkSession: r.resumeFrom != null,
        model: _model(r.model),
        effort: effortArg(effort),
        agent: r.agent,
        permissionMode: r.permissionMode,
        maxBudgetUsd: r.maxBudgetUsd ?? limits.budgetUsd,
        maxTurns: limits.maxTurns,
        allowedTools: mcp.allowed,
        disallowedTools: mcp.disallowed,
      ),
      cwd: path,
      title: title,
      root: ws.path,
      environment: env,
    );
    await send(id, prompt);
    return id;
  }

  /// Sends a user message; resumes the session (`--resume`, same worktree)
  /// when it has no live process.
  Future<void> send(String id, String text) async {
    var msg = text.trim();
    if (msg.isEmpty) return;
    final notices = await _takeNotices(id);
    if (notices != null && notices.isNotEmpty) {
      msg = '${notices.join('\n')}\n\n$msg';
    }
    var p = _procs[id];
    if (p == null) {
      await resume(id);
      p = _procs[id];
      if (p == null) return;
    }
    final proc = p;
    await _enqueue(id, proc, () async {
      final json = AppEventTypes.userMessage(msg, DateTime.now());
      final row = await _repo.appendEvent(
        id,
        type: AppEventTypes.user,
        json: _encode(json),
      );
      _timeline(id).push(UnknownEvent(json), seq: row.seq);
      await _repo.setStatus(id, SessionStatus.running);
      await _syncTask(id, SessionStatus.running);
      await _specs.onActive(id);
    });
    proc.busy = true;
    proc.busySince = DateTime.now();
    proc.lastActivity = DateTime.now();
    _publish();
    await proc.process.send(msg);
  }

  /// Line of the app in the session's timeline (gate results, hooks…).
  Future<void> note(String id, String text, {bool error = false}) =>
      _note(id, text, error: error);

  /// Message sent to the agent when the user saves [path] by hand.
  static String userEditNotice(String path) =>
      'O usuário editou $path manualmente; releia antes de alterar.';

  /// Code screen: the user saved [path] (relative to the worktree) while the
  /// session works there (see [_notices]). Returns true when it was sent
  /// now.
  Future<bool> notifyUserEdit(String id, String path) async {
    final text = userEditNotice(path);
    final list = _notices.putIfAbsent(id, () => []);
    if (!list.contains(text)) {
      list.add(text);
      await _durable((r) => r.addNotice(id, text));
    }
    final p = _procs[id];
    if (p == null || p.pending.isNotEmpty || p.stopping) return false;
    if (p.busy) {
      await _sendMidTurn(id, p);
    } else {
      await _flushNotices(id);
    }
    return true;
  }

  /// Notices not delivered yet (tests / UI).
  List<String> pendingNotices(String id) =>
      List.unmodifiable(_notices[id] ?? const []);

  /// Splash: notices left in the database when the app closed.
  Future<void> restoreNotices() async {
    try {
      final stored = await ref.read(durableStateRepoProvider).notices();
      for (final MapEntry(:key, :value) in stored.entries) {
        final list = _notices.putIfAbsent(key, () => []);
        for (final n in value) {
          if (!list.contains(n)) list.add(n);
        }
      }
    } catch (e) {
      debugPrint('avisos pendentes não restaurados — $e');
    }
  }

  /// [_notices] of [id] were delivered: forget them (memory and database).
  Future<List<String>?> _takeNotices(String id) async {
    final list = _notices.remove(id);
    if (list != null) await _durable((r) => r.clearNotices(id));
    return list;
  }

  Future<void> _durable(Future<void> Function(DurableStateRepo r) job) async {
    try {
      await job(ref.read(durableStateRepoProvider));
    } catch (e) {
      debugPrint('estado durável não gravado — $e');
    }
  }

  Future<void> _flushNotices(String id) async {
    final p = _procs[id];
    if (p == null || p.busy || p.stopping || _shuttingDown) return;
    if (!(_notices[id]?.isNotEmpty ?? false)) return;
    final text = (await _takeNotices(id))!.join('\n');
    try {
      await send(id, text);
    } catch (e) {
      debugPrint('sessão $id: aviso de edição não enviado — $e');
    }
  }

  /// Writes the notices into the running turn (no new turn, no status
  /// change: the turn's `result` still ends it).
  Future<void> _sendMidTurn(String id, _Proc p) async {
    final list = await _takeNotices(id);
    if (list == null || list.isEmpty) return;
    final msg = list.join('\n');
    await _enqueue(id, p, () async {
      final json = AppEventTypes.userMessage(msg, DateTime.now());
      final row = await _repo.appendEvent(
        id,
        type: AppEventTypes.user,
        json: _encode(json),
      );
      _timeline(id).push(UnknownEvent(json), seq: row.seq);
    });
    p.lastActivity = DateTime.now();
    await p.process.send(msg);
  }

  /// Starts `claude --resume <id>` in the session's worktree (no message).
  Future<void> resume(String id) {
    if (_procs.containsKey(id)) return Future.value();
    return _resuming[id] ??= _resume(id).whenComplete(() {
      // Block body: returning the removed Future would await itself.
      _resuming.remove(id);
    });
  }

  Future<void> _resume(String id) async {
    final s = await _repo.getById(id);
    if (s == null) throw SessionException('Sessão $id não encontrada.');
    if (s.status == SessionStatus.merged) {
      throw const SessionException(
        'Esta sessão já foi integrada (merge) e o worktree foi removido.',
      );
    }
    await _note(id, 'Sessão retomada (--resume)');
    final ws = await ref.read(workspacesRepoProvider).getById(s.workspaceId);
    if (s.provider == 'codex' &&
        s.permissionMode == 'bypassPermissions' &&
        (ws == null || s.worktreePath == ws.path)) {
      throw const SessionException('Codex YOLO exige um worktree isolado.');
    }
    final limits = await _agentLimits(s.agentName, ws?.path);
    final mcp = await _mcpRules();
    await _start(
      id,
      ClaudeOptions(
        resumeId: id,
        model: _model(s.model),
        effort: s.provider != 'claude'
            ? effortArg(s.effort)
            : _effort(s.effort),
        agent: s.agentName,
        permissionMode: skipOnlyInWorktree(
          ClaudePermissionMode.fromCli(s.permissionMode),
          worktree: s.worktreePath,
          root: ws?.path,
        ),
        maxBudgetUsd: limits.budgetUsd,
        maxTurns: limits.maxTurns,
        allowedTools: mcp.allowed,
        disallowedTools: mcp.disallowed,
      ),
      cwd: s.worktreePath,
      title: _titleOf(s),
      baseCost: s.costUsd,
      root: ws?.path,
      environment: ws == null ? null : await _environmentOf(s, ws),
    );
    await _repo.setStatus(id, SessionStatus.completed);
  }

  /// Fork: new session (`--resume <id> --fork-session --session-id <new>`) in
  /// a **new worktree** created from the parent's branch (uncommitted changes
  /// of the parent are not copied). Without a worktree (parent ran in the
  /// workspace root) the fork also runs in the root. Returns the new id.
  Future<String> fork(
    String id, {
    required String prompt,
    String? title,
  }) async {
    final parent = await _repo.getById(id);
    if (parent == null) throw SessionException('Sessão $id não encontrada.');
    final ws = await ref
        .read(workspacesRepoProvider)
        .getById(parent.workspaceId);
    if (ws == null) throw const SessionException('Workspace não encontrado.');
    final newId = ref.read(sessionIdGeneratorProvider)();
    final name = (title?.trim().isNotEmpty ?? false)
        ? title!.trim()
        : 'Fork de ${_titleOf(parent)}';
    String path = ws.path, branch = parent.branch;
    if (parent.worktreePath != ws.path) {
      final factory = ref.read(gitServiceFactoryProvider);
      try {
        // The parent's uncommitted changes go along (DT-18).
        String? stash;
        try {
          stash = await factory(parent.worktreePath).stashCreate();
        } on GitException catch (e) {
          debugPrint('fork de $id: alterações não copiadas — $e');
        }
        final wt = await factory(ws.path)
            .addWorktree(sessionSlug(name, newId), baseBranch: parent.branch);
        path = wt.path;
        branch = wt.branch;
        if (stash != null) {
          try {
            await factory(path).stashApply(stash);
          } on GitException {
            // No worktree / branch left behind without a session.
            try {
              await factory(ws.path).removeWorktree(path, force: true);
              await factory(ws.path).deleteBranch(branch, force: true);
            } on GitException catch (e) {
              debugPrint('worktree $path não removido — $e');
            }
            rethrow;
          }
        }
        await _setupWorktree(ws.path, wt);
      } on GitException catch (e) {
        throw SessionException('Falha ao criar o worktree do fork: $e');
      }
    }
    // "Sem perguntar" never in the workspace root (F12), as in create/resume.
    final mode = skipOnlyInWorktree(
      ClaudePermissionMode.fromCli(parent.permissionMode),
      worktree: path,
      root: ws.path,
    );
    await _repo.insert(
      id: newId,
      workspaceId: ws.id,
      worktreePath: path,
      branch: branch,
      model: parent.model,
      provider: parent.provider,
      runConfig: parent.runConfig,
      effort: parent.effort,
      agentName: parent.agentName,
      title: name,
      permissionMode: mode?.cliValue ?? parent.permissionMode,
      taskId: parent.taskId,
      // Same merge target as the parent (its worktree came from there).
      baseBranch: parent.worktreePath != ws.path ? parent.baseBranch : null,
      // total_cost_usd keeps counting the parent's cost.
      costUsd: parent.costUsd,
    );
    await _note(newId, 'Fork de "${_titleOf(parent)}" (${_short(id)})');
    final limits = await _agentLimits(parent.agentName, ws.path);
    final mcp = await _mcpRules();
    await _start(
      newId,
      ClaudeOptions(
        sessionId: newId,
        resumeId: id,
        forkSession: true,
        model: _model(parent.model),
        effort: parent.provider != 'claude'
            ? effortArg(parent.effort)
            : _effort(parent.effort),
        agent: parent.agentName,
        permissionMode: mode,
        maxBudgetUsd: limits.budgetUsd,
        maxTurns: limits.maxTurns,
        allowedTools: mcp.allowed,
        disallowedTools: mcp.disallowed,
      ),
      cwd: path,
      title: name,
      baseCost: parent.costUsd,
      root: ws.path,
      environment: worktreeEnvironment(root: ws.path, worktree: path),
    );
    await send(newId, prompt);
    return newId;
  }

  /// Approves a pending request. [always] sends the first
  /// `permission_suggestion` back as `updatedPermissions` ("Sempre permitir").
  Future<void> approve(
    String id,
    String requestId, {
    bool always = false,
    Map<String, dynamic>? updatedInput,
  }) async {
    final p = _procs[id];
    final req = _take(id, requestId);
    if (p == null || req == null) return;
    final suggestion = req.permissionSuggestions.isEmpty
        ? null
        : req.permissionSuggestions.first;
    await p.process.approve(
      requestId,
      updatedPermissions: always && suggestion != null ? [suggestion] : null,
      updatedInput: updatedInput,
    );
    await _afterAnswer(id);
  }

  Future<void> deny(
    String id,
    String requestId, {
    String message = 'O usuário negou esta ação no Promptorium.',
  }) async {
    final p = _procs[id];
    final req = _take(id, requestId);
    if (p == null || req == null) return;
    await p.process.deny(requestId, message);
    await _afterAnswer(id);
  }

  /// SIGTERM (then SIGKILL); the session becomes `stopped`.
  Future<void> stop(String id) async {
    final p = _procs[id];
    if (p == null) {
      final s = await _repo.getById(id);
      if (s != null && !s.status.isTerminal) {
        await _repo.setStatus(id, SessionStatus.stopped);
        await _specs.onEnded(id, SessionStatus.stopped);
      }
      return;
    }
    p.stopping = true;
    await p.process.stop();
  }

  /// Ends the live process (if any) **without** recording "parada" and waits
  /// until its exit is processed. Used by the Review merge before removing
  /// the worktree (the caller sets the final status).
  Future<void> release(String id) async {
    final p = _procs[id];
    if (p == null) return;
    p
      ..stopping = true
      ..released = true;
    await p.process.stop(timeout: const Duration(seconds: 2));
    await p.exited.future.timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  /// App closing: SIGTERM every live process (SIGKILL after [timeout]) so no
  /// `claude` is left orphaned. Statuses stay as they are; the splash of the
  /// next launch turns running / waiting sessions into `interrupted`.
  Future<void> shutdown({Duration timeout = const Duration(seconds: 2)}) async {
    _shuttingDown = true;
    await Future.wait([
      for (final p in _procs.values.toList())
        p.process.stop(timeout: timeout).then((_) {}, onError: (_) {}),
    ]);
  }

  /// Changes the permission mode used the next time the process starts.
  /// "Sem perguntar" is refused for a session in the workspace root (F12).
  Future<void> setPermissionMode(String id, ClaudePermissionMode mode) async {
    if (mode == ClaudePermissionMode.skipPermissions) {
      final s = await _repo.getById(id);
      final ws = s == null
          ? null
          : await ref.read(workspacesRepoProvider).getById(s.workspaceId);
      if (s != null && ws != null && s.worktreePath == ws.path) {
        throw const SessionException(
          '"Sem perguntar" só roda em worktree isolado.',
        );
      }
    }
    final session = await _repo.getById(id);
    final current = _procs[id];
    if (session != null &&
        session.provider != 'claude' &&
        current != null &&
        (current.busy ||
            current.pending.isNotEmpty ||
            current.subagents.isNotEmpty)) {
      throw const SessionException(
        'Pare o turno antes de alterar as permissões Codex.',
      );
    }
    await _repo.setPermissionMode(id, mode.cliValue);
    if (session != null && session.provider != 'claude') {
      if (session.runConfig != null) {
        final config = jsonDecode(session.runConfig!) as Map<String, dynamic>;
        config['permissionMode'] = mode.cliValue;
        await _repo.setRunConfig(id, jsonEncode(config));
      }
      if (current != null) await release(id);
      await _note(
        id,
        'Modo de permissão: ${permissionModeLabel(mode, provider: "codex")} (ao retomar)',
      );
      return;
    }

    // A live process switches now (except to/from "sem perguntar", which is
    // a start flag of the CLI).
    final p = _procs[id];
    if (p == null) return;
    if (p.skipPermissions && mode != ClaudePermissionMode.skipPermissions) {
      // Leaving "sem perguntar": the process keeps skipping approvals, so an
      // idle one closes and the next message resumes in [mode].
      if (!p.busy && p.pending.isEmpty && p.subagents.isEmpty) {
        await _note(
          id,
          'Modo de permissão: ${mode.cliValue} (processo reiniciado na '
          'próxima mensagem)',
        );
        await release(id);
      } else {
        await _note(
          id,
          'Modo de permissão: ${mode.cliValue} — vale quando a sessão '
          'reiniciar; este turno continua sem perguntar',
          error: true,
        );
      }
    } else if (mode != ClaudePermissionMode.skipPermissions) {
      await p.process.setPermissionMode(mode);
      await _note(id, 'Modo de permissão: ${mode.cliValue}');
    }
  }

  /// Whether the session has a running `claude -p` process.
  bool isAlive(String id) => _procs.containsKey(id);

  /// Context of the session's last answer (null: no process or no usage).
  int? contextTokens(String id) => _procs[id]?.contextTokens;

  /// A spec session that goes on to more steps (SPEC-017 R4).
  Future<void> setSteps(String id, String steps, String title) async {
    await _repo.setSteps(id, steps, title);
    _procs[id]?.title = title;
    _publish();
  }

  /// Closes the process of every session idle for the configured time (no
  /// turn running, no approval or sub-agent pending). The session stays as
  /// it was and "Retomar" / sending a message resumes it (`--resume`).
  /// Returns the ids closed. Called every minute by `main.dart` (no timer
  /// here: widget tests do not allow pending timers).
  Future<List<String>> closeIdle({DateTime? now}) async {
    final minutes = ref.read(runPrefsProvider).idleMinutes;
    if (minutes <= 0 || _shuttingDown) return const [];
    final limit = Duration(minutes: minutes);
    final at = now ?? DateTime.now();
    final closed = <String>[];
    for (final e in _procs.entries.toList()) {
      final p = e.value;
      if (p.busy ||
          p.stopping ||
          p.pending.isNotEmpty ||
          p.subagents.isNotEmpty ||
          at.difference(p.lastActivity) < limit) {
        continue;
      }
      closed.add(e.key);
      try {
        await _note(
          e.key,
          'Suspensa após $minutes min sem atividade (Retomar continua de '
          'onde parou)',
        );
        await release(e.key);
      } catch (err) {
        debugPrint('sessão ${e.key}: não suspensa — $err');
      }
    }
    return closed;
  }

  /// Limits of the agent (DT-23): budget from `agent_settings` of the
  /// effective definition (project wins) → `--max-budget-usd`; `maxTurns` of
  /// the frontmatter → `--max-turns` (passed explicitly: not verified that
  /// `--agent` applies it to the main thread). Errors = no limits.
  Future<({double? budgetUsd, int? maxTurns})> _agentLimits(
    String? agent,
    String? workspacePath,
  ) async {
    if (agent == null || agent.isEmpty) {
      return (budgetUsd: null, maxTurns: null);
    }
    try {
      final entry = await ref
          .read(agentRepositoryProvider(workspacePath))
          .find(agent);
      if (entry == null) return (budgetUsd: null, maxTurns: null);
      final setting = await ref
          .read(agentSettingsRepoProvider)
          .get(agent, entry.scope);
      final budget = setting?.budgetUsd;
      final turns = entry.file.maxTurns;
      return (
        budgetUsd: budget != null && budget > 0 ? budget : null,
        maxTurns: turns != null && turns >= 1 ? turns : null,
      );
    } catch (e) {
      debugPrint('agente $agent: limites não lidos — $e');
      return (budgetUsd: null, maxTurns: null);
    }
  }

  /// MCP tool rules (Fase 11): "Permitido" → `--allowedTools`, "Bloqueado"
  /// → `--disallowedTools`. Sessions have no read-only mode, so "Permitido"
  /// always applies (re-read on every start / resume / fork).
  Future<McpRuleArgs> _mcpRules() =>
      readMcpRuleArgs(ref.read(mcpToolRulesRepoProvider));

  // --- process lifecycle -----------------------------------------------------

  Future<void> _start(
    String id,
    ClaudeOptions options, {
    required String cwd,
    required String title,
    double baseCost = 0,
    String? root,
    Map<String, String>? environment,
  }) async {
    if (_shuttingDown) {
      throw const SessionException('O aplicativo está sendo encerrado.');
    }
    final session = (await _repo.getById(id))!;
    final ManagedAgentRun process;
    try {
      if (session.provider != 'claude') {
        final saved = session.runConfig == null
            ? <String, dynamic>{}
            : jsonDecode(session.runConfig!) as Map<String, dynamic>;
        String? externalId;
        if (options.resumeId != null) {
          final source = await _repo.getById(options.resumeId!);
          if (source != null && source.provider != session.provider) {
            throw const AgentUnavailable(
              'Não é possível retomar uma sessão Claude no Codex.',
            );
          }
          externalId =
              source?.externalId ?? (source == null ? options.resumeId : null);
          if (externalId == null) {
            throw const AgentUnavailable(
              'A sessão Codex não tem thread externa para retomar.',
            );
          }
        }
        final effective = AgentStartOptions(
          workingDirectory: cwd,
          mode: PromptMode.edit,
          resumeId: externalId,
          forkSession: options.forkSession,
          model: options.model,
          effort: options.effort,
          permissionMode: options.permissionMode,
          environment: environment,
          autocompact: saved['autocompact'] as String?,
          agent: options.agent,
          maxBudgetUsd: options.maxBudgetUsd,
          maxTurns: options.maxTurns,
          mcpAllowedTools: options.allowedTools,
          mcpDisallowedTools: options.disallowedTools,
        );
        final run = await ref
            .read(agentProviderByIdProvider(session.provider))
            .start(effective);
        process = run as ManagedAgentRun;
        await _repo.setRunConfig(
          id,
          jsonEncode({
            'provider': session.provider,
            'mode': 'edit',
            'permissionMode': options.permissionMode?.cliValue,
            'model': session.model,
            'effort': session.effort,
            if (effective.autocompact != null)
              'autocompact': effective.autocompact,
          }),
        );
      } else if (session.provider == 'claude') {
        final settingsFile = await _prepareHooks(id, cwd: cwd, root: root);
        process = ClaudeRun(
          await ClaudeProcess.start(
            options.copyWith(
              autocompact: ref.read(runPrefsProvider).autocompact,
              settingsFile: settingsFile,
            ),
            workingDirectory: cwd,
            executable: ref.read(claudeExecutableProvider),
            starter: ref.read(claudeProcessStarterProvider),
            environment: environment,
          ),
        );
      } else {
        throw AgentUnavailable(
          'Provedor de sessão não suportado: ${session.provider}.',
        );
      }
    } catch (e) {
      await _note(id, 'Falha ao iniciar ${session.provider}: $e', error: true);
      await _repo.setStatus(id, SessionStatus.failed);
      throw SessionException('Falha ao iniciar ${session.provider}: $e');
    }
    final p = _Proc(
      process,
      title,
      baseCost,
      skipPermissions:
          options.permissionMode == ClaudePermissionMode.skipPermissions,
    );
    _procs[id] = p;
    try {
      await _repo.setPid(id, process.pid);
    } catch (e) {
      debugPrint('sessão $id: pid não gravado — $e');
    }
    if (environment != null) {
      ref.read(worktreeEnvProvider.notifier).set(cwd, environment);
    }
    p.logSub = process.logs.listen(
      (l) => debugPrint('${session.provider}[$id] $l'),
      onError: (_) {},
    );
    p.sub = process.events.listen(
      (e) => _enqueue(id, p, () => _handle(id, p, e)),
      onDone: () => _enqueue(id, p, () => _onExit(id, p)),
    );
    _publish();
  }

  /// A new session / fork worktree: `copiar:` and `preparar:` of the
  /// project's config. Failure removes the worktree (nothing was done in
  /// it yet) and is reported to the caller.
  Future<void> _setupWorktree(String root, CreatedWorktree wt) async {
    final config = ProjectConfig.loadSync(root);
    final wc = config.worktree;
    if (wc.copy.isEmpty && wc.prepare == null) return;
    final git = ref.read(gitServiceFactoryProvider)(root);
    final r =
        await WorktreeSetup(
          root: git,
          shell: ref.read(shellRunnerProvider),
        ).run(
          wt.path,
          copy: wc.copy,
          prepare: wc.prepare,
          timeout: config.gate.timeout,
          environment: worktreeEnvironment(root: root, worktree: wt.path),
        );
    if (r.ok) return;
    try {
      await git.removeWorktree(wt.path, force: true);
      await git.deleteBranch(wt.branch, force: true);
    } on GitException catch (e) {
      debugPrint('worktree ${wt.path} não removido — $e');
    }
    throw GitException(
      'preparar: (${wc.prepare}) falhou',
      stdout: r.prepare!.output,
    );
  }

  /// `PROMPTORIUM_*` of a stored session (spec code and port when it works
  /// on a spec).
  Future<Map<String, String>> _environmentOf(Session s, Workspace ws) async {
    final spec = s.specId == null
        ? null
        : await ref.read(specsRepoProvider).getById(s.specId!);
    final base = spec == null
        ? null
        : ProjectConfig.loadSync(ws.path).worktree.basePort;
    return worktreeEnvironment(
      root: ws.path,
      worktree: s.worktreePath,
      specCode: spec?.code,
      port: base == null || spec?.worktreeIndex == null
          ? null
          : base + spec!.worktreeIndex!,
    );
  }

  /// The app's hooks of the session (`--settings`); null = none (off in
  /// Configurações → Automações, no `python3`, or an error writing them).
  Future<String?> _prepareHooks(
    String id, {
    required String cwd,
    String? root,
  }) async {
    final extra = disabledExtensionsJson(ref.read(runExtensionsProvider));
    final hooks = ref.read(managedHooksProvider);
    // No hooks of the app (tests, no python3): only the extensions turned
    // off, if any (SPEC-017 R2).
    Future<String?> plain() =>
        writeRunSettings(ref.read(runSettingsDirProvider), extra);
    if (hooks == null) return plain();
    await _hookCleanups[id];
    try {
      if (!await pythonAvailable()) return await plain();
      final settings = ref.read(appSettingsProvider.notifier);
      final enabled = {
        for (final h in ManagedHook.values)
          if (settings.get(h.settingKey) != '0') h,
      };
      final config = root == null ? null : ProjectConfig.loadSync(root);
      return await hooks.prepare(
        id,
        enabled: enabled,
        rules: blockRules(
          projectGlobs: config?.blockedCommands ?? const [],
          root: root,
          cwd: cwd,
        ),
        formatCommand: config?.formatCommand,
        extra: extra,
      );
    } catch (e) {
      debugPrint('sessão $id: hooks do app não preparados — $e');
      return null;
    }
  }

  /// New lines of the session's hooks log → timeline notes.
  Future<void> _readHooks(String id, _Proc p) async {
    final hooks = ref.read(managedHooksProvider);
    if (hooks == null) return;
    try {
      final (items, offset) = await hooks.readLog(id, p.hookOffset);
      p.hookOffset = offset;
      for (final a in items) {
        await _note(id, a.text, error: a.error);
        if (ref.mounted) ref.read(hookActivityProvider.notifier).add(a);
      }
    } catch (e) {
      debugPrint('sessão $id: log de hooks não lido — $e');
    }
  }

  Future<void> _enqueue(String id, _Proc p, Future<void> Function() job) {
    final next = p.queue.then((_) => job()).catchError((
      Object e,
      StackTrace st,
    ) {
      debugPrint('sessão $id: $e\n$st');
    });
    p.queue = next;
    return next;
  }

  Future<void> _handle(String id, _Proc p, ClaudeEvent e) async {
    if (!ref.mounted) return;
    p.lastActivity = DateTime.now();
    // 1. Persist (one row per stdout line; stream deltas are not stored).
    int? seq;
    if (e is! StreamDelta && e is! StreamOther) {
      if (identical(e.json, p.lastJson) && e.json.isNotEmpty) {
        seq = p.lastSeq; // same line expanded into several ToolResults
      } else {
        final row = await _repo.appendEvent(
          id,
          type: eventTypeKey(e),
          json: eventJson(e),
        );
        p
          ..lastJson = e.json
          ..lastSeq = row.seq;
        seq = row.seq;
      }
    }

    // 2. Status / usage.
    switch (e) {
      case SystemInit():
        if (e.sessionId != null) await _repo.setExternalId(id, e.sessionId!);
        await recordKnownExtensions(ref, e.json);
        state = SessionManagerState(live: state.live, lastInit: e);
      case PermissionRequest():
        p.pending.add(e);
        p.pendingAt[e.requestId] = DateTime.now();
        await _repo.setStatus(id, SessionStatus.waitingApproval);
        await _syncTask(id, SessionStatus.waitingApproval);
        await _specs.onActive(id);
        _notify(
          'Aprovação pendente',
          '${p.title}: ${e.displayName ?? e.toolName} '
              '${toolTarget(e.toolName, e.input)}',
          id,
          approval: true,
        );
      case ControlCancel():
        if (_take(id, e.requestId) != null) await _afterAnswer(id);
      case AssistantMessage():
        if (e.json['message'] case {'usage': final Map<String, dynamic> u}
            when e.parentToolUseId == null) {
          final usage = Usage.fromJson(u);
          final ctx =
              usage.inputTokens +
              usage.cacheReadInputTokens +
              usage.cacheCreationInputTokens;
          if (ctx > 0) p.contextTokens = ctx;
        }
        for (final b in e.blocks) {
          if (b is ToolUseBlock && ToolItem.isSubagentTool(b.name)) {
            p.subagents.add(b.id);
          }
        }
      case ToolResult():
        p.subagents.remove(e.toolUseId);
        await _readHooks(id, p);
      case Result():
        p.lastCost = math.max(p.lastCost, e.totalCostUsd);
        final u = e.usage;
        await _repo.recordResult(
          id,
          totalCostUsd: p.lastCost,
          tokensIn:
              u.inputTokens +
              u.cacheCreationInputTokens +
              u.cacheReadInputTokens,
          tokensOut: u.outputTokens,
        );
        p.subagents.clear();
        p.busy = false;
        p.busySince = null;
        _publish();
        final status = e.isSuccess
            ? SessionStatus.completed
            : SessionStatus.failed;
        await _repo.setStatus(id, status);
        await _syncTask(id, status, fromResult: true);
        await _specs.onResult(id, e);
        ref.invalidate(sessionChangesProvider(id));
        _notify(
          e.isSuccess ? 'Sessão concluída' : 'Sessão falhou',
          p.title,
          id,
        );
        // Not awaited: send() enqueues behind this job.
        if (_notices[id]?.isNotEmpty ?? false) {
          unawaited(Future<void>.microtask(() => _flushNotices(id)));
        }
      case RateLimit():
        await ref.read(usageTrackerProvider).handle(e);
      default:
        break;
    }

    // 3. Timeline.
    _timeline(id).push(e, seq: seq);
    if (e is AssistantMessage ||
        e is ToolResult ||
        e is Result ||
        e is PermissionRequest) {
      _publish();
    }
  }

  Future<void> _onExit(String id, _Proc p) async {
    try {
      await _recordExit(id, p);
    } finally {
      if (!p.exited.isCompleted) p.exited.complete();
    }
  }

  Future<void> _recordExit(String id, _Proc p) async {
    await p.logSub?.cancel();
    final code = await p.process.exitCode;
    _procs.remove(id);
    if (ref.mounted) {
      try {
        await _repo.setPid(id, null);
      } catch (_) {
        // the database is closing
      }
    }
    if (ref.mounted && !_shuttingDown) await _readHooks(id, p);
    final hooks = ref.mounted ? ref.read(managedHooksProvider) : null;
    if (hooks != null) {
      final done = hooks.cleanup(id).catchError((Object e) {
        debugPrint('sessão $id: hooks não removidos — $e');
      });
      _hookCleanups[id] = done;
      unawaited(
        done.whenComplete(() {
          if (_hookCleanups[id] == done) _hookCleanups.remove(id);
        }),
      );
    }
    if (!ref.mounted || _shuttingDown) return;
    if (p.released) {
      _publish();
      return;
    }
    _publish();
    final s = await _repo.getById(id);
    if (s == null) return;
    if (p.stopping) {
      await _note(id, 'Sessão parada pelo usuário');
      await _repo.setStatus(id, SessionStatus.stopped);
      await _specs.onEnded(id, SessionStatus.stopped);
    } else if (!s.status.isTerminal) {
      await _note(
        id,
        'O processo do Claude Code encerrou (código $code)',
        error: true,
      );
      await _repo.setStatus(id, SessionStatus.failed);
      await _specs.onEnded(id, SessionStatus.failed);
      _notify('Sessão falhou', '${p.title}: processo encerrou ($code)', id);
    }
  }

  PermissionRequest? _take(String id, String requestId) {
    final p = _procs[id];
    if (p == null) return null;
    final i = p.pending.indexWhere((r) => r.requestId == requestId);
    if (i < 0) return null;
    final req = p.pending.removeAt(i);
    p.pendingAt.remove(requestId);
    _publish();
    return req;
  }

  /// After the last pending request is answered: waiting → running.
  Future<void> _afterAnswer(String id) async {
    if (_procs[id]?.pending.isNotEmpty ?? false) return;
    final s = await _repo.getById(id);
    if (s?.status == SessionStatus.waitingApproval) {
      await _repo.setStatus(id, SessionStatus.running);
    }
  }

  void _publish() {
    if (!ref.mounted) return;
    state = SessionManagerState(
      lastInit: state.lastInit,
      live: {
        for (final MapEntry(:key, :value) in _procs.entries)
          key: LiveSession(
            alive: value.process.isRunning,
            subagentsRunning: value.subagents.length,
            busySince: value.busy ? value.busySince : null,
            approvals: [
              for (final r in value.pending)
                PendingApproval(
                  sessionId: key,
                  sessionTitle: value.title,
                  request: r,
                  receivedAt: value.pendingAt[r.requestId] ?? value.started,
                ),
            ],
          ),
      },
    );
  }

  // --- helpers ---------------------------------------------------------------

  SessionsRepo get _repo => ref.read(sessionsRepoProvider);

  /// Moves the session's task (`sessions.task_id`) on the kanban
  /// ([taskStatusForSession]). Errors only log.
  Future<void> _syncTask(
    String id,
    SessionStatus status, {
    bool fromResult = false,
  }) async {
    try {
      final taskId = (await _repo.getById(id))?.taskId;
      if (taskId == null) return;
      final tasks = ref.read(tasksRepoProvider);
      final task = await tasks.getById(taskId);
      if (task == null) return;
      final next = taskStatusForSession(
        task.status,
        status,
        fromResult: fromResult,
      );
      if (next != null) await tasks.setStatus(taskId, next);
    } catch (e) {
      debugPrint('sessão $id: tarefa não atualizada — $e');
    }
  }

  SpecRunner get _specs => ref.read(specRunnerProvider);

  SessionTimelineNotifier _timeline(String id) =>
      ref.read(sessionTimelineProvider(id).notifier);

  Future<void> _note(String id, String text, {bool error = false}) async {
    final json = AppEventTypes.noteMessage(text, error: error);
    final row = await _repo.appendEvent(
      id,
      type: AppEventTypes.note,
      json: _encode(json),
    );
    _timeline(id).push(UnknownEvent(json), seq: row.seq);
  }

  /// Native notification. The click goes back to the screen the session was
  /// created from; approvals always go to Sessões (only answered there).
  void _notify(String title, String body, String id, {bool approval = false}) {
    final section = approval
        ? AppSection.sessions
        : (_origins[id] ?? AppSection.sessions);
    unawaited(
      ref
          .read(notificationsRepoProvider)
          .add(title: title, body: body, section: section.name, sessionId: id)
          .catchError((Object e) => debugPrint('notificação não gravada: $e')),
    );
    ref
        .read(appNotifierProvider)
        .show(
          title,
          body,
          onClick: () {
            final origin = _origins[id] ?? AppSection.sessions;
            ref.read(selectedSessionProvider.notifier).select(id);
            ref
                .read(navigationProvider.notifier)
                .go(approval ? AppSection.sessions : origin);
          },
        );
  }

  static String? _model(String m) => m.isEmpty || m == 'inherit' ? null : m;

  /// Stored effort of a session (null for rows before schema v7 = default).
  String? _effort(String? stored) =>
      effortArg(stored ?? ref.read(runPrefsProvider).effort(RunKind.session));

  static String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

  static String _titleOf(Session s) =>
      (s.title?.isNotEmpty ?? false) ? s.title! : 'Sessão ${_short(s.id)}';

  static String _encode(Map<String, dynamic> j) => jsonEncode(j);
}

/// "Sem perguntar" never runs in the workspace root (F12): a stored
/// session there resumes in the default mode.
ClaudePermissionMode? skipOnlyInWorktree(
  ClaudePermissionMode? mode, {
  required String worktree,
  required String? root,
}) => mode == ClaudePermissionMode.skipPermissions && worktree == root
    ? ClaudePermissionMode.defaultMode
    : mode;

/// Title shown for a session row.
String sessionTitle(Session s) => (s.title?.isNotEmpty ?? false)
    ? s.title!
    : 'Sessão ${s.id.substring(0, math.min(8, s.id.length))}';

/// ASCII, lowercase, `-`-separated slug of [text] (accents folded), at most
/// [maxLength] characters. May be empty.
String slugify(String text, {int maxLength = 32}) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final buf = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  var slug = buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > maxLength) {
    slug = slug.substring(0, maxLength).replaceAll(RegExp(r'-+$'), '');
  }
  return slug;
}

/// Worktree slug: ascii lowercase title + 6 chars of the id
/// (`GitService.slugPattern`).
String sessionSlug(String title, String id) {
  final slug = slugify(title);
  final suffix = id.replaceAll('-', '');
  final tail = suffix.substring(0, math.min(6, suffix.length)).toLowerCase();
  return slug.isEmpty ? 'sessao-$tail' : '$slug-$tail';
}

/// `PROMPTORIUM_*` of each worktree that had a session in this app session,
/// by path (the embedded terminals use them).
class WorktreeEnvs extends Notifier<Map<String, Map<String, String>>> {
  @override
  Map<String, Map<String, String>> build() => const {};

  void set(String path, Map<String, String> env) =>
      state = {...state, path: env};
}

final worktreeEnvProvider =
    NotifierProvider<WorktreeEnvs, Map<String, Map<String, String>>>(
      WorktreeEnvs.new,
    );

final sessionManagerProvider =
    NotifierProvider<SessionManager, SessionManagerState>(SessionManager.new);

/// Session shown in the Sessions screen (null = first of the list).
class SelectedSession extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedSessionProvider = NotifierProvider<SelectedSession, String?>(
  SelectedSession.new,
);
