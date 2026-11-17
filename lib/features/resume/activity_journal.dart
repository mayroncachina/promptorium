import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/git/gh_cli.dart' show CiState;
import '../../data/providers.dart';
import '../../data/repos/activity_events_repo.dart';
import '../activities/activity.dart' show specSeed;
import '../board/board_screen.dart' show specStepsProvider;
import '../board/step_gate.dart';
import '../prompt/conversation_manager.dart';
import '../repository/releases/release_dispatcher.dart';
import '../review/ci_fixer.dart';
import '../review/pr_babysitter.dart';
import '../sessions/session_manager.dart';

/// The journal of "Retomar de onde parei" (SPEC-080 R6): what finished,
/// written as it finishes. The transitions are pure functions over what
/// the app already follows (specs and steps, PRs, Corrigir CI, releases,
/// sessions and conversations); [ActivityJournal] feeds them.

/// What finished (the `kind` column).
enum JournalKind {
  spec('SPEC'),
  gate('GATE'),
  pr('PR'),
  ci('CI'),
  release('RELEASE'),
  session('SESSÃO'),
  conversation('PROMPT'),
  autopilot('AUTOPILOT');

  const JournalKind(this.tag);

  /// The badge of the card's item (R5).
  final String tag;

  static JournalKind parse(String v) =>
      values.where((k) => k.name == v).firstOrNull ?? JournalKind.session;
}

/// How it finished (R6): ✓, ✕ or ! on the card (R15).
enum JournalOutcome {
  ok('✓'),
  failed('✕'),
  attention('!');

  const JournalOutcome(this.mark);

  final String mark;

  static JournalOutcome parse(String v) =>
      values.where((k) => k.name == v).firstOrNull ?? JournalOutcome.ok;
}

/// A turn longer than this enters the journal (R6).
const longTurn = Duration(minutes: 2);

/// One event of the journal.
@immutable
class JournalEntry {
  const JournalEntry({
    required this.workspaceId,
    required this.kind,
    required this.outcome,
    required this.title,
    required this.at,
    this.detail = '',
    this.seed,
    this.specId,
    this.sessionId,
    this.conversationId,
    this.prNumber,
    this.releaseTag,
    this.fixedGroupKey,
    this.id,
  });

  final int? id;
  final int workspaceId;
  final JournalKind kind;
  final JournalOutcome outcome;

  /// `SPEC-077 · Copiar código`, `PR #267`, `v0.18.0`.
  final String title;

  /// `passou no gate · R1–R4`, `mergeado`.
  final String detail;
  final String? seed;
  final int? specId;
  final String? sessionId;
  final int? conversationId;
  final int? prNumber;
  final String? releaseTag;
  final DateTime at;

  /// A key given by hand (else [groupKey] picks one).
  final String? fixedGroupKey;

  /// What joins events into one item (R8): the spec, else the PR, the
  /// release, the session or the conversation.
  String get groupKey =>
      fixedGroupKey ??
      (specId != null
          ? 'spec:$specId'
          : prNumber != null
          ? 'pr:$workspaceId:$prNumber'
          : releaseTag != null
          ? 'release:$workspaceId:$releaseTag'
          : sessionId != null
          ? 'session:$sessionId'
          : conversationId != null
          ? 'conv:$conversationId'
          : '${kind.name}:$workspaceId');

  ActivityEventsCompanion toCompanion() => ActivityEventsCompanion.insert(
    workspaceId: workspaceId,
    kind: kind.name,
    outcome: outcome.name,
    title: title,
    detail: Value(detail),
    seed: Value(seed),
    specId: Value(specId),
    sessionId: Value(sessionId),
    conversationId: Value(conversationId),
    prNumber: Value(prNumber),
    releaseTag: Value(releaseTag),
    groupKey: groupKey,
    at: at,
  );

  static JournalEntry fromRow(ActivityEvent e) => JournalEntry(
    id: e.id,
    workspaceId: e.workspaceId,
    kind: JournalKind.parse(e.kind),
    outcome: JournalOutcome.parse(e.outcome),
    title: e.title,
    detail: e.detail,
    seed: e.seed,
    specId: e.specId,
    sessionId: e.sessionId,
    conversationId: e.conversationId,
    prNumber: e.prNumber,
    releaseTag: e.releaseTag,
    fixedGroupKey: e.groupKey,
    at: e.at,
  );

