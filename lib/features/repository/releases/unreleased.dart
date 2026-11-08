import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/git/gh_cli.dart' show CliRunner;
import '../../../core/git/git_service.dart';
import 'semver.dart';

/// A commit parser of `cliff.toml` (`{ message = "^feat", group = "…" }`).
@immutable
class CommitParser {
  const CommitParser(this.message, {this.group, this.skip = false});

  final RegExp message;
  final String? group;
  final bool skip;
}

/// A `commit_preprocessors` entry: [pattern] replaced by [replace] (`$1`).
@immutable
class CommitPreprocessor {
  const CommitPreprocessor(this.pattern, this.replace);

  final RegExp pattern;
  final String replace;

  String apply(String message) => message.replaceAllMapped(
    pattern,
    (m) => replace.replaceAllMapped(
      RegExp(r'\$\{?(\d+)\}?'),
      (g) => m.group(int.parse(g.group(1)!)) ?? '',
    ),
  );
}

/// How the commits become groups (SPEC-044 R3): the rules of the
/// project's `cliff.toml` or, without it, the groups of the Promptorium.
@immutable
class CliffRules {
  const CliffRules({
    this.preprocessors = const [],
    this.parsers = const [],
    this.filterUnconventional = true,
    this.featuresAlwaysBumpMinor = true,
    this.breakingAlwaysBumpMajor = true,
    this.fromFile = false,
  });

  final List<CommitPreprocessor> preprocessors;
  final List<CommitParser> parsers;
  final bool filterUnconventional;

  /// `[bump]` of git-cliff (both default to true there).
  final bool featuresAlwaysBumpMinor;
  final bool breakingAlwaysBumpMajor;

  /// Read from the project's `cliff.toml`.
  final bool fromFile;

  /// Group titles in the order of the parsers.
  List<String> get groupOrder => {
    for (final p in parsers)
      if (p.group != null) p.group!,
  }.toList();

  /// The groups of the Promptorium's `cliff.toml`, for projects without one.
  static final promptorium = CliffRules(
    parsers: [
      CommitParser(RegExp(r'^chore\(release\)'), skip: true),
      CommitParser(RegExp('^feat'), group: 'Funcionalidades'),
      CommitParser(RegExp('^fix'), group: 'Correções'),
      CommitParser(RegExp('^perf'), group: 'Desempenho'),
      CommitParser(RegExp('^refactor'), group: 'Refatoração'),
      CommitParser(RegExp('^docs?'), group: 'Documentação'),
      CommitParser(RegExp('^test'), group: 'Testes'),
      CommitParser(RegExp('^(build|ci)'), group: 'Build e CI'),
      CommitParser(RegExp('^(chore|style)'), group: 'Manutenção'),
      CommitParser(RegExp('^revert'), group: 'Reversões'),
    ],
  );

  /// Reads the parts of a `cliff.toml` that decide the groups. Anything it
  /// can't read falls back to [promptorium]'s parsers.
  factory CliffRules.parse(String toml) {
    List<Map<String, String>> tables(String key) {
      final start = RegExp(
        '^$key\\s*=\\s*\\[',
        multiLine: true,
      ).firstMatch(toml);
      if (start == null) return const [];
      // The array ends at the first `]` alone on a line.
      final end = RegExp(
        r'^\]',
        multiLine: true,
      ).firstMatch(toml.substring(start.end));
      final body = toml.substring(
        start.end,
        end == null ? toml.length : start.end + end.start,
      );
      return [
        for (final t in RegExp(r'\{([^{}]*)\}').allMatches(body))
          {
            for (final kv in RegExp(
              r'''(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|'[^']*'|true|false)''',
            ).allMatches(t.group(1)!))
              kv.group(1)!: _tomlValue(kv.group(2)!),
          },
      ];
    }

    bool? flag(String key) {
      final m = RegExp(
        '^$key\\s*=\\s*(true|false)',
        multiLine: true,
      ).firstMatch(toml);
      return m == null ? null : m.group(1) == 'true';
    }

    RegExp? regex(String? source) {
      if (source == null) return null;
      try {
        return RegExp(source);
      } on FormatException {
        return null;
      }
    }

    final parsers = [
      for (final t in tables('commit_parsers'))
        if (regex(t['message']) case final re?)
          CommitParser(
            re,
            group: t['group'] == null ? null : _groupTitle(t['group']!),
            skip: t['skip'] == 'true',
          ),
    ];
    return CliffRules(
      preprocessors: [
        for (final t in tables('commit_preprocessors'))
          if (regex(t['pattern']) case final re?)
            CommitPreprocessor(re, t['replace'] ?? ''),
      ],
      parsers: parsers.isEmpty ? promptorium.parsers : parsers,
      filterUnconventional: flag('filter_unconventional') ?? true,
      featuresAlwaysBumpMinor: flag('features_always_bump_minor') ?? true,
      breakingAlwaysBumpMajor: flag('breaking_always_bump_major') ?? true,
      fromFile: true,
    );
  }
}

