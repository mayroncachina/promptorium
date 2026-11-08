import 'dart:convert';
import 'dart:io';

/// `which`, `gh` and `git-cliff` simulated (the pattern of the Review's
/// `FakeCommands`); git runs for real through `GitService`.
class FakeGh {
  FakeGh({this.hasGh = true, this.authed = true, this.hasCliff = false});

  bool hasGh;
  bool authed;
  bool hasCliff;
  String account = 'mayroncachina';

  /// Rows of `gh api repos/{owner}/{repo}/releases`.
  List<Map<String, Object?>> releases = [];
  bool releasesFail = false;

  /// `git-cliff --bumped-version` / `--unreleased` outputs.
  String bumped = 'v0.12.0\n';
  String cliffChangelog =
      '## [0.12.0] - 2026-11-08\n\n### Funcionalidades\n'
      '- **repo:** Releases (abc1234)\n';

  /// Rows of `gh run list`, answered in order (the last one repeats).
  List<List<Map<String, Object?>>> runLists = [];

  /// `gh run view` answers, in order (the last one repeats).
  List<Map<String, Object?>> runViews = [];
  String failedLog = '';
  List<Map<String, Object?>> prs = [];

  /// Rows of `gh pr list --state merged` (Higiene, SPEC-047).
  List<Map<String, Object?>> mergedPrs = [];
  bool dispatchFails = false;
  String draftUrl = 'https://github.com/o/r/releases/tag/untagged-1';

  final calls = <(String, List<String>)>[];

  Iterable<List<String>> ghCalls(String sub) => [
    for (final c in calls)
      if (c.$1 == 'gh' && c.$2.take(2).join(' ') == sub) c.$2,
  ];

  Future<ProcessResult> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
  }) async {
    calls.add((exe, args));
    ProcessResult ok(Object out) =>
        ProcessResult(1, 0, out is String ? out : jsonEncode(out), '');
    ProcessResult fail(String err) => ProcessResult(1, 1, '', err);
    if (exe == 'which') {
      return hasGh ? ok('/usr/bin/gh\n') : fail('');
    }
    if (exe == 'git-cliff') {
      if (!hasCliff) throw const ProcessException('git-cliff', []);
      if (args.contains('--bumped-version')) return ok(bumped);
      if (args.contains('--unreleased')) return ok(cliffChangelog);
      return ok('git-cliff 2.6.0\n');
    }
    if (exe == 'xdg-open') return ok('');
    if (exe != 'gh') return ok('');
    if (!hasGh) throw const ProcessException('gh', []);
    final sub = args.take(2).join(' ');
    switch (sub) {
      case 'auth status':
        return authed
            ? ok(
                'github.com\n  ✓ Logged in to github.com account $account '
                '(keyring)\n',
              )
            : fail('You are not logged into any GitHub hosts.');
      case 'workflow run':
        return dispatchFails ? fail('HTTP 422') : ok('');
      case 'run list':
        if (runLists.isEmpty) return ok([]);
        return ok(runLists.length == 1 ? runLists.first : runLists.removeAt(0));
      case 'run view':
        if (args.contains('--log-failed')) return ok(failedLog);
        if (runViews.isEmpty) return fail('not found');
        return ok(runViews.length == 1 ? runViews.first : runViews.removeAt(0));
      case 'run cancel':
        return ok('');
      case 'release create':
        return ok('$draftUrl\n');
      case 'pr list':
        return ok(args.contains('merged') ? mergedPrs : prs);
    }
    if (args.first == 'api') {
      return releasesFail ? fail('HTTP 502') : ok(releases);
    }
    return ok('');
  }
}

/// A row of the releases endpoint.
Map<String, Object?> releaseRow(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  String? publishedAt,
  String body = '',
  List<(String, int)> assets = const [],
}) => {
  'tag_name': tag,
  'name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'published_at': draft ? null : publishedAt ?? '2026-11-07T13:41:53Z',
  'created_at': '2026-11-07T13:29:00Z',
  'html_url': 'https://github.com/o/r/releases/tag/$tag',
  'body': body,
  'assets': [
    for (final (name, size) in assets)
      {
        'name': name,
        'size': size,
        'browser_download_url': 'https://github.com/o/r/releases/$name',
      },
  ],
};