  @override
  String toString() => '${kind.name}/${outcome.name} $title · $detail';
}

/// `#267` of a PR url (null = none).
int? prNumberOf(String? url) {
  final m = RegExp(r'/pull/(\d+)').firstMatch(url ?? '');
  return m == null ? null : int.parse(m[1]!);
}

/// What the journal knows of a session: its workspace, its spec, its PR.
typedef JournalSession = ({
  String id,
  int workspaceId,
  String title,
  Spec? spec,
  String? prUrl,
});

String _specTitle(Spec s) => '${s.code} · ${s.title}';

/// `R1–R4` or `R1, R3` of the ids of [steps] (the gate's line, R5).
String stepRange(List<String> steps) {
  if (steps.isEmpty) return '';
  if (steps.length == 1) return steps.single;
  final nums = [for (final s in steps) int.tryParse(s.replaceAll('R', ''))];
  final simple = steps.every((s) => RegExp(r'^R\d+$').hasMatch(s));
  if (simple) {
    final n = nums.cast<int>()..sort();
    final consecutive = [for (var i = 1; i < n.length; i++) n[i] - n[i - 1]]
        .every((d) => d == 1);
    if (consecutive) return 'R${n.first}–R${n.last}';
  }
  return steps.join(', ');
}

/// Specs and their steps: a step done, the gate passed or failed, the spec
/// in Review or concluded (R6).
List<JournalEntry> specTransitions({
  required int workspaceId,
  required List<Spec> before,
  required List<Spec> after,
  required List<SpecStep> stepsBefore,
  required List<SpecStep> stepsAfter,
  required DateTime now,
}) {
  final out = <JournalEntry>[];
  final old = {for (final s in before) s.id: s};
  final specs = {for (final s in after) s.id: s};
  final oldSteps = {for (final r in stepsBefore) '${r.specId}:${r.step}': r};

  // The steps of each spec whose gate passed in this change (one event).
  final gatePassed = <int, List<String>>{};
  final gateFailed = <int, List<(String, GateReport)>>{};
  final stepDone = <int, List<String>>{};
  for (final r in stepsAfter) {
    final was = oldSteps['${r.specId}:${r.step}'];
    if (was == null) continue;
    final spec = specs[r.specId];
    if (spec == null) continue;
    final report = GateReport.decode(r.gateReport);
    final oldReport = GateReport.decode(was.gateReport);
    final newGate =
        report != null && (oldReport == null || report.at != oldReport.at);
    if (newGate && !report.ok) {
      (gateFailed[spec.id] ??= []).add((r.step, report));
    }
    if (was.doneAt == null && r.doneAt != null) {
      if (newGate || report != null && report.ok) {
        (gatePassed[spec.id] ??= []).add(r.step);
      } else {
        (stepDone[spec.id] ??= []).add(r.step);
      }
    }
  }
  for (final spec in after) {
    final seed = specSeed(workspaceId, spec.code);
    JournalEntry e(JournalKind k, JournalOutcome o, String detail) =>
        JournalEntry(
          workspaceId: workspaceId,
          kind: k,
          outcome: o,
          title: _specTitle(spec),
          detail: detail,
          seed: seed,
          specId: spec.id,
          at: now,
        );
    if (gatePassed[spec.id] case final steps?) {
      out.add(
        e(
          JournalKind.gate,
          JournalOutcome.ok,
          'passou no gate · ${stepRange(steps)}',
        ),
      );
    }
    if (stepDone[spec.id] case final steps?) {
      out.add(
        e(
          JournalKind.spec,
          JournalOutcome.ok,
          'terminou a etapa ${stepRange(steps)}',
        ),
      );
    }
    for (final (step, report)
        in gateFailed[spec.id] ?? const <(String, GateReport)>[]) {
      out.add(
        e(
          JournalKind.gate,
          JournalOutcome.failed,
          'falhou no gate em $step · ${report.summary}',
        ),
      );
    }
    final was = old[spec.id];
    if (was == null || was.stage == spec.stage) continue;
    if (spec.stage == SpecStage.review) {
      out.add(e(JournalKind.spec, JournalOutcome.ok, 'foi para Review'));
    } else if (spec.stage == SpecStage.done) {
      out.add(e(JournalKind.spec, JournalOutcome.ok, 'concluída'));
    }
  }
  return out;
}

