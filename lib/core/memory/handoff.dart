import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// State of one ai-memory handoff (`state` of the wire row).
enum HandoffState {
  open('aberta'),
  accepted('aceita'),
  expired('expirada');

  const HandoffState(this.label);
  final String label;

  static HandoffState parse(Object? raw) => switch (raw) {
    'accepted' => HandoffState.accepted,
    'expired' => HandoffState.expired,
    _ => HandoffState.open,
  };
}

/// Display name of an ai-memory agent kind (`claude-code`, `codex`, …).
String aiMemoryAgentName(String? kind) => switch (kind) {
  'claude-code' || 'claude' => 'Claude Code',
  'codex' => 'Codex',
  null || '' => 'agente desconhecido',
  final other => other,
};

/// One handoff ("passagem") as `memory_handoff_list` returns it (SPEC-098
/// R9). The text fields come from the person's prompts and tools: they are
/// untrusted data, shown as plain text only (R13).
@immutable
class Handoff {
  const Handoff({
    required this.id,
    required this.fromAgent,
    required this.state,
    this.createdAt,
    this.fromSessionId,
    this.ownerUser,
    this.cwd,
    this.summary = '',
    this.openQuestions = const [],
    this.nextSteps = const [],
    this.filesTouched = const [],
    this.acceptedBy,
    this.acceptedAt,
    this.acceptedByUser,
  });

  final String id;

  /// Agent kind that wrote it (`claude-code`, `codex`, …).
  final String fromAgent;
  final HandoffState state;
  final DateTime? createdAt;

  /// Null = manual (`memory_handoff_begin`), project-wide; else written by
  /// that session's end (automatic, scoped to its directory).
  final String? fromSessionId;

  /// Operator that owns it; null = shared with the project (or a
  /// single-operator server, where nothing is attributed).
  final String? ownerUser;
  final String? cwd;
  final String summary;
  final List<String> openQuestions;
  final List<String> nextSteps;
  final List<String> filesTouched;
  final String? acceptedBy;
  final DateTime? acceptedAt;
  final String? acceptedByUser;

  bool get manual => fromSessionId == null;
  bool get isOpen => state == HandoffState.open;
  String get agentName => aiMemoryAgentName(fromAgent);
  String get origin => manual ? 'manual' : 'automática · fim da sessão';

  /// First characters of the id, for "Copiar id 01JDX4…".
  String get shortId => id.length <= 6 ? id : '${id.substring(0, 6)}…';

  static Handoff? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] ?? raw['handoff_id'];
    if (id is! String || id.isEmpty) return null;
    List<String> list(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e != null && '$e'.trim().isNotEmpty) '$e',
    ];
    String? str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    return Handoff(
      id: id,
      fromAgent: str(raw['from_agent']) ?? '',
      state: HandoffState.parse(raw['state']),
      createdAt: parseAiMemoryTime(raw['created_at']),
      fromSessionId: str(raw['from_session_id']),
      ownerUser: str(raw['owner_user']),
      cwd: str(raw['cwd']),
      summary: raw['summary'] is String ? raw['summary'] as String : '',
      openQuestions: list(raw['open_questions']),
      nextSteps: list(raw['next_steps']),
      filesTouched: list(raw['files_touched']),
      acceptedBy: str(raw['accepted_by']),
      acceptedAt: parseAiMemoryTime(raw['accepted_at']),
      acceptedByUser: str(raw['accepted_by_user']),
    );
  }
}

/// ai-memory timestamps: RFC 3339 strings (jiff) or Unix microseconds.
DateTime? parseAiMemoryTime(Object? raw) {
  if (raw is String) return DateTime.tryParse(raw)?.toLocal();
  if (raw is int) {
    // Microseconds since the epoch (the `*_us` fields).
    return DateTime.fromMicrosecondsSinceEpoch(raw).toLocal();
  }
  return null;
}

/// A session newer than every open handoff that never ended nor left one
/// (`newer_unended_session`, R10): cut off by a quota or a crash.
@immutable
class UnendedSession {
  const UnendedSession({
    required this.sessionId,
    required this.agentKind,
    this.cwd,
    this.lastActivityAt,
  });

  final String sessionId;
  final String agentKind;
  final String? cwd;
  final DateTime? lastActivityAt;

  String get agentName => aiMemoryAgentName(agentKind);
  String get shortId =>
      sessionId.length <= 8 ? sessionId : sessionId.substring(0, 8);

  static UnendedSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['session_id'];
    if (id is! String || id.isEmpty) return null;
    return UnendedSession(
      sessionId: id,
      agentKind: raw['agent_kind'] is String ? raw['agent_kind'] as String : '',
      cwd: raw['cwd'] is String ? raw['cwd'] as String : null,
      lastActivityAt: parseAiMemoryTime(raw['last_activity_at']),
    );
  }
}

/// Who owns a handoff, as the panel says it (R9).
enum HandoffOwnerKind { you, shared, other }

/// The handoffs of a project with what the panel derives from them: owner,
/// delivery order and the one the next session will receive (R9).
@immutable
class HandoffList {
  const HandoffList({
    this.handoffs = const [],
    this.unended,
    this.workspacePath,
  });

  /// In delivery order: see [HandoffList.parse].
  final List<Handoff> handoffs;
  final UnendedSession? unended;
  final String? workspacePath;

