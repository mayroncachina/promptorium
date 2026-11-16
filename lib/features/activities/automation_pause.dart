import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../board/autopilot.dart';

/// "Pausar automáticos" (SPEC-076 R8): one switch, kept in `app_settings`,
/// that holds the Autopilot (the "Executar tudo" and the scheduled start do
/// not start new specs) and the automatic "Corrigir CI". Turns already on
/// their way finish; nothing is stopped.
const automationPausedKey = 'automaticos.pausados';

class AutomationPause extends Notifier<bool> {
  @override
  bool build() => ref.watch(
    appSettingsProvider.select((s) => s[automationPausedKey] == '1'),
  );

  Future<void> set(bool paused) async {
    final settings = ref.read(appSettingsProvider.notifier);
    if (paused) {
      await settings.set(automationPausedKey, '1');
      return;
    }
    await settings.remove(automationPausedKey);
    // Back on: the Autopilot looks at its queue again.
    final pilot = ref.read(autopilotProvider.notifier);
    for (final id in ref.read(autopilotProvider)) {
      unawaited(pilot.tick(id));
    }
  }
}

final automationPausedProvider = NotifierProvider<AutomationPause, bool>(
  AutomationPause.new,
);

/// Whether the automatics are paused, read outside a widget.
bool automationPaused(Ref ref) =>
    ref.read(appSettingsProvider.notifier).get(automationPausedKey) == '1';

/// "Pausar após o turno" (SPEC-076 R8, P10): sessions whose spec does not go
/// on to the next step when the running turn ends. In memory: the flag is
/// spent by that turn.
class PauseAfterTurn extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String sessionId) => state = state.contains(sessionId)
      ? ({...state}..remove(sessionId))
      : {...state, sessionId};

  /// Takes the flag of [sessionId]: true when it was set.
  bool take(String sessionId) {
    if (!state.contains(sessionId)) return false;
    state = {...state}..remove(sessionId);
    return true;
  }
}

final pauseAfterTurnProvider = NotifierProvider<PauseAfterTurn, Set<String>>(
  PauseAfterTurn.new,
);
