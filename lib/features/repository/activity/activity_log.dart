import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/agent_trailer.dart' show agentTrailerKey;
import '../../../core/git/git_service.dart';
import '../graph/commit_log.dart' show ChangedFile, parseNumstat;
import '../graph/lane_layout.dart';

/// One commit read by the Atividade (SPEC-046 R6): `git log --numstat` of
/// the default branch and of the `spec/*` branches.
@immutable
class ActivityCommit implements LaneCommit {
  const ActivityCommit({
    required this.sha,
    required this.parents,
    required this.author,
    required this.time,
    required this.committed,
    required this.subject,
    this.trailers = '',
    this.files = const [],
    this.branches = const [],
  });

  @override
  final String sha;
  @override
  final List<String> parents;
  final String author;

  /// Author date: the day the work was done (the map, the cycle).
  final DateTime time;

  /// Committer date (the `since` of the marking, as in SPEC-048).
  final DateTime committed;
  @override
  final String subject;

  /// Values of the `Promptorium-Agente` trailer, separated by `\x1d`.
  final String trailers;

  /// Against the first parent; empty on a merge.
  final List<ChangedFile> files;

  /// Branches whose tip this commit is (filled by [ActivityLog.laneCommits]).
  @override
  final List<String> branches;

  bool get isMerge => parents.length > 1;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  ActivityCommit withBranches(List<String> b) => ActivityCommit(
    sha: sha,
    parents: parents,
    author: author,
    time: time,
    committed: committed,
    subject: subject,
    trailers: trailers,
    files: files,
    branches: b,
  );

  List<Object?> toJson() => [
    sha,
    parents.join(' '),
    author,
    time.millisecondsSinceEpoch ~/ 1000,
    committed.millisecondsSinceEpoch ~/ 1000,
    subject,
    trailers,
    [
      for (final f in files) [f.path, f.added, f.removed],
    ],
  ];

  static ActivityCommit fromJson(List<dynamic> j) => ActivityCommit(
    sha: j[0] as String,
    parents: [
      for (final p in (j[1] as String).split(' '))
        if (p.isNotEmpty) p,
    ],
    author: j[2] as String,
    time: DateTime.fromMillisecondsSinceEpoch((j[3] as int) * 1000),
    committed: DateTime.fromMillisecondsSinceEpoch((j[4] as int) * 1000),
    subject: j[5] as String,
    trailers: j[6] as String,
    files: [
      for (final f in j[7] as List<dynamic>)
        ChangedFile(f[0] as String, f[1] as int?, f[2] as int?),
    ],
  );
}

/// A tag and its date (the release days, R2).
@immutable
class ActivityTag {
  const ActivityTag(this.name, this.date);

  final String name;
  final DateTime date;
}

/// What the Atividade reads from git: the commits (topological order,
/// newest first), the tips they were read up to and the tags.
@immutable
class ActivityLog {
  const ActivityLog({
    required this.tips,
    required this.commits,
    this.tags = const [],
  });

  /// Ref → SHA of the branches read (`refs/heads/main`, `refs/remotes/
  /// origin/spec/042-sprints`…): the key of the cache.
  final Map<String, String> tips;
  final List<ActivityCommit> commits;
  final List<ActivityTag> tags;

  /// The commits with the short names of the branches on their tips, for
  /// [layoutLanes].
  List<ActivityCommit> laneCommits() {
    final byTip = <String, List<String>>{};
    for (final e in tips.entries) {
      final name = e.key.startsWith('refs/heads/')
          ? e.key.substring(11)
          : e.key.startsWith('refs/remotes/')
          ? e.key.substring(13)
          : e.key;
      byTip.putIfAbsent(e.value, () => []).add(name);
    }
    for (final names in byTip.values) {
      // Locals first, as the Grafo gives them.
      names.sort((a, b) {
        final ra = tips.containsKey('refs/heads/$a') ? 0 : 1;
        final rb = tips.containsKey('refs/heads/$b') ? 0 : 1;
        return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
      });
    }
    return [
      for (final c in commits)
        byTip[c.sha] == null ? c : c.withBranches(byTip[c.sha]!),
    ];
  }

  String encode() => jsonEncode({
    'versao': ActivityLogReader.cacheVersion,
    'pontas': tips,
    'commits': [for (final c in commits) c.toJson()],
  });