String _tomlValue(String raw) {
  if (raw.startsWith("'")) return raw.substring(1, raw.length - 1);
  if (!raw.startsWith('"')) return raw;
  return raw
      .substring(1, raw.length - 1)
      .replaceAllMapped(
        RegExp(r'\\(.)'),
        (m) => switch (m.group(1)) {
          'n' => '\n',
          't' => '\t',
          final c => c!,
        },
      );
}

/// `<!-- 0 -->Funcionalidades` → `Funcionalidades`.
String _groupTitle(String raw) =>
    raw.replaceAll(RegExp(r'<!--.*?-->'), '').trim();

/// A commit of the branch, as `git log` gives it.
@immutable
class RawCommit {
  const RawCommit({
    required this.sha,
    required this.subject,
    this.body = '',
    this.parents = 1,
  });

  final String sha;
  final String subject;
  final String body;
  final int parents;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
  bool get isMerge => parents > 1;
}

/// A commit in a group: `tipo(escopo)!: descrição`.
@immutable
class GroupedCommit {
  const GroupedCommit({
    required this.commit,
    required this.type,
    required this.description,
    this.scope,
    this.breaking = false,
  });

  final RawCommit commit;
  final String type;
  final String? scope;
  final String description;
  final bool breaking;

  /// `escopo: descrição`.
  String get short => scope == null ? description : '$scope: $description';
}

final _conventional = RegExp(r'^(\w+)(?:\(([^)]*)\))?(!)?:\s*(.+)$');

/// `(group, commit)` of [c] under [rules], or null when it stays out (not
/// conventional, `skip`, or no parser matches).
(String group, GroupedCommit commit)? classifyCommit(
  RawCommit c,
  CliffRules rules,
) {
  var subject = c.subject.trim();
  for (final p in rules.preprocessors) {
    subject = p.apply(subject);
  }
  final m = _conventional.firstMatch(subject);
  if (m == null && rules.filterUnconventional) return null;
  for (final p in rules.parsers) {
    if (!p.message.hasMatch(subject)) continue;
    if (p.skip) return null;
    if (p.group == null) continue;
    return (
      p.group!,
      GroupedCommit(
        commit: c,
        type: m?.group(1) ?? '',
        scope: (m?.group(2)?.isEmpty ?? true) ? null : m!.group(2),
        description: m?.group(4) ?? subject,
        breaking:
            m?.group(3) != null ||
            RegExp(r'^BREAKING[ -]CHANGE:', multiLine: true).hasMatch(c.body),
      ),
    );
  }
  return null;
}

/// A group of the "Não lançado" card.
@immutable
class CommitGroup {
  const CommitGroup(this.title, this.commits);

  final String title;

  /// Oldest first, as git-cliff sorts them.
  final List<GroupedCommit> commits;

  /// `sprints: concluir sprint · tray: radar na bandeja` (the card's line).
  String get summary => commits.map((c) => c.short).join(' · ');
}

/// A spec merged since the last tag (R3).
@immutable
class MergedSpec {
  const MergedSpec(this.code, {this.title});

  /// `SPEC-042`.
  final String code;
  final String? title;
}

final _specBranch = RegExp(r'\bspec/(\d{2,})(?:[-/]|\b)');
final _specCode = RegExp(r'\bSPEC-(\d{2,})\b');

