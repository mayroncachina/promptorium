import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/gh_cli.dart';
import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../sessions/session_manager.dart';
import 'ci_log.dart';
import 'pr_babysitter.dart';
import 'pr_import.dart';
import 'review_service.dart';

/// Author of the rows of the CI fixes in the spec's review history
/// (SPEC-073 R4): resolved and in round 0, like the conflict resolutions,
/// so never an open comment nor a review round.
const ciFixAuthor = 'ci';

/// What the agent answers when the failure is not the code's (R4).
const ciExternalPrefix = 'CI: falha externa';

/// A user-facing failure of "Corrigir CI" / "Rodar de novo".
class CiFixException implements Exception {
  const CiFixException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where a CI fix is (SPEC-073 R5–R8, R12): what the card's badge and the
/// Review show.
enum CiFixPhase {
  /// The session is busy: the message goes when the turn ends (R5).
  queued,

  /// The agent is fixing (the message went to the session).
  fixing,

  /// The app pushed the fix; the CI runs on the new commit.
  running,

  /// "Rodar de novo": the failed jobs run again (R8).
  rerunning,

  /// The CI passed on the fix's commit (until the next event of the PR).
  fixed,

  /// The automatic fix's commit is red too: the automatic stops (R12).
  stopped,

  /// The agent finished without a commit (R6).
  noCommit,

  /// The agent answered [ciExternalPrefix] (R6).
  external,

  /// The push was refused (R6).
  pushRefused,

  /// A PR brought into the app without write permission: the commit stays
  /// local (R10).
  local,
}

/// The CI fix of one session.
@immutable
class CiFixState {
  const CiFixState({
    required this.phase,
    required this.since,
    this.sha = '',
    this.checks = 0,
    this.detail,
    this.pushedSha,
    this.attempt = 0,
    this.auto = false,
    this.round = 0,
    this.headBefore,
  });

  final CiFixPhase phase;

  /// When [phase] started.
  final DateTime since;

  /// The red commit being fixed.
  final String sha;

  /// Failed checks sent to the agent.
  final int checks;

  /// The agent's answer, git's reason or the gh error.
  final String? detail;

  /// Commit the app pushed (running / fixed / stopped).
  final String? pushedSha;

  /// "Rodar de novo" attempt (2 = the first rerun).
  final int attempt;

  /// Started by the automatic (R11).
  final bool auto;

  /// CI1, CI2… of the session.
  final int round;

  /// HEAD of the worktree when the message went (a commit = HEAD moved).
  final String? headBefore;

  /// A fix is on its way: "Corrigir CI" does not send again (R4).
  bool get inFlight => phase == CiFixPhase.queued || phase == CiFixPhase.fixing;

  CiFixState copyWith({
    CiFixPhase? phase,
    String? detail,
    String? pushedSha,
    int? attempt,
  }) => CiFixState(
    phase: phase ?? this.phase,
    since: phase == null || phase == this.phase ? since : DateTime.now(),
    sha: sha,
    checks: checks,
    detail: detail ?? this.detail,
    pushedSha: pushedSha ?? this.pushedSha,
    attempt: attempt ?? this.attempt,
    auto: auto,
    round: round,
    headBefore: headBefore,
  );
}

/// `pr.ci.<sessão>` in `app_settings` (R11): the last red commit a fix was
/// sent for and by whom, the commit that fix pushed, whether the automatic
/// stopped, the commit already run again by the automatic and the count of
/// fixes and reruns. Durable state that needs no table.
@immutable
class CiRecord {
  const CiRecord({
    this.sha = '',
    this.auto = false,
    this.fixSha,
    this.stopped = false,
    this.rerunSha,
    this.rounds = 0,
    this.reruns = 0,
  });

  static String key(String sessionId) => 'pr.ci.$sessionId';

  final String sha;
  final bool auto;
  final String? fixSha;
  final bool stopped;
  final String? rerunSha;
  final int rounds;
  final int reruns;

