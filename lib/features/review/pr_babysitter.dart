import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/gh_cli.dart' show CiState, ciStateOf;
import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../project/project_config.dart' show ProjectConfig;
import '../sessions/app_notifier.dart';
import '../sessions/session_manager.dart';
import 'ci_fixer.dart';
import 'restack.dart' show howResolvedInstruction;
import 'review_service.dart';
import '../activities/automation_pause.dart';

/// A comment of the PR (conversation or review body).
@immutable
class PrComment {
  const PrComment({
    required this.author,
    required this.body,
    required this.at,
    this.kind = 'comentário',
    this.externalId,
    this.path,
    this.line,
    this.commitSha,
  });

  final String? externalId;
  final String? path;
  final int? line;
  final String? commitSha;
  final String author;
  final String body;
  final DateTime at;

  /// `comentário` / `review: CHANGES_REQUESTED`…
  final String kind;
}

/// Arguments that make `gh api --paginate` print one row per line
/// (`--slurp` only exists from gh 2.48 on; Ubuntu ships 2.45).
const ghRowPerLine = ['--paginate', '--jq', '.[]'];

/// The rows of a `gh api` answer: a JSON list (or list of pages), or one
/// JSON value per line ([ghRowPerLine]). Throws [FormatException].
List<Object?> decodeGhRows(String out) {
  final text = out.trim();
  if (text.isEmpty) return const [];
  try {
    final whole = jsonDecode(text);
    return whole is List ? whole : [whole];
  } on FormatException {
    return [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) jsonDecode(line),
    ];
  }
}

/// The review threads of `gh api …/pulls/<n>/comments` (rows, or pages of
/// rows): one comment per thread, with its replies appended.
List<PrComment> parsePrInlineComments(List<Object?> decoded) {
  final rows = <Map>[
    for (final page in decoded)
      if (page is List) ...page.whereType<Map>() else if (page is Map) page,
  ];
  final replies = <String, List<Map>>{};
  for (final row in rows) {
    if (row['in_reply_to_id'] != null) {
      replies.putIfAbsent('${row['in_reply_to_id']}', () => []).add(row);
    }
  }
  String author(Map row) =>
      row['user'] is Map ? '${row['user']['login'] ?? '?'}' : '?';
  return [
    for (final row in rows)
      if (row['in_reply_to_id'] == null)
        PrComment(
          author: author(row),
          externalId: 'github:${row['id']}',
          path: row['path'] as String?,
          line: (row['line'] as num? ?? row['original_line'] as num?)?.toInt(),
          commitSha: row['commit_id'] as String?,
          body: [
            '${row['body'] ?? ''}',
            for (final reply in replies['${row['id']}'] ?? <Map>[])
              '@${author(reply)}: ${reply['body'] ?? ''}',
          ].join('\n'),
          at: DateTime.tryParse('${row['created_at']}') ?? DateTime(1970),
        ),
  ];
}

/// Row of a PR comment in the spec's review history (or, with no spec, the
/// session's: SPEC-050 P1): keyed by its id on the host, so reading the PR
/// again never duplicates it.
ReviewCommentsCompanion prCommentRow(
  int? specId,
  int round,
  PrComment c, {
  String? sessionId,
}) => ReviewCommentsCompanion.insert(
  specId: Value(specId),
  sessionId: Value(specId == null ? sessionId : null),
  round: round,
  author: 'pr',
  body: '@${c.author}: ${c.body}',
  externalId: Value(c.externalId),
  path: Value(c.path),
  line: Value(c.line),
  commitSha: Value(c.commitSha),
  verdict: Value(c.kind.contains('CHANGES') ? 'corrigir' : null),
);

/// The run and the job of a GitHub Actions check, from its `detailsUrl`
/// (`…/actions/runs/<run>/job/<job>`); null when it is not one.
({int run, int? job})? actionsRunOf(String? url) {
  final m = RegExp(r'/actions/runs/(\d+)(?:/jobs?/(\d+))?')
      .firstMatch(url ?? '');
  if (m == null) return null;
  return (run: int.parse(m[1]!), job: m[2] == null ? null : int.parse(m[2]!));
}

