import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'gh_cli.dart';

/// The issues of one GitHub repository through `gh` (SPEC-074). Every call
/// names the repository ([repo], `owner/name`): with several remotes `gh`
/// would otherwise ask which one is the default.

/// State filter of "Importar issues" (R3).
enum IssueStateFilter { open, closed, all }

/// Who the issue is assigned to (R3): anyone, me, one login or nobody.
@immutable
class IssueAssigneeFilter {
  const IssueAssigneeFilter._(this.kind, [this.login]);

  static const any = IssueAssigneeFilter._('any');
  static const me = IssueAssigneeFilter._('me');
  static const none = IssueAssigneeFilter._('none');
  const IssueAssigneeFilter.person(String login) : this._('person', login);

  final String kind;
  final String? login;

  @override
  bool operator ==(Object other) =>
      other is IssueAssigneeFilter &&
      other.kind == kind &&
      other.login == login;

  @override
  int get hashCode => Object.hash(kind, login);
}

/// One label of an issue or of the repository.
@immutable
class GhLabel {
  const GhLabel(this.name, {this.color = ''});

  final String name;

  /// `d73a4a` (without `#`; empty when unknown).
  final String color;

  @override
  bool operator ==(Object other) => other is GhLabel && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// An issue of the repository (never a pull request).
@immutable
class GhIssue {
  const GhIssue({
    required this.number,
    required this.title,
    this.body = '',
    this.state = 'open',
    this.labels = const [],
    this.milestone,
    this.assignees = const [],
    this.url,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
    this.closedBy,
  });

  final int number;
  final String title;

  /// Markdown (empty when the issue has no text).
  final String body;

  /// `open` / `closed`.
  final String state;
  final List<GhLabel> labels;

  /// Title of the milestone.
  final String? milestone;

  /// Logins.
  final List<String> assignees;
  final String? url;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;

  /// Login of who closed it (REST) or `PR #250` (GraphQL).
  final String? closedBy;

  bool get closed => state == 'closed';

  /// Items of a checklist in the text (`- [ ]` / `- [x]`).
  int get checklistItems =>
      RegExp(r'^\s*[-*+]\s+\[[ xX]\]', multiLine: true).allMatches(body).length;

  /// Images in the text (Markdown or `<img>`).
  int get images => RegExp(
    r'!\[[^\]]*\]\([^)]*\)|<img\b',
    caseSensitive: false,
  ).allMatches(body).length;
}

/// One page of [GhIssues.list]: the issues, the total with the filters and
/// whether there are more pages.
@immutable
class GhIssuePage {
  const GhIssuePage({
    required this.issues,
    required this.total,
    required this.page,
  });

  final List<GhIssue> issues;
  final int total;
  final int page;

  bool get hasMore => page * GhIssues.pageSize < total;

  /// How many the next page brings ("Carregar mais 8").
  int get nextCount => hasMore
      ? (total - page * GhIssues.pageSize).clamp(0, GhIssues.pageSize)
      : 0;
}

/// What GitHub says of one issue linked to a spec (R9).
@immutable
class GhIssueState {
  const GhIssueState({
    required this.number,
    required this.found,
    this.closed = false,
    this.closedAt,
    this.closedBy,
  });

  final int number;

  /// False: deleted, transferred or a pull request.
  final bool found;
  final bool closed;
  final DateTime? closedAt;

  /// `PR #250`, `à mão` (null while open).
  final String? closedBy;
}

/// The repository's settings that matter for the issues (R2).
@immutable
class GhRepoInfo {
  const GhRepoInfo({
    required this.nameWithOwner,
    this.hasIssuesEnabled = true,
    this.defaultBranch,
  });

