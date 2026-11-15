import 'dart:convert';
import 'dart:io';

/// A GitHub repository simulated behind `gh` for the issues (SPEC-074):
/// `which`, `gh auth status`, `gh repo view`, the search, the issue
/// endpoints, `gh issue create`, GraphQL states and the comments. Nothing
/// reaches GitHub.
class FakeIssuesGh {
  FakeIssuesGh({
    this.hasGh = true,
    this.authed = true,
    this.issuesEnabled = true,
    this.repo = 'ana-souza/loja-da-ana',
    this.defaultBranch = 'main',
  });

  bool hasGh;
  bool authed;
  bool issuesEnabled;
  String repo;
  String defaultBranch;
  String account = 'ana-souza';

  /// Issues (and PRs, with `pull_request`) by number.
  final issues = <int, Map<String, Object?>>{};

  /// Comments by issue number.
  final comments = <int, List<Map<String, Object?>>>{};

  /// Every `gh` call fails as offline.
  bool offline = false;

  /// `gh issue create` fails.
  bool createFails = false;
  int nextNumber = 300;
  int _nextComment = 9000;

  final calls = <(String, List<String>)>[];

  Iterable<List<String>> get ghCalls => [
    for (final c in calls)
      if (c.$1 == 'gh') c.$2,
  ];

  /// Calls that wrote something on GitHub (create, comment, edit).
  Iterable<List<String>> get writes => [
    for (final a in ghCalls)
      if ((a.length > 1 && a[0] == 'issue' && a[1] == 'create') ||
          a.contains('POST') ||
          a.contains('PATCH'))
        a,
  ];

  /// Adds an issue (or a PR with [pr]).
  Map<String, Object?> add(
    int number,
    String title, {
    String body = '',
    String state = 'open',
    List<String> labels = const [],
    String? milestone,
    List<String> assignees = const [],
    bool pr = false,
    String updatedAt = '2026-11-10T10:00:00Z',
    String? closedAt,
  }) => issues[number] = {
    'number': number,
    'title': title,
    'body': body,
    'state': state,
    'labels': [
      for (final l in labels) {'name': l, 'color': 'd73a4a'},
    ],
    'milestone': milestone == null ? null : {'title': milestone},
    'assignees': [
      for (final a in assignees) {'login': a},
    ],
    'html_url': 'https://github.com/$repo/issues/$number',
    'created_at': '2026-11-01T10:00:00Z',
    'updated_at': updatedAt,
    'closed_at': closedAt,
    if (pr) 'pull_request': {'url': 'x'},
  };

  /// How a closed issue was closed, for GraphQL (`PR #250` or null = by
  /// hand).
  final closedByPr = <int, int>{};

