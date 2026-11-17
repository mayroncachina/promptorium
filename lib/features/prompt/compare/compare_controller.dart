import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_event.dart';
import '../../../core/claude/run_extensions.dart';
import '../../../core/claude/run_prefs.dart';
import '../../../core/claude/usage_poller.dart';
import '../../../core/claude/usage_tracker.dart';
import '../../../core/providers/agent_registry.dart';
import '../../../core/providers/provider_preferences.dart';
import '../../../data/providers.dart';
import '../../../data/repos/conversations_repo.dart';
import '../../mcp/mcp_rules.dart';
import '../../sessions/session_manager.dart'
    show LiveTool, PendingApproval, liveTextLine, sessionIdGeneratorProvider;
import '../../sessions/timeline.dart';
import '../conversation_manager.dart';
import '../plan_ready.dart' show planDraftsProvider, planOfRequest;
import 'compare_run.dart';
import 'compare_weight.dart';

/// Runs and keeps the comparisons of the Prompt (SPEC-079): both sides
/// start together as forks of the conversation's session (R5), each with
/// its own process, approvals and Parar (R9, R10); choosing one moves the
/// conversation onto its fork (R11), discarding goes back (R12). The run
/// is saved as one `conversation_events` row while it waits (R13).

/// The deny message of `ExitPlanMode` on a side: the plan is held until
/// the side is chosen (R3).
const comparePlanHold =
    'Plano recebido no Promptorium, em comparação com outra resposta. Não '
    'edite arquivos nem saia do modo plano; responda só "ok".';

/// What "Retomar" sends to a side stopped mid-answer (R13).
const compareResumeMessage = 'Continue a resposta de onde parou.';

/// What the view needs of a side while it lives in memory.
@immutable
class CompareLive {
  const CompareLive({
    required this.timeline,
    this.version = 0,
    this.approvals = const [],
    this.recent = const [],
    this.calls = 0,
    this.lastText,
  });

  /// Mutable on purpose (deltas); [version] changes with it.
  final Timeline timeline;
  final int version;
  final List<PendingApproval> approvals;

  /// Newest tool calls of the turn, newest first (Atividades, R9).
  final List<LiveTool> recent;
  final int calls;
  final String? lastText;

  LiveTool? get tool => recent.firstOrNull;
}

/// One comparison waiting for a choice and its live sides.
@immutable
class CompareView {
  const CompareView({required this.run, this.live = const {}});

  final CompareRun run;
  final Map<String, CompareLive> live;

  CompareLive liveOf(String letter) =>
      live[letter] ?? CompareLive(timeline: run.side(letter).timeline());
}

class _Side {
  _Side(this.letter, this.timeline);

  final String letter;
  Timeline timeline;
  int version = 0;
  AgentRun? run;
  StreamSubscription<ClaudeEvent>? sub;
  StreamSubscription<String>? logSub;
  Future<void> queue = Future.value();
  final List<PermissionRequest> pending = [];
  final Map<String, DateTime> pendingAt = {};
  final Map<String, int> tools = {};
  final List<LiveTool> recent = [];
  String? lastText;
  bool stopping = false;
}

class _Live {
  _Live(this.run, this.sides);

  CompareRun run;
  final Map<String, _Side> sides;
  Timer? saveTimer;
  bool measuring = false;
}

class CompareController extends Notifier<Map<int, CompareView>> {
  final Map<int, _Live> _lives = {};
  final Set<int> _restored = {};
  bool _shuttingDown = false;

  @override
  Map<int, CompareView> build() {
    ref.onDispose(() {
      for (final l in _lives.values) {
        l.saveTimer?.cancel();
        for (final s in l.sides.values) {
          s.stopping = true;
          s.run?.stop(timeout: const Duration(seconds: 2));
        }
      }
    });
    return const {};
  }

  ConversationsRepo get _repo => ref.read(conversationsRepoProvider);

  /// The comparison of [conversationId] waiting for a choice (R14).
  CompareRun? openOf(int conversationId) => _lives[conversationId]?.run;

  // --- start -----------------------------------------------------------------