  CiRecord copyWith({
    String? sha,
    bool? auto,
    String? Function()? fixSha,
    bool? stopped,
    String? rerunSha,
    int? rounds,
    int? reruns,
  }) => CiRecord(
    sha: sha ?? this.sha,
    auto: auto ?? this.auto,
    fixSha: fixSha == null ? this.fixSha : fixSha(),
    stopped: stopped ?? this.stopped,
    rerunSha: rerunSha ?? this.rerunSha,
    rounds: rounds ?? this.rounds,
    reruns: reruns ?? this.reruns,
  );

  String encode() => jsonEncode({
    'sha': sha,
    'origem': auto ? 'automatico' : 'voce',
    'correcao': ?fixSha,
    if (stopped) 'parado': true,
    'rodou-de-novo': ?rerunSha,
    'rodadas': rounds,
    'tentativas': reruns,
  });

  static CiRecord decode(String? text) {
    if (text == null || text.isEmpty) return const CiRecord();
    try {
      final j = jsonDecode(text);
      if (j is! Map) return const CiRecord();
      return CiRecord(
        sha: '${j['sha'] ?? ''}',
        auto: j['origem'] == 'automatico',
        fixSha: j['correcao'] as String?,
        stopped: j['parado'] == true,
        rerunSha: j['rodou-de-novo'] as String?,
        rounds: (j['rodadas'] as num?)?.toInt() ?? 0,
        reruns: (j['tentativas'] as num?)?.toInt() ?? 0,
      );
    } on FormatException {
      return const CiRecord();
    }
  }
}

/// The failed checks of a PR's commit with the excerpt of their logs.
@immutable
class CiFailure {
  const CiFailure({
    required this.sha,
    required this.total,
    required this.failed,
    this.excerpt = const CiLogExcerpt(),
    this.logErrors = const {},
  });

  final String sha;

  /// Every check of the commit.
  final int total;
  final List<PrCheck> failed;
  final CiLogExcerpt excerpt;

  /// Runs whose log could not be read (gh's error).
  final Map<int, String> logErrors;

  List<PrCheck> get withLog => [
    for (final c in failed)
      if (c.hasLog) c,
  ];

  List<PrCheck> get withoutLog => [
    for (final c in failed)
      if (!c.hasLog) c,
  ];

  /// The runs that failed, in order.
  List<int> get runs => {for (final c in withLog) c.runId!}.toList();

  /// Why "Corrigir CI" is off (R9); null = it can run.
  String? get blockReason => failed.isEmpty
      ? 'Nenhum check falhou neste commit'
      : withLog.isEmpty
      ? 'Nenhum check com log do GitHub Actions'
      : null;

  /// The excerpt of a check (its job, or a job of its matrix group).
  CiJobExcerpt? excerptOf(PrCheck c) => excerpt.jobs
      .where((j) => j.job == c.name || j.alsoIn.contains(c.name))
      .firstOrNull;
}

String shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);

/// The PR's number in its URL (`…/pull/57` → `#57`).
String prLabel(String? url) {
  final m = RegExp(r'/pull/(\d+)').firstMatch(url ?? '');
  return m == null ? 'PR' : 'PR #${m[1]}';
}

/// Message of "Corrigir CI" (R4).
String ciFixMessage({required String pr, required CiFailure failure}) {
  final b = StringBuffer(
    'O CI do $pr falhou no commit ${shortSha(failure.sha)} '
    '(${failure.failed.length} de ${failure.total} checks).\n',
  );
  for (final j in failure.excerpt.jobs) {
    b
      ..writeln()
      ..writeln(
        [
          '## ${j.job}',
          if (j.step.isNotEmpty) j.step,
          if (j.alsoIn.isNotEmpty) 'mesmo erro em ${j.alsoIn.join(', ')}',
        ].join(' · '),
      );
    for (final l in j.lines) {
      b.writeln(l);
    }
  }
  if (failure.excerpt.omittedJobs.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        'Fora do teto do trecho (veja o log completo): '
        '${failure.excerpt.omittedJobs.join(', ')}.',
      );
  }
  for (final MapEntry(:key, :value) in failure.logErrors.entries) {
    b.writeln('Log do run $key não lido: $value');
  }
  if (failure.withoutLog.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        'Sem log (fora do Actions): '
        '${failure.withoutLog.map((c) => c.name).join(', ')}.',
      );
  }
  b
    ..writeln(
      'Log completo: '
      '${failure.runs.map((r) => 'gh run view $r --log-failed').join(' ; ')}',
    )
    ..writeln()
    ..writeln('1. Ache a causa. Não mude o teste para esconder a falha.')
    ..writeln('2. Corrija no worktree e rode os testes afetados e o lint.')
    ..writeln(
      '3. Faça commit, sem push. O Promptorium envia ao PR e acompanha o CI.',
    )
    ..write(
      'Se a falha não for do código (rede, runner, segredo ausente), não '
      'mude nada e responda começando com "$ciExternalPrefix: <motivo>".',
    );
  return b.toString();
}

