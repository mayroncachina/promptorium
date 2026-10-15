import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_event.dart';
import '../../data/providers.dart';
import 'timeline.dart';

/// Immutable handle on a (mutable) [Timeline]: a new snapshot is emitted on
/// every change so widgets rebuild.
@immutable
class TimelineSnapshot {
  const TimelineSnapshot(
    this.timeline, {
    required this.version,
    this.loading = false,
  });

  final Timeline timeline;
  final int version;
  final bool loading;

  List<TimelineItem> get items => timeline.items;
}

/// One persisted event row (`session_events` / `conversation_events`).
typedef StoredTimelineEvent = ({String json, DateTime at, int seq});

/// Timeline fed by stored rows first ([loadStored]), then by live events
/// ([push]). Shared by sessions and Prompt conversations.
///
/// Live events that arrive while the stored ones are loading are buffered;
/// those already stored (same or lower `seq`) are dropped after the load.
abstract class StoredTimelineNotifier extends Notifier<TimelineSnapshot> {
  final Timeline _t = Timeline();
  final List<(int?, ClaudeEvent)> _pending = [];
  bool _loaded = false;
  int _version = 0;

  /// Rows already persisted, in `seq` order.
  Future<List<StoredTimelineEvent>> loadStored();

  /// Label used in debug logs.
  String get debugName;

  @override
  TimelineSnapshot build() {
    _load();
    return TimelineSnapshot(_t, version: 0, loading: true);
  }

  Future<void> _load() async {
    var maxSeq = 0;
    try {
      for (final r in await loadStored()) {
        _t.applyStored(r.json, at: r.at);
        if (r.seq > maxSeq) maxSeq = r.seq;
      }
    } catch (e) {
      debugPrint('timeline $debugName: falha ao carregar eventos — $e');
    }
    _loaded = true;
    for (final (seq, e) in _pending) {
      if (seq == null || seq > maxSeq) _t.apply(e);
    }
    _pending.clear();
    _emit();
  }

  /// Applies a live event ([seq] = its stored `seq`, null when the event is
  /// not stored, e.g. `stream_event`).
  void push(ClaudeEvent e, {int? seq}) {
    if (!_loaded) {
      _pending.add((seq, e));
      return;
    }
    _t.apply(e);
    _emit();
  }

  void _emit() {
    try {
      state = TimelineSnapshot(_t, version: ++_version);
    } catch (_) {
      // disposed
    }
  }
}

/// Timeline of one session (`session_events` + live events from
/// `SessionManager`).
class SessionTimelineNotifier extends StoredTimelineNotifier {
  SessionTimelineNotifier(this.sessionId);

  final String sessionId;

  @override
  String get debugName => sessionId;

  @override
  Future<List<StoredTimelineEvent>> loadStored() async => [
    for (final r in await ref.read(sessionsRepoProvider).events(sessionId))
      (json: r.json, at: r.createdAt, seq: r.seq),
  ];
}

final sessionTimelineProvider =
    NotifierProvider.family<SessionTimelineNotifier, TimelineSnapshot, String>(
      SessionTimelineNotifier.new,
    );