/// The PR of a session: opened (the session got a `prUrl`), and any error
/// of the session (R6).
List<JournalEntry> sessionTransitions({
  required int workspaceId,
  required List<Session> before,
  required List<Session> after,
  required Map<int, Spec> specs,
  required DateTime now,
}) {
  final out = <JournalEntry>[];
  final old = {for (final s in before) s.id: s};
  for (final s in after) {
    final was = old[s.id];
    if (was == null) continue;
    final spec = specs[s.specId];
    final seed = spec == null
        ? 'session:${s.id}'
        : specSeed(workspaceId, spec.code);
    final title = spec == null ? sessionTitle(s) : _specTitle(spec);
    if (was.prUrl == null && s.prUrl != null) {
      final n = prNumberOf(s.prUrl);
      out.add(
        JournalEntry(
          workspaceId: workspaceId,
          kind: JournalKind.pr,
          outcome: JournalOutcome.ok,
          title: title,
          detail: n == null ? 'PR aberto' : 'PR #$n aberto',
          seed: seed,
          specId: spec?.id,
          sessionId: s.id,
          prNumber: n,
          at: now,
        ),
      );
    }
    if (was.status != SessionStatus.failed &&
        s.status == SessionStatus.failed) {
      out.add(
        JournalEntry(
          workspaceId: workspaceId,
          kind: JournalKind.session,
          outcome: JournalOutcome.failed,
          title: title,
          detail: 'parou com erro',
          seed: seed,
          specId: spec?.id,
          sessionId: s.id,
          at: now,
        ),
      );
    }
  }
  return out;
}

/// The PRs followed by the babysitter: merged, closed, CI passed or failed
/// (R6). [sessions] says whose PR it is.
List<JournalEntry> prTransitions({
  required Map<String, PrWatch> before,
  required Map<String, PrWatch> after,
  required Map<String, JournalSession> sessions,
  required DateTime now,
}) {
  final out = <JournalEntry>[];
  for (final MapEntry(key: id, value: w) in after.entries) {
    final status = w.status;
    final was = before[id]?.status;
    final s = sessions[id];
    if (status == null || was == null || s == null) continue;
    final n = prNumberOf(s.prUrl);
    final pr = n == null ? 'PR' : 'PR #$n';
    JournalEntry e(JournalKind k, JournalOutcome o, String detail) =>
        JournalEntry(
          workspaceId: s.workspaceId,
          kind: k,
          outcome: o,
          title: s.spec == null
              ? (n == null ? s.title : pr)
              : _specTitle(s.spec!),
          detail: detail,
          seed: s.spec == null
              ? 'session:${s.id}'
              : specSeed(s.workspaceId, s.spec!.code),
          specId: s.spec?.id,
          sessionId: s.id,
          prNumber: n,
          at: now,
        );
    if (was.open && !status.open) {
      out.add(
        status.state == 'MERGED'
            ? e(JournalKind.pr, JournalOutcome.ok, '$pr mergeado')
            : e(
                JournalKind.pr,
                JournalOutcome.attention,
                '$pr fechado sem merge',
              ),
      );
      continue;
    }
    if (!status.open) continue;
    final ci = status.ci;
    final changed = ci != was.ci || status.headSha != was.headSha;
    if (!changed || status.checks.any((c) => c.running)) continue;
    if (ci == CiState.passed && was.ci != CiState.passed) {
      out.add(e(JournalKind.ci, JournalOutcome.ok, 'CI do $pr passou'));
    } else if (ci == CiState.failed &&
        (was.ci != CiState.failed || status.headSha != was.headSha)) {
      final names = [for (final c in status.failedChecks) '`${c.name}`'];
      out.add(
        e(
          JournalKind.ci,
          JournalOutcome.failed,
          'CI do $pr falhou${names.isEmpty ? '' : ' em ${names.take(2).join(', ')}'}',
        ),
      );
    }
  }
  return out;
}

