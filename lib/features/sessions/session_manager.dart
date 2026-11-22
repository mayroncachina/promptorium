import 'dart:async';
import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/memory/ai_memory_env.dart';
import '../../core/claude/claude_args.dart';
import '../../core/claude/claude_cli.dart';
import '../../core/claude/claude_event.dart';
import '../../core/claude/claude_process.dart';
import '../../core/codex/codex_provider.dart' show CodexRun;
import '../../core/git/worktree_roots.dart';
import '../../core/codex/codex_probe.dart' show codexNoSandboxMessage;
import '../../core/providers/provider_availability.dart';
import '../../ui/providers/provider_logos.dart' show providerModelLabel;
import '../../core/claude/managed_hooks.dart';
import '../../core/claude/run_extensions.dart';
import '../../core/claude/run_prefs.dart';
import '../../core/claude/usage_tracker.dart';
import '../../core/providers/agent_registry.dart';
import '../../core/providers/permission_policy.dart';
import '../../core/providers/provider_preferences.dart';
import '../../core/git/agent_trailer.dart';
import '../../core/git/git_service.dart';
import '../../core/git/worktree_setup.dart';
import '../../core/mcp/app_mcp_config.dart';
import '../../core/mcp/app_mcp_server.dart' show AppMcpServer, McpAccess;
import '../../core/mcp/app_mcp_tools.dart' show alwaysAllowSuggestions;
import '../../core/process/shell_runner.dart';
import '../../core/secrets/secret_guard.dart';
import '../../core/secrets/secret_scanner.dart';
import '../../data/providers.dart';
import '../../data/repos/durable_state_repo.dart';
import '../../data/repos/sessions_repo.dart';
import '../../ui/shell/navigation.dart';
import '../agents/agent_repository.dart';
import '../board/spec_runner.dart';
import '../mcp/mcp_rules.dart';
import '../prompt/conversation_manager.dart' show conversationManagerProvider;
import '../project/project_config.dart';
import '../review/ci_fixer.dart' show ciFixerProvider;
import '../review/conflict_resolution.dart' show conflictResolverProvider;
import '../secrets/secret_blocks.dart';
import '../notifications/agent_alerts.dart' show alertSettingsProvider;
import '../tasks/task_rules.dart';
import 'app_notifier.dart';
import '../cost/usage_ledger.dart';
import 'restore/restore_service.dart';
import 'session_changes.dart';
import 'session_composer_draft.dart';
import '../context/compaction_controller.dart';
import '../context/context_tracker.dart';
import 'timeline.dart';
import 'timeline_provider.dart';

export '../../core/claude/claude_cli.dart' show claudeProcessStarterProvider;

/// Generates session ids (`--session-id`, UUID v4).
/// Prefix of the session row that carries a VIBE through the Review
/// (SPEC-069 R7): the VIBE talks in a conversation of the Prompt, so what
/// the Review sends to that session goes to the conversation.
const vibeSessionPrefix = 'vibe-';

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
    this.prUrl,
    this.draft = false,
    this.parentSessionId,
    this.startEvent,
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

  /// PR the session works on from the start ("Trazer PR", SPEC-050 R3);
  /// stored before the process starts, so its hooks already refuse the
  /// forced pushes (R7).
  final String? prUrl;

  /// SPEC-099 P1: the process starts idle and [prompt] goes to the
  /// session's message field ([sessionComposerDraftProvider]); nothing is
  /// sent until the person sends it. An empty prompt is allowed.
  final bool draft;

  /// The session this one continues (SPEC-099 R9; the link of SPEC-096).
  final String? parentSessionId;

  /// App event written before anything else (the "continuação" record,
  /// SPEC-099 P5): the note at the top of the timeline.
  final Map<String, dynamic>? startEvent;
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

/// One tool call of a live session (SPEC-076 R3): what the Atividades and
/// the robots show. [input] is the raw input (the target is computed with
/// the session's worktree as root).
@immutable
class LiveTool {
  const LiveTool({
    required this.id,
    required this.name,
    required this.input,
    required this.at,
    this.done = false,
    this.kind = LiveToolKind.tool,
    this.files = const [],
  });

  /// A Claude tool call, seen through its neutral events (SPEC-095 R9).
  factory LiveTool.fromBlock(ToolUseBlock b, {DateTime? at}) {
    final files = b.fileChanges;
    return LiveTool(
      id: b.id,
      name: b.name,
      input: b.input,
      at: at ?? DateTime.now(),
      kind: files.isNotEmpty
          ? LiveToolKind.file
          : b.command != null
          ? LiveToolKind.command
          : LiveToolKind.tool,
      files: [for (final f in files) f.path],
    );
  }

  final String id;
  final String name;
  final Map<String, dynamic> input;
  final DateTime at;

  /// Its result arrived: the agent is between tools (thinking).
  final bool done;

  /// What the call does, whatever the provider.
  final LiveToolKind kind;

  /// Files it changes.
  final List<String> files;

  LiveTool finished() => LiveTool(
    id: id,
    name: name,
    input: input,
    at: at,
    done: true,
    kind: kind,
    files: files,
  );
}

/// What a live tool call does (SPEC-095): the Atividades pick the pose from
/// it, not from a tool name.
enum LiveToolKind { tool, file, command }

/// The live tool of a neutral event (a Codex file change or command), or
/// null (SPEC-095 R9).
LiveTool? liveToolOfNeutral(AgentEvent e, {DateTime? at}) => switch (e) {
  FileChangeEvent() => LiveTool(
    id: e.toolUseId,
    name: NeutralToolNames.file,
    input: {'path': e.path},
    at: at ?? DateTime.now(),
    done: e.status != FileChangeStatus.proposed,
    kind: LiveToolKind.file,
    files: [e.path],
  ),
  CommandEvent() => LiveTool(
    id: e.toolUseId,
    name: NeutralToolNames.command,
    input: {'command': e.displayCommand},
    at: at ?? DateTime.now(),
    done: e.done,
    kind: LiveToolKind.command,
  ),
  _ => null,
};

/// Records the neutral live tool [t] in [recent] (newest first, five at
/// most): a new call is inserted (true), a known one updated (its files
/// merged, done when it ends).
bool recordLiveTool(List<LiveTool> recent, LiveTool t) {
  final i = recent.indexWhere((x) => x.id == t.id);
  if (i < 0) {
    recent.insert(0, t);
    if (recent.length > 5) recent.removeLast();
    return true;
  }
  final old = recent[i];
  recent[i] = LiveTool(
    id: old.id,
    name: old.name,
    input: old.input,
    at: old.at,
    done: t.done,
    kind: old.kind,
    files: {...old.files, ...t.files}.toList(),
  );
  return false;
}