/// The specs of [commits]: the `spec/NNN-*` branch of a merge or a
/// `SPEC-NNN` in the subject, in code order (R3).
List<MergedSpec> mergedSpecs(
  List<RawCommit> commits, {
  Map<String, String> titles = const {},
}) {
  final codes = <String>{};
  for (final c in commits) {
    for (final m in [
      if (c.isMerge) ..._specBranch.allMatches(c.subject),
      ..._specCode.allMatches(c.subject),
    ]) {
      codes.add('SPEC-${m.group(1)}');
    }
  }
  final sorted = codes.toList()..sort();
  return [for (final c in sorted) MergedSpec(c, title: titles[c])];
}

/// Why the version goes up (the card's second line).
enum BumpReason {
  first('primeira versão'),
  breaking('há mudanças incompatíveis'),
  feature('há funcionalidades novas'),
  fix('só correções e manutenção');

  const BumpReason(this.label);

  final String label;
}

BumpReason bumpReason(List<GroupedCommit> commits, SemVer? last) {
  if (last == null) return BumpReason.first;
  if (commits.any((c) => c.breaking)) return BumpReason.breaking;
  if (commits.any((c) => c.type == 'feat')) return BumpReason.feature;
  return BumpReason.fix;
}

/// The next version without git-cliff (R3): an incompatible change bumps
/// the major, `feat` the minor, the rest the patch. Before 1.0 an
/// incompatible change bumps the minor and `feat` the patch. With a
/// `cliff.toml`, its `[bump]` options decide the 0.x case as git-cliff
/// does. No tag yet = `0.1.0`.
SemVer nextVersion(
  List<GroupedCommit> commits,
  SemVer? last, {
  CliffRules? cliff,
}) {
  if (last == null) return const SemVer(0, 1, 0);
  final base = SemVer(last.major, last.minor, last.patch);
  final reason = bumpReason(commits, last);
  final zero = last.major == 0;
  final major = zero && !(cliff?.breakingAlwaysBumpMajor ?? false)
      ? base.bumpMinor()
      : base.bumpMajor();
  final minor = zero && !(cliff?.featuresAlwaysBumpMinor ?? false)
      ? base.bumpPatch()
      : base.bumpMinor();
  return switch (reason) {
    BumpReason.breaking => major,
    BumpReason.feature => minor,
    _ => last.isPrerelease ? base : base.bumpPatch(),
  };
}

/// What is on the default branch after the last tag (R3, R4).
@immutable
class Unreleased {
  const Unreleased({
    required this.branch,
    required this.commitCount,
    required this.groups,
    required this.specs,
    required this.suggested,
    required this.reason,
    required this.changelog,
    this.lastTag,
    this.byGitCliff = false,
    this.cliffRules,
  });

  final String branch;

  /// The last version tag (null = none: everything since the first commit).
  final String? lastTag;
  final int commitCount;
  final List<CommitGroup> groups;
  final List<MergedSpec> specs;

  /// The version the card suggests (`git cliff --bumped-version` or
  /// [nextVersion]).
  final SemVer suggested;
  final BumpReason reason;

  /// The preview of the changelog for [suggested] (R4).
  final String changelog;

  /// [suggested] and [changelog] came from git-cliff.
  final bool byGitCliff;
  final CliffRules? cliffRules;

  SemVer? get lastVersion => lastTag == null ? null : SemVer.tryParse(lastTag!);

  bool get isEmpty => commitCount == 0;

  /// The tag the suggestion would get (`v0.12.0`).
  String get suggestedTag => tagFor('$suggested', lastTag: lastTag);
}

/// Groups [commits] (newest first, as `git log` gives them) under [rules],
/// in the order of the parsers.
List<CommitGroup> groupCommits(List<RawCommit> commits, CliffRules rules) {
  final byGroup = <String, List<GroupedCommit>>{};
  for (final c in commits.reversed) {
    final r = classifyCommit(c, rules);
    if (r != null) byGroup.putIfAbsent(r.$1, () => []).add(r.$2);
  }
  final order = rules.groupOrder;
  final titles = byGroup.keys.toList()
    ..sort((a, b) {
      final ia = order.indexOf(a), ib = order.indexOf(b);
      return (ia < 0 ? order.length : ia).compareTo(ib < 0 ? order.length : ib);
    });
  return [for (final t in titles) CommitGroup(t, byGroup[t]!)];
}

