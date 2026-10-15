import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_event.dart';
import '../../core/claude/usage_tracker.dart';
import '../../core/providers/agent_registry.dart';
import '../../data/providers.dart';
import '../../data/repos/conversations_repo.dart';
import '../sessions/session_manager.dart'
    show PendingApproval, sessionIdGeneratorProvider;
import '../sessions/timeline.dart';
import '../sessions/timeline_provider.dart';

/// Runtime state of a conversation with a live agent process.
@immutable
class LiveConversation {
  const LiveConversation({
    this.alive = true,
    this.busy = false,
    this.approvals = const [],
  });

  final bool alive;

  /// A message was sent and its `result` has not arrived yet.
  final bool busy;
  final List<PendingApproval> approvals;
}

@immutable
class ConversationManagerState {
  const ConversationManagerState({this.live = const {}});

  final Map<int, LiveConversation> live;

  bool isAlive(int id) => live[id]?.alive ?? false;

  bool isBusy(int id) => live[id]?.busy ?? false;

  List<PendingApproval> approvalsOf(int id) =>
      live[id]?.approvals ?? const <PendingApproval>[];
}

class ConversationException implements Exception {
  const ConversationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Conversation title from its first message (first line, ≤ [max] chars).
String conversationTitle(String text, {int max = 60}) {
  final line = text
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  final clean = line
      .replaceAll(RegExp(r'^[#>*\-\s]+'), '')
      .replaceAll(RegExp(r'[`*_]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.isEmpty) return 'Nova conversa';
  if (clean.length <= max) return clean;
  final cut = clean.substring(0, max);
  final space = cut.lastIndexOf(' ');
  return '${(space > max ~/ 2 ? cut.substring(0, space) : cut).trimRight()}…';
}

class _Run {
  _Run(this.run, this.mode, this.model, this.title, this.lastCost, this.sid);

  final AgentRun run;
  final PromptMode mode;
  final String model;
  String title;

  /// Claude session id used by this process (`--session-id` / `--resume`).
  final String sid;
  double lastCost;
  bool busy = false;
  bool stopping = false;
  bool sawInit = false;
  final List<PermissionRequest> pending = [];
  final Map<String, DateTime> pendingAt = {};
  final DateTime started = DateTime.now();
  Future<void> queue = Future.value();
  Map<String, dynamic>? lastJson;
  int? lastSeq;
  StreamSubscription<ClaudeEvent>? sub;
  StreamSubscription<String>? logSub;
}

/// Free conversations of the Prompt screen (plano, Fase 6): one agent
/// process per live conversation, running in the **workspace root** (no
/// worktree). Events are stored in `conversation_events` (except stream
/// deltas) and feed [conversationTimelineProvider].
///
/// The mode / model are applied when the process starts; changing them on a
/// live conversation restarts it with `--resume` on the next message.
class ConversationManager extends Notifier<ConversationManagerState> {
  final Map<int, _Run> _runs = {};
  final Map<int, Future<_Run>> _starting = {};
  bool _shuttingDown = false;

  @override
  ConversationManagerState build() {
    ref.onDispose(() {
      for (final r in _runs.values) {
        r.stopping = true;
        r.run.stop(timeout: const Duration(seconds: 2));
      }
    });
    return const ConversationManagerState();
  }

  ConversationsRepo get _repo => ref.read(conversationsRepoProvider);

  // --- public API ------------------------------------------------------------

  /// Creates a conversation in [workspace] and sends [text]. Returns its id.
  Future<int> create({
    required Workspace workspace,
    required String text,
    PromptMode mode = PromptMode.ask,
    String model = 'inherit',
    String providerId = ClaudeCodeProvider.providerId,
  }) async {
    final msg = text.trim();
    if (msg.isEmpty) throw const ConversationException('Escreva uma mensagem.');
    final c = await _repo.insert(
      workspaceId: workspace.id,
      title: conversationTitle(msg),
      model: model,
      provider: providerId,
      mode: mode.name,
    );
    await send(c.id, msg);
    return c.id;
  }

  /// Sends a message; (re)starts the process when needed.
  Future<void> send(int id, String text) async {
    final msg = text.trim();
    if (msg.isEmpty) return;
    final conv = await _repo.getById(id);
    if (conv == null) throw ConversationException('Conversa $id não existe.');
    var r = _runs[id];
    final mode = PromptMode.fromName(conv.mode);
    if (r != null && (r.mode != mode || r.model != conv.model)) {
      await _note(
        id,
        'Modo/modelo alterado (${mode.label} · ${modelLabel(conv.model)}); '
        'reiniciando com --resume',
      );
      await _stopRun(id, r);
      r = null;
    }
    r ??= await _ensureStarted(conv);
    final run = r;
    await _enqueue(id, run, () async {
      final json = AppEventTypes.userMessage(msg, DateTime.now());
      final row = await _repo.appendEvent(
        id,
        type: AppEventTypes.user,
        json: jsonEncode(json),
      );
      await _repo.countMessage(id);
      _timeline(id).push(UnknownEvent(json), seq: row.seq);
    });
    run.busy = true;
    _publish();
    await run.run.send(msg);
  }

  Future<void> setMode(int id, PromptMode mode) => _repo.setMode(id, mode.name);

  Future<void> setModel(int id, String model) => _repo.setModel(id, model);

  Future<void> approve(int id, String requestId, {bool always = false}) async {
    final r = _runs[id];
    final req = _take(id, requestId);
    if (r == null || req == null) return;
    final s = req.permissionSuggestions;
    await r.run.approve(
      requestId,
      updatedPermissions: always && s.isNotEmpty ? [s.first] : null,
    );
  }

  Future<void> deny(
    int id,
    String requestId, {
    String message = 'O usuário negou esta ação no Promptorium.',
  }) async {
    final r = _runs[id];
    final req = _take(id, requestId);
    if (r == null || req == null) return;
    await r.run.deny(requestId, message);
  }

  /// Stops the process (the next message resumes it).
  Future<void> stop(int id) async {
    final r = _runs[id];
    if (r != null) await _stopRun(id, r);
  }

  /// App closing: stop every process (see `SessionManager.shutdown`).
  Future<void> shutdown({Duration timeout = const Duration(seconds: 2)}) async {
    _shuttingDown = true;
    await Future.wait([
      for (final r in _runs.values.toList())
        r.run.stop(timeout: timeout).then((_) {}, onError: (_) {}),
    ]);
  }

  bool isAlive(int id) => _runs.containsKey(id);

  // --- lifecycle -------------------------------------------------------------

  Future<_Run> _ensureStarted(Conversation conv) {
    final r = _runs[conv.id];
    if (r != null) return Future.value(r);
    return _starting[conv.id] ??= _startRun(conv).whenComplete(() {
      _starting.remove(conv.id);
    });
  }

  Future<_Run> _startRun(Conversation conv) async {
    if (_shuttingDown) {
      throw const ConversationException('O aplicativo está sendo encerrado.');
    }
    final ws = await ref.read(workspacesRepoProvider).getById(conv.workspaceId);
    if (ws == null) {
      throw const ConversationException('Workspace da conversa não existe.');
    }
    final provider = ref.read(agentProviderByIdProvider(conv.provider));
    if (!provider.enabled) {
      throw ConversationException(
        '${provider.displayName} ainda não está disponível.',
      );
    }
    final resume = conv.claudeSessionId;
    final sid = resume ?? ref.read(sessionIdGeneratorProvider)();
    final mode = PromptMode.fromName(conv.mode);
    final AgentRun run;
    try {
      run = await provider.start(
        AgentStartOptions(
          workingDirectory: ws.path,
          mode: mode,
          sessionId: resume == null ? sid : null,
          resumeId: resume,
          model: conv.model,
        ),
      );
    } catch (e) {
      await _note(
        conv.id,
        'Falha ao iniciar ${provider.displayName}: $e',
        error: true,
      );
      throw ConversationException(
        'Falha ao iniciar ${provider.displayName}: $e',
      );
    }
    final r = _Run(run, mode, conv.model, conv.title, conv.costUsd, sid);
    _runs[conv.id] = r;
    r.logSub = run.logs.listen(
      (l) => debugPrint('conversa[${conv.id}] $l'),
      onError: (_) {},
    );
    r.sub = run.events.listen(
      (e) => _enqueue(conv.id, r, () => _handle(conv.id, r, e)),
      onDone: () => _enqueue(conv.id, r, () => _onExit(conv.id, r)),
    );
    _publish();
    return r;
  }

  Future<void> _stopRun(int id, _Run r) async {
    r.stopping = true;
    await r.run.stop();
    // Wait for the exit bookkeeping so a restart does not race with it.
    await r.queue;
    if (identical(_runs[id], r)) _runs.remove(id);
    _publish();
  }

  Future<void> _enqueue(int id, _Run r, Future<void> Function() job) {
    final next = r.queue.then((_) => job()).catchError((
      Object e,
      StackTrace st,
    ) {
      debugPrint('conversa $id: $e\n$st');
    });
    r.queue = next;
    return next;
  }

  Future<void> _handle(int id, _Run r, ClaudeEvent e) async {
    if (!ref.mounted) return;
    int? seq;
    if (e is! StreamDelta && e is! StreamOther) {
      if (identical(e.json, r.lastJson) && e.json.isNotEmpty) {
        seq = r.lastSeq;
      } else {
        final row = await _repo.appendEvent(
          id,
          type: eventTypeKey(e),
          json: eventJson(e),
        );
        r
          ..lastJson = e.json
          ..lastSeq = row.seq;
        seq = row.seq;
      }
    }

    switch (e) {
      case SystemInit():
        if (!r.sawInit) {
          r.sawInit = true;
          // The session exists in the CLI now: later starts use --resume.
          await _repo.setClaudeSession(id, e.sessionId ?? r.sid);
        }
      case PermissionRequest():
        r.pending.add(e);
        r.pendingAt[e.requestId] = DateTime.now();
      case ControlCancel():
        _take(id, e.requestId);
      case Result():
        final delta = math.max(0.0, e.totalCostUsd - r.lastCost);
        r.lastCost = math.max(r.lastCost, e.totalCostUsd);
        final u = e.usage;
        await _repo.recordResult(
          id,
          totalCostUsd: r.lastCost,
          tokensIn:
              u.inputTokens +
              u.cacheCreationInputTokens +
              u.cacheReadInputTokens,
          tokensOut: u.outputTokens,
        );
        await _repo.countMessage(id);
        await ref.read(usageTrackerProvider).handle(e, costDelta: delta);
        r.busy = false;
      case RateLimit():
        await ref.read(usageTrackerProvider).handle(e);
      default:
        break;
    }

    _timeline(id).push(e, seq: seq);
    if (e is PermissionRequest || e is Result || e is ControlCancel) {
      _publish();
    }
  }

  Future<void> _onExit(int id, _Run r) async {
    await r.logSub?.cancel();
    final code = await r.run.exitCode;
    if (identical(_runs[id], r)) _runs.remove(id);
    if (!ref.mounted || _shuttingDown) return;
    _publish();
    if (!r.stopping && r.busy) {
      await _note(
        id,
        'O processo do agente encerrou antes de responder (código $code)',
        error: true,
      );
    } else if (r.stopping && r.busy) {
      await _note(id, 'Resposta interrompida');
    }
  }

  PermissionRequest? _take(int id, String requestId) {
    final r = _runs[id];
    if (r == null) return null;
    final i = r.pending.indexWhere((p) => p.requestId == requestId);
    if (i < 0) return null;
    final req = r.pending.removeAt(i);
    r.pendingAt.remove(requestId);
    _publish();
    return req;
  }

  void _publish() {
    if (!ref.mounted) return;
    state = ConversationManagerState(
      live: {
        for (final MapEntry(:key, :value) in _runs.entries)
          key: LiveConversation(
            alive: value.run.isRunning,
            busy: value.busy,
            approvals: [
              for (final p in value.pending)
                PendingApproval(
                  sessionId: value.sid,
                  sessionTitle: value.title,
                  request: p,
                  receivedAt: value.pendingAt[p.requestId] ?? value.started,
                ),
            ],
          ),
      },
    );
  }

  ConversationTimelineNotifier _timeline(int id) =>
      ref.read(conversationTimelineProvider(id).notifier);

  Future<void> _note(int id, String text, {bool error = false}) async {
    final json = AppEventTypes.noteMessage(text, error: error);
    final row = await _repo.appendEvent(
      id,
      type: AppEventTypes.note,
      json: jsonEncode(json),
    );
    _timeline(id).push(UnknownEvent(json), seq: row.seq);
  }
}

final conversationManagerProvider =
    NotifierProvider<ConversationManager, ConversationManagerState>(
      ConversationManager.new,
    );

/// Timeline of one conversation (`conversation_events` + live events).
class ConversationTimelineNotifier extends StoredTimelineNotifier {
  ConversationTimelineNotifier(this.conversationId);

  final int conversationId;

  @override
  String get debugName => 'conversa $conversationId';

  @override
  Future<List<StoredTimelineEvent>> loadStored() async => [
    for (final r
        in await ref.read(conversationsRepoProvider).events(conversationId))
      (json: r.json, at: r.createdAt, seq: r.seq),
  ];
}

final conversationTimelineProvider =
    NotifierProvider.family<
      ConversationTimelineNotifier,
      TimelineSnapshot,
      int
    >(ConversationTimelineNotifier.new);

/// Conversation shown in the Prompt screen (null = new conversation draft).
class SelectedConversation extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? id) => state = id;
}

final selectedConversationProvider =
    NotifierProvider<SelectedConversation, int?>(SelectedConversation.new);

/// Provider / model / mode chosen for the next new conversation.
@immutable
class PromptDraft {
  const PromptDraft({
    this.providerId = ClaudeCodeProvider.providerId,
    this.model = 'inherit',
    this.mode = PromptMode.ask,
  });

  final String providerId;
  final String model;
  final PromptMode mode;

  PromptDraft copyWith({String? providerId, String? model, PromptMode? mode}) =>
      PromptDraft(
        providerId: providerId ?? this.providerId,
        model: model ?? this.model,
        mode: mode ?? this.mode,
      );
}

class PromptDraftController extends Notifier<PromptDraft> {
  @override
  PromptDraft build() => const PromptDraft();

  void set(PromptDraft d) => state = d;
}

final promptDraftProvider =
    NotifierProvider<PromptDraftController, PromptDraft>(
      PromptDraftController.new,
    );

/// `sonnet` → `Sonnet`; `inherit` → `Modelo padrão`.
String modelLabel(String model) {
  if (model.isEmpty || model == 'inherit') return 'Modelo padrão';
  return model[0].toUpperCase() + model.substring(1);
}
