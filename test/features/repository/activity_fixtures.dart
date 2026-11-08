import 'package:promptorium/features/repository/activity/activity_log.dart';
import 'package:promptorium/features/repository/activity/activity_stats.dart';
import 'package:promptorium/features/repository/graph/commit_log.dart'
    show ChangedFile;
import 'package:promptorium/features/repository/releases/unreleased.dart';

/// Fixed clock of the Atividade tests: a Sunday at noon.
final activityNow = DateTime(2026, 11, 8, 12);

DateTime daysAgo(num n, {DateTime? from}) =>
    (from ?? activityNow).subtract(Duration(minutes: (n * 24 * 60).round()));

ActivityCommit ac(
  String sha,
  List<String> parents,
  num ago,
  String subject, {
  List<ChangedFile> files = const [],
  String trailers = '',
}) => ActivityCommit(
  sha: sha,
  parents: parents,
  author: 'Teste',
  time: daysAgo(ago),
  committed: daysAgo(ago),
  subject: subject,
  trailers: trailers,
  files: files,
);

/// main ─ SPEC-042 (mother, plus the daughter t1 that started first) merged
/// 5 days ago ─ SPEC-043 merged 2 days ago ─ a docs commit of SPEC-044 on
/// main yesterday. Topological order, newest first.
///
/// SPEC-042: first commit (t1) 12 days ago → 7 days of cycle.
/// SPEC-043: first commit 4 days ago → 2 days.
List<ActivityCommit> specHistory() => [
  ac('d', ['m2'], 1, 'docs: SPEC-044, atividade'),
  ac(
    'm2',
    ['m1', 's43b'],
    2,
    'Merge pull request #96 from o/spec/043-conflito',
  ),
  ac(
    's43b',
    ['s43a'],
    3,
    'fix(repo): conflito',
    files: const [ChangedFile('lib/a.dart', 5, 1)],
  ),
  ac('s43a', ['m1'], 4, 'docs: SPEC-043, conflito'),
  ac('m1', ['b', 's42m'], 5, 'Merge pull request #94 from o/spec/042-sprints'),
  ac(
    's42m',
    ['s42a', 't1'],
    9,
    'Merge pull request #95 from o/spec/042-t1-dados',
  ),
  ac(
    't1',
    ['b'],
    12,
    'feat(sprints): dados',
    files: const [
      ChangedFile('lib/a.dart', 10, 2),
      ChangedFile('lib/a.g.dart', 400, 300),
      ChangedFile('pubspec.lock', 30, 3),
    ],
  ),
  ac('s42a', ['b'], 10, 'docs: SPEC-042, sprints'),
  ac('b', [], 100, 'inicial'),
];

ActivityLog logOf(
  List<ActivityCommit> commits, {
  Map<String, String>? tips,
  List<ActivityTag> tags = const [],
}) => ActivityLog(
  tips: tips ?? {'refs/heads/main': commits.first.sha},
  commits: commits,
  tags: tags,
);

ActivityReports reportsOf(ActivityLog log, {CliffRules? cliff}) =>
    buildActivityReports(
      ActivityInput(
        log: log,
        defaultBranch: 'main',
        now: activityNow,
        cliff: cliff ?? CliffRules.promptorium,
      ),
    );