  /// Sends [prompt] to the two sides (R5). [conversationId] null creates
  /// the conversation (with side A's model and mode). Returns its id.
  Future<int> start({
    required Workspace workspace,
    int? conversationId,
    required String prompt,
    required CompareChoice a,
    required CompareChoice b,
    String? providerId,
  }) async {
    final msg = prompt.trim();
    if (msg.isEmpty) throw const ConversationException('Escreva uma mensagem.');
    final problem = compareSidesProblem(a, b);
    if (problem != null) throw ConversationException(problem);
    if (_shuttingDown) {
      throw const ConversationException('O aplicativo está sendo encerrado.');
    }
    Conversation? conv;
    if (conversationId == null) {
      final provider =
          providerId ?? ref.read<String>(defaultAgentProvider(workspace.id));
      conv = await _repo.insert(
        workspaceId: workspace.id,
        title: conversationTitle(msg),
        model: a.model,
        provider: provider,
        mode: a.mode.name,
      );
    } else {
      conv = await _repo.getById(conversationId);
      if (conv == null) {
        throw ConversationException('Conversa $conversationId não existe.');
      }
      if (conv.specId != null) {
        throw const ConversationException(
          'A conversa de uma VIBE não compara respostas.',
        );
      }
      await restore(conv.id);
      if (_lives.containsKey(conv.id)) {
        throw const ConversationException(compareBlockedMessage);
      }
      if (ref.read(conversationManagerProvider).isBusy(conv.id)) {
        throw const ConversationException(
          'Espere a resposta terminar para comparar.',
        );
      }
      if (conv.archivedAt != null) await _repo.unarchive(conv.id);
    }
    final id = conv.id;
    _restored.add(id);
    // P8: the last pair of the workspace.
    await ref
        .read(appSettingsProvider.notifier)
        .set(compareSidesKey(workspace.id), encodeCompareSides(a, b));
    final newId = ref.read(sessionIdGeneratorProvider);
    var run = CompareRun(
      conversationId: id,
      prompt: msg,
      at: DateTime.now(),
      sides: [
        CompareSide(
          letter: 'A',
          model: a.model,
          mode: a.mode,
          sessionId: newId(),
        ),
        CompareSide(
          letter: 'B',
          model: b.model,
          mode: b.mode,
          sessionId: newId(),
        ),
      ],
      originalSessionId: conv.claudeSessionId,
      originalModel: conv.model,
      originalMode: PromptMode.fromName(conv.mode),
    );
    final row = await _repo.appendEvent(
      id,
      type: AppEventTypes.compare,
      json: run.encode(),
    );
    await _repo.countMessage(id);
    run = run.copyWith(seq: row.seq);
    final live = _Live(run, {
      for (final s in run.sides) s.letter: _Side(s.letter, Timeline()),
    });
    _lives[id] = live;
    _publish();
    // R8: the usage before the two sides start.
    final before = await _readUsage();
    live.run = live.run.copyWith(before: before);
    final c = conv;
    await Future.wait([
      for (final s in run.sides) _startSide(c, workspace, live, s.letter, msg),
    ]);
    await _save(id);
    return id;
  }

  Future<void> _startSide(
    Conversation conv,
    Workspace ws,
    _Live live,
    String letter,
    String text, {
    String? resumeOwn,
  }) async {
    var side = live.run.side(letter);
    // Stopped while the usage was read.
    if (side.state != CompareSideState.starting) return;
    final provider = ref.read(agentProviderByIdProvider(conv.provider));
    final origin = live.run.originalSessionId;
    final AgentRun run;
    try {
      if (!provider.enabled) {
        throw AgentUnavailable(
          '${provider.displayName} ainda não está disponível.',
        );
      }
      final mcp = await readMcpRuleArgs(ref.read(mcpToolRulesRepoProvider));
      final prefs = ref.read(runPrefsProvider);
      final claude = conv.provider == 'claude';
      run = await provider.start(
        AgentStartOptions(
          workingDirectory: ws.path,
          mode: side.mode,
          // R5: a fork of the conversation's session (the original does not
          // change), or a new session; "Retomar" continues the side's own.
          sessionId: resumeOwn == null ? side.sessionId : null,
          resumeId: resumeOwn ?? origin,
          forkSession: resumeOwn == null && origin != null,
          model: side.model,
          effort: effortArg(
            providerEffort(ref, conv.provider, RunKind.conversation),
          ),
          autocompact: claude ? prefs.autocompact : null,
          mcpAllowedTools: mcp.allowed,
          mcpDisallowedTools: mcp.disallowed,
          settingsFile: claude ? await runSettingsFile(ref) : null,
        ),
      );
    } catch (e) {
      side = live.run.side(letter);
      live.run = live.run.withSide(
        side.copyWith(
          state: CompareSideState.error,
          error: 'Falha ao iniciar ${provider.displayName}: $e',
        ),
      );
      _publish();
      return;
    }
    final s = live.sides[letter]!
      ..run = run
      ..stopping = false
      ..tools.clear()
      ..recent.clear()
      ..pending.clear()
      ..pendingAt.clear();
    final id = conv.id;
    s.logSub = run.logs.listen(
      (l) => debugPrint('comparar[$id/$letter] $l'),
      onError: (_) {},
    );
    s.sub = run.events.listen(
      (e) => _enqueue(s, () => _handle(id, letter, run, e)),
      onDone: () => _enqueue(s, () => _onExit(id, letter, run)),
    );
    live.run = live.run.withSide(
      live.run
          .side(letter)
          .copyWith(state: CompareSideState.running, startedAt: DateTime.now()),
    );
    _publish();
    await run.send(text);
  }

