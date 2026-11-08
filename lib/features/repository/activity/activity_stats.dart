import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/git/git_service.dart' show CommitOrigin, CommitOriginKind;
import '../graph/lane_layout.dart';
import '../graph/spec_branch.dart';
import '../graph/spec_of_commit.dart';
import '../releases/semver.dart';
import '../releases/unreleased.dart';
import 'activity_log.dart';

/// The periods of the Atividade (R1).
enum ActivityPeriod {
  days30(30, '30 dias'),
  days90(90, '90 dias'),
  year(365, '1 ano');

  const ActivityPeriod(this.days, this.label);

  final int days;
  final String label;
}

/// Group of the commits outside the conventional pattern (R3).
const otherGroup = 'Outros';

/// Most named groups in "Commits por tipo"; the smaller ones join
/// [otherGroup] (R3).
const maxTypeGroups = 6;

/// Files the analysis leaves out (R5): generated code and lockfiles.
const ignoredFiles = [
  '*.g.dart',
  '*.freezed.dart',
  '*.mocks.dart',
  'pubspec.lock',
  'package-lock.json',
  'yarn.lock',
  'pnpm-lock.yaml',
  'Cargo.lock',
  'poetry.lock',
  'Gemfile.lock',
  'composer.lock',
  'go.sum',
];

/// Whether [path] matches one of [patterns] (a glob on the file name:
/// `*.g.dart`, `pubspec.lock`).
bool isIgnoredFile(String path, [List<String> patterns = ignoredFiles]) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  for (final p in patterns) {
    final re = RegExp(
      '^${RegExp.escape(p).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
    );
    if (re.hasMatch(name) || re.hasMatch(path)) return true;
  }
  return false;
}

/// Local midnight of [t].
DateTime dayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Monday of the week of [t].
DateTime weekOf(DateTime t) {
  final d = dayOf(t);
  return DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
}