/// Runtime state of a session with a live process.
@immutable
class LiveSession {
  const LiveSession({
    this.alive = true,
    this.approvals = const [],
    this.subagentsRunning = 0,
    this.busySince,
    this.tool,
    this.recent = const [],
    this.calls = 0,
    this.files = 0,
    this.lastText,
  });

  /// The newest top-level tool call of the turn (null = none yet).
  final LiveTool? tool;

  /// The last five top-level tool calls, newest first.
  final List<LiveTool> recent;

  /// Tool calls / files edited in the running (or last) turn.
  final int calls;
  final int files;

  /// The newest text of the agent (one line, cut).
  final String? lastText;

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
/// Records the top-level tool call [b] in [p] (SPEC-076 R3).
void _trackTool(_Proc p, ToolUseBlock b) {
  if (p.recent.any((t) => t.id == b.id)) return;
  final t = LiveTool.fromBlock(b);
  p.recent.insert(0, t);
  if (p.recent.length > 5) p.recent.removeLast();
  p.calls++;
  p.files.addAll(t.files);
}

/// Records a neutral file change or command in [p] (SPEC-095 R9): one call
/// per item, every file it changes.
void _trackNeutral(_Proc p, AgentEvent e) {
  final t = liveToolOfNeutral(e);
  if (t == null) return;
  if (!p.seenNeutral.contains(t.id)) {
    p.seenNeutral.add(t.id);
    p.calls++;
  }
  recordLiveTool(p.recent, t);
  p.files.addAll(t.files);
}

/// The agent's text as one line of at most 200 characters.
String liveTextLine(String text) {
  final one = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return one.length <= 200 ? one : '${one.substring(0, 199)}…';
}

class _Proc {
  _Proc(
    this.process,
    this.title,
    this.lastCost, {
    this.skipPermissions = false,
  });

  final ManagedAgentRun process;
  String title;

  /// Workspace of the session (SPEC-096 R15).
  int? workspaceId;

  /// "Codex · gpt-6.2-sol" of a session not run by the Claude Code: goes
  /// with its notifications (SPEC-096 R3). Null for Claude.
  String? who;

  /// Started with `--dangerously-skip-permissions` (a start flag: a live
  /// switch to another mode does not undo it).
  final bool skipPermissions;

  /// Highest cumulative `total_cost_usd` seen (the session cost).
  double lastCost;

  /// Last `total_cost_usd` of this process (the cost of a turn is the
  /// difference; SPEC-081 R1). Null before its first `result`.
  double? seenCost;
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

  /// Ids of the neutral calls of the turn already counted (SPEC-095).
  final Set<String> seenNeutral = {};

  /// A message was sent and its `result` has not arrived yet (turn running).
  bool busy = false;

  /// When [busy] became true.
  DateTime? busySince;

  /// "Compactar agora" is running (SPEC-087 R9): its `result` only closes
  /// the request — no status, gate, review or notification.
  bool compacting = false;

  /// Set by [SessionManager.release]: the exit records nothing.
  bool released = false;

  /// Completed once [SessionManager._onExit] ran.
  final Completer<void> exited = Completer<void>();

  /// Workspace whose `git: marcar-commits-de-agente` this process started
  /// with (SPEC-048): its commits carry the trailer until it ends.
  String? markedRoot;
  Future<void> queue = Future.value();
  Map<String, dynamic>? lastJson;
  int? lastSeq;

  /// Link of the process to the Promptorium MCP (SPEC-052): revoked and
  /// its file removed when the process ends.
  McpRunLink? mcp;
  AppMcpServer? mcpServer;

  /// Bytes of the hooks log already shown.
  int hookOffset = 0;

  /// SPEC-076 R3: the newest tool calls (newest first), calls and edited
  /// files of the turn, and the agent's newest text.
  final List<LiveTool> recent = [];
  int calls = 0;
  final Set<String> files = {};
  String? lastText;

  /// The usage limit of this turn was noted (SPEC-099 R2): once per turn.
  bool limitNoted = false;
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

  /// Restore point of the first message of a session, recorded by [create]
  /// before the process starts (SPEC-084 R1).
  final Map<String, RestorePoint?> _firstPoints = {};

  /// Screen that was open when each session was created (Tarefas, Projeto,
  /// Skills…): clicking its "concluída / falhou" notification goes back
  /// there. Kept for the app session only (default: Sessões).
  final Map<String, AppSection> _origins = {};

  /// Set by [shutdown]: exits are not recorded (the next launch marks the
  /// sessions as interrupted) and no new process starts.
  bool _shuttingDown = false;

  /// Sessions whose hook has the Vigia de segredos (SPEC-085 R1); the
  /// others are checked at the end of each turn (R2).
  final Set<String> _secretHooks = {};

  /// Sessions told once that they have no hook (R2), and the findings
  /// already shown by the end-of-turn check.
  final Set<String> _secretNoHookNoted = {};

  /// Claude sessions started without `python3` (no hook at all, R2).
  final Set<String> _noPython = {};

  /// Tests have no hooks: let them exercise the end-of-turn check (R2).
  @visibleForTesting
  static bool secretTurnCheckWithoutHooks = false;
  final Map<String, Set<String>> _secretSeen = {};

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
    if (prompt.isEmpty && !r.draft) {
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
        await setupWorktree(ws.path, wt);
      } else {
        branch = await git.currentBranch() ?? 'HEAD';
      }
    } on GitException catch (e) {
      throw SessionException('Falha ao criar o worktree: $e');
    }
    // SPEC-096 R10a: without the sandbox, the Codex runs only in a worktree
    // with full access (and the app commits at the end of the turn).
    if (provider == ProviderCapabilities.codex.providerId &&
        ref
                .read(providerAvailabilityProvider(provider))
                .value
                ?.sandboxWarning !=
            null &&
        (path == ws.path ||
            r.permissionMode != ClaudePermissionMode.skipPermissions)) {
      if (r.useWorktree && r.worktreePath == null && path != ws.path) {
        try {
          await git.removeWorktree(path, force: true);
          await git.deleteBranch(branch, force: true);
        } on GitException catch (e) {
          debugPrint('worktree $path não removido — $e');
        }
      }
      throw SessionException(codexNoSandboxMessage());
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
        providerEffortFrom(
          ref.read(runPrefsProvider),
          ref.read(appSettingsProvider),
          provider,
          RunKind.session,
        );
    await _repo.insert(
      id: id,
      workspaceId: ws.id,
      worktreePath: path,
      branch: branch,
      model: r.model,
      provider: provider,
      externalId: isClaudeCode(provider) ? id : null,
      effort: effort,
      agentName: r.agent,
      title: title,
      permissionMode: r.permissionMode.cliValue,
      taskId: r.taskId,
      specId: r.specId,
      steps: r.steps,
      baseBranch: base,
      duelId: r.duelId,
      parentSessionId: r.parentSessionId,
    );
    if (r.prUrl != null) await _repo.setPrUrl(id, r.prUrl!);
    if (r.startEvent != null) await _appEvent(id, r.startEvent!);
    if (r.origin != null) await _note(id, r.origin!);
    if (r.draft) {
      // SPEC-099 P1: idle, with the message in the field.
      await _startNew(id, r, provider: provider, effort: effort, path: path);
      await _repo.setStatus(id, SessionStatus.completed);
      if (prompt.isNotEmpty) {
        ref.read(sessionComposerDraftProvider.notifier).put(id, prompt);
      }
      return id;
    }
    // SPEC-084 R1: the point of the first turn before the agent starts (its
    // start competes with the git work for the machine).
    _firstPoints[id] = await _checkpoint(id, prompt);
    await _startNew(id, r, provider: provider, effort: effort, path: path);
    try {
      await send(id, prompt);
    } finally {
      _firstPoints.remove(id);
    }
    return id;
  }

