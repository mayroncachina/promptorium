import 'package:flutter/foundation.dart';

import '../../../core/git/git_service.dart';
import 'lane_layout.dart';
import 'spec_branch.dart';

enum RefKind { head, local, remote, tag }

/// A ref decorating a commit (`%D`): `main`, `origin/main`, `v0.11.0`.
@immutable
class CommitRef {
  const CommitRef(this.kind, this.name);

  final RefKind kind;

  /// Short name (`main`, `origin/main`, `v0.11.0`; `HEAD` when detached).
  final String name;

  /// `main` of `origin/main` (the name itself for the other kinds).
  String get branchName {
    if (kind != RefKind.remote) return name;
    final slash = name.indexOf('/');
    return slash < 0 ? name : name.substring(slash + 1);
  }

  @override
  bool operator ==(Object other) =>
      other is CommitRef && other.kind == kind && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);

  @override
  String toString() => name;
}

/// One commit of the log (SPEC-045 R1).
@immutable
class CommitRow implements LaneCommit {
  const CommitRow({
    required this.sha,
    required this.parents,
    required this.author,
    required this.time,
    required this.subject,
    this.refs = const [],
  });

  @override
  final String sha;
  @override
  final List<String> parents;
  final String author;

  /// Author date.
  final DateTime time;
  @override
  final String subject;
  final List<CommitRef> refs;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  bool get isMerge => parents.length > 1;

  @override
  List<String> get branches => [
    for (final r in refs)
      if (r.kind == RefKind.local) r.name,
    for (final r in refs)
      if (r.kind == RefKind.remote) r.name,
  ];

  List<String> get tags => [
    for (final r in refs)
      if (r.kind == RefKind.tag) r.name,
  ];

  /// HEAD points here (the branch checked out, or detached).
  bool get isHead => refs.any((r) => r.kind == RefKind.head);