  List<Handoff> get open => [
    for (final h in handoffs)
      if (h.isOpen) h,
  ];
  List<Handoff> get closed => [
    for (final h in handoffs)
      if (!h.isOpen) h,
  ];

  /// Whether the server attributes handoffs to operators: on a single-user
  /// server every row comes without `owner_user`.
  bool get attributed => handoffs.any((h) => h.ownerUser != null);

  /// `memory_handoff_list` returns the caller's own handoffs plus the ones
  /// shared with the project (another operator's only with `any_owner`,
  /// which the app never asks for). So on an attributed server an owner is
  /// "você" and no owner is "compartilhada"; unattributed, all are yours.
  HandoffOwnerKind ownerOf(Handoff h, {String? operator}) {
    if (!attributed) return HandoffOwnerKind.you;
    if (h.ownerUser == null) return HandoffOwnerKind.shared;
    if (operator != null && h.ownerUser != operator) {
      return HandoffOwnerKind.other;
    }
    return HandoffOwnerKind.you;
  }

  String ownerLabel(Handoff h) => switch (ownerOf(h)) {
    HandoffOwnerKind.you => 'você',
    HandoffOwnerKind.shared => 'compartilhada',
    HandoffOwnerKind.other => h.ownerUser!,
  };

  /// Discarding is only offered on open handoffs of their own owner (P6).
  bool canDiscard(Handoff h) => h.isOpen && ownerOf(h) == HandoffOwnerKind.you;

  /// The handoff ai-memory will hand to the next session started in the
  /// workspace: a manual one first (project-wide, newest), else the newest
  /// automatic one whose directory is the workspace or inside it.
  Handoff? get nextDelivered {
    for (final h in open) {
      if (h.manual) return h;
    }
    for (final h in open) {
      if (!h.manual && _inWorkspace(h.cwd)) return h;
    }
    return null;
  }

  bool _inWorkspace(String? cwd) {
    final ws = workspacePath;
    if (ws == null || cwd == null) return ws == null;
    return p.equals(cwd, ws) || p.isWithin(ws, cwd);
  }

  /// "worktree: spec-parser" when the handoff came from another directory
  /// than the workspace root (a worktree, usually).
  String? directoryLabel(Handoff h) {
    final cwd = h.cwd;
    if (cwd == null) return null;
    final ws = workspacePath;
    if (ws != null && p.equals(cwd, ws)) return null;
    final name = p.basename(cwd);
    if (ws != null && p.isWithin(ws, cwd)) return 'pasta: $name';
    return 'worktree: $name';
  }

  /// Parses the JSON of `memory_handoff_list`: `{handoffs: [...],
  /// newer_unended_session?}`. The order is ai-memory's delivery order:
  /// manual first, then automatic, each newest first; closed ones (history)
  /// after the open ones.
  static HandoffList parse(Object? json, {String? workspacePath}) {
    final rows = json is Map ? json['handoffs'] : json;
    final list = <Handoff>[
      if (rows is List)
        for (final r in rows) ?Handoff.fromJson(r),
    ];
    int rank(Handoff h) => h.isOpen ? (h.manual ? 0 : 1) : 2;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch);
    });
    return HandoffList(
      handoffs: list,
      unended: json is Map
          ? UnendedSession.fromJson(json['newer_unended_session'])
          : null,
      workspacePath: workspacePath,
    );
  }
}

/// One wiki page of `memory_briefing.recent_pages`.
@immutable
class BriefingPage {
  const BriefingPage({required this.path, this.title, this.updatedAt});
  final String path;
  final String? title;
  final DateTime? updatedAt;
}

/// What the panel shows of `memory_briefing` (R8, R12).
@immutable
class MemoryBriefing {
  const MemoryBriefing({
    this.workspace,
    this.project,
    this.pages = 0,
    this.sessions = 0,
    this.observations = 0,
    this.lastObservationAt,
    this.recentPages = const [],
  });

  final String? workspace;
  final String? project;
  final int pages;
  final int sessions;
  final int observations;
  final DateTime? lastObservationAt;
  final List<BriefingPage> recentPages;

  /// `default/promptorium`.
  String? get scope =>
      workspace == null || project == null ? null : '$workspace/$project';

  static MemoryBriefing parse(Object? json) {
    if (json is! Map) return const MemoryBriefing();
    final counts = json['counts'];
    int count(String k) =>
        counts is Map && counts[k] is num ? (counts[k] as num).toInt() : 0;
    final scope = json['scope'];
    final pages = json['recent_pages'];
    return MemoryBriefing(
      workspace: scope is Map && scope['workspace'] is String
          ? scope['workspace'] as String
          : null,
      project: scope is Map && scope['project'] is String
          ? scope['project'] as String
          : null,
      pages: count('pages_latest'),
      sessions: count('sessions'),
      observations: count('observations'),
      lastObservationAt: parseAiMemoryTime(json['last_observation_at']),
      recentPages: [
        if (pages is List)
          for (final pg in pages)
            if (pg is Map && pg['path'] is String)
              BriefingPage(
                path: pg['path'] as String,
                title: pg['title'] is String ? pg['title'] as String : null,
                updatedAt: parseAiMemoryTime(pg['updated_at']),
              ),
      ].take(5).toList(),
    );
  }
}
