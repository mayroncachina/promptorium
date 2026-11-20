import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a Contexto panel lives: the Prompt or the Sessions screen.
enum ContextPlace { prompt, sessions }

/// Whether the Contexto panel is open on a screen (SPEC-087 P1: the meter
/// is the entry point; the panel is not a permanent dashboard).
class ContextPanelOpen extends Notifier<bool> {
  ContextPanelOpen(this.place);

  final ContextPlace place;

  @override
  bool build() => false;

  void set(bool v) => state = v;

  void toggle() => state = !state;
}

final contextPanelOpenProvider =
    NotifierProvider.family<ContextPanelOpen, bool, ContextPlace>(
      ContextPanelOpen.new,
    );

/// A request to scroll a timeline to an item ("Ir ao turno", R6). The
/// token makes two jumps to the same index distinct.
class TimelineJump {
  TimelineJump(this.index);

  final int index;
}

/// The pending jump of a timeline (key: `session:<id>` / `conv:<id>`).
class TimelineJumpController extends Notifier<TimelineJump?> {
  TimelineJumpController(this.key);

  final String key;

  @override
  TimelineJump? build() => null;

  void jump(int index) => state = TimelineJump(index);
}

final timelineJumpProvider =
    NotifierProvider.family<TimelineJumpController, TimelineJump?, String>(
      TimelineJumpController.new,
    );

/// The tab the panel of a screen shows (the warning's "Revisar próximos
/// anexos" opens Fontes).
class ContextPanelTab extends Notifier<int> {
  ContextPanelTab(this.place);

  final ContextPlace place;

  /// 0 = Uso, 1 = Fontes.
  @override
  int build() => 0;

  void set(int tab) => state = tab;
}

final contextPanelTabProvider =
    NotifierProvider.family<ContextPanelTab, int, ContextPlace>(
      ContextPanelTab.new,
    );

/// Warnings dismissed in this run of the app (R10: one per crossing). The
/// key names the history, the turn and the reference of the warning.
class DismissedContextWarnings extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void dismiss(String key) => state = {...state, key};
}

final dismissedContextWarningsProvider =
    NotifierProvider<DismissedContextWarnings, Set<String>>(
      DismissedContextWarnings.new,
    );