/// The changelog of [version] in git-cliff's format (the `cliff.toml` of
/// the Promptorium), for projects without git-cliff (R4).
String renderChangelog(
  String version,
  List<CommitGroup> groups, {
  required DateTime date,
}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final day = '${date.year}-${two(date.month)}-${two(date.day)}';
  String upperFirst(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  final b = StringBuffer(
    '## [${version.replaceFirst(RegExp('^v'), '')}] - $day\n',
  );
  for (final g in groups) {
    b.writeln('\n### ${g.title}');
    for (final c in g.commits) {
      b.writeln(
        '- ${c.scope == null ? '' : '**${c.scope}:** '}'
        '${c.breaking ? '[**incompatível**] ' : ''}'
        '${upperFirst(c.description)} (${c.commit.shortSha})',
      );
    }
  }
  return b.toString().trimRight();
}

/// Parses `git log --format=%H%x1f%P%x1f%s%x1f%b%x1e`.
List<RawCommit> parseLog(String out) => [
  for (final rec in out.split('\x1e'))
    if (rec.trim().isNotEmpty)
      () {
        final f = rec.trim().split('\x1f');
        return RawCommit(
          sha: f[0],
          parents: f.length > 1
              ? f[1].split(' ').where((p) => p.isNotEmpty).length
              : 1,
          subject: f.length > 2 ? f[2] : '',
          body: f.length > 3 ? f[3].trim() : '',
        );
      }(),
];

/// Reads the "Não lançado" card of [root]: the commits of [branchRef] after
/// [lastTag], with git-cliff when [cliff] runs (R3, R4).
Future<Unreleased> loadUnreleased({
  required String root,
  required GitService git,
  required String branch,
  required String branchRef,
  required String? lastTag,
  CliRunner? cliff,
  Map<String, String> specTitles = const {},
  DateTime? today,
}) async {
  final range = lastTag == null ? branchRef : '$lastTag..$branchRef';
  final commits = parseLog(
    await git.git(['log', '--format=%H%x1f%P%x1f%s%x1f%b%x1e', range]),
  );
  final file = File('$root/cliff.toml');
  final rules = file.existsSync()
      ? CliffRules.parse(file.readAsStringSync())
      : CliffRules.promptorium;
  final groups = groupCommits(commits, rules);
  final grouped = [for (final g in groups) ...g.commits];
  final last = lastTag == null ? null : SemVer.tryParse(lastTag);
  var suggested = nextVersion(
    grouped,
    last,
    cliff: rules.fromFile ? rules : null,
  );
  var byCliff = false;
  String? changelog;
  if (cliff != null && rules.fromFile && commits.isNotEmpty) {
    final bumped = await _cliff(cliff, root, ['--bumped-version']);
    final v = bumped == null
        ? null
        : SemVer.tryParse(bumped.trim().split('\n').last.trim());
    if (v != null) {
      suggested = v;
      byCliff = true;
      changelog = await cliffChangelog(
        cliff,
        root,
        tagFor('$v', lastTag: lastTag),
      );
    }
  }
  return Unreleased(
    branch: branch,
    lastTag: lastTag,
    commitCount: commits.length,
    groups: groups,
    specs: mergedSpecs(commits, titles: specTitles),
    suggested: suggested,
    reason: bumpReason(grouped, last),
    changelog:
        changelog ??
        renderChangelog('$suggested', groups, date: today ?? DateTime.now()),
    byGitCliff: byCliff,
    cliffRules: rules,
  );
}

/// `git-cliff --unreleased --tag <tag> --strip all` (null = it failed).
Future<String?> cliffChangelog(CliRunner cliff, String root, String tag) async {
  final out = await _cliff(cliff, root, [
    '--unreleased',
    '--tag',
    tag,
    '--strip',
    'all',
  ]);
  return out?.trim();
}

Future<String?> _cliff(CliRunner run, String root, List<String> args) async {
  try {
    final r = await run('git-cliff', args, workingDirectory: root);
    return r.exitCode == 0 ? '${r.stdout}' : null;
  } on ProcessException {
    return null;
  }
}

/// Whether `git-cliff` runs here.
Future<bool> gitCliffAvailable(CliRunner run, String root) async =>
    await _cliff(run, root, ['--version']) != null;
