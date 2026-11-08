import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs a short command in a folder (same shape as the Review's
/// `CommandRunner`, so a fake of one serves the other). Injected so tests
/// can simulate `gh`.
typedef CliRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

Future<ProcessResult> _defaultCli(
  String exe,
  List<String> args, {
  String? workingDirectory,
}) => Process.run(exe, args, workingDirectory: workingDirectory);

/// The runner of [GhCli] (overridden in tests).
final cliRunnerProvider = Provider<CliRunner>((ref) => _defaultCli);

/// A `gh` command that failed (non-zero exit, `gh` missing, bad JSON).
class GhException implements Exception {
  const GhException(this.message, {this.arguments = const [], this.stderr});

  final String message;
  final List<String> arguments;
  final String? stderr;

  @override
  String toString() {
    final err = stderr?.trim() ?? '';
    return err.isEmpty ? message : '$message: $err';
  }
}

/// What `gh auth status` says (SPEC-044 R9).
@immutable
class GhAuth {
  const GhAuth._({
    required this.installed,
    required this.loggedIn,
    this.account,
  });

  const GhAuth.missing() : this._(installed: false, loggedIn: false);
  const GhAuth.loggedOut() : this._(installed: true, loggedIn: false);
  const GhAuth.loggedIn(String? account)
    : this._(installed: true, loggedIn: true, account: account);

  final bool installed;
  final bool loggedIn;

  /// `mayroncachina` (null when the output doesn't name it).
  final String? account;

  bool get ok => installed && loggedIn;

  @override
  bool operator ==(Object other) =>
      other is GhAuth &&
      other.installed == installed &&
      other.loggedIn == loggedIn &&
      other.account == account;

  @override
  int get hashCode => Object.hash(installed, loggedIn, account);
}

/// A file attached to a release.
@immutable
class GhAsset {
  const GhAsset({required this.name, this.size, this.url});

  final String name;

  /// Bytes; null when unknown.
  final int? size;
  final String? url;
}

/// A release of the repository on GitHub.
@immutable
class GhRelease {
  const GhRelease({
    required this.tagName,
    this.name = '',
    this.isDraft = false,
    this.isPrerelease = false,
    this.isLatest = false,
    this.publishedAt,
    this.createdAt,
    this.body = '',
    this.url,
    this.assets = const [],
  });

  final String tagName;
  final String name;
  final bool isDraft;
  final bool isPrerelease;
  final bool isLatest;
  final DateTime? publishedAt;
  final DateTime? createdAt;

  /// Notes (Markdown).
  final String body;
  final String? url;
  final List<GhAsset> assets;
}

/// A workflow of the repository (`gh workflow list`).
@immutable
class GhWorkflow {
  const GhWorkflow({required this.name, required this.path, this.state = ''});

  final String name;

  /// `.github/workflows/create-release.yml`.
  final String path;

  /// `active` / `disabled_manually`…
  final String state;
}

/// A run of a workflow (`gh run list`).
@immutable
class GhRun {
  const GhRun({
    required this.id,
    this.status = '',
    this.conclusion = '',
    this.createdAt,
    this.url,
    this.title = '',
    this.headBranch = '',
  });

  /// `databaseId`.
  final int id;

  /// `queued` / `in_progress` / `completed`.
  final String status;

  /// `success` / `failure` / `cancelled`… (empty while running).
  final String conclusion;
  final DateTime? createdAt;
  final String? url;
  final String title;
  final String headBranch;
}

/// A step of a job.
@immutable
class GhStep {
  const GhStep({
    required this.name,
    this.number = 0,
    this.status = '',
    this.conclusion = '',
    this.startedAt,
    this.completedAt,
  });

  final String name;
  final int number;
  final String status;
  final String conclusion;
  final DateTime? startedAt;
  final DateTime? completedAt;
}

/// A job of a run, with its steps.
@immutable
class GhJob {
  const GhJob({
    required this.name,
    this.status = '',
    this.conclusion = '',
    this.startedAt,
    this.completedAt,
    this.url,
    this.steps = const [],
  });

  final String name;
  final String status;
  final String conclusion;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? url;
  final List<GhStep> steps;
}

/// `gh run view <id> --json …`.
@immutable
class GhRunView {
  const GhRunView({
    required this.id,
    this.status = '',
    this.conclusion = '',
    this.jobs = const [],
    this.url,
    this.createdAt,
    this.workflowName = '',
  });

  final int id;
  final String status;
  final String conclusion;
  final List<GhJob> jobs;
  final String? url;
  final DateTime? createdAt;
  final String workflowName;

  bool get completed => status == 'completed';
}

/// A pull request (`gh pr list`).
@immutable
class GhPullRequest {
  const GhPullRequest({
    required this.number,
    required this.url,
    this.title = '',
    this.headRefName = '',
    this.state = '',
  });

  final int number;
  final String url;
  final String title;
  final String headRefName;
  final String state;
}

DateTime? _date(Object? v) =>
    v is String && v.isNotEmpty && !v.startsWith('0001-')
    ? DateTime.tryParse(v)
    : null;

String _str(Object? v) => v is String ? v : '';

int? _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');

/// A thin wrapper of the GitHub CLI for the Repositório screen (SPEC-044).
/// Every call runs in [cwd] (the repository), so `gh` finds the remote.
/// The Review services may move to it later; they don't use it yet.
class GhCli {
  GhCli(this._run, {required this.cwd});

  final CliRunner _run;
  final String cwd;

  Future<ProcessResult> _raw(List<String> args) async {
    try {
      return await _run('gh', args, workingDirectory: cwd);
    } on ProcessException catch (e) {
      throw GhException(
        'gh não encontrado',
        arguments: args,
        stderr: e.message,
      );
    }
  }

  /// `gh <args>`, stdout. Throws [GhException].
  Future<String> gh(List<String> args) async {
    final r = await _raw(args);
    if (r.exitCode != 0) {
      final err = '${r.stderr}'.trim();
      throw GhException(
        'gh ${args.take(2).join(' ')} falhou',
        arguments: args,
        stderr: err.isEmpty ? '${r.stdout}'.trim() : err,
      );
    }
    return '${r.stdout}';
  }

  Future<Object?> _json(List<String> args) async {
    final out = await gh(args);
    try {
      return jsonDecode(out.trim().isEmpty ? 'null' : out);
    } on FormatException {
      throw GhException('resposta inválida do gh', arguments: args);
    }
  }

  /// Whether `gh` is installed (`which gh`).
  Future<bool> ghAvailable() async {
    try {
      final r = await _run('which', ['gh'], workingDirectory: cwd);
      return r.exitCode == 0 && '${r.stdout}'.trim().isNotEmpty;
    } on ProcessException {
      return false;
    }
  }

  /// `gh auth status` on [hostname]: installed, logged in and the account.
  Future<GhAuth> ghAuthStatus({String hostname = 'github.com'}) async {
    if (!await ghAvailable()) return const GhAuth.missing();
    final ProcessResult r;
    try {
      r = await _raw(['auth', 'status', '--hostname', hostname]);
    } on GhException {
      return const GhAuth.missing();
    }
    if (r.exitCode != 0) return const GhAuth.loggedOut();
    final out = '${r.stdout}\n${r.stderr}';
    final account = RegExp(r'account\s+(\S+)|as\s+(\S+)').firstMatch(out);
    return GhAuth.loggedIn(account?.group(1) ?? account?.group(2));
  }

  /// The releases of the repository, newest first, with notes and files
  /// (`gh api repos/{owner}/{repo}/releases`): one call gives what `gh
  /// release list` leaves out (the files and their sizes).
  Future<List<GhRelease>> releaseList({int limit = 50}) async {
    final j = await _json([
      'api',
      'repos/{owner}/{repo}/releases?per_page=$limit',
    ]);
    return parseReleases(j);
  }

  /// Parses the JSON of the releases endpoint (tolerant; bad rows skipped).
  /// `isLatest` = the newest published release that is not a pre-release.
  static List<GhRelease> parseReleases(Object? j) {
    if (j is! List) return const [];
    final out = <GhRelease>[];
    for (final r in j.whereType<Map>()) {
      final tag = _str(r['tag_name']);
      if (tag.isEmpty) continue;
      out.add(
        GhRelease(
          tagName: tag,
          name: _str(r['name']),
          isDraft: r['draft'] == true,
          isPrerelease: r['prerelease'] == true,
          publishedAt: _date(r['published_at']),
          createdAt: _date(r['created_at']),
          body: _str(r['body']),
          url: r['html_url'] is String ? r['html_url'] as String : null,
          assets: [
            for (final a in (r['assets'] is List ? r['assets'] as List : []))
              if (a is Map && _str(a['name']).isNotEmpty)
                GhAsset(
                  name: _str(a['name']),
                  size: _int(a['size']),
                  url: a['browser_download_url'] is String
                      ? a['browser_download_url'] as String
                      : null,
                ),
          ],
        ),
      );
    }
    final published = [
      for (final r in out)
        if (!r.isDraft && !r.isPrerelease && r.publishedAt != null) r,
    ]..sort((a, b) => b.publishedAt!.compareTo(a.publishedAt!));
    final latest = published.firstOrNull?.tagName;
    return [
      for (final r in out)
        r.tagName == latest
            ? GhRelease(
                tagName: r.tagName,
                name: r.name,
                isDraft: r.isDraft,
                isPrerelease: r.isPrerelease,
                isLatest: true,
                publishedAt: r.publishedAt,
                createdAt: r.createdAt,
                body: r.body,
                url: r.url,
                assets: r.assets,
              )
            : r,
    ];
  }

  /// `gh workflow list --json name,path,state`.
  Future<List<GhWorkflow>> workflowList() async {
    final j = await _json([
      'workflow',
      'list',
      '--all',
      '--json',
      'name,path,state',
    ]);
    return [
      if (j is List)
        for (final w in j.whereType<Map>())
          if (_str(w['path']).isNotEmpty)
            GhWorkflow(
              name: _str(w['name']),
              path: _str(w['path']),
              state: _str(w['state']),
            ),
    ];
  }

  /// `gh workflow run <file> --ref <ref> -f key=value…`.
  Future<void> workflowRun(
    String file, {
    required String ref,
    Map<String, String> inputs = const {},
  }) => gh([
    'workflow',
    'run',
    file,
    '--ref',
    ref,
    for (final e in inputs.entries) ...['-f', '${e.key}=${e.value}'],
  ]);

  static const runFields =
      'databaseId,status,conclusion,createdAt,url,displayTitle,headBranch';

  /// `gh run list --workflow <file> --event <event>`, newest first.
  Future<List<GhRun>> runList({
    required String workflow,
    String event = 'workflow_dispatch',
    int limit = 10,
  }) async {
    final j = await _json([
      'run',
      'list',
      '--workflow',
      workflow,
      '--event',
      event,
      '--limit',
      '$limit',
      '--json',
      runFields,
    ]);
    return [
      if (j is List)
        for (final r in j.whereType<Map>())
          if (_int(r['databaseId']) case final id?)
            GhRun(
              id: id,
              status: _str(r['status']),
              conclusion: _str(r['conclusion']),
              createdAt: _date(r['createdAt']),
              url: r['url'] is String ? r['url'] as String : null,
              title: _str(r['displayTitle']),
              headBranch: _str(r['headBranch']),
            ),
    ];
  }

  static const runViewFields =
      'databaseId,status,conclusion,jobs,url,createdAt,workflowName';

  /// `gh run view <id> --json status,conclusion,jobs…`.
  Future<GhRunView> runView(int id) async => parseRunView(
    id,
    await _json(['run', 'view', '$id', '--json', runViewFields]),
  );

  /// Parses `gh run view --json [runViewFields]`.
  static GhRunView parseRunView(int id, Object? j) {
    if (j is! Map) throw const GhException('resposta inválida do gh run view');
    List<GhStep> steps(Object? v) => [
      if (v is List)
        for (final s in v.whereType<Map>())
          GhStep(
            name: _str(s['name']),
            number: _int(s['number']) ?? 0,
            status: _str(s['status']),
            conclusion: _str(s['conclusion']),
            startedAt: _date(s['startedAt']),
            completedAt: _date(s['completedAt']),
          ),
    ];
    return GhRunView(
      id: _int(j['databaseId']) ?? id,
      status: _str(j['status']),
      conclusion: _str(j['conclusion']),
      url: j['url'] is String ? j['url'] as String : null,
      createdAt: _date(j['createdAt']),
      workflowName: _str(j['workflowName']),
      jobs: [
        if (j['jobs'] is List)
          for (final job in (j['jobs'] as List).whereType<Map>())
            GhJob(
              name: _str(job['name']),
              status: _str(job['status']),
              conclusion: _str(job['conclusion']),
              startedAt: _date(job['startedAt']),
              completedAt: _date(job['completedAt']),
              url: job['url'] is String ? job['url'] as String : null,
              steps: steps(job['steps']),
            ),
      ],
    );
  }

  /// `gh run cancel <id>`.
  Future<void> runCancel(int id) => gh(['run', 'cancel', '$id']);

  /// The last [lines] lines of `gh run view <id> --log-failed`, without the
  /// `job<TAB>step<TAB>` columns gh puts in front.
  Future<List<String>> runFailedLog(int id, {int lines = 40}) async =>
      tailFailedLog(await gh(['run', 'view', '$id', '--log-failed']), lines);

  static List<String> tailFailedLog(String out, int lines) {
    final all = [
      for (final l in const LineSplitter().convert(out))
        if (l.trim().isNotEmpty) l.split('\t').skip(2).join('\t').trimRight(),
    ];
    return all.length <= lines ? all : all.sublist(all.length - lines);
  }

  /// `gh release create <tag> --target <branch> --draft --notes-file <f>`;
  /// returns the URL gh prints.
  Future<String> releaseCreateDraft(
    String tag, {
    required String target,
    required String notesFile,
  }) async {
    final out = await gh([
      'release',
      'create',
      tag,
      '--target',
      target,
      '--draft',
      '--title',
      tag,
      '--notes-file',
      notesFile,
    ]);
    return out
        .split('\n')
        .map((l) => l.trim())
        .lastWhere((l) => l.startsWith('http'), orElse: () => '');
  }

  /// PRs (any state) whose head is [head] or, without [head], that match
  /// [search] (`gh pr list --search`).
  Future<List<GhPullRequest>> prList({String? head, String? search}) async {
    final j = await _json([
      'pr',
      'list',
      '--state',
      'all',
      '--limit',
      '10',
      if (head != null) ...['--head', head],
      if (search != null) ...['--search', search],
      '--json',
      'number,url,title,headRefName,state',
    ]);
    return [
      if (j is List)
        for (final p in j.whereType<Map>())
          if (_int(p['number']) case final n? when p['url'] is String)
            GhPullRequest(
              number: n,
              url: p['url'] as String,
              title: _str(p['title']),
              headRefName: _str(p['headRefName']),
              state: _str(p['state']),
            ),
    ];
  }
}

/// A [GhCli] for a repository folder.
final ghCliFactoryProvider = Provider<GhCli Function(String cwd)>((ref) {
  final run = ref.watch(cliRunnerProvider);
  return (cwd) => GhCli(run, cwd: cwd);
});