/// Corrigir CI finished: fixed, or gave up (R6).
List<JournalEntry> ciFixTransitions({
  required Map<String, CiFixState> before,
  required Map<String, CiFixState> after,
  required Map<String, JournalSession> sessions,
  required DateTime now,
}) {
  final out = <JournalEntry>[];
  for (final MapEntry(key: id, value: st) in after.entries) {
    final was = before[id]?.phase;
    if (was == st.phase) continue;
    final s = sessions[id];
    if (s == null) continue;
    final ok = st.phase == CiFixPhase.fixed;
    final gaveUp = switch (st.phase) {
      CiFixPhase.stopped ||
      CiFixPhase.noCommit ||
      CiFixPhase.external ||
      CiFixPhase.pushRefused => true,
      _ => false,
    };
    if (!ok && !gaveUp) continue;
    final n = prNumberOf(s.prUrl);
    out.add(
      JournalEntry(
        workspaceId: s.workspaceId,
        kind: JournalKind.ci,
        outcome: ok ? JournalOutcome.ok : JournalOutcome.failed,
        title: s.spec == null
            ? (n == null ? s.title : 'PR #$n')
            : _specTitle(s.spec!),
        detail: ok
            ? 'Corrigir CI corrigiu na rodada ${st.round}'
            : 'Corrigir CI desistiu na rodada ${st.round}',
        seed: s.spec == null
            ? 'session:${s.id}'
            : specSeed(s.workspaceId, s.spec!.code),
        specId: s.spec?.id,
        sessionId: s.id,
        prNumber: n,
        at: now,
      ),
    );
  }
  return out;
}

/// A release published or failed (R6).
List<JournalEntry> releaseTransitions({
  required Map<int, ReleaseRun> before,
  required Map<int, ReleaseRun> after,
  required DateTime now,
}) {
  final out = <JournalEntry>[];
  for (final MapEntry(key: ws, value: r) in after.entries) {
    final was = before[ws];
    if (!r.status.done || r.status == ReleaseRunStatus.cancelled) continue;
    if (was != null && was.tag == r.tag && was.status.done) continue;
    final ok = r.status != ReleaseRunStatus.failure;
    out.add(
      JournalEntry(
        workspaceId: ws,
        kind: JournalKind.release,
        outcome: ok ? JournalOutcome.ok : JournalOutcome.failed,
        title: r.tag,
        detail: switch (r.status) {
          ReleaseRunStatus.draftCreated => 'rascunho criado no GitHub',
          ReleaseRunStatus.failure =>
            'falhou${r.failedJob == null ? '' : ' em `${r.failedJob}`'}',
          _ => 'publicada',
        },
        releaseTag: r.tag,
        at: now,
      ),
    );
  }
  return out;
}

String _minutes(Duration d) => d.inMinutes < 60
    ? '${d.inMinutes} min'
    : '${d.inHours} h ${d.inMinutes % 60} min';

/// Sessions out of the Quadro's steps: a turn longer than 2 min (R6). The
/// spec agents' turns are already in the steps and the gate.
List<JournalEntry> turnTransitions({
  required SessionManagerState before,
  required SessionManagerState after,
  required Map<String, JournalSession> sessions,
  required DateTime now,
}) {
  final out = <JournalEntry>[];
  for (final MapEntry(key: id, value: was) in before.live.entries) {
    final since = was.busySince;
    if (since == null) continue;
    final l = after.live[id];
    if (l != null && l.busySince != null) continue;
    final took = now.difference(since);
    if (took <= longTurn) continue;
    final s = sessions[id];
    if (s == null || s.spec != null) continue;
    out.add(
      JournalEntry(
        workspaceId: s.workspaceId,
        kind: JournalKind.session,
        outcome: JournalOutcome.ok,
        title: s.title,
        detail: 'terminou um turno de ${_minutes(took)}',
        seed: 'session:$id',
        sessionId: id,
        at: now,
      ),
    );
  }
  return out;
}

/// What the journal knows of a conversation.
typedef JournalConversation = ({
  int id,
  int workspaceId,
  String title,
  Spec? spec,
});