  final String nameWithOwner;
  final bool hasIssuesEnabled;
  final String? defaultBranch;
}

DateTime? _date(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

String _str(Object? v) => v is String ? v : '';

int? _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');

/// Quotes a search qualifier value with spaces (`label:"good first"`).
String _q(String v) =>
    RegExp(r'[\s"]').hasMatch(v) ? '"${v.replaceAll('"', '')}"' : v;

class GhIssues {
  GhIssues(this.gh, {required this.repo});

  final GhCli gh;

  /// `owner/name`.
  final String repo;

  /// Issues per page of "Importar issues" (R3).
  static const pageSize = 50;

  Future<Object?> _json(List<String> args) async {
    final out = await gh.gh(args);
    try {
      return jsonDecode(out.trim().isEmpty ? 'null' : out);
    } on FormatException {
      throw GhException('resposta inválida do gh', arguments: args);
    }
  }

  /// The search query of [list] (`repo:o/r is:issue state:open …`).
  String searchQuery({
    IssueStateFilter state = IssueStateFilter.open,
    List<String> labels = const [],
    String? milestone,
    IssueAssigneeFilter assignee = IssueAssigneeFilter.any,
    String search = '',
  }) => [
    'repo:$repo',
    'is:issue',
    if (state == IssueStateFilter.open) 'state:open',
    if (state == IssueStateFilter.closed) 'state:closed',
    for (final l in labels) 'label:${_q(l)}',
    if (milestone != null && milestone.isNotEmpty) 'milestone:${_q(milestone)}',
    switch (assignee.kind) {
      'me' => 'assignee:@me',
      'none' => 'no:assignee',
      'person' when assignee.login != null => 'assignee:${assignee.login}',
      _ => '',
    },
    if (search.trim().isNotEmpty) '${search.trim()} in:title,body',
  ].where((s) => s.isNotEmpty).join(' ');

  /// One page (1-based) of the issues that match the filters, newest first,
  /// with the total (`gh api search/issues`, 50 per page). Pull requests
  /// never come: `is:issue` leaves them out, and a row that still is one
  /// is dropped.
  Future<GhIssuePage> list({
    IssueStateFilter state = IssueStateFilter.open,
    List<String> labels = const [],
    String? milestone,
    IssueAssigneeFilter assignee = IssueAssigneeFilter.any,
    String search = '',
    int page = 1,
  }) async {
    final q = searchQuery(
      state: state,
      labels: labels,
      milestone: milestone,
      assignee: assignee,
      search: search,
    );
    final j = await _json([
      'api',
      '-X',
      'GET',
      'search/issues',
      '-f',
      'q=$q',
      '-f',
      'sort=created',
      '-f',
      'order=desc',
      '-f',
      'per_page=$pageSize',
      '-f',
      'page=$page',
    ]);
    final items = j is Map && j['items'] is List ? j['items'] as List : [];
    return GhIssuePage(
      issues: [for (final i in items.whereType<Map>()) ?parseIssue(i)],
      total: j is Map ? _int(j['total_count']) ?? 0 : 0,
      page: page,
    );
  }

  /// One issue of the REST API (null = a pull request or a bad row).
  static GhIssue? parseIssue(Map<Object?, Object?> i) {
    if (i.containsKey('pull_request') && i['pull_request'] != null) {
      return null;
    }
    final n = _int(i['number']);
    if (n == null) return null;
    String login(Object? v) => v is Map ? _str(v['login']) : '';
    final milestone = i['milestone'];
    return GhIssue(
      number: n,
      title: _str(i['title']),
      body: _str(i['body']),
      state: _str(i['state']).toLowerCase().isEmpty
          ? 'open'
          : _str(i['state']).toLowerCase(),
      labels: [
        if (i['labels'] case final List ls)
          for (final l in ls)
            if (l is Map && _str(l['name']).isNotEmpty)
              GhLabel(_str(l['name']), color: _str(l['color']))
            else if (l is String && l.isNotEmpty)
              GhLabel(l),
      ],
      milestone: milestone is Map && _str(milestone['title']).isNotEmpty
          ? _str(milestone['title'])
          : null,
      assignees: [
        if (i['assignees'] case final List people)
          for (final a in people)
            if (login(a).isNotEmpty) login(a),
      ],
      url: i['html_url'] is String ? i['html_url'] as String : null,
      createdAt: _date(i['created_at']),
      updatedAt: _date(i['updated_at']),
      closedAt: _date(i['closed_at']),
      closedBy: login(i['closed_by']).isEmpty ? null : login(i['closed_by']),
    );
  }

  /// One issue by number (`gh api repos/o/r/issues/N`). A pull request is
  /// not an issue: [GhException].
  Future<GhIssue> view(int number) async {
    final j = await _json(['api', 'repos/$repo/issues/$number']);
    final issue = j is Map ? parseIssue(j) : null;
    if (issue == null) {
      throw GhException('#$number não é uma issue de $repo');
    }
    return issue;
  }

  /// `gh issue create`; returns the number of the new issue.
  Future<int> create({
    required String title,
    required String body,
    List<String> labels = const [],
    String? milestone,
    String? assignee,
  }) async {
    final out = await gh.gh([
      'issue',
      'create',
      '--repo',
      repo,
      '--title',
      title,
      '--body',
      body,
      for (final l in labels) ...['--label', l],
      if (milestone != null && milestone.isNotEmpty) ...[
        '--milestone',
        milestone,
      ],
      if (assignee != null && assignee.isNotEmpty) ...['--assignee', assignee],
    ]);
    final url = out
        .split('\n')
        .map((l) => l.trim())
        .lastWhere((l) => l.startsWith('http'), orElse: () => '');
    final n = int.tryParse(url.split('/').last);
    if (n == null) {
      throw GhException('gh issue create não devolveu o número da issue');
    }
    return n;
  }

  /// The state of every issue in [numbers] in one GraphQL query (R9). An
  /// issue that no longer resolves (deleted, transferred, a PR) comes with
  /// `found: false`.
  Future<List<GhIssueState>> states(Iterable<int> numbers) async {
    final list = numbers.toSet().toList()..sort();
    if (list.isEmpty) return const [];
    final parts = repo.split('/');
    final fields = [
      for (final n in list)
        'i$n: issue(number: $n) { number state closedAt '
            'timelineItems(last: 1, itemTypes: [CLOSED_EVENT]) { nodes { '
            '... on ClosedEvent { closer { __typename '
            '... on PullRequest { number } } } } } }',
    ].join(' ');
    final args = [
      'api',
      'graphql',
      '-f',
      'query=query(\$owner: String!, \$name: String!) { '
          'repository(owner: \$owner, name: \$name) { $fields } }',
      '-f',
      'owner=${parts.first}',
      '-f',
      'name=${parts.length > 1 ? parts[1] : ''}',
    ];
    // A missing issue makes gh exit non-zero, but the others still come in
    // `data` on stdout: the output is read either way.
    final r = await gh.ghResult(args);
    final out = '${r.stdout}';
    if (r.exitCode != 0 && !out.contains('"data"')) {
      final err = '${r.stderr}'.trim();
      throw GhException(
        'gh api graphql falhou',
        arguments: args,
        stderr: err.isEmpty ? out.trim() : err,
      );
    }
    Object? j;
    try {
      j = jsonDecode(out);
    } on FormatException {
      throw GhException('resposta inválida do gh api graphql', arguments: args);
    }
    return parseStates(list, j);
  }

  /// Parses the answer of [states].
  static List<GhIssueState> parseStates(List<int> numbers, Object? j) {
    final data = j is Map ? j['data'] : null;
    final repoNode = data is Map ? data['repository'] : null;
    if (repoNode is! Map) {
      throw const GhException('resposta inválida do gh api graphql');
    }
    return [
      for (final n in numbers)
        if (repoNode['i$n'] case final Map node)
          () {
            final closed = _str(node['state']).toUpperCase() == 'CLOSED';
            String? by;
            if (closed) {
              final nodes = node['timelineItems'] is Map
                  ? (node['timelineItems'] as Map)['nodes']
                  : null;
              final closer = nodes is List && nodes.isNotEmpty
                  ? (nodes.last is Map ? (nodes.last as Map)['closer'] : null)
                  : null;
              by = closer is Map && _int(closer['number']) != null
                  ? 'PR #${_int(closer['number'])}'
                  : 'à mão';
            }
            return GhIssueState(
              number: n,
              found: true,
              closed: closed,
              closedAt: closed ? _date(node['closedAt']) : null,
              closedBy: by,
            );
          }()
        else
          GhIssueState(number: n, found: false),
    ];
  }

  /// The labels of the repository (`gh label list`).
  Future<List<GhLabel>> labels() async {
    final j = await _json([
      'label',
      'list',
      '--repo',
      repo,
      '--limit',
      '200',
      '--json',
      'name,color',
    ]);
    return [
      if (j is List)
        for (final l in j.whereType<Map>())
          if (_str(l['name']).isNotEmpty)
            GhLabel(_str(l['name']), color: _str(l['color'])),
    ];
  }

  /// Titles of the open milestones.
  Future<List<String>> milestones() async {
    final j = await _json([
      'api',
      'repos/$repo/milestones?state=open&per_page=100',
    ]);
    return [
      if (j is List)
        for (final m in j.whereType<Map>())
          if (_str(m['title']).isNotEmpty) _str(m['title']),
    ];
  }

  /// Logins that can be assigned.
  Future<List<String>> assignees() async {
    final j = await _json(['api', 'repos/$repo/assignees?per_page=100']);
    return [
      if (j is List)
        for (final a in j.whereType<Map>())
          if (_str(a['login']).isNotEmpty) _str(a['login']),
    ];
  }

  /// Name, issues on or off and the default branch (`gh repo view`).
  Future<GhRepoInfo> info() async {
    final j = await _json([
      'repo',
      'view',
      repo,
      '--json',
      'nameWithOwner,hasIssuesEnabled,defaultBranchRef',
    ]);
    if (j is! Map) throw const GhException('resposta inválida do gh repo view');
    final ref = j['defaultBranchRef'];
    final branch = ref is Map ? _str(ref['name']) : '';
    return GhRepoInfo(
      nameWithOwner: _str(j['nameWithOwner']).isEmpty
          ? repo
          : _str(j['nameWithOwner']),
      hasIssuesEnabled: j['hasIssuesEnabled'] != false,
      defaultBranch: branch.isEmpty ? null : branch,
    );
  }

  /// Creates or edits the one comment of [number] that carries [marker]
  /// (R10): the comments are searched for the marker; found, it is edited
  /// (`PATCH`), else a new one is created. Returns the comment id.
  Future<int> upsertComment(int number, String marker, String body) async {
    final text = body.contains(marker) ? body : '$marker\n$body';
    int? found;
    for (var page = 1; page <= 10 && found == null; page++) {
      final j = await _json([
        'api',
        'repos/$repo/issues/$number/comments?per_page=100&page=$page',
      ]);
      final rows = j is List ? j.whereType<Map>().toList() : const <Map>[];
      for (final c in rows) {
        if (_str(c['body']).contains(marker)) {
          found = _int(c['id']);
          break;
        }
      }
      if (rows.length < 100) break;
    }
    if (found != null) {
      await gh.gh([
        'api',
        '-X',
        'PATCH',
        'repos/$repo/issues/comments/$found',
        '-f',
        'body=$text',
      ]);
      return found;
    }
    final j = await _json([
      'api',
      '-X',
      'POST',
      'repos/$repo/issues/$number/comments',
      '-f',
      'body=$text',
    ]);
    final id = j is Map ? _int(j['id']) : null;
    if (id == null) throw const GhException('resposta inválida do gh api');
    return id;
  }
}