/// "Corrigir CI" and "Rodar de novo" (SPEC-073): reads the logs of the
/// failed checks, sends them to the PR's session, pushes the agent's commit
/// when the turn ends and follows the CI of the new commit. One fix per red
/// commit ([CiRecord]).
class CiFixer extends Notifier<Map<String, CiFixState>> {
  @override
  Map<String, CiFixState> build() => const {};

  AppSettingsController get _settings => ref.read(appSettingsProvider.notifier);

  CiRecord record(String sessionId) =>
      CiRecord.decode(_settings.get(CiRecord.key(sessionId)));

  Future<void> _save(String sessionId, CiRecord r) =>
      _settings.set(CiRecord.key(sessionId), r.encode());

  void _set(String sessionId, CiFixState? s) {
    final next = {...state};
    if (s == null) {
      next.remove(sessionId);
    } else {
      next[sessionId] = s;
    }
    state = next;
  }

  /// Sessions whose turn is a CI fix: the spec stays in Review (R7, P3).
  bool isFixing(String sessionId) =>
      state[sessionId]?.phase == CiFixPhase.fixing;

  /// Messages waiting for a busy session (R5).
  final _queued = <String, String>{};

  /// "Corrigir CI" calls on their way (two clicks send once).
  final _starting = <String>{};

  final _failures = <String, (String, Future<CiFailure>)>{};

  /// The PR brought into the app without write permission (R10).
  bool pushBlocked(String sessionId) {
    final meta = importedPrOf(ref.read(appSettingsProvider), sessionId);
    return meta != null && !meta.canPush;
  }

  Future<GhCli> _gh(String sessionId) async {
    final s = await ref.read(sessionsRepoProvider).getById(sessionId);
    final ws = s == null
        ? null
        : await ref.read(workspacesRepoProvider).getById(s.workspaceId);
    if (ws == null) throw const CiFixException('Sessão sem workspace.');
    return GhCli(ref.read(commandRunnerProvider), cwd: ws.path);
  }

  /// The failure of [status]'s commit with the logs (cached per commit).
  Future<CiFailure> failure(String sessionId, PrStatus status) {
    final cached = _failures[sessionId];
    if (cached != null && cached.$1 == status.headSha && status.headSha != '') {
      return cached.$2;
    }
    final job = _load(sessionId, status);
    _failures[sessionId] = (status.headSha, job);
    // A failed read is tried again next time.
    job.catchError((Object _) {
      if (identical(_failures[sessionId]?.$2, job)) {
        _failures.remove(sessionId);
      }
      return CiFailure(sha: '', total: 0, failed: const []);
    });
    return job;
  }

  Future<CiFailure> _load(String sessionId, PrStatus status) async {
    final failed = status.failedChecks;
    final runs = {
      for (final c in failed)
        if (c.hasLog) c.runId!,
    };
    if (runs.isEmpty) {
      return CiFailure(
        sha: status.headSha,
        total: status.checks.length,
        failed: failed,
      );
    }
    final gh = await _gh(sessionId);
    final raw = StringBuffer();
    final jobRun = <String, int>{};
    final errors = <int, String>{};
    for (final run in runs) {
      try {
        final log = await gh.runFailedLogRaw(run);
        for (final line in const LineSplitter().convert(log)) {
          final tab = line.indexOf('\t');
          if (tab <= 0) continue;
          jobRun.putIfAbsent(line.substring(0, tab).trim(), () => run);
        }
        raw.writeln(log.trimRight());
      } on GhException catch (e) {
        errors[run] = '$e';
      }
    }
    int? runOf(String job) =>
        failed.where((c) => c.name == job).firstOrNull?.runId ?? jobRun[job];
    return CiFailure(
      sha: status.headSha,
      total: status.checks.length,
      failed: failed,
      excerpt: ciLogExcerpt('$raw', runOf: runOf),
      logErrors: errors,
    );
  }