  /// Branch labels (R4): the local ones, and a remote one only when its
  /// local copy is not on this commit.
  List<CommitRef> get branchLabels {
    final locals = {
      for (final r in refs)
        if (r.kind == RefKind.local) r.name,
    };
    return [
      for (final r in refs)
        if (r.kind == RefKind.local ||
            (r.kind == RefKind.remote && !locals.contains(r.branchName)))
          r,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is CommitRow &&
      other.sha == sha &&
      other.subject == subject &&
      listEquals(other.refs, refs) &&
      listEquals(other.parents, parents);

  @override
  int get hashCode => Object.hash(sha, subject, Object.hashAll(refs));
}

/// What the tab shows (R6).
enum GraphScope {
  /// Every branch and tag (the default).
  all,

  /// Only the default branch, one commit per merge (`--first-parent`).
  defaultBranch,

  /// The default branch and the `spec/*` branches not merged into it.
  openSpecs,
}

/// Which commits to read (R6).
@immutable
class GraphQuery {
  const GraphQuery({
    this.scope = GraphScope.all,
    this.remoteOnly = false,
    this.day,
  });

  final GraphScope scope;

  /// Also the remote branches without a local copy.
  final bool remoteOnly;

  /// Only the commits of this (local) day: the Atividade of SPEC-046 opens
  /// the Grafo on a day. Null = every day.
  final DateTime? day;

  GraphQuery copyWith({
    GraphScope? scope,
    bool? remoteOnly,
    DateTime? Function()? day,
  }) => GraphQuery(
    scope: scope ?? this.scope,
    remoteOnly: remoteOnly ?? this.remoteOnly,
    day: day == null ? this.day : day(),
  );

  @override
  bool operator ==(Object other) =>
      other is GraphQuery &&
      other.scope == scope &&
      other.remoteOnly == remoteOnly &&
      other.day == day;

  @override
  int get hashCode => Object.hash(scope, remoteOnly, day);
}

/// The refs of the repository, read once per load.
@immutable
class RepoRefs {
  const RepoRefs({
    this.locals = const [],
    this.remotes = const [],
    this.tags = const [],
    this.unmergedSpecs = const [],
  });

  /// `main`, `spec/042-sprints`…
  final List<String> locals;

  /// `origin/main`… (`origin/HEAD` left out).
  final List<String> remotes;
  final List<String> tags;

  /// Local and remote `spec/*` branches not merged into the default one.
  final List<String> unmergedSpecs;

  /// `origin/x` → `x`.
  static String stripRemote(String remote) {
    final slash = remote.indexOf('/');
    return slash < 0 ? remote : remote.substring(slash + 1);
  }

  /// Remote branches without a local copy.
  List<String> get remoteOnly {
    final l = locals.toSet();
    return [
      for (final r in remotes)
        if (!l.contains(stripRemote(r))) r,
    ];
  }

  /// Numbers of the specs with a branch not merged yet (R3: open specs
  /// start expanded, the others collapsed).
  Set<int> get openSpecNumbers => {
    for (final b in unmergedSpecs) ?parseSpecBranch(b)?.number,
  };
}

/// A page of the log.
typedef CommitPage = ({List<CommitRow> rows, bool more});

/// Reads the log for the Grafo tab (SPEC-045 R1, R6, R7): pages of
/// [pageSize] commits in topological order, read with `git log --skip`.
class CommitLog {
  CommitLog(this.git, {required this.defaultBranch, this.remote});

  static const pageSize = 300;

  final GitService git;
  final String defaultBranch;
  final String? remote;

  static const _fields = '%H%x00%P%x00%an%x00%at%x00%D%x00%s';

  Future<RepoRefs> refs() async {
    final out = await git.git([
      'for-each-ref',
      '--format=%(refname)',
      'refs/heads',
      'refs/remotes',
      'refs/tags',
    ]);
    final locals = <String>[], remotes = <String>[], tags = <String>[];
    for (final line in out.split('\n')) {
      final r = line.trim();
      if (r.startsWith('refs/heads/')) {
        locals.add(r.substring('refs/heads/'.length));
      } else if (r.startsWith('refs/remotes/')) {
        if (!r.endsWith('/HEAD')) remotes.add(r.substring(13));
      } else if (r.startsWith('refs/tags/')) {
        tags.add(r.substring('refs/tags/'.length));
      }
    }
    // Merged = reachable from the default branch, local or remote (a local
    // copy left behind does not make the merged specs open again).
    final bases = <String>{
      if (locals.contains(defaultBranch)) defaultBranch,
      ?_remoteBase(remotes),
    };
    List<String>? unmerged;
    for (final base in bases) {
      try {
        final no = await git.git([
          'for-each-ref',
          '--format=%(refname)',
          '--no-merged=$base',
          'refs/heads/spec',
          'refs/remotes',
        ]);
        final names = [
          for (final line in no.split('\n'))
            if (line.trim() case final r when r.isNotEmpty)
              if (r.startsWith('refs/heads/'))
                r.substring('refs/heads/'.length)
              else if (parseSpecBranch(r.substring(13)) != null &&
                  !r.endsWith('/HEAD'))
                r.substring(13),
        ];
        unmerged = unmerged == null
            ? names
            : [
                for (final n in unmerged)
                  if (names.contains(n)) n,
              ];
      } on GitException {
        continue;
      }
    }
    return RepoRefs(
      locals: locals,
      remotes: remotes,
      tags: tags,
      unmergedSpecs: unmerged ?? const [],
    );
  }

  /// The default branch: the local one, or its remote copy.
  String? _baseRef(List<String> locals, List<String> remotes) {
    if (locals.contains(defaultBranch)) return defaultBranch;
    return _remoteBase(remotes);
  }

  /// The remote copy of the default branch (`origin/main`).
  String? _remoteBase(List<String> remotes) {
    final r = remote == null ? null : '$remote/$defaultBranch';
    if (r != null && remotes.contains(r)) return r;
    return remotes
        .where((x) => RepoRefs.stripRemote(x) == defaultBranch)
        .firstOrNull;
  }

  /// The revisions `git log` walks for [q] (R6). Stashes and
  /// `refs/promptorium/*` never enter.
  List<String> revisions(GraphQuery q, RepoRefs refs) {
    final base = _baseRef(refs.locals, refs.remotes);
    final localSet = refs.locals.toSet();
    bool remoteWanted(String r) =>
        q.remoteOnly || localSet.contains(RepoRefs.stripRemote(r));
    final List<String> revs;
    switch (q.scope) {
      case GraphScope.all:
        revs = [
          for (final l in refs.locals) 'refs/heads/$l',
          for (final r in refs.remotes)
            if (remoteWanted(r)) 'refs/remotes/$r',
          for (final t in refs.tags) 'refs/tags/$t',
          'HEAD',
        ];
      case GraphScope.defaultBranch:
        revs = [base ?? 'HEAD'];
      case GraphScope.openSpecs:
        final open = {
          for (final b in refs.unmergedSpecs)
            if (localSet.contains(b)) b,
        };
        revs = [
          base ?? 'HEAD',
          for (final b in refs.unmergedSpecs)
            if (localSet.contains(b))
              'refs/heads/$b'
            else if (open.contains(RepoRefs.stripRemote(b)) || q.remoteOnly)
              'refs/remotes/$b',
        ];
    }
    return revs;
  }

  List<String> _logArgs(GraphQuery q, List<String> revs) {
    final day = q.day;
    final start = day == null ? null : DateTime(day.year, day.month, day.day);
    return [
      if (q.scope == GraphScope.defaultBranch) '--first-parent',
      if (start != null) ...[
        '--since=${start.millisecondsSinceEpoch ~/ 1000}',
        '--until=${DateTime(start.year, start.month, start.day + 1).millisecondsSinceEpoch ~/ 1000 - 1}',
      ],
      ...revs,
    ];
  }

  /// Commits [skip]..[skip] + [limit] of [revs] (from [revisions]).
  Future<CommitPage> page(
    GraphQuery q,
    List<String> revs, {
    int skip = 0,
    int limit = pageSize,
  }) async {
    final out = await git.git([
      'log',
      '--topo-order',
      '--decorate=full',
      '--decorate-refs=refs/heads',
      '--decorate-refs=refs/remotes',
      '--decorate-refs=refs/tags',
      '--decorate-refs=HEAD',
      '--format=%x1e$_fields',
      '--skip=$skip',
      '-n',
      '${limit + 1}',
      ..._logArgs(q, revs),
      '--',
    ]);
    final rows = parseCommitLog(out);
    final more = rows.length > limit;
    return (rows: more ? rows.sublist(0, limit) : rows, more: more);
  }

  /// How many commits [revs] has (`300 de 1.284 commits`).
  Future<int> count(GraphQuery q, List<String> revs) async {
    final out = await git.git([
      'rev-list',
      '--count',
      ..._logArgs(q, revs),
      '--',
    ]);
    return int.tryParse(out.trim()) ?? 0;
  }
}

/// A file changed by a commit (`--numstat`); null counts = binary.
@immutable
class ChangedFile {
  const ChangedFile(this.path, this.added, this.removed);

  final String path;
  final int? added;
  final int? removed;
}

/// What the commit panel shows (SPEC-045 R5).
@immutable
class CommitDetails {
  const CommitDetails({
    required this.message,
    required this.files,
    this.branches = const [],
    this.tags = const [],
  });

  /// The whole message.
  final String message;

  /// Against the first parent (a merge shows what it brought in).
  final List<ChangedFile> files;

  /// Branches (local and remote) and tags that contain the commit.
  final List<String> branches;
  final List<String> tags;

  /// The lines after the subject.
  String get body {
    final i = message.indexOf('\n');
    return i < 0 ? '' : message.substring(i + 1).trim();
  }

  int get added => files.fold(0, (n, f) => n + (f.added ?? 0));
  int get removed => files.fold(0, (n, f) => n + (f.removed ?? 0));
}

/// `12\t3\tpath` lines of `--numstat -z`-less output; renames keep the new
/// path (`a => b`, `dir/{a => b}/x`).
List<ChangedFile> parseNumstat(String out) => [
  for (final line in out.split('\n'))
    if (line.split('\t') case [final a, final r, ...final rest]
        when rest.isNotEmpty)
      ChangedFile(_renamed(rest.join('\t')), int.tryParse(a), int.tryParse(r)),
];

String _renamed(String p) {
  final brace = RegExp(r'\{([^{}]*) => ([^{}]*)\}').firstMatch(p);
  if (brace != null) {
    return p
        .replaceRange(brace.start, brace.end, brace.group(2)!)
        .replaceAll('//', '/');
  }
  final arrow = p.indexOf(' => ');
  return arrow < 0 ? p : p.substring(arrow + 4);
}

extension CommitDetailsReader on CommitLog {
  /// The panel of [c] (R5): message, files with +/− and what contains it.
  Future<CommitDetails> details(CommitRow c) async {
    final message = await git.git(['show', '-s', '--format=%B', c.sha]);
    final numstat = c.parents.isEmpty
        ? await git.git(['show', '--numstat', '--format=', c.sha])
        : await git.git(['diff', '--numstat', c.parents.first, c.sha]);
    final branches = await git.git([
      'branch',
      '-a',
      '--contains',
      c.sha,
      '--format=%(refname)',
    ]);
    final tags = await git.git(['tag', '--contains', c.sha]);
    List<String> lines(String s) => [
      for (final l in s.split('\n'))
        if (l.trim().isNotEmpty && !l.trim().endsWith('/HEAD')) l.trim(),
    ];
    return CommitDetails(
      message: message.trim(),
      files: parseNumstat(numstat),
      branches: [
        for (final r in lines(branches))
          r.startsWith('refs/heads/')
              ? r.substring(11)
              : r.startsWith('refs/remotes/')
              ? r.substring(13)
              : r,
      ],
      tags: lines(tags),
    );
  }

  /// Unified diff of [path] in [c] (against its first parent).
  Future<String> fileDiff(CommitRow c, String path) => c.parents.isEmpty
      ? git.git(['show', '--format=', c.sha, '--', path])
      : git.git(['diff', c.parents.first, c.sha, '--', path]);
}

/// The refs of `%D` with `--decorate=full`: `HEAD -> refs/heads/main,
/// tag: refs/tags/v1, refs/remotes/origin/main`. Other refs (stash,
/// `refs/promptorium/*`, `origin/HEAD`) are left out.
List<CommitRef> parseDecorations(String d) {
  final out = <CommitRef>[];
  for (var part in d.split(', ')) {
    part = part.trim();
    if (part.isEmpty) continue;
    if (part == 'HEAD') {
      out.add(const CommitRef(RefKind.head, 'HEAD'));
      continue;
    }
    if (part.startsWith('HEAD -> ')) {
      out.add(const CommitRef(RefKind.head, 'HEAD'));
      part = part.substring('HEAD -> '.length);
    }
    if (part.startsWith('tag: ')) part = part.substring(5);
    if (part.startsWith('refs/heads/')) {
      out.add(CommitRef(RefKind.local, part.substring(11)));
    } else if (part.startsWith('refs/remotes/')) {
      if (!part.endsWith('/HEAD')) {
        out.add(CommitRef(RefKind.remote, part.substring(13)));
      }
    } else if (part.startsWith('refs/tags/')) {
      out.add(CommitRef(RefKind.tag, part.substring(10)));
    }
  }
  return out;
}

/// Rows of `git log --format=%x1e%H%x00%P%x00%an%x00%at%x00%D%x00%s`.
List<CommitRow> parseCommitLog(String out) {
  final rows = <CommitRow>[];
  for (final record in out.split('\x1e')) {
    final r = record.endsWith('\n')
        ? record.substring(0, record.length - 1)
        : record;
    if (r.trim().isEmpty) continue;
    final f = r.split('\x00');
    if (f.length < 6) continue;
    rows.add(
      CommitRow(
        sha: f[0],
        parents: [
          for (final p in f[1].split(' '))
            if (p.isNotEmpty) p,
        ],
        author: f[2],
        time: DateTime.fromMillisecondsSinceEpoch(
          (int.tryParse(f[3]) ?? 0) * 1000,
        ),
        refs: parseDecorations(f[4]),
        subject: f.sublist(5).join(' ').trimRight(),
      ),
    );
  }
  return rows;
}