  /// The first process of a new session ([create]).
  Future<void> _startNew(
    String id,
    NewSessionRequest r, {
    required String provider,
    required String? effort,
    required String path,
  }) async {
    final ws = r.workspace;
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
      title: r.title.trim(),
      root: ws.path,
      environment: env,
    );
  }

  /// Sends a user message; resumes the session (`--resume`, same worktree)
  /// when it has no live process.
  Future<void> send(
    String id,
    String text, {
    List<ImagePart> images = const [],
  }) async {
    var msg = text.trim();
    if (msg.isEmpty) return;
    // SPEC-069 R7: the Review talks to a VIBE in its conversation.
    if (id.startsWith(vibeSessionPrefix)) {
      final s = await _repo.getById(id);
      final conv = s?.specId == null
          ? null
          : await ref.read(specsRepoProvider).conversationOf(s!.specId!);
      if (conv == null) {
        throw const SessionException('A conversa desta VIBE não existe mais.');
      }
      // SPEC-081 P6: a mark of the CI fixer goes with the message.
      ref.read(usageLedgerProvider).moveMark(id, conv.id);
      await ref.read(conversationManagerProvider.notifier).send(conv.id, msg);
      return;
    }
    // SPEC-071 R7: a message is activity from now on, so [closeIdle] does
    // not close the process while it is on its way.
    _procs[id]?.lastActivity = DateTime.now();
    final notices = await _takeNotices(id);
    if (notices != null && notices.isNotEmpty) {
      msg = '${notices.join('\n')}\n\n$msg';
    }
    var p = await _liveProc(id);
    if (p == null) {
      await resume(id);
      p = _procs[id];
      if (p == null) return;
    }
    final proc = p;
    // Busy before the queue (R7): the turn is this message's.
    proc.busy = true;
    proc.busySince = DateTime.now();
    proc.lastActivity = DateTime.now();
    // A new turn counts its own calls and files (SPEC-076 R3).
    proc
      ..calls = 0
      ..files.clear()
      ..seenNeutral.clear()
      ..limitNoted = false;
    _publish();
    // SPEC-084 R1: the restore point of the turn, before the message goes
    // (the first one was recorded by [create]).
    final point = _firstPoints.containsKey(id)
        ? _firstPoints.remove(id)
        : await _checkpoint(id, text);
    await _enqueue(id, proc, () async {
      final json = AppEventTypes.userMessage(msg, DateTime.now());
      final row = await _repo.appendEvent(
        id,
        type: AppEventTypes.user,
        json: _encode(json),
      );
      _timeline(id).push(UnknownEvent(json), seq: row.seq);
      if (point != null) await _restore.attachSeq(point.id, row.seq);
      await _repo.setStatus(id, SessionStatus.running);
      await _syncTask(id, SessionStatus.running);
      await _specs.onActive(id);
    });
    await proc.process.send(msg, images: images);
  }

  /// "Compactar agora" (SPEC-087 R9): the native `/compact` on the idle
  /// process (resumed when closed), one request at a time. The session's
  /// permissions stay as they are; a failure keeps the history.
  Future<void> compactNow(String id, {String? focus}) async {
    final s = await _repo.getById(id);
    if (s == null) throw SessionException('Sessão $id não existe.');
    if (!isClaudeCode(s.provider)) {
      throw const SessionException(
        'Este agente não tem um comando nativo de compactação confirmado.',
      );
    }
    var p = await _liveProc(id);
    if (p != null && (p.busy || p.compacting)) {
      throw const SessionException(
        'Espere a resposta atual: compactar só com o agente ocioso.',
      );
    }
    if (p == null) {
      await resume(id);
      p = _procs[id];
      if (p == null) return;
    }
    final proc = p;
    proc
      ..busy = true
      ..compacting = true
      ..busySince = DateTime.now()
      ..lastActivity = DateTime.now();
    _publish();
    await _note(id, 'Compactação pedida pelo app (/compact).');
    await proc.process.send(compactCommand(focus));
  }

  /// Whether a message with images can go to the live process of [id] as
  /// images: a Codex model without the `image` modality cannot (SPEC-051
  /// R8). No live process = unknown (false).
  bool acceptsImages(String id) {
    final p = _procs[id]?.process;
    if (p == null) return false;
    return p is! CodexRun || p.supportsImages;
  }

  /// Restore point of the start of a turn (SPEC-084 R1–R4): a failure or
  /// files left out only become a line in the timeline; the turn goes on.
  Future<RestorePoint?> _checkpoint(String id, String text) async {
    try {
      final s = await _repo.getById(id);
      if (s == null) return null;
      final r = await _restore.start(
        workspaceId: s.workspaceId,
        worktree: s.worktreePath,
        sessionId: id,
        prompt: text,
      );
      if (r.failure != null) {
        await _note(id, 'Ponto de restauração não gravado: ${r.failure}');
      }
      if (r.large.isNotEmpty) await _note(id, largeFilesNote(r.large));
      return r.point;
    } catch (e) {
      debugPrint('sessão $id: ponto de restauração — $e');
      return null;
    }
  }

  /// "2 arquivos grandes fora do ponto: `dump.sql`, `video.mp4`" (R4).
  static String largeFilesNote(List<String> files) {
    final names = [for (final f in files) '`${f.split('/').last}`'].join(', ');
    return files.length == 1
        ? '1 arquivo grande fora do ponto: $names'
        : '${files.length} arquivos grandes fora do ponto: $names';
  }

  /// What the agent hears after an undo, with its next message (R8).
  static String undoNotice(int turn) =>
      'O usuário desfez o turno $turn; os arquivos voltaram ao estado '
      'anterior. Releia antes de alterar.';

  /// Keeps [text] for the next message of [id] (the path of the manual-edit
  /// notices), without starting a turn now (SPEC-084 R8).
  Future<void> queueNotice(String id, String text) async {
    final list = _notices.putIfAbsent(id, () => []);
    if (list.contains(text)) return;
    list.add(text);
    await _durable((r) => r.addNotice(id, text));
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
    // SPEC-084 R7: an edit during the turn is the person's too.
    _restore.noteUserEdit(id, path);
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

  /// A message of the app to the agent (the Vigia de segredos, SPEC-085
  /// R9): delivered like [notifyUserEdit] (now, in the running turn, or
  /// with the next message).
  ///
  /// [resume]: a session without a process is resumed with the message
  /// (the agent repeats the commit, R9).
  Future<bool> notifyAgent(
    String id,
    String text, {
    bool resume = false,
  }) async {
    final list = _notices.putIfAbsent(id, () => []);
    if (!list.contains(text)) {
      list.add(text);
      await _durable((r) => r.addNotice(id, text));
    }
    final p = _procs[id];
    if (p == null && resume && !_shuttingDown) {
      final all = await _takeNotices(id) ?? [text];
      try {
        await send(id, all.join('\n'));
        return true;
      } catch (e) {
        _notices.putIfAbsent(id, () => []).addAll(all);
        debugPrint('sessão $id: aviso do vigia fica para a próxima — $e');
        return false;
      }
    }
    if (p == null || p.pending.isNotEmpty || p.stopping) return false;
    if (p.busy) {
      await _sendMidTurn(id, p);
    } else {
      await _flushNotices(id);
    }
    return true;
  }

  /// Appends an app event of the Vigia de segredos to the session's
  /// timeline (`promptorium_secrets` / `promptorium_secret_resolved`).
  Future<void> appendSecretEvent(String id, Map<String, dynamic> json) async {
    final row = await _repo.appendEvent(
      id,
      type: '${json['type']}',
      json: _encode(json),
    );
    _timeline(id).push(UnknownEvent(json), seq: row.seq);
    _publish();
  }

  /// Rewrites the rules of the Vigia de segredos of every live session of
  /// [workspaceId] (a waiver was added or removed, R11).
  Future<void> refreshSecrets(int workspaceId) async {
    final hooks = ref.read(managedHooksProvider);
    if (hooks == null) return;
    for (final id in [..._secretHooks]) {
      try {
        final row = await _repo.getById(id);
        if (row == null || row.workspaceId != workspaceId) continue;
        final cwd = row.worktreePath;
        await hooks.writeSecrets(
          id,
          await ref
              .read(secretGuardProvider)
              .hookJson(workspaceId: workspaceId, root: cwd),
        );
      } catch (e) {
        debugPrint('sessão $id: regras do vigia não atualizadas — $e');
      }
    }
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

  /// The message of "Retomar" for an interrupted / failed session.
  static const continueMessage = 'Continue de onde parou.';

  /// "Retomar" of an interrupted / failed session: resumes it with
  /// [continueMessage], once (SPEC-071 R10): a second click while the first
  /// is on its way waits for it instead of sending the message again.
  Future<void> continueSession(String id) {
    return _continuing[id] ??= send(id, continueMessage).whenComplete(() {
      _continuing.remove(id);
    });
  }

  /// Whether [continueSession] or [resume] of [id] is under way.
  bool isResuming(String id) =>
      _continuing.containsKey(id) || _resuming.containsKey(id);

  final Map<String, Future<void>> _continuing = {};

  /// Starts `claude --resume <id>` in the session's worktree (no message).
  Future<void> resume(String id) async {
    if (await _liveProc(id) != null) return;
    return _resuming[id] ??= _resume(id).whenComplete(() {
      // Block body: returning the removed Future would await itself.
      _resuming.remove(id);
    });
  }

  Future<void> _resume(String id) async {
    if (id.startsWith(vibeSessionPrefix)) {
      throw const SessionException('Esta VIBE continua na conversa do Prompt.');
    }
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
    // SPEC-099 P1: a continued session whose message was never sent has
    // nothing for the CLI to resume: it starts again, as new.
    final fresh = !await _repo.hasEventOfType(id, AppEventTypes.user);
    await _start(
      id,
      ClaudeOptions(
        sessionId: fresh && isClaudeCode(s.provider) ? id : null,
        resumeId: fresh ? null : id,
        model: _model(s.model),
        effort: !isClaudeCode(s.provider)
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
        await setupWorktree(ws.path, wt);
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
      // SPEC-096 R16: "bifurcada de …".
      parentSessionId: id,
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
        effort: !isClaudeCode(parent.provider)
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
    // SPEC-052 R4: criar_* only ever "nesta sessão".
    final suggestions = alwaysAllowSuggestions(
      req.toolName,
      req.permissionSuggestions,
    );
    final suggestion = suggestions.isEmpty ? null : suggestions.first;
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

  /// "Interromper" (SPEC-096 R12): the Codex turn ends with
  /// `turn/interrupt` and the session becomes `interrupted` (never failed);
  /// the process stays for "Retomar". Other providers have no live
  /// interrupt here: [stop].
  Future<void> interrupt(String id) async {
    final p = _procs[id];
    if (p == null) return;
    if (p.process is CodexRun) {
      await p.process.interrupt();
      return;
    }
    await stop(id);
  }

  /// Whether the turn of [id] can be interrupted now (a Codex turn running).
  bool canInterrupt(String id) {
    final p = _procs[id];
    return p != null && p.busy && p.process is CodexRun;
  }

  Future<void> _markInterruptedByUser(String id) async {
    final s = await _repo.getById(id);
    if (s == null) return;
    final config = s.runConfig == null
        ? <String, dynamic>{}
        : jsonDecode(s.runConfig!) as Map<String, dynamic>;
    config['interrupted'] = 'user';
    await _repo.setRunConfig(id, jsonEncode(config));
  }

  /// R10, R10a: commits what the Codex left in its worktree at the end of
  /// a writing turn, with the agent's message as body and the trailer of
  /// SPEC-048. Never in the project root, never in Perguntar / Planejar.
  Future<void> _codexTurnCommit(String id, _Proc p, String? answer) async {
    final s = await _repo.getById(id);
    if (s == null) return;
    final ws = await ref.read(workspacesRepoProvider).getById(s.workspaceId);
    if (ws == null || s.worktreePath == ws.path) return;
    final access = AgentAccess.fromClaudeMode(
      ClaudePermissionMode.fromCli(s.permissionMode),
    );
    if (access == null ||
        access == AgentAccess.ask ||
        access == AgentAccess.plan) {
      return;
    }
    final git = ref.read(gitServiceFactoryProvider)(s.worktreePath);
    final config = ProjectConfig.loadSync(ws.path);
    final trailer = config.git.markAgentCommits
        ? agentTrailerLine(
            agentModelLabel(s.model, s.provider),
            await _agentOrigin(s),
          )
        : null;
    final committed = await git.commitAll(
      codexTurnCommitMessage(_titleOf(s), answer),
      trailer: trailer,
    );
    if (committed) {
      await _note(id, 'O app commitou o que o Codex deixou no worktree.');
      ref.invalidate(sessionChangesProvider(id));
    }
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
        !isClaudeCode(session.provider) &&
        current != null &&
        (current.busy ||
            current.pending.isNotEmpty ||
            current.subagents.isNotEmpty)) {
      throw const SessionException(
        'Pare o turno antes de alterar as permissões Codex.',
      );
    }
    await _repo.setPermissionMode(id, mode.cliValue);
    if (session != null && !isClaudeCode(session.provider)) {
      if (session.runConfig != null) {
        final config = jsonDecode(session.runConfig!) as Map<String, dynamic>;
        config['permissionMode'] = mode.cliValue;
        await _repo.setRunConfig(id, jsonEncode(config));
      }
      // R14: the Codex takes a policy per turn — an idle process keeps
      // running and the next turn/start uses the new access.
      if (current != null) {
        await current.process.setPermissionMode(mode);
        await _note(
          id,
          'Modo de permissão: ${permissionModeLabel(mode, provider: "codex")} '
          '(no próximo turno)',
        );
        return;
      }
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

  /// The process of [id], or null. One that already exited but whose end
  /// is not processed yet (suspended, killed) is waited for, up to 5 s, and
  /// then dropped: "Retomar" and a new message must start a new one, not
  /// write to a dead process.
  Future<_Proc?> _liveProc(String id) async {
    final p = _procs[id];
    // A released process is on its way out (SPEC-071 R7): wait for it and
    // resume, so nothing is written to it.
    if (p == null || (p.process.isRunning && !p.released)) return p;
    await p.exited.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    if (identical(_procs[id], p)) {
      _procs.remove(id);
      _publish();
    }
    return _procs[id];
  }

  /// Context of the session's last answer (null: no process or no usage).
  int? contextTokens(String id) => _procs[id]?.contextTokens;

  /// A spec session that goes on to more steps (SPEC-017 R4).
  Future<void> setSteps(String id, String steps, String title) async {
    await _repo.setSteps(id, steps, title);
    _procs[id]?.title = title;
    _originOverrides.remove(id);
    if (_procs[id]?.markedRoot != null) {
      final s = await _repo.getById(id);
      if (s != null) await _writeOrigin(id, await _agentOrigin(s));
    }
    _publish();
  }

  /// Origin of the commits the session makes from now on (SPEC-048 R2):
  /// `SPEC-043 conflito` before "Resolver conflito", `SPEC-042 base` after
  /// a redone base conflicted. Kept until the steps change; null = back to
  /// the step / session origin.
  Future<void> setAgentOrigin(String id, String? origin) async {
    if (origin == null) {
      _originOverrides.remove(id);
    } else {
      _originOverrides[id] = origin;
    }
    if (_procs[id]?.markedRoot == null) return;
    final s = await _repo.getById(id);
    if (s != null) await _writeOrigin(id, await _agentOrigin(s));
  }

  final Map<String, String> _originOverrides = {};

  /// Live sessions of [root] started with the marking on (R8: turning it
  /// off applies to the next sessions only).
  int markedLiveSessions(String root) =>
      _procs.values.where((p) => p.markedRoot == root).length;

  /// `SPEC-042 R2` / `sessão <nome>` (or the override of [setAgentOrigin]).
  Future<String> _agentOrigin(Session s) async {
    final override = _originOverrides[s.id];
    if (override != null) return override;
    final spec = s.specId == null
        ? null
        : await ref.read(specsRepoProvider).getById(s.specId!);
    if (spec != null) return stepOrigin(spec.code, parseSessionSteps(s.steps));
    return sessionOrigin(_titleOf(s));
  }

  Future<void> _writeOrigin(String id, String origin) async {
    await ref.read(agentGitHooksProvider)?.setOrigin(id, origin);
  }

  /// `PROMPTORIUM_AGENTE` / `PROMPTORIUM_ORIGEM` / `core.hooksPath` of the
  /// session when its project has the marking on; empty otherwise.
  Future<Map<String, String>> _agentEnv(Session s, String root) async {
    final config = ProjectConfig.loadSync(root);
    if (!config.git.markAgentCommits) return const {};
    final hooks = ref.read(agentGitHooksProvider);
    if (hooks == null) return const {};
    return agentCommitEnv(
      enabled: true,
      hooks: hooks,
      git: await ref.read(gitVersionProvider.future),
      model: agentModelLabel(s.model, s.provider),
      origin: await _agentOrigin(s),
      sessionId: s.id,
    );
  }

  /// SPEC-096 R15: leaving [workspaceId] ends the idle Codex processes of
  /// its sessions (like [closeIdle], without waiting the idle time). A
  /// session with a turn, an approval or a sub-agent on its way keeps
  /// running; sessions of other workspaces are untouched. "Retomar"
  /// resumes the thread. Returns the ids ended.
  Future<List<String>> releaseCodexOf(int workspaceId) async {
    if (_shuttingDown) return const [];
    final ended = <String>[];
    for (final e in _procs.entries.toList()) {
      final p = e.value;
      if (p.workspaceId != workspaceId ||
          p.process is! CodexRun ||
          p.busy ||
          p.stopping ||
          p.pending.isNotEmpty ||
          p.subagents.isNotEmpty) {
        continue;
      }
      ended.add(e.key);
      try {
        await release(e.key);
        await _note(
          e.key,
          'Processo do Codex encerrado ao trocar de workspace (Retomar '
          'continua de onde parou)',
        );
      } catch (err) {
        debugPrint('sessão ${e.key}: não encerrada — $err');
      }
    }
    return ended;
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
      if (!identical(_procs[e.key], p) ||
          p.busy ||
          p.stopping ||
          p.pending.isNotEmpty ||
          p.subagents.isNotEmpty ||
          at.difference(p.lastActivity) < limit) {
        continue;
      }
      // SPEC-071 R7: no await between the decision and [release] (which
      // marks the process released at once): a message sent from here on
      // waits for the exit and resumes the session instead of being written
      // to a dying process.
      closed.add(e.key);
      try {
        await release(e.key);
        await _note(
          e.key,
          'Suspensa após $minutes min sem atividade (Retomar continua de '
          'onde parou)',
        );
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

  /// The budget in US\$ of [agent] (`agent_settings`), shown as "fica para
  /// trás" when the work goes to a provider without it (SPEC-099 R3).
  Future<double?> agentBudget(String? agent, String? workspacePath) async =>
      (await _agentLimits(agent, workspacePath)).budgetUsd;

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
    // SPEC-048: only the agent's process gets the marking, never the
    // terminals of the worktree (worktreeEnvProvider below).
    final marking = await _agentEnv(session, root ?? cwd);
    // SPEC-098 R6: step sessions of the Quadro capture but leave no
    // automatic handoff (P3); free sessions keep ai-memory's behavior.
    final memory = await aiMemoryRunEnvironment(
      ref,
      session.specId != null
          ? AiMemoryRunKind.stepSession
          : AiMemoryRunKind.free,
    );
    final extra = {...marking, ...memory};
    final processEnv = extra.isEmpty
        ? environment
        : {...?environment, ...extra};
    final ManagedAgentRun process;
    McpRunLink? mcpLink;
    try {
      if (!isClaudeCode(session.provider)) {
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
        final provider = agentProviderForFlow(
          ref,
          session.provider,
          session.specId == null ? AppFlow.sessions : AppFlow.runSpec,
        );
        final caps = provider.capabilities;
        final mode = options.permissionMode;
        // R7: the stored mode becomes the app's access; Claude-only modes
        // (`auto`, `dontAsk`) fail closed.
        final access = mode == null
            ? AgentAccess.edit
            : AgentAccess.fromClaudeMode(mode) ??
                  (throw AgentUnavailable(
                    '${provider.displayName}: o modo ${mode.cliValue} é só '
                    'do Claude Code.',
                  ));
        final compact = saved['autocompact'] as String?;
        final effective = AgentStartOptions.forAccess(
          access,
          workingDirectory: cwd,
          resumeId: externalId,
          forkSession: options.forkSession,
          model: options.model,
          effort: options.effort,
          environment: processEnv,
          // R5: agent, budget and turns only where the provider has them.
          extras: extrasFor(
            caps,
            claude: ClaudeExtras(
              autocompact: compact,
              agent: options.agent,
              maxBudgetUsd: options.maxBudgetUsd,
              maxTurns: options.maxTurns,
              mcpAllowedTools: options.allowedTools,
              mcpDisallowedTools: options.disallowedTools,
              permissionMode: mode,
            ),
            // SPEC-096 R10: in a linked worktree, `git commit` writes in
            // its slice of the git common dir; nothing else is opened.
            codex: CodexExtras(
              compactLimit: compact,
              writableRoots: root != null && root != cwd
                  ? worktreeWritableRoots(cwd)
                  : const [],
            ),
          ),
        );
        final run = await provider.start(effective);
        process = run as ManagedAgentRun;
        await _repo.setRunConfig(
          id,
          jsonEncode({
            'provider': session.provider,
            'mode': 'edit',
            'permissionMode': options.permissionMode?.cliValue,
            'model': session.model,
            'effort': session.effort,
            'autocompact': ?compact,
          }),
        );
      } else if (isClaudeCode(session.provider)) {
        final settingsFile = await _prepareHooks(id, cwd: cwd, root: root);
        // SPEC-052 R1: the app's MCP server, with a token of this process.
        mcpLink = await openMcpRun(
          ref,
          workspaceId: session.workspaceId,
          sessionId: id,
          access: McpAccess.write,
          specId: session.specId,
          steps: session.steps,
          title: title,
          skipApproval:
              options.permissionMode == ClaudePermissionMode.skipPermissions,
        );
        process = ClaudeRun(
          await ClaudeProcess.start(
            options.copyWith(
              autocompact: ref.read(runPrefsProvider).autocompact,
              settingsFile: settingsFile,
              mcpConfigs: [...options.mcpConfigs, ?mcpLink?.configPath],
              allowedTools: [
                ...options.allowedTools,
                ...?mcpLink?.allowedTools,
              ],
            ),
            workingDirectory: cwd,
            executable: ref.read(claudeExecutableProvider),
            starter: ref.read(claudeProcessStarterProvider),
            environment: processEnv,
          ),
        );
      } else {
        throw AgentUnavailable(
          'Provedor de sessão não suportado: ${session.provider}.',
        );
      }
    } catch (e) {
      await closeMcpRun(ref.read(appMcpServerProvider), mcpLink);
      await _note(id, 'Falha ao iniciar ${session.provider}: $e', error: true);
      await _repo.setStatus(id, SessionStatus.failed);
      throw SessionException('Falha ao iniciar ${session.provider}: $e');
    }
    final p =
        _Proc(
            process,
            title,
            baseCost,
            skipPermissions:
                options.permissionMode == ClaudePermissionMode.skipPermissions,
          )
          ..workspaceId = session.workspaceId
          ..who = isClaudeCode(session.provider)
              ? null
              : providerModelLabel(session.provider, session.model)
          ..markedRoot = marking.isEmpty ? null : (root ?? cwd)
          ..mcp = mcpLink
          ..mcpServer = mcpLink == null ? null : ref.read(appMcpServerProvider);
    _procs[id] = p;
    if (p.markedRoot != null) {
      ref.read(markedSessionsProvider.notifier).add(id, p.markedRoot!);
    }
    try {
      await _repo.setPid(id, process.pid);
    } catch (e) {
      debugPrint('sessão $id: pid não gravado — $e');
    }
    if (environment != null) {
      ref.read(worktreeEnvProvider.notifier).set(cwd, environment);
    }
    // SPEC-087 R7: what this execution received (effective threshold).
    await _appEvent(
      id,
      ContextEventTypes.runEvent(
        autocompact: isClaudeCode(session.provider)
            ? ref.read(runPrefsProvider).autocompact
            : null,
        model: session.model,
        provider: session.provider,
      ),
    );
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

  /// A new session / fork / PR worktree: `copiar:` and `preparar:` of the
  /// project's config. Failure removes the worktree (nothing was done in
  /// it yet) and is reported to the caller.
  Future<void> setupWorktree(String root, CreatedWorktree wt) async {
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
      if (!await pythonAvailable()) {
        _noPython.add(id);
        return await plain();
      }
      final settings = ref.read(appSettingsProvider.notifier);
      final enabled = {
        for (final h in ManagedHook.values)
          if (settings.get(h.settingKey) != '0') h,
      };
      final config = root == null ? null : ProjectConfig.loadSync(root);
      // A PR brought into the app (SPEC-050 R7): its published history is
      // someone else's, so no forced push of any kind.
      final row = await _repo.getById(id);
      final foreignPr = row?.prUrl != null && row?.specId == null;
      // SPEC-085 R1: the rules of the Vigia de segredos for the hook.
      Map<String, Object?>? secrets;
      if (enabled.contains(ManagedHook.secrets) && row != null) {
        try {
          secrets = await ref
              .read(secretGuardProvider)
              .hookJson(workspaceId: row.workspaceId, root: cwd);
        } catch (e) {
          debugPrint('sessão $id: regras do vigia não preparadas — $e');
        }
      }
      if (secrets != null) {
        _secretHooks.add(id);
      } else {
        _secretHooks.remove(id);
      }
      return await hooks.prepare(
        id,
        enabled: enabled,
        rules: blockRules(
          projectGlobs: config?.blockedCommands ?? const [],
          extra: foreignPr ? prForcePushRules : const [],
          root: root,
          cwd: cwd,
        ),
        formatCommand: config?.formatCommand,
        secrets: secrets,
        extra: extra,
      );
    } catch (e) {
      _secretHooks.remove(id);
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
        if (a.secrets != null) {
          await _secretBlocked(id, a.secrets!);
        } else {
          await _note(id, a.text, error: a.error);
        }
        if (a.waived.isNotEmpty) {
          try {
            await ref.read(secretWaiversRepoProvider).touch(a.waived);
          } catch (_) {}
        }
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
    if (isStoredEvent(e)) {
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
          if (e.parentToolUseId != null) continue;
          if (b is ToolUseBlock) _trackTool(p, b);
          if (b is TextBlock && b.text.trim().isNotEmpty) {
            p.lastText = liveTextLine(b.text);
          }
        }
      case ToolResult():
        p.subagents.remove(e.toolUseId);
        if (e.parentToolUseId == null) {
          final i = p.recent.indexWhere((t) => t.id == e.toolUseId);
          if (i >= 0) p.recent[i] = p.recent[i].finished();
        }
        await _readHooks(id, p);
      case Result():
        final turn = turnCost(
          e.totalCostUsd,
          lastSeen: p.seenCost,
          stored: p.lastCost,
        );
        p.seenCost = e.totalCostUsd;
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
        // SPEC-081 R1: one entry per turn, with its spec and origin.
        await ref
            .read(usageLedgerProvider)
            .recordSessionTurn(id, e, costUsd: turn);
        // SPEC-087 R7, R12: threshold and composition, without a turn.
        if (p.process case final ContextUsageRun run) {
          unawaited(run.requestContextUsage());
        }
        // SPEC-087 R9: the end of "Compactar agora" is not a work turn.
        if (p.compacting) {
          p
            ..compacting = false
            ..busy = false
            ..busySince = null;
          _publish();
          break;
        }
        p.subagents.clear();
        p.busy = false;
        p.busySince = null;
        _publish();
        // SPEC-096 R12, P3: an interrupted turn can be resumed; the reason
        // ("por você") stays with the session until it starts again.
        final status = e.isSuccess
            ? SessionStatus.completed
            : e.isInterrupted
            ? SessionStatus.interrupted
            : SessionStatus.failed;
        if (e.isInterrupted && e.interruptReason == 'user') {
          await _markInterruptedByUser(id);
        }
        await _repo.setStatus(id, status);
        await _syncTask(id, status, fromResult: true);
        await _specs.onResult(id, e);
        // SPEC-043 R1: a conflict resolution goes to the gate.
        await ref
            .read(conflictResolverProvider)
            .onResult(id, e.isSuccess ? e.result : null);
        // SPEC-073 R5, R6: a queued CI fix goes; a CI fix is pushed.
        await ref
            .read(ciFixerProvider.notifier)
            .onResult(id, e.isSuccess ? e.result : null);
        ref.invalidate(sessionChangesProvider(id));
        // SPEC-084 R1: the end of the turn (not awaited: the next start
        // waits for it in the restore queue of the worktree).
        // SPEC-096 R10, R10a: what the Codex left uncommitted in its
        // worktree is committed by the app at the end of the turn, before
        // the end of the point is captured (in the same queue).
        final codex = p.process is CodexRun;
        final turnEnd = _restore.end(
          sessionId: id,
          beforeEnd: codex
              ? () => _codexTurnCommit(id, p, e.result).catchError(
                  (Object err) =>
                      debugPrint('sessão $id: commit do app — $err'),
                )
              : null,
        );
        // SPEC-111 R4: the panel reloads once the app's commit is done
        // (the reload above ran before it).
        if (codex) {
          unawaited(
            turnEnd.then((_) {
              if (ref.mounted) ref.invalidate(sessionChangesProvider(id));
            }),
          );
        }
        _notify(
          e.isSuccess
              ? 'Sessão concluída'
              : e.isInterrupted
              ? 'Sessão interrompida'
              : 'Sessão falhou',
          p.title,
          id,
        );
        // SPEC-085 R2: no hook, the turn's commits are checked now (after
        // the app's commit of a Codex turn, so it is checked too).
        if (!_secretHooks.contains(id)) {
          unawaited(
            (codex ? turnEnd : Future<void>.value())
                .then((_) => _secretTurnCheck(id))
                .catchError((Object e) => debugPrint('sessão $id: vigia — $e')),
          );
        }
        // Not awaited: send() enqueues behind this job.
        if (_notices[id]?.isNotEmpty ?? false) {
          unawaited(Future<void>.microtask(() => _flushNotices(id)));
        }
      case RateLimit():
        await ref.read(usageTrackerProvider).handle(e);
        // SPEC-099 R2: the session stops at the limit.
        if (e.status == 'rejected') {
          await _noteLimit(
            id,
            p,
            provider: 'claude',
            minutes: switch (e.rateLimitType) {
              'seven_day' || 'seven_day_opus' || 'seven_day_sonnet' => 10080,
              _ => 300,
            },
            resetsAt: e.resetsAt ?? e.fiveHourResetsAt,
            kind: e.rateLimitType,
          );
        }
      case QuotaEvent(:final reached) when reached != null:
        final w = e.windows
            .where((w) => (w.usedPercent ?? 0) >= 100)
            .firstOrNull;
        await _noteLimit(
          id,
          p,
          provider: e.provider,
          minutes: w?.minutes ?? 300,
          resetsAt: w?.resetsAt,
          kind: reached,
        );
      // SPEC-095 R9: files and commands of any provider.
      case FileChangeEvent():
        _trackNeutral(p, e);
      case CommandEvent():
        _trackNeutral(p, e);
      case ContextUsageEvent(:final tokens):
        if (tokens > 0) p.contextTokens = tokens;
      default:
        break;
    }

    // 3. Timeline.
    _timeline(id).push(e, seq: seq);
    if (e is AssistantMessage ||
        e is ToolResult ||
        e is Result ||
        e is PermissionRequest ||
        e is FileChangeEvent ||
        e is CommandEvent) {
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
    // Only this process: a resume may already have started the next one.
    if (identical(_procs[id], p)) {
      _procs.remove(id);
      if (p.markedRoot != null && ref.mounted) {
        ref.read(markedSessionsProvider.notifier).remove(id);
        await ref.read(agentGitHooksProvider)?.clearOrigin(id);
      }
    }
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
    // SPEC-052 R2: the token dies with the process.
    await closeMcpRun(p.mcpServer, p.mcp);
    if (!ref.mounted || _shuttingDown) return;
    // SPEC-084 R1: the process died in the middle of a turn — its end.
    if (p.busy) await _restore.end(sessionId: id);
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
            tool: value.recent.firstOrNull,
            recent: List.unmodifiable(value.recent),
            calls: value.calls,
            files: value.files.length,
            lastText: value.lastText,
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

  RestoreService get _restore => ref.read(restoreServiceProvider);

  SessionTimelineNotifier _timeline(String id) =>
      ref.read(sessionTimelineProvider(id).notifier);

  /// The hook (or the end-of-turn check) blocked a commit, push or PR
  /// (SPEC-085 R7): the card in the timeline, the request "Segredo
  /// encontrado" and the notification. [j] is the hook's log line: the
  /// findings are already masked.
  Future<void> _secretBlocked(String id, Map<String, Object?> j) async {
    final findings = [
      if (j['achados'] case final List l)
        for (final f in l) ?SecretFinding.fromJson(f),
    ];
    if (findings.isEmpty) return;
    final action = '${j['acao'] ?? 'commit'}';
    final block = 's${DateTime.now().microsecondsSinceEpoch}';
    await appendSecretEvent(
      id,
      AppEventTypes.secretsEvent(
        block: block,
        action: action,
        command: j['comando'] as String?,
        findings: [for (final f in findings) f.toJson()],
        partial: j['parcial'] == true,
      ),
    );
    final row = await _repo.getById(id);
    if (row == null || !ref.mounted) return;
    final title = _procs[id]?.title ?? _titleOf(row);
    final pending = PendingSecret(
      key: sessionSecretKey(id),
      workspaceId: row.workspaceId,
      sessionId: id,
      specId: row.specId,
      title: title,
      findings: findings,
      at: DateTime.now(),
      action: action,
    );
    ref.read(secretBlocksProvider.notifier).add(pending);
    _notify('Segredo encontrado', '$title: ${pending.detail}', id);
  }

  /// SPEC-085 R2: a session without the hook (Codex, no `python3`) has its
  /// commits not sent yet checked at the end of each turn; the push of the
  /// app is the last barrier.
  Future<void> _secretTurnCheck(String id) async {
    if (_secretHooks.contains(id) || !ref.mounted) return;
    final guard = ref.read(secretGuardProvider);
    if (!guard.prefs.enabled) return;
    final row = await _repo.getById(id);
    final cwd = row?.worktreePath;
    if (row == null || cwd == null) return;
    // Only where the hook cannot run: Codex, or no python3.
    if (row.provider != 'codex' &&
        !_noPython.contains(id) &&
        !secretTurnCheckWithoutHooks) {
      return;
    }
    if (_secretNoHookNoted.add(id)) {
      final why = row.provider == 'codex' ? 'Codex' : 'sem python3';
      await _note(
        id,
        'Vigia de segredos sem hook nesta sessão ($why): os commits são '
        'conferidos ao fim do turno e antes do push',
      );
    }
    final SecretScan res;
    try {
      res = await guard.scan(
        cwd,
        SecretCheckKind.push,
        workspaceId: row.workspaceId,
      );
    } catch (e) {
      debugPrint('sessão $id: vigia de segredos não conferiu o turno — $e');
      return;
    }
    final seen = _secretSeen.putIfAbsent(id, () => {});
    final fresh = [
      for (final f in res.findings)
        if (seen.add('${f.path}\u0000${f.ruleId}\u0000${f.fingerprint}')) f,
    ];
    if (fresh.isEmpty) return;
    await _secretBlocked(id, {
      'acao': 'commit',
      'achados': [for (final f in fresh) f.toJson()],
      'parcial': res.partial,
    });
  }

  /// "Limite de uso atingido" in the timeline, once per turn (SPEC-099 R2).
  Future<void> _noteLimit(
    String id,
    _Proc p, {
    required String provider,
    int? minutes,
    DateTime? resetsAt,
    String? kind,
  }) async {
    if (p.limitNoted) return;
    p.limitNoted = true;
    await _appEvent(
      id,
      AppEventTypes.limitEvent(
        provider: provider,
        minutes: minutes,
        resetsAt: resetsAt,
        kind: kind,
      ),
    );
  }

  Future<void> _appEvent(String id, Map<String, dynamic> json) async {
    final row = await _repo.appendEvent(
      id,
      type: '${json['type']}',
      json: _encode(json),
    );
    _timeline(id).push(UnknownEvent(json), seq: row.seq);
  }

  Future<void> _note(String id, String text, {bool error = false}) async {
    final json = AppEventTypes.noteMessage(text, error: error);
    final row = await _repo.appendEvent(
      id,
      type: AppEventTypes.note,
      json: _encode(json),
    );
    _timeline(id).push(UnknownEvent(json), seq: row.seq);
  }

  /// The bell, and the native notification of "concluída" / "falhou": the
  /// click goes back to the screen the session was created from. Approvals
  /// go to the bell pointing at Sessões; the system notification is
  /// [AgentAlerts]'s (SPEC-086).
  void _notify(String title, String text, String id, {bool approval = false}) {
    // SPEC-096 R3: who ran it, when it is not the Claude Code.
    final who = _procs[id]?.who;
    final body = who == null ? text : '$text · $who';
    final section = approval
        ? AppSection.sessions
        : (_origins[id] ?? AppSection.sessions);
    unawaited(
      ref
          .read(notificationsRepoProvider)
          .add(title: title, body: body, section: section.name, sessionId: id)
          .catchError((Object e) => debugPrint('notificação não gravada: $e')),
    );
    // SPEC-086: an approval goes to the system through [AgentAlerts] (the
    // robot, R1); "concluída" / "falhou" only with its option on (R15).
    if (approval || !ref.read(alertSettingsProvider).sessions) return;
    ref
        .read(appNotifierProvider)
        .show(
          title,
          body,
          onClick: () {
            ref.read(selectedSessionProvider.notifier).select(id);
            ref
                .read(navigationProvider.notifier)
                .go(_origins[id] ?? AppSection.sessions);
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

/// Live sessions started with `git: marcar-commits-de-agente` on: session
/// id → workspace root (SPEC-048 R8, "Desliga nas próximas sessões").
class MarkedSessions extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void add(String id, String root) => state = {...state, id: root};

  void remove(String id) {
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
  }
}

final markedSessionsProvider =
    NotifierProvider<MarkedSessions, Map<String, String>>(MarkedSessions.new);

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

/// Message of the app's commit at the end of a Codex turn (SPEC-096 R10):
/// the session title as subject and the agent's last message as body.
String codexTurnCommitMessage(String title, String? answer) {
  final subject = title.trim().isEmpty ? 'Alterações do Codex' : title.trim();
  final body = (answer ?? '').trim();
  if (body.isEmpty) return subject;
  final cut = body.length > 4000 ? '${body.substring(0, 4000)}…' : body;
  return '$subject\n\n$cut';
}
