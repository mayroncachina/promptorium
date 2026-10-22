import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../sessions/app_notifier.dart';
import '../sessions/session_manager.dart';
import 'review_service.dart';

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

/// What `gh pr view --json …` says about a PR.
@immutable
class PrStatus {
  const PrStatus({
    required this.state,
    this.mergeable = 'UNKNOWN',
    this.reviewDecision = '',
    this.comments = const [],
    this.checks = const [],
  });

  /// `OPEN` / `MERGED` / `CLOSED`.
  final String state;

  /// `MERGEABLE` / `CONFLICTING` / `UNKNOWN`.
  final String mergeable;

  /// `APPROVED` / `CHANGES_REQUESTED` / `REVIEW_REQUIRED` / ''.
  final String reviewDecision;
  final List<PrComment> comments;

  /// (name, `SUCCESS` / `FAILURE` / `PENDING`…).
  final List<(String, String)> checks;

  bool get open => state == 'OPEN';
  bool get conflicting => mergeable == 'CONFLICTING';

  String get summary {
    final failed = checks.where((c) => c.$2 == 'FAILURE').length;
    final pending = checks
        .where((c) => c.$2 != 'SUCCESS' && c.$2 != 'FAILURE')
        .length;
    return [
      switch (state) {
        'MERGED' => 'mergeado',
        'CLOSED' => 'fechado',
        _ => 'aberto',
      },
      if (conflicting) 'com conflito',
      if (checks.isNotEmpty)
        failed > 0
            ? '$failed check(s) falhando'
            : pending > 0
            ? '$pending check(s) rodando'
            : 'checks ✓',
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
    'state,mergeable,reviewDecision,comments,reviews,statusCheckRollup';

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
    checks: [
      for (final c in (j['statusCheckRollup'] as List? ?? const []))
        if (c is Map)
          (
            '${c['name'] ?? c['context'] ?? '?'}',
            '${c['conclusion'] ?? c['state'] ?? c['status'] ?? ''}'
                .toUpperCase(),
          ),
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
    'Explique na resposta como resolveu cada conflito.';

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

  /// Reads the PR of [sessionId] and acts on what changed.
  Future<void> check(String sessionId) async {
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
    // The agent's commits go to the PR when the session is idle.
    if (ref.read(sessionManagerProvider).live[sessionId]?.busy ?? false) return;
    try {
      await review.pushIfAhead(sessionId);
    } catch (e) {
      debugPrint('PR $sessionId: push não feito — $e');
    }
  }

  Future<void> _recordRound(Session s, List<PrComment> news) async {
    final specId = s.specId;
    if (specId == null) return;
    final repo = ref.read(reviewCommentsRepoProvider);
    final rounds = (await repo.bySpec(specId)).map((c) => c.round);
    final round = rounds.isEmpty
        ? 1
        : rounds.reduce((a, b) => a > b ? a : b) + 1;
    for (final c in news) {
      await repo.insertExternal(
        ReviewCommentsCompanion.insert(
          specId: specId,
          round: round,
          author: 'pr',
          body: '@${c.author}: ${c.body}',
          externalId: Value(c.externalId),
          path: Value(c.path),
          line: Value(c.line),
          commitSha: Value(c.commitSha),
          verdict: Value(c.kind.contains('CHANGES') ? 'corrigir' : null),
        ),
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