  Future<PrStatus> _status(String sessionId) async {
    final known = ref.read(prBabysitterProvider)[sessionId]?.status;
    if (known != null) return known;
    final status = await ref.read(reviewServiceProvider).prView(sessionId);
    if (status == null) throw const CiFixException('A sessão não tem PR.');
    return status;
  }

  Future<String?> _head(String sessionId) async {
    final s = await ref.read(sessionsRepoProvider).getById(sessionId);
    if (s == null) return null;
    try {
      return await ref
          .read(gitServiceFactoryProvider)(s.worktreePath)
          .headSha();
    } on GitException {
      return null;
    }
  }

  /// "Corrigir CI" (R4): the logs of the failed checks go to the PR's
  /// session, which is resumed when it has no process; with the session
  /// busy, the message waits for the turn to end (R5). One fix at a time:
  /// a second call while one is on its way does nothing. Returns false when
  /// nothing was sent nor queued.
  Future<bool> fix(String sessionId, {bool auto = false}) async {
    if ((state[sessionId]?.inFlight ?? false) || !_starting.add(sessionId)) {
      return false;
    }
    try {
      final status = await _status(sessionId);
      if (!status.open) throw const CiFixException('O PR não está aberto.');
      final failure = await this.failure(sessionId, status);
      if (failure.blockReason case final reason?) {
        throw CiFixException(reason);
      }
      final s = await ref.read(sessionsRepoProvider).getById(sessionId);
      if (s == null) throw const CiFixException('Sessão não encontrada.');
      final message = ciFixMessage(pr: prLabel(s.prUrl), failure: failure);
      final r = record(sessionId);
      final round = r.rounds + 1;
      await _save(
        sessionId,
        r.copyWith(
          sha: failure.sha,
          auto: auto,
          fixSha: () => null,
          // A fix by hand gives the automatic back (R12).
          stopped: auto ? r.stopped : false,
          rounds: round,
        ),
      );
      final next = CiFixState(
        phase: CiFixPhase.fixing,
        since: DateTime.now(),
        sha: failure.sha,
        checks: failure.withLog.length,
        auto: auto,
        round: round,
        headBefore: await _head(sessionId),
      );
      final busy =
          ref.read(sessionManagerProvider).live[sessionId]?.busy ?? false;
      if (busy) {
        _queued[sessionId] = message;
        _set(sessionId, next.copyWith(phase: CiFixPhase.queued));
        return true;
      }
      await _send(sessionId, next, message);
      return true;
    } finally {
      _starting.remove(sessionId);
    }
  }

  Future<void> _send(String sessionId, CiFixState st, String message) async {
    _set(sessionId, st.copyWith(phase: CiFixPhase.fixing));
    final line =
        'Corrigir CI · commit ${shortSha(st.sha)} · ${st.checks} '
        '${st.checks == 1 ? 'check' : 'checks'} · rodada CI${st.round}'
        '${st.auto ? ' · automático' : ''}';
    final manager = ref.read(sessionManagerProvider.notifier);
    try {
      if (!sessionId.startsWith(vibeSessionPrefix)) {
        await manager.note(sessionId, line);
      }
      await _history(sessionId, line, st.sha);
      await manager.send(sessionId, message);
    } on SessionException catch (e) {
      _set(sessionId, null);
      throw CiFixException('$e');
    }
  }

  /// The row of the spec's history (R4): round 0, resolved.
  Future<void> _history(String sessionId, String body, String sha) async {
    final s = await ref.read(sessionsRepoProvider).getById(sessionId);
    if (s == null) return;
    try {
      await ref.read(reviewCommentsRepoProvider).insertAll([
        ReviewCommentsCompanion.insert(
          specId: Value(s.specId),
          sessionId: Value(s.specId == null ? sessionId : null),
          round: 0,
          author: ciFixAuthor,
          body: body,
          commitSha: Value(sha),
          resolved: const Value(true),
        ),
      ]);
    } catch (e) {
      debugPrint('histórico do CI não gravado — $e');
    }
  }