/// One check of a PR (SPEC-073 R1): a GitHub Actions job (with the run and
/// the job of its log) or anything else (a `StatusContext`, another app),
/// which has no log the app can read (R9).
@immutable
class PrCheck {
  const PrCheck({
    required this.name,
    required this.state,
    this.workflow = '',
    this.url,
    this.runId,
    this.jobId,
  });

  final String name;

  /// `SUCCESS` / `FAILURE` / `PENDING` / `IN_PROGRESS`…
  final String state;

  /// Workflow of an Actions check ('' = unknown or not Actions).
  final String workflow;

  /// Page of the check on the host.
  final String? url;
  final int? runId, jobId;

  /// `gh run view <run> --log-failed` serves its log.
  bool get hasLog => runId != null;

  CiState get ci => ciStateOf([state]);
  bool get failed => ci == CiState.failed;
  bool get running => ci == CiState.running;

  @override
  bool operator ==(Object other) =>
      other is PrCheck &&
      other.name == name &&
      other.state == state &&
      other.workflow == workflow &&
      other.url == url &&
      other.runId == runId &&
      other.jobId == jobId;

  @override
  int get hashCode => Object.hash(name, state, workflow, url, runId, jobId);

  @override
  String toString() => 'PrCheck($name, $state)';
}

/// The check of a `statusCheckRollup` entry (null = not a map).
PrCheck? parsePrCheck(Object? c) {
  if (c is! Map) return null;
  String text(Object? v) => v == null ? '' : '$v'.trim();
  final status = text(c['conclusion']).isNotEmpty
      ? text(c['conclusion'])
      : text(c['state']).isNotEmpty
      ? text(c['state'])
      : text(c['status']);
  final context = c['__typename'] == 'StatusContext' || c['context'] != null;
  final url = text(c['detailsUrl']).isNotEmpty
      ? text(c['detailsUrl'])
      : text(c['targetUrl']);
  final run = context ? null : actionsRunOf(url);
  return PrCheck(
    name: text(c['name']).isNotEmpty
        ? text(c['name'])
        : text(c['context']).isNotEmpty
        ? text(c['context'])
        : '?',
    state: status.toUpperCase(),
    workflow: text(c['workflowName']),
    url: url.isEmpty ? null : url,
    runId: run?.run,
    jobId: run?.job,
  );
}

/// What `gh pr view --json …` says about a PR.
@immutable
class PrStatus {
  const PrStatus({
    required this.state,
    this.mergeable = 'UNKNOWN',
    this.reviewDecision = '',
    this.comments = const [],
    this.checks = const [],
    this.headSha = '',
  });

  /// `OPEN` / `MERGED` / `CLOSED`.
  final String state;

  /// `MERGEABLE` / `CONFLICTING` / `UNKNOWN`.
  final String mergeable;

  /// `APPROVED` / `CHANGES_REQUESTED` / `REVIEW_REQUIRED` / ''.
  final String reviewDecision;
  final List<PrComment> comments;
  final List<PrCheck> checks;

  /// The PR's commit (`headRefOid`; '' = unknown).
  final String headSha;

  bool get open => state == 'OPEN';
  bool get conflicting => mergeable == 'CONFLICTING';

  List<PrCheck> get failedChecks => [
    for (final c in checks)
      if (c.failed) c,
  ];

  /// The CI of the PR's commit.
  CiState get ci => ciStateOf(checks.map((c) => c.state));

  String get summary {
    final failed = checks.where((c) => c.failed).length;
    final pending = checks.where((c) => c.running).length;
    return [
      switch (state) {
        'MERGED' => 'mergeado',
        'CLOSED' => 'fechado',
        _ => 'aberto',
      },
      if (conflicting) 'com conflito',
      if (checks.isNotEmpty)
        failed > 0
            // SPEC-073 R2: "2 de 5 checks falharam".
            ? '$failed de ${checks.length} '
                  '${checks.length == 1 ? 'check' : 'checks'} '
                  '${failed == 1 ? 'falhou' : 'falharam'}'
            : pending > 0
            ? '$pending check(s) rodando'
            : 'checks ✓',
      if (headSha.isNotEmpty)
        'commit ${headSha.substring(0, headSha.length.clamp(0, 7))}',
      switch (reviewDecision) {
        'APPROVED' => 'aprovado',
        'CHANGES_REQUESTED' => 'mudanças pedidas',
        'REVIEW_REQUIRED' => 'aguardando review',
        _ => null,
      },
      '${comments.length} comentário(s)',
    ].whereType<String>().join(' · ');
  }
}

