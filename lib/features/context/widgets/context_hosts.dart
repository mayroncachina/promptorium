import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../prompt/conversation_manager.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/timeline_provider.dart';
import '../context_panel_state.dart';
import '../context_snapshot.dart';
import '../context_sources.dart';
import 'context_indicator.dart';
import 'context_panel.dart';

/// Which history a meter / panel reads: a Prompt conversation or a session.
@immutable
sealed class ContextTarget {
  const ContextTarget();

  ContextPlace get place;

  /// Key of [timelineJumpProvider].
  String get jumpKey;

  String get placeLabel;

  TimelineSnapshot watchTimeline(WidgetRef ref);

  bool watchAlive(WidgetRef ref);
}

class ConversationTarget extends ContextTarget {
  const ConversationTarget(this.id);

  final int id;

  @override
  ContextPlace get place => ContextPlace.prompt;

  @override
  String get jumpKey => 'conv:$id';

  @override
  String get placeLabel => 'Conversa';

  @override
  TimelineSnapshot watchTimeline(WidgetRef ref) =>
      ref.watch(conversationTimelineProvider(id));

  @override
  bool watchAlive(WidgetRef ref) =>
      ref.watch(conversationManagerProvider.select((s) => s.isAlive(id)));

  @override
  bool operator ==(Object other) =>
      other is ConversationTarget && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class SessionTarget extends ContextTarget {
  const SessionTarget(this.id);

  final String id;

  @override
  ContextPlace get place => ContextPlace.sessions;

  @override
  String get jumpKey => 'session:$id';

  @override
  String get placeLabel => 'Sessão';

  @override
  TimelineSnapshot watchTimeline(WidgetRef ref) =>
      ref.watch(sessionTimelineProvider(id));

  @override
  bool watchAlive(WidgetRef ref) =>
      ref.watch(sessionManagerProvider.select((s) => s.isAlive(id)));

  @override
  bool operator ==(Object other) => other is SessionTarget && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The meter above a composer (R2): reads the history's tracker and opens
/// the panel of its screen.
class ContextBar extends ConsumerWidget {
  const ContextBar({super.key, required this.target});

  final ContextTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = target.watchTimeline(ref);
    final open = ref.watch(contextPanelOpenProvider(target.place));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: ContextIndicator(
        snapshot: snap.timeline.context.snapshot,
        alive: target.watchAlive(ref),
        open: open,
        onOpen: () =>
            ref.read(contextPanelOpenProvider(target.place).notifier).toggle(),
      ),
    );
  }
}

/// The Contexto panel of [target] (R2–R6). [autocompact], [actions] and
/// [nextSend] are filled by the compaction controls (T3).
class ContextPanelHost extends ConsumerWidget {
  const ContextPanelHost({
    super.key,
    required this.target,
    this.title,
    this.autocompact,
    this.actions,
    this.nextSend,
  });

  final ContextTarget target;
  final String? title;
  final Widget? autocompact;
  final Widget? actions;
  final Widget? nextSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = target.watchTimeline(ref);
    final tracker = snap.timeline.context;
    void jump(int index) =>
        ref.read(timelineJumpProvider(target.jumpKey).notifier).jump(index);
    return ContextPanel(
      key: ValueKey('context-panel-${target.jumpKey}'),
      snapshot: tracker.snapshot,
      sources: tracker.sources,
      place: target.placeLabel,
      title: title,
      alive: target.watchAlive(ref),
      onClose: () =>
          ref.read(contextPanelOpenProvider(target.place).notifier).set(false),
      // The item after the reading (its answer) is the one to show.
      onJump: (ContextReading r) => jump(r.itemIndex - 1),
      // R5: a source opens the event that originated it.
      onOpenSource: (ContextSource s) => jump(s.itemIndex - 1),
      autocompact: autocompact,
      actions: actions,
      nextSend: nextSend,
    );
  }
}