  Future<ProcessResult> call(
    String exe,
    List<String> args, {
    String? workingDirectory,
  }) async {
    calls.add((exe, args));
    ProcessResult ok(Object out) =>
        ProcessResult(1, 0, out is String ? out : jsonEncode(out), '');
    ProcessResult fail(String err, {String out = ''}) =>
        ProcessResult(1, 1, out, err);
    if (exe == 'which') return hasGh ? ok('/usr/bin/gh\n') : fail('');
    if (exe == 'xdg-open') return ok('');
    if (exe != 'gh') return ok('');
    if (!hasGh) throw const ProcessException('gh', []);
    if (offline) {
      return fail('error connecting to api.github.com: no such host');
    }
    final sub = args.take(2).join(' ');
    if (sub == 'auth status') {
      return authed
          ? ok('github.com\n  ✓ Logged in to github.com account $account\n')
          : fail(
              'You are not logged into any GitHub hosts. To log in, run: '
              'gh auth login',
            );
    }
    if (sub == 'repo view') {
      return ok({
        'nameWithOwner': repo,
        'hasIssuesEnabled': issuesEnabled,
        'defaultBranchRef': {'name': defaultBranch},
      });
    }
    if (sub == 'issue create') {
      if (createFails) return fail('HTTP 422: Validation Failed');
      final title = args[args.indexOf('--title') + 1];
      final body = args[args.indexOf('--body') + 1];
      final n = nextNumber++;
      add(n, title, body: body);
      return ok('https://github.com/$repo/issues/$n\n');
    }
    if (sub == 'label list') {
      return ok([
        {'name': 'bug', 'color': 'd73a4a'},
        {'name': 'checkout', 'color': 'f2a541'},
        {'name': 'enhancement', 'color': 'a2eeef'},
      ]);
    }
    if (args.first != 'api') return ok('');
    if (args[1] == 'graphql') return _graphql(args, ok, fail);
    final method = args.contains('-X') ? args[args.indexOf('-X') + 1] : 'GET';
    final path = args.firstWhere(
      (a) => a.startsWith('repos/') || a.startsWith('search/'),
    );
    String field(String name) {
      for (var i = 0; i < args.length - 1; i++) {
        if (args[i] == '-f' && args[i + 1].startsWith('$name=')) {
          return args[i + 1].substring(name.length + 1);
        }
      }
      return '';
    }

    if (path == 'search/issues') return ok(_search(field('q'), field('page')));
    final uri = Uri.parse(path);
    final seg = uri.pathSegments;
    // repos/o/r/issues/N
    if (seg.length == 5 && seg[3] == 'issues') {
      final i = issues[int.parse(seg[4])];
      return i == null ? fail('gh: Not Found (HTTP 404)') : ok(i);
    }
    // repos/o/r/issues/comments/ID
    if (seg.length == 6 && seg[4] == 'comments' && method == 'PATCH') {
      final id = int.parse(seg[5]);
      for (final list in comments.values) {
        for (final c in list) {
          if (c['id'] == id) c['body'] = field('body');
        }
      }
      return ok({'id': id});
    }
    // repos/o/r/issues/N/comments
    if (seg.length == 6 && seg[5] == 'comments') {
      final n = int.parse(seg[4]);
      if (method == 'POST') {
        final c = {'id': _nextComment++, 'body': field('body')};
        comments.putIfAbsent(n, () => []).add(c);
        return ok(c);
      }
      return ok(comments[n] ?? const []);
    }
    if (seg.length == 4 && seg[3] == 'milestones') {
      return ok([
        {'title': 'v1.2'},
        {'title': 'v1.3'},
      ]);
    }
    if (seg.length == 4 && seg[3] == 'assignees') {
      return ok([
        {'login': 'ana-souza'},
        {'login': 'lucas-andrade'},
      ]);
    }
    return ok('');
  }

  Map<String, Object?> _search(String q, String page) {
    final terms = q.split(' ');
    bool has(String t) => terms.contains(t);
    final labels = [
      for (final t in terms)
        if (t.startsWith('label:')) t.substring(6).replaceAll('"', ''),
    ];
    final words = [
      for (final t in terms)
        if (!t.contains(':')) t.toLowerCase(),
    ];
    final all = issues.values.where((i) {
      if (has('state:open') && i['state'] != 'open') return false;
      if (has('state:closed') && i['state'] != 'closed') return false;
      final names = [for (final l in i['labels'] as List) (l as Map)['name']];
      if (!labels.every(names.contains)) return false;
      final text = '${i['title']} ${i['body']}'.toLowerCase();
      if (!words.every(text.contains)) return false;
      return true;
    }).toList()..sort((a, b) => (b['number'] as int) - (a['number'] as int));
    final p = int.tryParse(page) ?? 1;
    final from = (p - 1) * 50;
    return {
      'total_count': all.length,
      // The search API of GitHub may still bring a PR: the client drops it.
      'items': all.skip(from).take(50).toList(),
    };
  }

  ProcessResult _graphql(
    List<String> args,
    ProcessResult Function(Object) ok,
    ProcessResult Function(String, {String out}) fail,
  ) {
    final query = args.firstWhere((a) => a.startsWith('query='));
    final numbers = [
      for (final m in RegExp(r'issue\(number: (\d+)\)').allMatches(query))
        int.parse(m.group(1)!),
    ];
    final repoNode = <String, Object?>{};
    var missing = false;
    for (final n in numbers) {
      final i = issues[n];
      if (i == null || i.containsKey('pull_request')) {
        repoNode['i$n'] = null;
        missing = true;
        continue;
      }
      final closed = i['state'] == 'closed';
      repoNode['i$n'] = {
        'number': n,
        'state': closed ? 'CLOSED' : 'OPEN',
        'closedAt': i['closed_at'],
        'timelineItems': {
          'nodes': [
            if (closed)
              {
                'closer': closedByPr[n] == null
                    ? null
                    : {'__typename': 'PullRequest', 'number': closedByPr[n]},
              },
          ],
        },
      };
    }
    final out = jsonEncode({
      'data': {'repository': repoNode},
      if (missing)
        'errors': [
          {'type': 'NOT_FOUND', 'message': 'Could not resolve to an Issue'},
        ],
    });
    return missing
        ? fail('gh: Could not resolve to an Issue', out: out)
        : ok(out);
  }
}
