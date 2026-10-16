import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../sessions/session_manager.dart';
import 'board_rules.dart';
import 'spec_runner.dart';

/// Quadro on autopilot (play / stop): while on for a workspace, every
/// approved spec in Backlog starts by itself as soon as its dependencies
/// are in Review or Feito (those still in Review are not merged, so the new
/// branch starts from theirs); specs without dependencies all start at once.
/// It turns itself off when no spec is running and none can start.
/// The state is in memory: it is off after restarting the app.
class Autopilot extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  bool isOn(int workspaceId) => state.contains(workspaceId);

  Future<void> start(int workspaceId) async {
    state = {...state, workspaceId};
    await tick(workspaceId);
  }

  /// Off, and the sessions the autopilot's specs have running are stopped
  /// (their steps go back to pending).
  Future<void> stop(int workspaceId) async {
    state = {...state}..remove(workspaceId);
    final manager = ref.read(sessionManagerProvider.notifier);
    final sessions = await ref
        .read(sessionsRepoProvider)
        .watchByWorkspace(workspaceId)
        .first;
    for (final s in sessions) {
      if (s.specId != null && manager.isAlive(s.id)) await manager.stop(s.id);
    }
  }

  /// Starts what can start now. Called on play and when a spec reaches Review.
  Future<void> tick(int workspaceId) async {
    if (!isOn(workspaceId)) return;
    final specs = ref.read(specsRepoProvider);
    final all = await specs.watchByWorkspace(workspaceId).first;
    final byCode = specsByCode(all);
    var started = 0;
    for (final s in all) {
      if (!isOnBoard(s) ||
          s.stage != SpecStage.backlog ||
          s.status == SpecStatus.done) {
        continue;
      }
      if (specBlockers(s, byCode, reviewUnblocks: true).isNotEmpty) continue;
      try {
        await ref.read(specRunnerProvider).runNext(s.id, reviewUnblocks: true);
      } catch (e) {
        debugPrint('autopilot: ${s.code} não iniciada — $e');
      }
    }
    // Nothing started now and nothing running: the last spec is finished
    // (or what is left cannot start by itself), so the autopilot turns off.
    final now = await specs.watchByWorkspace(workspaceId).first;
    if (started == 0 && !now.any((s) => s.stage == SpecStage.running)) {
      state = {...state}..remove(workspaceId);
    }
  }
}

final autopilotProvider = NotifierProvider<Autopilot, Set<int>>(Autopilot.new);