  Future<void> _enqueue(_Side s, Future<void> Function() job) {
    final next = s.queue.then((_) => job()).catchError((
      Object e,
      StackTrace st,
    ) {
      debugPrint('comparar ${s.letter}: $e\n$st');
    });
    s.queue = next;
    return next;
  }

  Future<void> _handle(
    int id,
    String letter,
    AgentRun run,
    ClaudeEvent e,
  ) async {
    if (!ref.mounted) return;
    final live = _lives[id];
    final s = live?.sides[letter];
    if (live == null || s == null || !identical(s.run, run)) return;
    var side = live.run.side(letter);
    if (e is! StreamDelta && e is! StreamOther) {
      side = side.copyWith(events: [...side.events, eventJson(e)]);
    }
    var finished = false;
    switch (e) {
      case SystemInit():
        side = side.copyWith(
          started: true,
          sessionId: e.sessionId ?? side.sessionId,
        );
      case PermissionRequest() when e.toolName == 'ExitPlanMode':
        // R3: "plano pronto" stops the side; approving waits for the choice.
        side = side.copyWith(plan: planOfRequest(e) ?? '');
        unawaited(run.deny(e.requestId, comparePlanHold));
      case PermissionRequest():
        s.pending.add(e);
        s.pendingAt[e.requestId] = DateTime.now();
      case ControlCancel():
        s.pending.removeWhere((p) => p.requestId == e.requestId);
        s.pendingAt.remove(e.requestId);
      case AssistantMessage() when e.parentToolUseId == null:
        for (final b in e.blocks) {
          if (b is ToolUseBlock && !s.recent.any((t) => t.id == b.id)) {
            s.tools[b.name] = (s.tools[b.name] ?? 0) + 1;
            s.recent.insert(
              0,
              LiveTool(
                id: b.id,
                name: b.name,
                input: b.input,
                at: DateTime.now(),
              ),
            );
            if (s.recent.length > 5) s.recent.removeLast();
          }
          if (b is TextBlock && b.text.trim().isNotEmpty) {
            s.lastText = liveTextLine(b.text);
          }
        }
      case ToolResult() when e.parentToolUseId == null:
        final i = s.recent.indexWhere((t) => t.id == e.toolUseId);
        if (i >= 0) s.recent[i] = s.recent[i].finished();
      case Result():
        finished = true;
        side = side.copyWith(
          metrics: CompareMetrics.ofResult(e, s.tools),
          state: side.plan != null
              ? CompareSideState.planReady
              : e.isSuccess
              ? CompareSideState.done
              : CompareSideState.error,
          error: e.isSuccess ? null : 'erro',
        );
        s.pending.clear();
        s.pendingAt.clear();
      case RateLimit():
        await ref.read(usageTrackerProvider).handle(e);
      default:
        break;
    }
    s.timeline.apply(e);
    s.version++;
    live.run = live.run.withSide(side);
    _publish();
    if (finished) {
      // The fork is on disk: an idle process is not kept.
      s.stopping = true;
      unawaited(run.stop());
      await _save(id);
      unawaited(_measure(id));
    } else if (e is! StreamDelta && e is! StreamOther) {
      _scheduleSave(id);
    }
  }

