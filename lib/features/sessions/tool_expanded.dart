import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'timeline.dart';
import 'timeline_provider.dart';

/// Tool calls of [items] in timeline order, subagent calls right after
/// their Task card (SPEC-058 R3: the neighbours of Anterior / Próxima).
List<ToolItem> flattenTools(List<TimelineItem> items) => [
  for (final i in items)
    if (i is ToolItem) ...[i, ...flattenTools(i.children)],
];

/// Tool [id] of [items], nested ones included.
ToolItem? findTool(List<TimelineItem> items, String id) {
  for (final i in items) {
    if (i is! ToolItem) continue;
    if (i.id == id) return i;
    final c = findTool(i.children, id);
    if (c != null) return c;
  }
  return null;
}

/// Tool calls of a session, in order (see [flattenTools]).
final sessionToolsProvider = Provider.family<List<ToolItem>, String>(
  (ref, sessionId) =>
      flattenTools(ref.watch(sessionTimelineProvider(sessionId)).items),
);

/// The expanded tool of the Sessions screen (SPEC-058). Kept after
/// [ToolExpandedController.close] with [open] false: the timeline of
/// [sessionId] then brings card [toolId] back into view, focused and
/// highlighted (R8). [seq] tells one close from the next.
@immutable
class ToolExpanded {
  const ToolExpanded({
    required this.sessionId,
    required this.toolId,
    this.origin,
    this.open = true,
    this.seq = 0,
  });

  final String sessionId;
  final String toolId;

  /// Global rectangle of the card that was clicked: the view grows from it
  /// (R9).
  final Rect? origin;
  final bool open;
  final int seq;

  ToolExpanded copyWith({String? toolId, bool? open, int? seq}) => ToolExpanded(
    sessionId: sessionId,
    toolId: toolId ?? this.toolId,
    origin: origin,
    open: open ?? this.open,
    seq: seq ?? this.seq,
  );
}

/// Cards of one session's timeline currently on screen, by tool id: the
/// view shrinks back to the card's rectangle and the timeline scrolls to it
/// when it closes (R8, R9).
class ToolCardRegistry {
  final _cards = <String, (BuildContext, Rect? Function())>{};

  /// Card [toolId] at [context]; [rect] gives its global rectangle.
  void add(String toolId, BuildContext context, Rect? Function() rect) =>
      _cards[toolId] = (context, rect);

  void remove(String toolId, BuildContext context) {
    if (identical(_cards[toolId]?.$1, context)) _cards.remove(toolId);
  }

  BuildContext? contextOf(String toolId) {
    final c = _cards[toolId]?.$1;
    return c != null && c.mounted ? c : null;
  }

  /// Global rectangle of the card of [toolId] (null when not laid out).
  Rect? rectOf(String toolId) =>
      contextOf(toolId) == null ? null : _cards[toolId]!.$2();
}

/// Opens, walks and closes the expanded tool (SPEC-058 R1–R3, R8).
class ToolExpandedController extends Notifier<ToolExpanded?> {
  final _registries = <String, ToolCardRegistry>{};
  ToolReveal? _reveal;
  var _seq = 0;

  @override
  ToolExpanded? build() => null;

  /// Cards of [sessionId] on screen.
  ToolCardRegistry cards(String sessionId) =>
      _registries.putIfAbsent(sessionId, ToolCardRegistry.new);

  bool get isOpen => state?.open ?? false;

  /// The card of [sessionId] to bring back after the last close, the same
  /// object until the next one (null = none, or another session's).
  ToolReveal? revealFor(String sessionId) {
    final s = state;
    if (s == null || s.open || s.sessionId != sessionId) return null;
    final r = _reveal;
    if (r != null && r.seq == s.seq && r.toolId == s.toolId) return r;
    return _reveal = ToolReveal(s.toolId, s.seq);
  }

  /// Expands tool [toolId] of [sessionId], growing from [origin] (global).
  void open(String sessionId, String toolId, {Rect? origin}) {
    state = ToolExpanded(
      sessionId: sessionId,
      toolId: toolId,
      origin: origin,
      seq: _seq,
    );
  }

  List<ToolItem> _tools() => state == null
      ? const []
      : ref.read(sessionToolsProvider(state!.sessionId));

  int _index() {
    final s = state;
    if (s == null) return -1;
    return _tools().indexWhere((t) => t.id == s.toolId);
  }

  bool get hasPrevious => isOpen && _index() > 0;

  bool get hasNext {
    if (!isOpen) return false;
    final i = _index();
    return i >= 0 && i < _tools().length - 1;
  }

  /// The tool before the open one (R3); stays put at the first.
  void previous() {
    if (!hasPrevious) return;
    state = state!.copyWith(toolId: _tools()[_index() - 1].id);
  }

  /// The tool after the open one (R3); stays put at the last.
  void next() {
    if (!hasNext) return;
    state = state!.copyWith(toolId: _tools()[_index() + 1].id);
  }

  /// Back to the layout; the last tool shown gets the focus (R8).
  void close() {
    final s = state;
    if (s == null || !s.open) return;
    state = s.copyWith(open: false, seq: ++_seq);
  }
}

final toolExpandedProvider =
    NotifierProvider<ToolExpandedController, ToolExpanded?>(
      ToolExpandedController.new,
    );

/// What a [ToolCard] asks of the screen around it: open the expanded view
/// and, after it closes, come back into view focused and highlighted. Absent
/// (Prompt), the card opens in place.
class ToolExpandHost extends InheritedWidget {
  const ToolExpandHost({
    super.key,
    required this.onOpen,
    required this.cards,
    required this.reveal,
    required super.child,
  });

  /// Expands [tool]; [origin] is the card's global rectangle.
  final void Function(ToolItem tool, Rect? origin) onOpen;
  final ToolCardRegistry cards;

  /// The card to bring back after a close (null = none).
  final ToolReveal? reveal;

  static ToolExpandHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolExpandHost>();

  @override
  bool updateShouldNotify(ToolExpandHost old) =>
      reveal != old.reveal || cards != old.cards;
}

/// One return to card [toolId] (R8). Taken by the first card that shows it,
/// so a card that scrolls out and back does not flash again.
class ToolReveal {
  ToolReveal(this.toolId, this.seq);

  final String toolId;
  final int seq;
  bool taken = false;
}
