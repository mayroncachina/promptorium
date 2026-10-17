import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../project/project_config.dart';
import '../sessions/app_notifier.dart';
import '../sessions/session_manager.dart';
import 'board_rules.dart';
import 'spec_runner.dart';

/// Quadro on autopilot (play / stop): while on for a workspace, every
/// approved spec in Backlog starts by itself as soon as its dependencies
/// are in Review or Feito (those still in Review are not merged, so the new
/// branch starts from theirs); specs without dependencies all start at once.
/// It turns itself off when no spec is running and none can start.
/// The state is in the database (schema v9): [restore] turns it back on
/// when the app opens.
class Autopilot extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  bool isOn(int workspaceId) => state.contains(workspaceId);

  Future<void> start(int workspaceId) async {
    state = {...state, workspaceId};
    await _store(workspaceId, true);
    await tick(workspaceId);
  }

  /// Splash: workspaces whose autopilot was on when the app closed.
  Future<void> restore() async {
    final on = await ref.read(durableStateRepoProvider).autopilotOn();
    if (on.isEmpty) return;
    state = {...state, ...on};
    for (final id in on) {
      await tick(id);
    }
  }

  Future<void> _store(int workspaceId, bool on) async {
    try {
      await ref.read(durableStateRepoProvider).setAutopilot(workspaceId, on);
    } catch (e) {
      debugPrint('autopilot de $workspaceId não gravado — $e');
    }
  }

  void _off(int workspaceId) {
    state = {...state}..remove(workspaceId);
    unawaited(_store(workspaceId, false));
  }

  /// Off, and the sessions the autopilot's specs have running are stopped
  /// (their steps go back to pending).
  Future<void> stop(int workspaceId) async {
    _off(workspaceId);
    final manager = ref.read(sessionManagerProvider.notifier);
    final sessions = await ref
        .read(sessionsRepoProvider)
        .watchByWorkspace(workspaceId)
        .first;
    for (final s in sessions) {
      if (s.specId != null && manager.isAlive(s.id)) await manager.stop(s.id);
    }
  }

  /// Spec sessions' cost of the day in [workspaceId] (`orcamento-dia`).
  Future<double> spentToday(int workspaceId, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final sessions = await ref
        .read(sessionsRepoProvider)
        .watchByWorkspace(workspaceId)
        .first;
    return sessions
        .where((s) => s.specId != null && !s.startedAt.isBefore(day))
        .fold<double>(0, (a, s) => a + s.costUsd);
  }

  /// Off (with a notification) when the day's budget is spent. Returns
  /// whether it turned off. Sessions already running finish their turn.
  Future<bool> checkBudget(int workspaceId) async {
    if (!isOn(workspaceId)) return false;
    final ws = await ref.read(workspacesRepoProvider).getById(workspaceId);
    if (ws == null) return false;
    final budget = ProjectConfig.loadSync(ws.path).autopilot.dailyBudgetUsd;
    if (budget == null) return false;
    final spent = await spentToday(workspaceId);
    if (spent < budget) return false;
    _off(workspaceId);
    unawaited(
      ref
          .read(appNotifierProvider)
          .show(
            'Autopilot parado',
            '${ws.name}: orçamento do dia atingido '
                '(US\$ ${spent.toStringAsFixed(2)} de '
                'US\$ ${budget.toStringAsFixed(2)}).',
          ),
    );
    return true;
  }

  /// Starts what can start now, up to `autopilot.paralelo` specs running at
  /// once. Called on play and when a spec reaches Review.
  Future<void> tick(int workspaceId) async {
    if (!isOn(workspaceId)) return;
    if (await checkBudget(workspaceId)) return;
    final ws = await ref.read(workspacesRepoProvider).getById(workspaceId);
    final parallel = ws == null
        ? null
        : ProjectConfig.loadSync(ws.path).autopilot.parallel;
    final specs = ref.read(specsRepoProvider);
    final all = await specs.watchByWorkspace(workspaceId).first;
    final byCode = specsByCode(all);
    var running = all.where((s) => s.stage == SpecStage.running).length;
    var started = 0;
    for (final s in all) {
      if (parallel != null && running >= parallel) break;
      if (!isOnBoard(s) ||
          s.stage != SpecStage.backlog ||
          s.status == SpecStatus.done) {
        continue;
      }
      if (specBlockers(s, byCode, reviewUnblocks: true).isNotEmpty) continue;
      try {
        await ref.read(specRunnerProvider).runNext(s.id, reviewUnblocks: true);
        started++;
        running++;
      } catch (e) {
        debugPrint('autopilot: ${s.code} não iniciada — $e');
      }
    }
    // Nothing started now and nothing running: the last spec is finished
    // (or what is left cannot start by itself), so the autopilot turns off.
    final now = await specs.watchByWorkspace(workspaceId).first;
    if (started == 0 && !now.any((s) => s.stage == SpecStage.running)) {
      _off(workspaceId);
    }
  }
}

final autopilotProvider = NotifierProvider<Autopilot, Set<int>>(Autopilot.new);