  /// Null when [text] is not a cache of this version.
  static ActivityLog? decode(String text) {
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['versao'] != ActivityLogReader.cacheVersion) return null;
      return ActivityLog(
        tips: (j['pontas'] as Map<String, dynamic>).cast<String, String>(),
        commits: [
          for (final c in j['commits'] as List<dynamic>)
            ActivityCommit.fromJson(c as List<dynamic>),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// How a [ActivityLogReader.load] went (the tests check R6 with it).
@immutable
class ActivityLoad {
  const ActivityLoad(this.log, {required this.read, required this.full});

  final ActivityLog log;

  /// Commits read from git this time (0 = all from the cache).
  final int read;

  /// The whole history was read (no cache, or a branch was rewritten).
  final bool full;
}

/// `%H %P %an %at %ct %s trailers`, then the `--numstat` lines.
const _format =
    '--format=%x1e%H%x1f%P%x1f%an%x1f%at%x1f%ct%x1f%s%x1f'
    '%(trailers:key=$agentTrailerKey,valueonly,separator=%x1d)%x1f';

/// Commits of `git log --numstat` with [_format].
List<ActivityCommit> parseActivityLog(String out) {
  final commits = <ActivityCommit>[];
  for (final rec in out.split('\x1e')) {
    if (rec.trim().isEmpty) continue;
    final f = rec.split('\x1f');
    if (f.length < 8) continue;
    DateTime at(String s) =>
        DateTime.fromMillisecondsSinceEpoch((int.tryParse(s) ?? 0) * 1000);
    commits.add(
      ActivityCommit(
        sha: f[0].trim(),
        parents: [
          for (final p in f[1].split(' '))
            if (p.isNotEmpty) p,
        ],
        author: f[2],
        time: at(f[3]),
        committed: at(f[4]),
        subject: f[5],
        trailers: f[6].trim(),
        files: parseNumstat(f.sublist(7).join('\x1f')),
      ),
    );
  }
  return commits;
}

/// Reads [ActivityLog] of a repository (SPEC-046 R6): the default branch
/// and the `spec/*` branches, local and remote. The result is kept in a
/// file by repository, with the tips it was read up to; the next load
/// reads only the commits after them (`git log <tips> --not <old tips>`),
/// and nothing when no tip moved. A rewritten branch (old commits no longer
/// reachable) reads everything again.
class ActivityLogReader {
  ActivityLogReader(
    this.git, {
    required this.defaultBranch,
    this.remote,
    this.cacheDir,
    this.useIsolate = true,
  });

  /// Bump when the format of the cache changes.
  static const cacheVersion = 1;

  final GitService git;
  final String defaultBranch;
  final String? remote;

  /// Folder of the cache files (null = memory only).
  final String? cacheDir;

  /// Decodes and writes the cache in another isolate (the tests may not).
  final bool useIsolate;

  /// Last log read per repository, so reopening the tab skips the file.
  static final _memory = <String, ActivityLog>{};

  @visibleForTesting
  static void clearMemory() => _memory.clear();

  String get _key => '${git.repoRoot}\x00$defaultBranch';

  /// File of the cache: `<name>-<hash of the path>.json`.
  String? get cacheFile {
    final dir = cacheDir;
    if (dir == null) return null;
    var h = 0x811c9dc5;
    for (final u in utf8.encode(_key)) {
      h = ((h ^ u) * 0x01000193) & 0xffffffff;
    }
    final name = git.repoName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$dir/$name-${h.toRadixString(16).padLeft(8, '0')}.json';
  }

  /// The branches read and their tips.
  Future<Map<String, String>> readTips() async {
    final patterns = [
      'refs/heads/$defaultBranch',
      'refs/heads/spec',
      if (remote != null) ...[
        'refs/remotes/$remote/$defaultBranch',
        'refs/remotes/$remote/spec',
      ],
    ];
    final out = await git.git([
      'for-each-ref',
      '--format=%(refname)%1f%(objectname)',
      ...patterns,
    ]);
    return {
      for (final line in out.split('\n'))
        if (line.split('\x1f') case [final r, final sha] when sha.isNotEmpty)
          r.trim(): sha.trim(),
    };
  }

  /// Tags and their dates (an annotated tag's date, or its commit's).
  Future<List<ActivityTag>> readTags() async {
    try {
      final out = await git.git([
        'for-each-ref',
        '--format=%(refname:short)%1f%(creatordate:unix)',
        'refs/tags',
      ]);
      return [
        for (final line in out.split('\n'))
          if (line.split('\x1f') case [final n, final t]
              when int.tryParse(t.trim()) != null)
            ActivityTag(
              n.trim(),
              DateTime.fromMillisecondsSinceEpoch(int.parse(t.trim()) * 1000),
            ),
      ];
    } on GitException {
      return const [];
    }
  }

  Future<String?> _readFile() async {
    final path = cacheFile;
    if (path == null) return null;
    final f = File(path);
    return await f.exists() ? f.readAsString() : null;
  }

  Future<ActivityLog?> _fromCache() async {
    final mem = _memory[_key];
    if (mem != null) return mem;
    final path = cacheFile;
    if (path == null) return null;
    try {
      if (useIsolate) {
        return await Isolate.run(() {
          final f = File(path);
          return f.existsSync()
              ? ActivityLog.decode(f.readAsStringSync())
              : null;
        });
      }
      final text = await _readFile();
      return text == null ? null : ActivityLog.decode(text);
    } catch (e) {
      debugPrint('Atividade: cache ilegível — $e');
      return null;
    }
  }

  Future<void> _save(ActivityLog log) async {
    _memory[_key] = log;
    final path = cacheFile;
    if (path == null) return;
    Future<void> write() async {
      final f = File(path);
      await f.parent.create(recursive: true);
      final tmp = File('$path.tmp');
      await tmp.writeAsString(log.encode(), flush: true);
      await tmp.rename(path);
    }

    try {
      if (useIsolate) {
        final noTags = ActivityLog(tips: log.tips, commits: log.commits);
        await Isolate.run(() async {
          final f = File(path);
          await f.parent.create(recursive: true);
          final tmp = File('$path.tmp');
          await tmp.writeAsString(noTags.encode(), flush: true);
          await tmp.rename(path);
        });
      } else {
        await write();
      }
    } catch (e) {
      debugPrint('Atividade: cache não gravado — $e');
    }
  }

  Future<List<ActivityCommit>> _log(
    Iterable<String> revs, {
    Iterable<String> not = const [],
  }) async {
    if (revs.isEmpty) return const [];
    final out = await git.git([
      'log',
      '--topo-order',
      '--numstat',
      _format,
      ...revs,
      if (not.isNotEmpty) ...['--not', ...not],
      '--',
    ]);
    return parseActivityLog(out);
  }

  /// Whether every commit of [old] is still reachable from [now].
  Future<bool> _stillReachable(
    Iterable<String> old,
    Iterable<String> now,
  ) async {
    if (old.isEmpty) return true;
    if (now.isEmpty) return false;
    try {
      final n = await git.git([
        'rev-list',
        '--count',
        ...old,
        '--not',
        ...now,
        '--',
      ]);
      return (int.tryParse(n.trim()) ?? 1) == 0;
    } on GitException {
      // An old tip no longer exists (gc'd after a rewrite).
      return false;
    }
  }

  Future<ActivityLoad> load() async {
    final tips = await readTips();
    final tags = await readTags();
    final cached = await _fromCache();
    final now = tips.values.toSet();
    if (cached != null && mapEquals(cached.tips, tips)) {
      _memory[_key] = cached;
      return ActivityLoad(
        ActivityLog(tips: tips, commits: cached.commits, tags: tags),
        read: 0,
        full: false,
      );
    }
    final old = cached?.tips.values.toSet() ?? const <String>{};
    if (cached != null && await _stillReachable(old, now)) {
      final added = await _log(now.difference(old), not: old);
      final log = ActivityLog(
        tips: tips,
        commits: [...added, ...cached.commits],
        tags: tags,
      );
      await _save(log);
      return ActivityLoad(log, read: added.length, full: false);
    }
    final all = await _log(now);
    final log = ActivityLog(tips: tips, commits: all, tags: tags);
    await _save(log);
    return ActivityLoad(log, read: all.length, full: true);
  }
}

/// Folder of the Atividade caches (`~/.promptorium/atividade`); null in the
/// tests (memory only), which override it with a temporary folder.
final activityCacheDirProvider = Provider<String?>((ref) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return '$home/.promptorium/atividade';
});