/// Median of [values] (null when empty).
double? median(List<double> values) {
  if (values.isEmpty) return null;
  final s = [...values]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Percentile [p] (0–100) of [values], interpolated between the closest
/// ranks (null when empty).
double? percentile(List<double> values, double p) {
  if (values.isEmpty) return null;
  final s = [...values]..sort();
  final rank = (p / 100) * (s.length - 1);
  final lo = rank.floor(), hi = rank.ceil();
  return s[lo] + (s[hi] - s[lo]) * (rank - lo);
}

/// `+38%` / `−12%` of [now] against [before] (null when there is no base).
String? changeLabel(num now, num before) {
  if (before == 0) return null;
  final pct = ((now - before) / before * 100).round();
  if (pct == 0) return '0%';
  return pct > 0 ? '+$pct%' : '−${pct.abs()}%';
}

/// A spec merged into the default branch, with its cycle (R4).
@immutable
class SpecCycle {
  const SpecCycle(this.number, {required this.merged, this.start});

  final int number;

  /// First merge of the spec (mother or a daughter) into the default branch.
  final DateTime merged;

  /// First commit on a `spec/NNN-*` branch (null = none read).
  final DateTime? start;

  String get code => specCode(number);

  /// Days from [start] to [merged] (null without a start).
  double? get days => start == null
      ? null
      : math.max(0, merged.difference(start!).inMinutes) / (60 * 24);
}

/// A commit of the history of a file (R5).
@immutable
class FileCommit {
  const FileCommit({
    required this.sha,
    required this.subject,
    required this.time,
    this.spec,
  });

  final String sha;
  final String subject;
  final DateTime time;

  /// `SPEC-042` (null = no spec).
  final String? spec;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

/// A file of "Arquivos mais alterados" (R5).
@immutable
class FileStat {
  const FileStat({
    required this.path,
    required this.commits,
    required this.added,
    required this.removed,
    required this.specs,
    required this.history,
  });

  final String path;
  final int commits;
  final int added;
  final int removed;

  /// Distinct specs, newest first.
  final List<String> specs;

  /// Its commits in the period, newest first.
  final List<FileCommit> history;

  int get lines => added + removed;
}

/// A day of the map (R2).
@immutable
class DayCell {
  const DayCell(this.day, this.commits, this.specs);

  final DateTime day;
  final int commits;

  /// Specs that got commits on the day, in code order.
  final List<String> specs;
}

/// Commits by type in a week (R3).
@immutable
class TypeWeek {
  const TypeWeek(this.week, this.counts);

  final DateTime week;
  final Map<String, int> counts;

  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// Who made the commits of a week (R8).
@immutable
class OriginWeek {
  const OriginWeek(
    this.week, {
    this.person = 0,
    this.agent = 0,
    this.app = 0,
    this.unmarked = 0,
  });

  final DateTime week;
  final int person, agent, app, unmarked;

  int get total => person + agent + app + unmarked;
}

/// "Quem fez os commits" (R8).
@immutable
class OriginStats {
  const OriginStats({
    required this.weeks,
    required this.person,
    required this.agent,
    required this.app,
    required this.unmarked,
    required this.models,
    this.since,
  });

  final List<OriginWeek> weeks;
  final int person, agent, app, unmarked;

  /// Agent commits by model, most first.
  final List<(String model, int count)> models;

  /// First marked commit of the history (null = never marked).
  final DateTime? since;

  /// Commits with a known origin (the base of the percentages).
  int get marked => person + agent + app;
}

/// The summary line (R1): the period and the one before it.
@immutable
class ActivitySummary {
  const ActivitySummary({
    required this.commits,
    required this.prevCommits,
    required this.specsMerged,
    required this.prevSpecsMerged,
    required this.releases,
    required this.prevReleases,
    this.firstRelease,
    this.lastRelease,
    this.medianCycle,
    this.prevMedianCycle,
  });

  final int commits, prevCommits;
  final int specsMerged, prevSpecsMerged;

  /// Null without tags (R7).
  final int? releases, prevReleases;
  final String? firstRelease, lastRelease;

  /// Days (null without spec branches / merged specs).
  final double? medianCycle, prevMedianCycle;
}

/// "Ciclo das specs" (R4).
@immutable
class CycleStats {
  const CycleStats({
    required this.hasSpecBranches,
    required this.cycles,
    this.median,
    this.p90,
  });

  /// False = the repository never used `spec/*` branches (R7).
  final bool hasSpecBranches;

  /// Specs merged in the period with a start, longest first.
  final List<SpecCycle> cycles;
  final double? median, p90;

  List<SpecCycle> get longest => cycles.take(5).toList();
}

/// Everything the tab shows for one period.
@immutable
class ActivityReport {
  const ActivityReport({
    required this.period,
    required this.from,
    required this.to,
    required this.summary,
    required this.days,
    required this.releaseDays,
    required this.typeGroups,
    required this.typeWeeks,
    required this.cycle,
    required this.files,
    required this.origins,
    required this.hasTags,
  });

  final ActivityPeriod period;

  /// First day of the period (local midnight) and now.
  final DateTime from, to;
  final ActivitySummary summary;

  /// Days with commits.
  final Map<DateTime, DayCell> days;

  /// Day → tags of the day (empty without tags, R7).
  final Map<DateTime, List<String>> releaseDays;

  /// Groups in order, [otherGroup] last.
  final List<String> typeGroups;
  final List<TypeWeek> typeWeeks;
  final CycleStats cycle;

  /// The 15 most changed files (R5).
  final List<FileStat> files;
  final OriginStats origins;
  final bool hasTags;

  /// Most commits of a day (the darkest tone of the map).
  int get maxDay => days.values.fold(0, (m, d) => math.max(m, d.commits));

  /// Tone 0–4 of [commits] on the map (R2).
  int level(int commits) {
    if (commits <= 0) return 0;
    final max = maxDay;
    if (max <= 1) return 4;
    return (1 + ((commits - 1) * 4 / max).floor()).clamp(1, 4);
  }
}

/// What the stats need besides the log.
@immutable
class ActivityInput {
  const ActivityInput({
    required this.log,
    required this.defaultBranch,
    required this.now,
    required this.cliff,
    this.ignored = ignoredFiles,
  });

  final ActivityLog log;
  final String defaultBranch;
  final DateTime now;
  final CliffRules cliff;
  final List<String> ignored;
}

/// What every period shares, worked out once from the whole history.
class PreparedActivity {
  PreparedActivity._({
    required this.input,
    required this.commits,
    required this.spec,
    required this.specTrack,
    required this.merges,
    required this.cycles,
    required this.origins,
    required this.markSince,
    required this.hasSpecBranches,
  });

  final ActivityInput input;

  /// Every commit of the log, newest first.
  final List<ActivityCommit> commits;

  /// Spec of each commit (index of [commits]): branch, merge or subject.
  final List<SpecBranch?> spec;

  /// Spec of the branch each commit was made on (null = another branch).
  final List<SpecBranch?> specTrack;

  /// Spec number → first merge into the default branch.
  final Map<int, DateTime> merges;

  /// Every merged spec (all the history), by number.
  final Map<int, SpecCycle> cycles;

  /// Origin of each commit (R8).
  final List<CommitOrigin> origins;
  final DateTime? markSince;
  final bool hasSpecBranches;

  factory PreparedActivity(ActivityInput input) {
    final commits = input.log.laneCommits();
    final rows = layoutLanes(commits, defaultBranch: input.defaultBranch).rows;
    final spec = <SpecBranch?>[];
    final specTrack = <SpecBranch?>[];
    for (final (i, c) in commits.indexed) {
      final track = rows[i].track;
      final isDefault =
          track == input.defaultBranch ||
          (track != null &&
              parseSpecBranch(track) == null &&
              track.endsWith('/${input.defaultBranch}'));
      spec.add(
        specOfCommit(track: isDefault ? null : track, subject: c.subject),
      );
      specTrack.add(isDefault ? null : parseSpecBranch(track));
    }

    // First-parent line of the default branch (local and remote copies).
    final bySha = {for (final c in commits) c.sha: c};
    final chain = <String>{};
    for (final e in input.log.tips.entries) {
      final ref = e.key;
      if (ref != 'refs/heads/${input.defaultBranch}' &&
          !(ref.startsWith('refs/remotes/') &&
              ref.endsWith('/${input.defaultBranch}'))) {
        continue;
      }
      String? at = e.value;
      while (at != null && chain.add(at)) {
        final c = bySha[at];
        at = c == null || c.parents.isEmpty ? null : c.parents.first;
      }
    }
    final merges = <int, DateTime>{};
    for (final c in commits) {
      if (!c.isMerge || !chain.contains(c.sha)) continue;
      final s = parseSpecBranch(branchFromMergeSubject(c.subject));
      if (s == null) continue;
      final prev = merges[s.number];
      if (prev == null || c.time.isBefore(prev)) merges[s.number] = c.time;
    }
    final starts = <int, DateTime>{};
    for (final (i, c) in commits.indexed) {
      final s = specTrack[i];
      if (s == null || c.isMerge && chain.contains(c.sha)) continue;
      final merged = merges[s.number];
      if (merged != null && c.time.isAfter(merged)) continue;
      final prev = starts[s.number];
      if (prev == null || c.time.isBefore(prev)) starts[s.number] = c.time;
    }
    final cycles = {
      for (final e in merges.entries)
        e.key: SpecCycle(e.key, merged: e.value, start: starts[e.key]),
    };

    DateTime? since;
    for (final c in commits) {
      if (c.trailers.isEmpty) continue;
      if (since == null || c.committed.isBefore(since)) since = c.committed;
    }
    final origins = [
      for (final c in commits)
        CommitOrigin.parse(
          '${c.sha}\x1f${c.author}\x1f${c.committed.toIso8601String()}'
          '\x1f${c.subject}\x1f${c.trailers}',
          since: since,
        ),
    ];
    final hasSpecBranches =
        specTrack.any((s) => s != null) ||
        input.log.tips.keys.any((r) => parseSpecBranch(r) != null);
    return PreparedActivity._(
      input: input,
      commits: commits,
      spec: spec,
      specTrack: specTrack,
      merges: merges,
      cycles: cycles,
      origins: origins,
      markSince: since,
      hasSpecBranches: hasSpecBranches,
    );
  }

  /// The tags counted as releases: the semantic versions, or every tag
  /// when none is one.
  List<ActivityTag> get releaseTags {
    final tags = input.log.tags;
    final semver = [
      for (final t in tags)
        if (SemVer.tryParse(t.name) != null) t,
    ];
    return semver.isEmpty ? tags : semver;
  }

  ActivityReport report(ActivityPeriod period) {
    final now = input.now;
    final today = dayOf(now);
    final from = DateTime(today.year, today.month, today.day - period.days + 1);
    final prevFrom = DateTime(from.year, from.month, from.day - period.days);
    bool inPeriod(DateTime t) => !t.isBefore(from) && !t.isAfter(now);
    bool inPrev(DateTime t) => !t.isBefore(prevFrom) && t.isBefore(from);

    var commitsNow = 0, commitsPrev = 0;
    final dayCommits = <DateTime, int>{};
    final daySpecs = <DateTime, Set<String>>{};
    final weeks = <DateTime>[
      for (
        var w = weekOf(from);
        !w.isAfter(today);
        w = DateTime(w.year, w.month, w.day + 7)
      )
        w,
    ];
    final typeCounts = <DateTime, Map<String, int>>{};
    final groupTotals = <String, int>{};
    final files = <String, _FileAcc>{};
    final originWeeks = <DateTime, List<int>>{};
    var person = 0, agent = 0, app = 0, unmarked = 0;
    final models = <String, int>{};

    for (final (i, c) in commits.indexed) {
      if (c.isMerge) continue;
      if (inPrev(c.time)) commitsPrev++;
      if (!inPeriod(c.time)) continue;
      commitsNow++;
      final day = dayOf(c.time);
      final week = weekOf(c.time);
      dayCommits[day] = (dayCommits[day] ?? 0) + 1;
      final s = spec[i];
      if (s != null) daySpecs.putIfAbsent(day, () => {}).add(s.code);

      final g =
          classifyCommit(
            RawCommit(sha: c.sha, subject: c.subject),
            input.cliff,
          )?.$1 ??
          otherGroup;
      final wc = typeCounts.putIfAbsent(week, () => {});
      wc[g] = (wc[g] ?? 0) + 1;
      groupTotals[g] = (groupTotals[g] ?? 0) + 1;

      for (final f in c.files) {
        if (isIgnoredFile(f.path, input.ignored)) continue;
        final acc = files.putIfAbsent(f.path, () => _FileAcc(f.path));
        acc.commits++;
        acc.added += f.added ?? 0;
        acc.removed += f.removed ?? 0;
        acc.history.add(
          FileCommit(
            sha: c.sha,
            subject: c.subject,
            time: c.time,
            spec: s?.code,
          ),
        );
      }

      final o = origins[i];
      final ow = originWeeks.putIfAbsent(week, () => [0, 0, 0, 0]);
      switch (o.kind) {
        case CommitOriginKind.person:
          person++;
          ow[0]++;
        case CommitOriginKind.agent:
          agent++;
          ow[1]++;
          final m = o.model ?? '?';
          models[m] = (models[m] ?? 0) + 1;
        case CommitOriginKind.app:
          app++;
          ow[2]++;
        case CommitOriginKind.unmarked:
          unmarked++;
          ow[3]++;
      }
    }

    // Groups: the cliff order, at most [maxTypeGroups] named.
    final order = input.cliff.groupOrder;
    var named = [
      for (final g in order)
        if ((groupTotals[g] ?? 0) > 0) g,
    ];
    if (named.length > maxTypeGroups) {
      final keep =
          ([...named]
                ..sort((a, b) => groupTotals[b]!.compareTo(groupTotals[a]!)))
              .take(maxTypeGroups)
              .toSet();
      named = [
        for (final g in named)
          if (keep.contains(g)) g,
      ];
    }
    final namedSet = named.toSet();
    final typeWeeks = [
      for (final w in weeks)
        () {
          final counts = <String, int>{};
          for (final e in (typeCounts[w] ?? const <String, int>{}).entries) {
            final g = namedSet.contains(e.key) ? e.key : otherGroup;
            counts[g] = (counts[g] ?? 0) + e.value;
          }
          return TypeWeek(w, counts);
        }(),
    ];
    final hasOther = typeWeeks.any((w) => (w.counts[otherGroup] ?? 0) > 0);
    final typeGroups = [...named, if (hasOther) otherGroup];

    // Releases.
    final tags = releaseTags;
    final hasTags = tags.isNotEmpty;
    final releaseDays = <DateTime, List<String>>{};
    final inNow = [
      for (final t in tags)
        if (inPeriod(t.date)) t,
    ]..sort((a, b) => a.date.compareTo(b.date));
    for (final t in inNow) {
      releaseDays.putIfAbsent(dayOf(t.date), () => []).add(t.name);
    }
    final prevReleases = tags.where((t) => inPrev(t.date)).length;

    // Cycle.
    final cyclesNow = [
      for (final c in cycles.values)
        if (inPeriod(c.merged)) c,
    ];
    final cyclesPrev = [
      for (final c in cycles.values)
        if (inPrev(c.merged)) c,
    ];
    List<double> daysOf(List<SpecCycle> l) => [for (final c in l) ?c.days];
    final timed = [
      for (final c in cyclesNow)
        if (c.days != null) c,
    ]..sort((a, b) => b.days!.compareTo(a.days!));

    // Files.
    final top = files.values.toList()
      ..sort((a, b) {
        final byCommits = b.commits.compareTo(a.commits);
        return byCommits != 0 ? byCommits : a.path.compareTo(b.path);
      });

    return ActivityReport(
      period: period,
      from: from,
      to: now,
      summary: ActivitySummary(
        commits: commitsNow,
        prevCommits: commitsPrev,
        specsMerged: cyclesNow.length,
        prevSpecsMerged: cyclesPrev.length,
        releases: hasTags ? inNow.length : null,
        prevReleases: hasTags ? prevReleases : null,
        firstRelease: inNow.firstOrNull?.name,
        lastRelease: inNow.lastOrNull?.name,
        medianCycle: median(daysOf(cyclesNow)),
        prevMedianCycle: median(daysOf(cyclesPrev)),
      ),
      days: {
        for (final e in dayCommits.entries)
          e.key: DayCell(
            e.key,
            e.value,
            (daySpecs[e.key]?.toList() ?? <String>[])..sort(),
          ),
      },
      releaseDays: releaseDays,
      typeGroups: typeGroups,
      typeWeeks: typeWeeks,
      cycle: CycleStats(
        hasSpecBranches: hasSpecBranches,
        cycles: timed,
        median: median(daysOf(timed)),
        p90: percentile(daysOf(timed), 90),
      ),
      files: [for (final f in top.take(15)) f.build()],
      origins: OriginStats(
        weeks: [
          for (final w in weeks)
            () {
              final v = originWeeks[w] ?? const [0, 0, 0, 0];
              return OriginWeek(
                w,
                person: v[0],
                agent: v[1],
                app: v[2],
                unmarked: v[3],
              );
            }(),
        ],
        person: person,
        agent: agent,
        app: app,
        unmarked: unmarked,
        models: (models.entries.map((e) => (e.key, e.value)).toList()
          ..sort((a, b) {
            final byCount = b.$2.compareTo(a.$2);
            return byCount != 0 ? byCount : a.$1.compareTo(b.$1);
          })),
        since: markSince,
      ),
      hasTags: hasTags,
    );
  }
}

class _FileAcc {
  _FileAcc(this.path);

  final String path;
  int commits = 0, added = 0, removed = 0;
  final history = <FileCommit>[];

  FileStat build() {
    final specs = <String>[];
    for (final h in history) {
      if (h.spec != null && !specs.contains(h.spec)) specs.add(h.spec!);
    }
    return FileStat(
      path: path,
      commits: commits,
      added: added,
      removed: removed,
      specs: specs,
      history: history,
    );
  }
}

/// The reports of the three periods and every merged spec.
@immutable
class ActivityReports {
  const ActivityReports(this.byPeriod, this.cycles);

  final Map<ActivityPeriod, ActivityReport> byPeriod;

  /// Every merged spec of the history (the medians by sprint, R4).
  final List<SpecCycle> cycles;

  ActivityReport operator [](ActivityPeriod p) => byPeriod[p]!;
}

/// The reports of the three periods (run off the UI thread, R6).
ActivityReports buildActivityReports(ActivityInput input) {
  final p = PreparedActivity(input);
  return ActivityReports({
    for (final period in ActivityPeriod.values) period: p.report(period),
  }, p.cycles.values.toList());
}

/// A done sprint and the median cycle of its specs (R4).
@immutable
class SprintCycle {
  const SprintCycle(this.name, this.median, this.specs);

  final String name;
  final double median;

  /// Merged specs of the sprint with a cycle.
  final int specs;
}

/// A sprint as [sprintCycles] needs it (the database row stays out of the
/// pure code).
typedef SprintRef = ({int id, String name, int position, DateTime? closedAt});

/// The median cycle of every sprint done inside [from]..[to], in sprint
/// order (R4). [specSprint] maps a spec code to its sprint; the cycles come
/// from the whole history (a sprint is its own window).
List<SprintCycle> sprintCycles({
  required List<SprintRef> doneSprints,
  required Map<String, int> specSprint,
  required Iterable<SpecCycle> cycles,
  required DateTime from,
  required DateTime to,
}) {
  final sorted = [
    for (final s in doneSprints)
      if (s.closedAt != null &&
          !s.closedAt!.isBefore(from) &&
          !s.closedAt!.isAfter(to))
        s,
  ]..sort((a, b) => a.position.compareTo(b.position));
  final out = <SprintCycle>[];
  for (final s in sorted) {
    final days = [
      for (final c in cycles)
        if (specSprint[c.code] == s.id) ?c.days,
    ];
    final m = median(days);
    if (m != null) out.add(SprintCycle(s.name, m, days.length));
  }
  return out;
}
