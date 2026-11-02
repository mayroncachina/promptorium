import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../features/board/widgets/wave_graph.dart';
import '../../features/sessions/session_manager.dart';

/// What the header mark says while specs run (SPEC-031 R3, R7): how many
/// specs of the active project are running, and the wave `i` of `n` the
/// Quadro's strip shows.
typedef BrandActivity = ({int running, int wave, int waves});

/// Specs of a project running right now: stage `running` and a live
/// session of the spec producing events. Conversations of the Prompt screen
/// have no spec and do not count; a step waiting for the person does not
/// either (its session is `waitingApproval` or gone).
BrandActivity? brandActivityOf(
  List<Spec> specs,
  List<Session> sessions,
  bool Function(String sessionId) isAlive,
) {
  final working = {
    for (final s in sessions)
      if (s.specId != null &&
          s.status == SessionStatus.running &&
          isAlive(s.id))
        s.specId!,
  };
  final running = specs
      .where((s) => s.stage == SpecStage.running && working.contains(s.id))
      .length;
  if (running == 0) return null;
  final waves = dependencyWaves(specs);
  final count = waves.values.fold(0, math.max) + 1;
  return (
    running: running,
    wave: (nextWave(specs, waves) ?? 0) + 1,
    waves: count,
  );
}

/// The label of the mark (tooltip and screen readers).
String brandLabel(BrandActivity? a) {
  if (a == null) return 'Promptorium';
  final specs =
      '${a.running} ${a.running == 1 ? 'spec' : 'specs'} '
      'em execução';
  return a.waves > 1
      ? 'Executando a onda ${a.wave} de ${a.waves} · $specs'
      : specs;
}

final brandActivityProvider = Provider<BrandActivity?>((ref) {
  final ws = ref.watch(activeWorkspaceProvider);
  if (ws == null) return null;
  final specs = ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
  final sessions =
      ref.watch(sessionsProvider(ws.id)).value ?? const <Session>[];
  // Only which sessions are alive matters, not every event they stream.
  final alive = ref.watch(
    sessionManagerProvider.select(
      (m) => ([
        for (final e in m.live.entries)
          if (e.value.alive) e.key,
      ]..sort()).join('\n'),
    ),
  );
  final ids = alive.isEmpty ? const <String>{} : alive.split('\n').toSet();
  return brandActivityOf(specs, sessions, ids.contains);
});
