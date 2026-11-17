import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/git/gh_cli.dart' show CiState, ciStateOf;
import '../../data/db/app_database.dart';
import '../../data/repos/activity_events_repo.dart';
import '../activities/activity.dart' show specSeed;
import 'activity_journal.dart';

/// What happened on GitHub with the app closed (SPEC-080 R7): before the
/// card is built, the PRs of the specs and the followed ones are read with
/// `gh pr view`, and merges, closes and finished CI since the last seen
/// time enter the journal with GitHub's time.

/// A PR to check.
typedef CatchUpPr = ({
  int workspaceId,

  /// The repository (`gh` runs in it).
  String repoPath,
  int number,
  String? sessionId,
  Spec? spec,

  /// The session's title (a PR without a spec).
  String title,
});

/// What `gh pr view --json [catchUpFields]` says.
typedef CatchUpView = ({
  String state,
  DateTime? mergedAt,
  DateTime? closedAt,
  String? mergedBy,
  CiState ci,

  /// When the last check finished (null = none finished, or one runs).
  DateTime? ciDoneAt,
  List<String> failed,
});

const catchUpFields = 'state,mergedAt,closedAt,mergedBy,statusCheckRollup';

DateTime? _date(Object? v) =>
    v is String && v.isNotEmpty && !v.startsWith('0001-')
    ? DateTime.tryParse(v)?.toLocal()
    : null;

/// Parses `gh pr view --json [catchUpFields]` (null = invalid).
CatchUpView? parseCatchUpView(String text) {
  Object? j;
  try {
    j = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (j is! Map) return null;
  final checks = [
    for (final c in (j['statusCheckRollup'] as List? ?? const []))
      if (c is Map) c,
  ];
  // A check run has `status`/`conclusion`; a commit status has `state`.
  String stateOf(Map c) {
    final conclusion = '${c['conclusion'] ?? ''}';
    if (conclusion.isNotEmpty) return conclusion;
    final status = '${c['status'] ?? ''}';
    if (status.isNotEmpty && status != 'COMPLETED') return 'PENDING';
    return '${c['state'] ?? 'PENDING'}';
  }

  final states = [for (final c in checks) stateOf(c)];
  final ci = ciStateOf(states);
  DateTime? done;
  if (ci == CiState.passed || ci == CiState.failed) {
    for (final c in checks) {
      final at = _date(c['completedAt']) ?? _date(c['startedAt']);
      if (at != null && (done == null || at.isAfter(done))) done = at;
    }
  }
  final by = j['mergedBy'];
  return (
    state: '${j['state'] ?? 'OPEN'}',
    mergedAt: _date(j['mergedAt']),
    closedAt: _date(j['closedAt']),
    mergedBy: by is Map ? '${by['login'] ?? ''}' : null,
    ci: ci,
    ciDoneAt: done,
    failed: [
      for (final c in checks)
        if (ciStateOf([stateOf(c)]) == CiState.failed)
          '${c['name'] ?? c['context'] ?? '?'}',
    ],
  );
}

/// The events of [pr] after [since] in [view] (R7).
List<JournalEntry> catchUpEntries(
  CatchUpPr pr,
  CatchUpView view,
  DateTime since,
) {
  final spec = pr.spec;
  final label = 'PR #${pr.number}';
  JournalEntry e(JournalKind k, JournalOutcome o, String detail, DateTime at) =>
      JournalEntry(
        workspaceId: pr.workspaceId,
        kind: k,
        outcome: o,
        title: spec == null ? label : '${spec.code} · ${spec.title}',
        detail: detail,
        seed: spec == null
            ? (pr.sessionId == null ? null : 'session:${pr.sessionId}')
            : specSeed(pr.workspaceId, spec.code),
        specId: spec?.id,
        sessionId: pr.sessionId,
        prNumber: pr.number,
        at: at,
      );
  final out = <JournalEntry>[];
  if (view.state == 'MERGED') {
    final at = view.mergedAt;
    if (at != null && at.isAfter(since)) {
      final by = view.mergedBy;
      out.add(
        e(
          JournalKind.pr,
          JournalOutcome.ok,
          by == null || by.isEmpty
              ? '$label mergeado'
              : '$label mergeado por $by',
          at,
        ),
      );
    }
    return out;
  }
  if (view.state == 'CLOSED') {
    final at = view.closedAt;
    if (at != null && at.isAfter(since)) {
      out.add(
        e(
          JournalKind.pr,
          JournalOutcome.attention,
          '$label fechado sem merge',
          at,
        ),
      );
    }
    return out;
  }
  if (view.ciDoneAt case final at? when at.isAfter(since)) {
    if (view.ci == CiState.passed) {
      out.add(e(JournalKind.ci, JournalOutcome.ok, 'CI do $label passou', at));
    } else if (view.ci == CiState.failed) {
      final names = [for (final n in view.failed.take(2)) '`$n`'];
      out.add(
        e(
          JournalKind.ci,
          JournalOutcome.failed,
          'CI do $label falhou'
          '${names.isEmpty ? '' : ' em ${names.join(', ')}'}',
          at,
        ),
      );
    }
  }
  return out;
}

/// The PRs worth checking: the sessions with a PR that is not merged by
/// the app, newest first, at most [limit] (each one is a `gh` call).
List<CatchUpPr> catchUpPrs({
  required List<Workspace> workspaces,
  required Map<int, List<Session>> sessions,
  required Map<int, List<Spec>> specs,
  required DateTime since,
  int limit = 30,
}) {
  final out = <(DateTime, CatchUpPr)>[];
  final keep = since.subtract(const Duration(days: activityJournalDays));
  for (final ws in workspaces) {
    final byId = {for (final s in specs[ws.id] ?? const <Spec>[]) s.id: s};
    final seen = <int>{};
    for (final s in sessions[ws.id] ?? const <Session>[]) {
      final n = prNumberOf(s.prUrl);
      if (n == null || !seen.add(n)) continue;
      if (s.status == SessionStatus.merged) continue;
      final spec = byId[s.specId];
      if (spec?.stage == SpecStage.done) continue;
      final at = s.endedAt ?? s.startedAt;
      if (s.endedAt != null && at.isBefore(keep)) continue;
      out.add((
        at,
        (
          workspaceId: ws.id,
          repoPath: ws.path,
          number: n,
          sessionId: s.id,
          spec: spec,
          title: s.title ?? 'PR #$n',
        ),
      ));
    }
  }
  out.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final p in out.take(limit)) p.$2];
}