/// Prompt and VIBE conversations: a turn longer than 2 min (R6).
List<JournalEntry> conversationTransitions({
  required ConversationManagerState before,
  required ConversationManagerState after,
  required Map<int, JournalConversation> conversations,
  required DateTime now,
}) {
  final out = <JournalEntry>[];
  for (final MapEntry(key: id, value: was) in before.live.entries) {
    final since = was.busySince;
    if (since == null || !was.busy) continue;
    final l = after.live[id];
    if (l != null && l.busy) continue;
    final took = now.difference(since);
    if (took <= longTurn) continue;
    final c = conversations[id];
    if (c == null) continue;
    final vibe = c.spec?.kind == SpecKind.vibe;
    out.add(
      JournalEntry(
        workspaceId: c.workspaceId,
        kind: JournalKind.conversation,
        outcome: JournalOutcome.ok,
        title: vibe ? _specTitle(c.spec!) : c.title,
        detail: 'terminou um turno de ${_minutes(took)}',
        seed: 'conv:$id',
        conversationId: id,
        fixedGroupKey: 'conv:$id',
        at: now,
      ),
    );
  }
  return out;
}

/// The Autopilot started a spec of the queue (R6).
JournalEntry autopilotStarted(int workspaceId, Spec spec, {DateTime? now}) =>
    JournalEntry(
      workspaceId: workspaceId,
      kind: JournalKind.autopilot,
      outcome: JournalOutcome.ok,
      title: _specTitle(spec),
      detail: 'Autopilot começou',
      seed: specSeed(workspaceId, spec.code),
      specId: spec.id,
      at: now ?? DateTime.now(),
    );

/// The Autopilot finished the queue (R6).
JournalEntry autopilotFinished(
  int workspaceId,
  int inReview, {
  DateTime? now,
}) => JournalEntry(
  workspaceId: workspaceId,
  kind: JournalKind.autopilot,
  outcome: JournalOutcome.ok,
  title: 'Autopilot',
  detail:
      'terminou a fila · $inReview ${inReview == 1 ? 'spec' : 'specs'} em Review',
  fixedGroupKey: 'autopilot:$workspaceId',
  at: now ?? DateTime.now(),
);

/// Writes [e] in the journal; errors only go to the log (the journal never
/// stops what finished).
Future<void> writeJournal(ActivityEventsRepo repo, JournalEntry e) async {
  try {
    await repo.add(e.toCompanion());
  } catch (err) {
    debugPrint('diário: ${e.title} não gravado — $err');
  }
}

/// Writes the journal: [record] by hand (the Autopilot, the GitHub
/// catch-up) and [start] follows the app's state and writes what
/// finishes.
class ActivityJournal {
  ActivityJournal(this._container);

  final ProviderContainer _container;
  final List<ProviderSubscription<Object?>> _subs = [];
  final Map<int, List<ProviderSubscription<Object?>>> _byWorkspace = {};
  bool _started = false;

  T _read<T>(ProviderListenable<T> p) => _container.read(p);

  /// Writes [e] (errors only go to the log: the journal never stops the
  /// app).
  Future<void> record(JournalEntry e) =>
      writeJournal(_read(activityEventsRepoProvider), e);

  void _recordAll(List<JournalEntry> list) {
    for (final e in list) {
      unawaited(record(e));
    }
  }

  // What is known of the sessions and conversations of every workspace.
  final Map<String, JournalSession> _sessions = {};
  final Map<int, JournalConversation> _conversations = {};
  final Map<int, Map<int, Spec>> _specs = {};