/// Fields asked to `gh pr view --json`.
const prViewFields =
    'state,mergeable,reviewDecision,comments,reviews,statusCheckRollup,'
    'headRefOid';

/// Parses the JSON of `gh pr view --json [prViewFields]` (null = invalid).
PrStatus? parsePrView(String text) {
  Object? j;
  try {
    j = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (j is! Map) return null;
  String login(Object? a) => a is Map ? '${a['login'] ?? '?'}' : '?';
  DateTime when(Object? v) => DateTime.tryParse('${v ?? ''}') ?? DateTime(1970);
  final comments = <PrComment>[
    for (final c in (j['comments'] as List? ?? const []))
      if (c is Map && '${c['body'] ?? ''}'.trim().isNotEmpty)
        PrComment(
          externalId: c['id'] == null ? null : 'github:${c['id']}',
          author: login(c['author']),
          body: '${c['body']}'.trim(),
          at: when(c['createdAt']),
        ),
    for (final r in (j['reviews'] as List? ?? const []))
      if (r is Map && '${r['body'] ?? ''}'.trim().isNotEmpty)
        PrComment(
          externalId: r['id'] == null ? null : 'github:${r['id']}',
          author: login(r['author']),
          body: '${r['body']}'.trim(),
          at: when(r['submittedAt']),
          kind: 'review: ${r['state'] ?? ''}',
        ),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return PrStatus(
    state: '${j['state'] ?? 'OPEN'}',
    mergeable: '${j['mergeable'] ?? 'UNKNOWN'}',
    reviewDecision: '${j['reviewDecision'] ?? ''}',
    comments: comments,
    headSha: '${j['headRefOid'] ?? ''}',
    checks: [
      for (final c in (j['statusCheckRollup'] as List? ?? const []))
        ?parsePrCheck(c),
    ],
  );
}

/// Message to the session with the PR comments it has not seen.
String prCommentsMessage(List<PrComment> comments) {
  final b = StringBuffer('Comentários novos no pull request:\n');
  for (final c in comments) {
    b
      ..writeln()
      ..writeln('@${c.author} (${c.kind}):')
      ..writeln(
        '${c.path == null ? '' : '${c.path}:${c.line ?? 0} — '}${c.body.substring(0, c.body.length.clamp(0, 4000))}',
      );
  }
  b
    ..writeln()
    ..write(
      'Faça os ajustes no worktree, rode os testes e faça commit; o '
      'Promptorium envia a branch para o PR.',
    );
  return b.toString();
}

/// Message of "Resolver conflito".
String conflictMessage(String base) =>
    'A branch tem conflito com $base. No worktree: rode `git fetch` (se '
    'houver remote) e `git merge $base`, resolva os conflitos mantendo o '
    'que as duas versões precisam, rode os testes e faça commit do merge. '
    '$howResolvedInstruction';

/// What the babysitter knows about one watched PR.
@immutable
class PrWatch {
  const PrWatch({this.status, this.checkedAt, this.error});

  final PrStatus? status;
  final DateTime? checkedAt;
  final String? error;
}

/// "Acompanhar PR" (F16): every few minutes (`main.dart` calls [tick];
/// no timer here) the watched PRs are read with `gh pr view --json`; new
/// comments go to the session as a correction round, the commits the
/// agent makes are pushed, and merge / conflict become notifications.
class PrBabysitter extends Notifier<Map<String, PrWatch>> {
  static const settingKey = 'pr.babysit';
  static String seenKey(String sessionId) => 'pr.seen.$sessionId';

  @override
  Map<String, PrWatch> build() => const {};

  AppSettingsController get _settings => ref.read(appSettingsProvider.notifier);

  Set<String> get watched => {
    for (final s in (_settings.get(settingKey) ?? '').split(','))
      if (s.isNotEmpty) s,
  };

  bool isWatching(String sessionId) => watched.contains(sessionId);

  Future<void> toggle(String sessionId) async {
    final w = watched;
    if (!w.remove(sessionId)) {
      w.add(sessionId);
      // Comments made before watching are not news.
      await _settings.set(seenKey(sessionId), DateTime.now().toIso8601String());
    }
    await _settings.set(settingKey, w.join(','));
    if (w.contains(sessionId)) await check(sessionId);
    state = {...state};
  }

  Future<void> tick() async {
    for (final id in watched) {
      await check(id);
    }
  }

  /// Checks running, one per session (SPEC-071 R2).
  final _checking = <String, Future<void>>{};

  /// Reads the PR of [sessionId] and acts on what changed. A PR not in
  /// "Acompanhar PR" only gets its status refreshed (SPEC-071 R2); a check
  /// already running for the session is joined, not repeated.
  Future<void> check(String sessionId) {
    final running = _checking[sessionId];
    if (running != null) return running;
    final job = _check(sessionId).whenComplete(() {
      // Block body: returning the removed Future would await itself.
      _checking.remove(sessionId);
    });
    return _checking[sessionId] = job;
  }

  Future<void> _check(String sessionId) async {
    final review = ref.read(reviewServiceProvider);
    final PrStatus? status;
    try {
      status = await review.prView(sessionId);
    } catch (e) {
      state = {
        ...state,
        sessionId: PrWatch(
          status: state[sessionId]?.status,
          error: '$e',
          checkedAt: DateTime.now(),
        ),
      };
      return;
    }
    if (status == null) return;
    final previous = state[sessionId]?.status;
    state = {
      ...state,
      sessionId: PrWatch(status: status, checkedAt: DateTime.now()),
    };
    // SPEC-073 R7: the CI of a fix's commit.
    final ciPhase = ref
        .read(ciFixerProvider.notifier)
        .onStatus(sessionId, status);
    // Not watched: "Verificar PR" only refreshes the status — no comments
    // to the agent, no round, no push.
    if (!isWatching(sessionId)) return;
    final s = await ref.read(sessionsRepoProvider).getById(sessionId);
    if (s == null) return;
    final title = s.title ?? sessionId;
    if (!status.open) {
      if (previous?.open ?? true) {
        _notify(
          status.state == 'MERGED' ? 'PR mergeado' : 'PR fechado',
          title,
          sessionId,
        );
      }
      final w = watched..remove(sessionId);
      await _settings.set(settingKey, w.join(','));
      return;
    }
    if (status.conflicting && !(previous?.conflicting ?? false)) {
      _notify('PR com conflito', title, sessionId);
    }
    if (ciPhase == CiFixPhase.stopped) {
      _notify(
        'O CI continua vermelho depois da correção automática',
        title,
        sessionId,
      );
    }
    // New comments → a correction round in the same session.
    final seen =
        DateTime.tryParse(_settings.get(seenKey(sessionId)) ?? '') ??
        DateTime(1970);
    final news = [
      for (final c in status.comments)
        if (c.at.isAfter(seen)) c,
    ];
    if (news.isNotEmpty) {
      await _settings.set(seenKey(sessionId), news.last.at.toIso8601String());
      await _recordRound(s, news);
      try {
        await ref
            .read(sessionManagerProvider.notifier)
            .send(sessionId, prCommentsMessage(news));
      } catch (e) {
        debugPrint('PR $sessionId: comentários não enviados — $e');
      }
      return;
    }
    // SPEC-073 R11, R12: the CI fixed without the user, once per commit.
    try {
      if (await _autoFixCi(s, status, title)) return;
    } catch (e) {
      debugPrint('PR $sessionId: correção automática do CI — $e');
    }
    // The agent's commits go to the PR when the session is idle.
    if (ref.read(sessionManagerProvider).live[sessionId]?.busy ?? false) return;
    try {
      await review.pushIfAhead(sessionId);
    } catch (e) {
      debugPrint('PR $sessionId: push não feito — $e');
    }
  }

  /// `review: corrigir-ci: automatico` (SPEC-073 R11, R12): with every
  /// check of a red commit finished, one fix per commit (an intermittent
  /// log runs again once first). The fix's own commit red stops it, until
  /// the CI is green or the user fixes or reruns by hand. Returns true when
  /// it acted.
  Future<bool> _autoFixCi(Session s, PrStatus status, String title) async {
    // SPEC-076 R8: "Pausar automáticos" holds the automatic fix.
    if (automationPaused(ref)) return false;
    final fixer = ref.read(ciFixerProvider.notifier);
    final id = s.id;
    final head = status.headSha;
    if (head.isEmpty) return false;
    final rec = fixer.record(id);
    final ci = status.ci;
    if (ci == CiState.passed && rec.stopped) {
      await _settings.set(
        CiRecord.key(id),
        rec.copyWith(stopped: false).encode(),
      );
      return false;
    }
    // One message covers every failure: wait for the checks to finish.
    if (ci != CiState.failed || status.checks.any((c) => c.running)) {
      return false;
    }
    final current = fixer.state[id]?.phase;
    if (current == CiFixPhase.queued ||
        current == CiFixPhase.fixing ||
        current == CiFixPhase.running ||
        current == CiFixPhase.rerunning ||
        current == CiFixPhase.stopped) {
      return false;
    }
    // The automatic fix's commit is red too (the app may have restarted
    // in between): stop and say so (R12).
    if (rec.auto && rec.fixSha == head && !rec.stopped) {
      await fixer.markStopped(id, head);
      _notify(
        'O CI continua vermelho depois da correção automática',
        title,
        id,
      );
      return true;
    }
    final ws = await ref.read(workspacesRepoProvider).getById(s.workspaceId);
    final config = ws == null ? null : ProjectConfig.loadSync(ws.path);
    if (config == null || !config.autoFixCi) return false;
    // R10: never on a PR brought without write permission.
    if (rec.stopped || fixer.pushBlocked(id) || rec.sha == head) return false;
    final failure = await fixer.failure(id, status);
    // P6: a check without log never goes to the agent.
    if (failure.blockReason != null) return false;
    final spec = s.specId == null
        ? null
        : await ref.read(specsRepoProvider).getById(s.specId!);
    final label = spec?.code ?? title;
    // P5: an intermittent failure runs again once before the fix.
    if (failure.excerpt.flaky != null && rec.rerunSha != head) {
      await fixer.rerun(id, auto: true);
      _notify('Rodando de novo o CI de $label sozinho', title, id);
      return true;
    }
    if (await fixer.fix(id, auto: true)) {
      _notify('Corrigindo o CI de $label sozinho', title, id);
    }
    return true;
  }

  Future<void> _recordRound(Session s, List<PrComment> news) async {
    final specId = s.specId;
    final repo = ref.read(reviewCommentsRepoProvider);
    final rounds =
        (specId != null
                ? await repo.bySpec(specId)
                : await repo.bySession(s.id))
            .map((c) => c.round);
    final round = rounds.isEmpty
        ? 1
        : rounds.reduce((a, b) => a > b ? a : b) + 1;
    for (final c in news) {
      await repo.insertExternal(
        prCommentRow(specId, round, c, sessionId: s.id),
      );
    }
  }

  void _notify(String title, String body, String sessionId) {
    unawaited(ref.read(appNotifierProvider).show(title, body));
    unawaited(
      ref
          .read(notificationsRepoProvider)
          .add(
            title: title,
            body: body,
            section: 'review',
            sessionId: sessionId,
          )
          .catchError((_) {}),
    );
  }
}

final prBabysitterProvider =
    NotifierProvider<PrBabysitter, Map<String, PrWatch>>(PrBabysitter.new);

/// `gh pr merge` methods.
enum PrMergeMethod {
  squash('--squash', 'Squash'),
  rebase('--rebase', 'Rebase'),
  merge('--merge', 'Merge commit');

  const PrMergeMethod(this.flag, this.label);

  final String flag;
  final String label;
}

/// Whether [git] has commits not on its upstream.
Future<bool> aheadOfUpstream(GitService git) async {
  try {
    final n = await git.git(['rev-list', '--count', '@{u}..HEAD']);
    return (int.tryParse(n.trim()) ?? 0) > 0;
  } on GitException {
    return false;
  }
}
