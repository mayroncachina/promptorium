import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/gh_issues.dart';
import '../../data/providers.dart';
import '../project/project_config.dart';
import 'issue_availability.dart';

/// The state of the linked issues (SPEC-074 R9): checked when the Quadro
/// opens and every 10 minutes with the app open, in one query per
/// workspace. A closed issue changes the badge only: nothing moves.

/// What changes in the row of [spec] for what GitHub says ([s]); null when
/// nothing changes. Only the issue columns: the status, the column of the
/// Quadro and the Bandeja stay as they are.
SpecsCompanion? issueStateChange(Spec spec, GhIssueState s) {
  final state = !s.found
      ? IssueState.notFound
      : s.closed
      ? IssueState.closed
      : IssueState.open;
  final closedAt = state == IssueState.closed ? s.closedAt : null;
  final closedBy = state == IssueState.closed ? s.closedBy : null;
  // The table gives local times, GitHub UTC: the same moment is the same.
  final sameAt = spec.issueClosedAt == null || closedAt == null
      ? spec.issueClosedAt == closedAt
      : spec.issueClosedAt!.isAtSameMomentAs(closedAt);
  if (spec.issueState == state && sameAt && spec.issueClosedBy == closedBy) {
    return null;
  }
  return SpecsCompanion(
    issueState: Value(state),
    issueClosedAt: Value(closedAt),
    issueClosedBy: Value(closedBy),
  );
}

/// How often the states are checked with the app open (null = never by
/// itself: the tests, where a periodic timer would outlive the test).
final issueWatchPeriodProvider = Provider<Duration?>(
  (ref) => Platform.environment.containsKey('FLUTTER_TEST')
      ? null
      : const Duration(minutes: 10),
);

class IssueStateWatcher {
  IssueStateWatcher(this._ref);

  final Ref _ref;
  final _timers = <int, Timer>{};
  final _running = <int, Future<int>>{};

  /// Checks the issues of the workspace [workspaceId] now and keeps
  /// checking every [issueWatchPeriodProvider]. Returns how many specs
  /// changed.
  Future<int> watch(int workspaceId) {
    final period = _ref.read(issueWatchPeriodProvider);
    if (period != null && !_timers.containsKey(workspaceId)) {
      _timers[workspaceId] = Timer.periodic(
        period,
        (_) => unawaited(check(workspaceId)),
      );
    }
    return check(workspaceId);
  }

  /// One check of the workspace (a second call while one runs joins it).
  Future<int> check(int workspaceId) =>
      _running[workspaceId] ??= _check(workspaceId).whenComplete(() {
        // Not `=> remove(...)`: that returns this very future, and
        // `whenComplete` would wait for itself.
        _running.remove(workspaceId);
      });

  Future<int> _check(int workspaceId) async {
    try {
      final repo = _ref.read(specsRepoProvider);
      final linked = [
        for (final s in await repo.watchByWorkspace(workspaceId).first)
          if (s.issueNumber != null) s,
      ];
      if (linked.isEmpty) return 0;
      final ws = await _ref.read(workspacesRepoProvider).getById(workspaceId);
      if (ws == null) return 0;
      if (!ProjectConfig.loadSync(ws.path).issues.checkClosed) return 0;
      final (client, _) = await githubIssuesOf(_ref, ws);
      // Without GitHub the badge stays, without the state (R2).
      if (client == null) return 0;
      final states = {
        for (final s in await client.states(linked.map((s) => s.issueNumber!)))
          s.number: s,
      };
      var changed = 0;
      for (final spec in linked) {
        final s = states[spec.issueNumber];
        if (s == null) continue;
        final change = issueStateChange(spec, s);
        if (change == null) continue;
        await repo.update(spec.id, change);
        changed++;
      }
      return changed;
    } catch (e) {
      debugPrint('Estado das issues: $e');
      return 0;
    }
  }

  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}

final issueStateWatcherProvider = Provider<IssueStateWatcher>((ref) {
  final w = IssueStateWatcher(ref);
  ref.onDispose(w.dispose);
  return w;
});

/// Watched by the Quadro: each time it opens, the issues of the workspace
/// are checked (R9).
final boardIssueCheckProvider = FutureProvider.autoDispose.family<int, int>(
  (ref, workspaceId) => ref.read(issueStateWatcherProvider).watch(workspaceId),
);
