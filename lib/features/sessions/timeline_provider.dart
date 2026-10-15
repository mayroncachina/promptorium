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

/// Timeline of one session: stored events (`session_events`) first, then the
/// live events pushed by `SessionManager`.
///
/// Live events that arrive while the stored ones are loading are buffered;
/// those already stored (same or lower `seq`) are dropped after the load.
class SessionTimelineNotifier extends Notifier<TimelineSnapshot> {
  SessionTimelineNotifier(this.sessionId);

  final String sessionId;
  final Timeline _t = Timeline();
  final List<(int?, ClaudeEvent)> _pending = [];
  bool _loaded = false;
  int _version = 0;

  @override
  TimelineSnapshot build() {
    _load();
    return TimelineSnapshot(_t, version: 0, loading: true);
  }

  Future<void> _load() async {
    var maxSeq = 0;
    try {
      final rows = await ref.read(sessionsRepoProvider).events(sessionId);
      for (final r in rows) {
        _t.applyStored(r.json, at: r.createdAt);
        if (r.seq > maxSeq) maxSeq = r.seq;
      }
    } catch (e) {
      debugPrint('timeline $sessionId: falha ao carregar eventos — $e');
    }
    _loaded = true;
    for (final (seq, e) in _pending) {
      if (seq == null || seq > maxSeq) _t.apply(e);
    }
    _pending.clear();
    _emit();
  }

  /// Applies a live event ([seq] = its `session_events.seq`, null when the
  /// event is not stored, e.g. `stream_event`).
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

final sessionTimelineProvider =
    NotifierProvider.family<SessionTimelineNotifier, TimelineSnapshot, String>(
      SessionTimelineNotifier.new,
    );