  Future<void> _onExit(int id, String letter, AgentRun run) async {
    final live = _lives[id];
    final s = live?.sides[letter];
    if (live == null || s == null || !identical(s.run, run)) return;
    await s.logSub?.cancel();
    final code = await run.exitCode;
    s
      ..run = null
      ..pending.clear()
      ..pendingAt.clear();
    // Closing the app: the row keeps "running" and comes back interrupted.
    if (!ref.mounted || _shuttingDown) return;
    final side = live.run.side(letter);
    if (side.state.live) {
      live.run = live.run.withSide(
        side.copyWith(
          state: s.stopping ? CompareSideState.stopped : CompareSideState.error,
          error: s.stopping
              ? null
              : 'O processo do agente encerrou antes de responder (código '
                    '$code)',
        ),
      );
    }
    _publish();
    await _save(id);
    await _measure(id);
  }

  // --- weight (R8) -----------------------------------------------------------

  Future<UsageReading?> _readUsage() async {
    try {
      final text = await ref
          .read(usageRunnerProvider)()
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
      if (text == null) return null;
      final r = parseUsageText(text, DateTime.now());
      if (r == null) return null;
      if (ref.mounted) await ref.read(rateLimitProvider.notifier).record(r);
      return UsageReading.of(r);
    } catch (e) {
      debugPrint('comparar: /usage — $e');
      return null;
    }
  }

  /// When both sides ended: the second reading and the weights.
  Future<void> _measure(int id, {bool read = true}) async {
    final live = _lives[id];
    if (live == null || !live.run.allDone || live.measuring) return;
    if (live.run.after != null ||
        live.run.sides.every((s) => s.weight != null)) {
      return;
    }
    live.measuring = true;
    try {
      final after = read && live.run.before != null ? await _readUsage() : null;
      if (!identical(_lives[id], live)) return;
      final r = ref.read(rateLimitProvider);
      final run = live.run;
      final costs = {
        for (final s in run.sides) s.letter: s.metrics?.costUsd ?? 0.0,
      };
      final w = compareWeights(
        costs: costs,
        before: run.before,
        after: after,
        last: r == null ? null : UsageReading.of(r),
        windowCosts: await _windowCosts(r),
      );
      var next = run.copyWith(after: after, measured: w.measured);
      for (final s in run.sides) {
        final sw = w.weights[s.letter];
        if (sw != null) next = next.withSide(s.copyWith(weight: sw));
      }
      live.run = next;
      _publish();
      await _save(id);
    } finally {
      live.measuring = false;
    }
  }

  /// Cost of what ran in the 5-hour window (the Atividades rule, R8).
  Future<Map<String, double>> _windowCosts(RateLimit? r) async {
    final start = r?.fiveHourResetsAt?.subtract(const Duration(hours: 5));
    try {
      final sessions = await ref.read(sessionsRepoProvider).watchAll().first;
      return {
        for (final s in sessions)
          if (s.costUsd > 0 &&
              (start == null || s.endedAt == null || s.endedAt!.isAfter(start)))
            'session:${s.id}': s.costUsd,
      };
    } catch (_) {
      return const {};
    }
  }

  // --- per side (R9, R10) ----------------------------------------------------

  Future<void> approve(
    int id,
    String letter,
    String requestId, {
    bool always = false,
    Map<String, dynamic>? updatedInput,
  }) async {
    final s = _lives[id]?.sides[letter];
    final req = _take(s, requestId);
    if (s?.run == null || req == null) return;
    await s!.run!.approve(
      requestId,
      updatedPermissions: always && req.permissionSuggestions.isNotEmpty
          ? [req.permissionSuggestions.first]
          : null,
      updatedInput: updatedInput,
    );
  }

  Future<void> deny(int id, String letter, String requestId) async {
    final s = _lives[id]?.sides[letter];
    final req = _take(s, requestId);
    if (s?.run == null || req == null) return;
    await s!.run!.deny(requestId, AppEventTypes.deniedMessage);
  }

  PermissionRequest? _take(_Side? s, String requestId) {
    if (s == null) return null;
    final i = s.pending.indexWhere((p) => p.requestId == requestId);
    if (i < 0) return null;
    s.pendingAt.remove(requestId);
    final r = s.pending.removeAt(i);
    _publish();
    return r;
  }

  /// "Parar" of one column (R10): what it answered stays, "interrompida".
  Future<void> stop(int id, String letter) async {
    final live = _lives[id];
    final s = live?.sides[letter];
    if (live == null || s == null) return;
    final side = live.run.side(letter);
    if (!side.state.live) return;
    s.stopping = true;
    final run = s.run;
    if (run == null) {
      live.run = live.run.withSide(
        side.copyWith(state: CompareSideState.stopped),
      );
      _publish();
      await _save(id);
      await _measure(id);
      return;
    }
    await run.stop();
    // The exit bookkeeping runs after the stream closes.
    await Future<void>.delayed(Duration.zero);
    await s.queue;
  }