  /// "Cancelar" of a queued fix (R5).
  Future<void> cancel(String sessionId) async {
    if (state[sessionId]?.phase != CiFixPhase.queued) return;
    _queued.remove(sessionId);
    final r = record(sessionId);
    await _save(
      sessionId,
      r.copyWith(rounds: (r.rounds - 1).clamp(0, 1 << 30)),
    );
    _set(sessionId, null);
  }

  /// "Rodar de novo" (R8): `gh run rerun <run> --failed` in each run that
  /// failed. A rerun by hand gives the automatic back (R12).
  Future<void> rerun(String sessionId, {bool auto = false}) async {
    final status = await _status(sessionId);
    final runs = {
      for (final c in status.failedChecks)
        if (c.hasLog) c.runId!,
    };
    if (runs.isEmpty) {
      throw const CiFixException('Nenhum check com log do GitHub Actions');
    }
    final gh = await _gh(sessionId);
    for (final run in runs) {
      try {
        await gh.runRerunFailed(run);
      } on GhException catch (e) {
        throw CiFixException('$e');
      }
    }
    final r = record(sessionId);
    final attempt = r.reruns + 2;
    await _save(
      sessionId,
      r.copyWith(
        reruns: r.reruns + 1,
        stopped: auto ? r.stopped : false,
        rerunSha: auto ? status.headSha : null,
      ),
    );
    _set(
      sessionId,
      CiFixState(
        phase: CiFixPhase.rerunning,
        since: DateTime.now(),
        sha: status.headSha,
        attempt: attempt,
        auto: auto,
        round: r.rounds,
      ),
    );
  }

  /// End of a turn of [sessionId] (called by the [SessionManager]): a
  /// queued fix goes now; a running fix is checked and its commit pushed.
  Future<void> onResult(String sessionId, String? result) async {
    final st = state[sessionId];
    if (st == null) return;
    if (st.phase == CiFixPhase.queued) {
      final message = _queued.remove(sessionId);
      if (message == null) return;
      // Not awaited: send() enqueues behind the job of this event.
      unawaited(
        Future<void>.microtask(() async {
          try {
            await _send(sessionId, st, message);
          } catch (e) {
            debugPrint('CI $sessionId: correção não enviada — $e');
          }
        }),
      );
      return;
    }
    if (st.phase != CiFixPhase.fixing) return;
    unawaited(Future<void>.microtask(() => _finish(sessionId, st, result)));
  }

  /// The agent finished a fix (R6): external failure, no commit, the push
  /// refused, or the commit pushed and the CI followed.
  Future<void> _finish(String sessionId, CiFixState st, String? result) async {
    final answer = (result ?? '').trim();
    final r = record(sessionId);
    Future<void> stop() async {
      if (st.auto) await _save(sessionId, r.copyWith(stopped: true));
    }

    if (answer.startsWith(ciExternalPrefix)) {
      await stop();
      _set(
        sessionId,
        st.copyWith(phase: CiFixPhase.external, detail: _clip(answer)),
      );
      return;
    }
    final head = await _head(sessionId);
    if (head == null || head == st.headBefore) {
      await stop();
      _set(
        sessionId,
        st.copyWith(
          phase: CiFixPhase.noCommit,
          detail: answer.isEmpty ? null : _clip(answer),
        ),
      );
      return;
    }
    await _push(sessionId, st, head);
  }