  /// Follows the app (once; the splash calls it).
  void start() {
    if (_started) return;
    _started = true;
    _subs
      ..add(
        _container.listen<AsyncValue<List<Workspace>>>(workspacesProvider, (
          _,
          next,
        ) {
          _follow(next.value ?? const []);
        }, fireImmediately: true),
      )
      ..add(
        _container.listen<Map<String, PrWatch>>(
          prBabysitterProvider,
          (before, after) => _recordAll(
            prTransitions(
              before: before ?? const {},
              after: after,
              sessions: _sessions,
              now: DateTime.now(),
            ),
          ),
        ),
      )
      ..add(
        _container.listen<Map<String, CiFixState>>(
          ciFixerProvider,
          (before, after) => _recordAll(
            ciFixTransitions(
              before: before ?? const {},
              after: after,
              sessions: _sessions,
              now: DateTime.now(),
            ),
          ),
        ),
      )
      ..add(
        _container.listen<Map<int, ReleaseRun>>(
          releaseDispatcherProvider,
          (before, after) => _recordAll(
            releaseTransitions(
              before: before ?? const {},
              after: after,
              now: DateTime.now(),
            ),
          ),
        ),
      )
      ..add(
        _container.listen<SessionManagerState>(
          sessionManagerProvider,
          (before, after) => _recordAll(
            turnTransitions(
              before: before ?? const SessionManagerState(),
              after: after,
              sessions: _sessions,
              now: DateTime.now(),
            ),
          ),
        ),
      )
      ..add(
        _container.listen<ConversationManagerState>(
          conversationManagerProvider,
          (before, after) => _recordAll(
            conversationTransitions(
              before: before ?? const ConversationManagerState(),
              after: after,
              conversations: _conversations,
              now: DateTime.now(),
            ),
          ),
        ),
      );
  }

  void _follow(List<Workspace> workspaces) {
    final ids = {for (final w in workspaces) w.id};
    for (final id in [..._byWorkspace.keys]) {
      if (ids.contains(id)) continue;
      for (final s in _byWorkspace.remove(id)!) {
        s.close();
      }
    }
    for (final ws in workspaces) {
      if (_byWorkspace.containsKey(ws.id)) continue;
      _byWorkspace[ws.id] = _followWorkspace(ws.id);
    }
  }

  List<ProviderSubscription<Object?>> _followWorkspace(int wsId) {
    List<Spec>? specs;
    List<SpecStep>? steps;
    void specsChanged(List<Spec>? nextSpecs, List<SpecStep>? nextSteps) {
      if (specs != null &&
          steps != null &&
          nextSpecs != null &&
          nextSteps != null) {
        _recordAll(
          specTransitions(
            workspaceId: wsId,
            before: specs!,
            after: nextSpecs,
            stepsBefore: steps!,
            stepsAfter: nextSteps,
            now: DateTime.now(),
          ),
        );
      }
      specs = nextSpecs ?? specs;
      steps = nextSteps ?? steps;
      if (nextSpecs != null) {
        _specs[wsId] = {for (final s in nextSpecs) s.id: s};
      }
    }

    List<Session>? sessions;
    return [
      _container.listen<AsyncValue<List<Spec>>>(specsProvider(wsId), (_, next) {
        if (next.value case final v?) specsChanged(v, steps);
      }, fireImmediately: true),
      _container.listen<AsyncValue<List<SpecStep>>>(specStepsProvider(wsId), (
        _,
        next,
      ) {
        if (next.value case final v?) specsChanged(specs, v);
      }, fireImmediately: true),
      _container.listen<AsyncValue<List<Session>>>(sessionsProvider(wsId), (
        _,
        next,
      ) {
        final v = next.value;
        if (v == null) return;
        final byId = _specs[wsId] ?? const <int, Spec>{};
        if (sessions != null) {
          _recordAll(
            sessionTransitions(
              workspaceId: wsId,
              before: sessions!,
              after: v,
              specs: byId,
              now: DateTime.now(),
            ),
          );
        }
        sessions = v;
        _sessions.removeWhere((_, s) => s.workspaceId == wsId);
        for (final s in v) {
          _sessions[s.id] = (
            id: s.id,
            workspaceId: wsId,
            title: sessionTitle(s),
            spec: byId[s.specId],
            prUrl: s.prUrl,
          );
        }
      }, fireImmediately: true),
      _container.listen<AsyncValue<List<Conversation>>>(
        conversationsProvider(wsId),
        (_, next) {
          final v = next.value;
          if (v == null) return;
          final byId = _specs[wsId] ?? const <int, Spec>{};
          _conversations.removeWhere((_, c) => c.workspaceId == wsId);
          for (final c in v) {
            _conversations[c.id] = (
              id: c.id,
              workspaceId: wsId,
              title: c.title,
              spec: byId[c.specId],
            );
          }
        },
        fireImmediately: true,
      ),
    ];
  }

  void dispose() {
    for (final s in [..._subs, for (final l in _byWorkspace.values) ...l]) {
      s.close();
    }
    _subs.clear();
    _byWorkspace.clear();
  }
}