  /// "Parar os dois".
  Future<void> stopBoth(int id) async {
    final live = _lives[id];
    if (live == null) return;
    await Future.wait([for (final l in live.sides.keys) stop(id, l)]);
  }

  /// "Retomar" (R13): continues the side's fork; a side that never started
  /// begins again.
  Future<void> resume(int id, String letter) async {
    final live = _lives[id];
    if (live == null) return;
    final side = live.run.side(letter);
    if (side.state.live) return;
    final conv = await _repo.getById(id);
    final ws = conv == null
        ? null
        : await ref.read(workspacesRepoProvider).getById(conv.workspaceId);
    if (conv == null || ws == null) return;
    live.run = live.run
        .copyWith(clearAfter: true)
        .withSide(
          side.copyWith(state: CompareSideState.starting, clearWeight: true),
        );
    for (final o in live.run.sides) {
      if (o.letter != letter && o.weight != null) {
        live.run = live.run.withSide(o.copyWith(clearWeight: true));
      }
    }
    _publish();
    await _startSide(
      conv,
      ws,
      live,
      letter,
      side.started ? compareResumeMessage : live.run.prompt,
      resumeOwn: side.started ? side.sessionId : null,
    );
    await _save(id);
  }

  // --- choose / discard (R11, R12) -------------------------------------------

  /// "Continuar com esta" (R11). Returns the chosen side.
  Future<CompareSide> choose(int id, String letter) async {
    final live = _lives[id];
    if (live == null) {
      throw const ConversationException('Esta comparação já terminou.');
    }
    if (!live.run.side(letter).state.choosable) {
      throw const ConversationException(
        'Espere este lado terminar, ou pare-o, para escolhê-lo.',
      );
    }
    for (final s in live.run.sides) {
      if (s.letter != letter && s.state.live) await stop(id, s.letter);
    }
    for (final s in live.sides.values) {
      await s.queue;
    }
    live.saveTimer?.cancel();
    final chosen = live.run.side(letter);
    final manager = ref.read(conversationManagerProvider.notifier);
    await manager.adoptSession(
      id,
      chosen.started ? chosen.sessionId : null,
      model: chosen.model,
      mode: chosen.mode,
    );
    var done = live.run.copyWith(status: CompareStatus.chosen, chosen: letter);
    for (final s in done.sides) {
      if (s.state.live) {
        done = done.withSide(s.copyWith(state: CompareSideState.stopped));
      }
    }
    if (done.seq != null) await _repo.updateEvent(id, done.seq!, done.encode());
    // The chosen answer as a normal one in the conversation.
    for (final raw in chosen.events) {
      final Object? j;
      try {
        j = jsonDecode(raw);
      } catch (_) {
        continue;
      }
      if (j is! Map<String, dynamic>) continue;
      final e = ClaudeEvent.fromJson(j);
      if (e is SystemInit) continue;
      await _repo.appendEvent(id, type: eventTypeKey(e), json: raw);
    }
    await _repo.countMessage(id);
    final m = chosen.metrics;
    if (m != null) {
      final conv = await _repo.getById(id);
      await _repo.recordResult(
        id,
        totalCostUsd: (conv?.costUsd ?? 0) + m.costUsd,
        tokensIn: m.tokensIn,
        tokensOut: m.tokensOut,
      );
    }
    // A Planejar side brings its "plano pronto" (approve, adjust).
    if (chosen.plan case final plan? when plan.trim().isNotEmpty) {
      ref.read(planDraftsProvider.notifier).set(id, plan);
    }
    _lives.remove(id);
    _publish();
    ref.invalidate(conversationTimelineProvider(id));
    return chosen;
  }