  Future<void> _push(String sessionId, CiFixState st, String head) async {
    final r = record(sessionId);
    if (pushBlocked(sessionId)) {
      _set(sessionId, st.copyWith(phase: CiFixPhase.local, pushedSha: head));
      return;
    }
    try {
      await ref.read(reviewServiceProvider).pushIfAhead(sessionId);
    } catch (e) {
      if (st.auto) await _save(sessionId, r.copyWith(stopped: true));
      _set(
        sessionId,
        st.copyWith(phase: CiFixPhase.pushRefused, detail: _clip('$e')),
      );
      return;
    }
    await _save(sessionId, r.copyWith(fixSha: () => head));
    _set(sessionId, st.copyWith(phase: CiFixPhase.running, pushedSha: head));
    if (!sessionId.startsWith(vibeSessionPrefix)) {
      final s = await ref.read(sessionsRepoProvider).getById(sessionId);
      try {
        await ref
            .read(sessionManagerProvider.notifier)
            .note(
              sessionId,
              'Push feito pelo app · ${shortSha(head)} → ${prLabel(s?.prUrl)} '
              '· CI rodando',
            );
      } catch (e) {
        debugPrint('CI $sessionId: nota do push não gravada — $e');
      }
    }
  }

  /// "Tentar de novo" after a refused push (R6).
  Future<void> retryPush(String sessionId) async {
    final st = state[sessionId];
    if (st == null || st.phase != CiFixPhase.pushRefused) return;
    final head = await _head(sessionId);
    if (head == null) return;
    await _push(sessionId, st, head);
  }

  /// Hides the result of a fix (no commit, external, local).
  void dismiss(String sessionId) => _set(sessionId, null);

  static String _clip(String text) =>
      text.length <= 600 ? text : '${text.substring(0, 600)}…';

  /// What the babysitter read of the PR (R7): the CI of the fix's commit
  /// says whether it worked. Returns the new phase, if it changed.
  CiFixPhase? onStatus(String sessionId, PrStatus status) {
    final st = state[sessionId];
    if (st == null) return null;
    final head = status.headSha;
    switch (st.phase) {
      case CiFixPhase.running:
        if (st.pushedSha == null || head.isEmpty || head != st.pushedSha) {
          return null;
        }
        switch (status.ci) {
          case CiState.passed || CiState.none:
            _set(sessionId, st.copyWith(phase: CiFixPhase.fixed));
            return CiFixPhase.fixed;
          case CiState.failed:
            if (st.auto) {
              unawaited(
                _save(sessionId, record(sessionId).copyWith(stopped: true)),
              );
              _set(sessionId, st.copyWith(phase: CiFixPhase.stopped));
              return CiFixPhase.stopped;
            }
            _set(sessionId, null);
            return null;
          case CiState.running:
            return null;
        }
      case CiFixPhase.rerunning:
        if (head != st.sha) {
          _set(sessionId, null);
          return null;
        }
        switch (status.ci) {
          case CiState.passed || CiState.none:
            _set(sessionId, st.copyWith(phase: CiFixPhase.fixed));
            return CiFixPhase.fixed;
          case CiState.failed:
            // The failed jobs may not have restarted yet: wait for a
            // check that runs.
            if (DateTime.now().difference(st.since) >
                const Duration(minutes: 2)) {
              _set(sessionId, null);
            }
            return null;
          case CiState.running:
            return null;
        }
      case CiFixPhase.fixed:
        final done = st.pushedSha ?? st.sha;
        if (head.isNotEmpty && head != done) _set(sessionId, null);
        return null;
      case CiFixPhase.noCommit ||
          CiFixPhase.external ||
          CiFixPhase.pushRefused ||
          CiFixPhase.local:
        if (head.isNotEmpty && head != st.sha && head != st.pushedSha) {
          _set(sessionId, null);
        }
        return null;
      case CiFixPhase.stopped:
        // Green again: the automatic is back (R12).
        if (status.ci == CiState.passed) {
          unawaited(
            _save(sessionId, record(sessionId).copyWith(stopped: false)),
          );
          _set(sessionId, null);
        }
        return null;
      case CiFixPhase.fixing:
        // The PR got a new commit while fixing (a VIBE, whose turns end in
        // its conversation, pushed by the babysitter): the CI runs on it.
        if (head.isNotEmpty && st.sha.isNotEmpty && head != st.sha) {
          _set(
            sessionId,
            st.copyWith(phase: CiFixPhase.running, pushedSha: head),
          );
          return CiFixPhase.running;
        }
        return null;
      case CiFixPhase.queued:
        return null;
    }
  }
}

final ciFixerProvider = NotifierProvider<CiFixer, Map<String, CiFixState>>(
  CiFixer.new,
);
