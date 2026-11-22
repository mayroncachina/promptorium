import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/memory/handoff.dart';
import '../../../data/providers.dart';
import '../timeline.dart';

/// How the work was passed (SPEC-099 R4–R7).
enum ContinuePath {
  /// The ai-memory handoff (R4): the new session receives it at start.
  aiMemory('ai-memory', 'Passagem do ai-memory'),

  /// The summary built by the app (R7): no ai-memory needed.
  summary('resumo', 'Resumo do app'),

  /// `ai-memory run` in the embedded terminal (R6): out of the timeline.
  terminal('terminal', 'Terminal com ai-memory run');

  const ContinuePath(this.wire, this.label);
  final String wire;
  final String label;

  static ContinuePath parse(Object? v) =>
      values.where((p) => p.wire == v).firstOrNull ?? ContinuePath.summary;
}

/// The "continuação" record (P5): the `promptorium_handoff` event written at
/// the start of the new session. With `sessions.parentSessionId` it is the
/// link in both directions (R9); the note and the card at the top of the
/// timeline come from it (R8).
@immutable
class ContinuationRecord {
  const ContinuationRecord({
    required this.toProvider,
    required this.path,
    required this.at,
    this.fromId,
    this.fromTitle,
    this.fromProvider,
    this.handoff,
    this.handoffOwner,
    this.text,
    this.sameWorktree = true,
  });

  /// The session continued (null = from a handoff with no known session,
  /// R13: no link).
  final String? fromId;
  final String? fromTitle;
  final String? fromProvider;
  final String toProvider;
  final ContinuePath path;
  final DateTime at;

  /// The handoff delivered (path [ContinuePath.aiMemory]).
  final Handoff? handoff;

  /// "você", "compartilhada" or the operator (as the panel says it).
  final String? handoffOwner;

  /// The summary sent (path [ContinuePath.summary]).
  final String? text;
  final bool sameWorktree;

  Map<String, dynamic> toJson() => {
    'type': AppEventTypes.handoff,
    'from': ?fromId,
    'from_title': ?fromTitle,
    'from_provider': ?fromProvider,
    'to_provider': toProvider,
    'path': path.wire,
    if (handoff case final h?)
      'handoff': {
        'id': h.id,
        'from_agent': h.fromAgent,
        'from_session_id': ?h.fromSessionId,
        'summary': h.summary,
        'created_at': ?h.createdAt?.toUtc().toIso8601String(),
        'open_questions': h.openQuestions,
        'next_steps': h.nextSteps,
        'files_touched': h.filesTouched,
        'cwd': ?h.cwd,
        'owner_user': ?h.ownerUser,
      },
    'handoff_owner': ?handoffOwner,
    'text': ?text,
    'same_worktree': sameWorktree,
    'at': at.toIso8601String(),
  };

  static ContinuationRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
    return ContinuationRecord(
      fromId: str(raw['from']),
      fromTitle: str(raw['from_title']),
      fromProvider: str(raw['from_provider']),
      toProvider: str(raw['to_provider']) ?? 'claude',
      path: ContinuePath.parse(raw['path']),
      at: DateTime.tryParse('${raw['at']}')?.toLocal() ?? DateTime.now(),
      handoff: Handoff.fromJson(raw['handoff']),
      handoffOwner: str(raw['handoff_owner']),
      text: str(raw['text']),
      sameWorktree: raw['same_worktree'] != false,
    );
  }

  static ContinuationRecord? decode(String raw) {
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}

/// The links of a workspace, by the id of the new session.
@immutable
class ContinuationLinks {
  const ContinuationLinks([this.byChild = const {}]);

  final Map<String, ContinuationRecord> byChild;

  /// Where [sessionId] came from (null = not a continuation).
  ContinuationRecord? of(String sessionId) => byChild[sessionId];

  /// The newest session that continued [sessionId] (null = none): only the
  /// immediate link of a chain (R9).
  String? continuedInto(String sessionId) {
    String? last;
    DateTime? at;
    for (final e in byChild.entries) {
      if (e.value.fromId != sessionId) continue;
      if (at == null || e.value.at.isAfter(at)) {
        last = e.key;
        at = e.value.at;
      }
    }
    return last;
  }

  bool isContinuation(String sessionId) => byChild.containsKey(sessionId);

  /// The newest session of the chain that starts at [sessionId] (P7: the
  /// Review follows it).
  String newestOfChain(String sessionId) {
    var id = sessionId;
    final seen = <String>{id};
    for (;;) {
      final next = continuedInto(id);
      if (next == null || !seen.add(next)) return id;
      id = next;
    }
  }
}

/// The continuation links of [workspaceId], live (R9).
final continuationLinksProvider =
    StreamProvider.family<ContinuationLinks, int>((ref, workspaceId) {
      return ref
          .watch(sessionsRepoProvider)
          .watchEventsOfType(workspaceId, AppEventTypes.handoff)
          .map(
            (rows) => ContinuationLinks({
              for (final e in rows.entries)
                e.key: ?ContinuationRecord.decode(e.value),
            }),
          );
    });
