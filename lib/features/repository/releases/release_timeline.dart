import 'package:flutter/foundation.dart';

import '../../../core/git/gh_cli.dart';
import '../../../core/git/git_service.dart';
import '../../../core/update/changelog_section.dart';
import 'semver.dart';

/// State of a version in the timeline (SPEC-044 R2).
enum ReleaseState {
  published('Publicada'),
  draft('Rascunho'),
  prerelease('Pré-release'),
  tagOnly('Só tag');

  const ReleaseState(this.label);

  final String label;
}

/// A version tag of the local repository.
@immutable
class LocalTag {
  const LocalTag(this.name, {this.date});

  final String name;

  /// `creatordate` of the tag.
  final DateTime? date;
}

/// One version of the timeline: a local tag, a release on GitHub, or both.
@immutable
class ReleaseEntry {
  const ReleaseEntry({
    required this.tag,
    required this.version,
    required this.state,
    this.date,
    this.isLatest = false,
    this.hasLocalTag = false,
    this.commits,
    this.previousTag,
    this.assets = const [],
    this.notes = '',
    this.url,
  });

  final String tag;
  final SemVer version;
  final ReleaseState state;

  /// Publication date (the release's, else the tag's).
  final DateTime? date;

  /// "mais recente" on GitHub.
  final bool isLatest;
  final bool hasLocalTag;

  /// Commits since [previousTag]; null when the tag is not local.
  final int? commits;

  /// The older version the [commits] count from.
  final String? previousTag;
  final List<GhAsset> assets;

  /// Notes of the release (Markdown), empty for a tag alone.
  final String notes;

  /// The release on GitHub.
  final String? url;

  /// The notes as the screen shows them: git-cliff's groups when the text
  /// follows its format (SPEC-038), else the whole text.
  ChangelogSection get section => latestChanges(notes, version: tag);

  ReleaseEntry withCommits(int? n, String? previous) => ReleaseEntry(
    tag: tag,
    version: version,
    state: state,
    date: date,
    isLatest: isLatest,
    hasLocalTag: hasLocalTag,
    commits: n,
    previousTag: previous,
    assets: assets,
    notes: notes,
    url: url,
  );
}

ReleaseState _stateOf(GhRelease r) => r.isDraft
    ? ReleaseState.draft
    : r.isPrerelease
    ? ReleaseState.prerelease
    : ReleaseState.published;

/// Joins [tags] and [releases] by tag name, keeps only what looks like a
/// version and sorts from the newest version to the oldest (R2). The commit
/// counts come later ([commitRanges], [ReleaseEntry.withCommits]).
List<ReleaseEntry> mergeTimeline({
  required List<LocalTag> tags,
  required List<GhRelease> releases,
}) {
  final local = {
    for (final t in tags)
      if (isVersionTag(t.name)) t.name: t,
  };
  final remote = {
    for (final r in releases)
      if (isVersionTag(r.tagName)) r.tagName: r,
  };
  final entries = [
    for (final name in {...local.keys, ...remote.keys})
      () {
        final r = remote[name];
        final t = local[name];
        return ReleaseEntry(
          tag: name,
          version: SemVer.tryParse(name)!,
          state: r == null ? ReleaseState.tagOnly : _stateOf(r),
          date: r?.publishedAt ?? r?.createdAt ?? t?.date,
          isLatest: r?.isLatest ?? false,
          hasLocalTag: t != null,
          assets: r?.assets ?? const [],
          notes: r?.body ?? '',
          url: r?.url,
        );
      }(),
  ];
  entries.sort((a, b) {
    final v = b.version.compareTo(a.version);
    if (v != 0) return v;
    return (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970));
  });
  return entries;
}

/// For each entry with a local tag, the older local tag its commits count
/// from (null = from the first commit): `(tag, previous)`.
List<(String, String?)> commitRanges(List<ReleaseEntry> entries) {
  final local = [
    for (final e in entries)
      if (e.hasLocalTag) e.tag,
  ];
  return [
    for (var i = 0; i < local.length; i++)
      (local[i], i + 1 < local.length ? local[i + 1] : null),
  ];
}

/// The version tags of the repository, newest first
/// (`git tag --sort=-creatordate`).
Future<List<LocalTag>> readLocalTags(GitService git) async {
  final out = await git.git([
    'tag',
    '--sort=-creatordate',
    '--format=%(refname:short)%09%(creatordate:iso-strict)',
  ]);
  return [
    for (final line in out.split('\n'))
      if (line.trim().isNotEmpty)
        () {
          final parts = line.split('\t');
          return LocalTag(
            parts.first.trim(),
            date: parts.length > 1 ? DateTime.tryParse(parts[1].trim()) : null,
          );
        }(),
  ].where((t) => isVersionTag(t.name)).toList();
}

/// The timeline with the commit count of each version that has a local tag
/// (`git rev-list --count previous..tag`).
Future<List<ReleaseEntry>> loadTimeline(
  GitService git, {
  required List<LocalTag> tags,
  required List<GhRelease> releases,
}) async {
  final entries = mergeTimeline(tags: tags, releases: releases);
  final counts = <String, (int?, String?)>{};
  for (final (tag, previous) in commitRanges(entries)) {
    try {
      final n = await git.git([
        'rev-list',
        '--count',
        previous == null ? tag : '$previous..$tag',
      ]);
      counts[tag] = (int.tryParse(n.trim()), previous);
    } on GitException {
      counts[tag] = (null, previous);
    }
  }
  return [
    for (final e in entries)
      if (counts[e.tag] case (final n, final prev)?)
        e.withCommits(n, prev)
      else
        e,
  ];
}