/// `gh pr view` of a PR in a repository; throws when `gh` is missing or
/// fails.
typedef GhPrView = Future<String> Function(
  String repoPath,
  int number,
  String fields,
);

/// Checks [prs] and writes what happened after [since] (R7). Returns false
/// when GitHub could not be read (no network, no `gh`): the card says so
/// and offers "Tentar de novo".
Future<bool> catchUpGithub({
  required List<CatchUpPr> prs,
  required DateTime since,
  required GhPrView view,
  required ActivityEventsRepo repo,
}) async {
  var ok = true;
  for (final pr in prs) {
    final CatchUpView? v;
    try {
      v = parseCatchUpView(await view(pr.repoPath, pr.number, catchUpFields));
    } catch (e) {
      debugPrint('Retomar: PR #${pr.number} não conferido — $e');
      ok = false;
      // Without `gh` or network every call fails the same way.
      if (prs.length > 1 && pr == prs.first) return false;
      continue;
    }
    if (v == null) continue;
    for (final e in catchUpEntries(pr, v, since)) {
      if (await repo.has(e.groupKey, e.kind.name, e.at)) continue;
      // The app already wrote this merge while it was open.
      final last = await repo.latestOf(e.groupKey, e.kind.name);
      if (last != null &&
          last.detail.startsWith(e.detail.split(' por ').first) &&
          last.at.difference(e.at).abs() < const Duration(minutes: 10)) {
        continue;
      }
      await writeJournal(repo, e);
    }
  }
  return ok;
}