  /// "Descartar os dois" (R12): stops what runs, removes both sides and
  /// gives back the prompt. A conversation that the comparison created
  /// (nothing else in it) is removed too ([deleted]).
  Future<({String prompt, bool deleted})> discard(int id) async {
    final live = _lives[id];
    if (live == null) return (prompt: '', deleted: false);
    await stopBoth(id);
    for (final s in live.sides.values) {
      await s.queue;
    }
    live.saveTimer?.cancel();
    _lives.remove(id);
    _publish();
    final run = live.run;
    if (run.seq != null) await _repo.deleteEvent(id, run.seq!);
    final conv = await _repo.getById(id);
    var deleted = false;
    if (conv != null) {
      final rest = await _repo.events(id);
      if (rest.isEmpty && conv.claudeSessionId == null) {
        await _repo.delete(id);
        deleted = true;
      } else if (conv.claudeSessionId != run.originalSessionId &&
          run.originalSessionId != null) {
        await _repo.setClaudeSession(id, run.originalSessionId!);
      }
    }
    ref.invalidate(conversationTimelineProvider(id));
    return (prompt: run.prompt, deleted: deleted);
  }

  // --- save / restore (R13) --------------------------------------------------

  void _scheduleSave(int id) {
    final live = _lives[id];
    if (live == null || (live.saveTimer?.isActive ?? false)) return;
    live.saveTimer = Timer(const Duration(seconds: 2), () => _save(id));
  }

  Future<void> _save(int id) async {
    final live = _lives[id];
    final seq = live?.run.seq;
    if (live == null || seq == null || !ref.mounted) return;
    live.saveTimer?.cancel();
    try {
      await _repo.updateEvent(id, seq, live.run.encode());
    } catch (e) {
      debugPrint('comparar: salvar $id — $e');
    }
  }

  /// Loads the comparison of [id] still waiting for a choice (once per
  /// conversation): a side that was running is interrupted now.
  Future<void> restore(int id) async {
    if (!_restored.add(id) || _lives.containsKey(id)) return;
    final rows = await _repo.events(id);
    CompareRun? run;
    for (final r in rows.reversed) {
      if (r.type != AppEventTypes.compare) continue;
      try {
        final j = jsonDecode(r.json);
        if (j is Map<String, dynamic>) {
          run = CompareRun.fromJson(j, conversationId: id, seq: r.seq);
        }
      } catch (_) {}
      break;
    }
    if (run == null || run.status != CompareStatus.open) return;
    var r = run;
    var interrupted = false;
    for (final s in run.sides) {
      if (s.state.live) {
        interrupted = true;
        r = r.withSide(s.copyWith(state: CompareSideState.stopped));
      }
    }
    _lives[id] = _Live(r, {
      for (final s in r.sides) s.letter: _Side(s.letter, s.timeline()),
    });
    _publish();
    if (interrupted) {
      await _save(id);
      await _measure(id, read: false);
    }
  }

  /// App closing: stop every side (see `ConversationManager.shutdown`).
  Future<void> shutdown({Duration timeout = const Duration(seconds: 2)}) async {
    _shuttingDown = true;
    await Future.wait([
      for (final l in _lives.values) ...[
        _save(l.run.conversationId),
        for (final s in l.sides.values)
          if (s.run case final run?)
            run.stop(timeout: timeout).then((_) {}, onError: (_) {}),
      ],
    ]);
  }

  void _publish() {
    if (!ref.mounted) return;
    state = {
      for (final MapEntry(:key, :value) in _lives.entries)
        key: CompareView(
          run: value.run,
          live: {
            for (final s in value.sides.values)
              s.letter: CompareLive(
                timeline: s.timeline,
                version: s.version,
                recent: List.unmodifiable(s.recent),
                calls: s.tools.values.fold(0, (a, n) => a + n),
                lastText: s.lastText,
                approvals: [
                  for (final p in s.pending)
                    PendingApproval(
                      sessionId: value.run.side(s.letter).sessionId ?? '',
                      sessionTitle: 'Comparação · ${s.letter}',
                      request: p,
                      receivedAt: s.pendingAt[p.requestId] ?? DateTime.now(),
                    ),
                ],
              ),
          },
        ),
    };
  }
}

final compareControllerProvider =
    NotifierProvider<CompareController, Map<int, CompareView>>(
      CompareController.new,
    );

/// The comparison of one conversation waiting for a choice (null = none).
final compareProvider = Provider.family<CompareView?, int>(
  (ref, id) => ref.watch(compareControllerProvider.select((m) => m[id])),
);

/// Loads the saved comparison of a conversation when it is opened (R13).
final compareRestoreProvider = FutureProvider.family<void, int>(
  (ref, id) => ref.read(compareControllerProvider.notifier).restore(id),
);

/// `app_settings` key of the last pair of sides of a workspace (P8).
String compareSidesKey(int workspaceId) => 'prompt.comparar.$workspaceId';
