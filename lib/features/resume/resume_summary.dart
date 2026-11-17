import 'package:flutter/foundation.dart';

import '../activities/activity.dart';
import '../home/home_inbox.dart';
import 'activity_journal.dart';

/// The card "Retomar de onde parei" (SPEC-080 R3–R5, R8, R9): what waits,
/// what finished while away and what keeps running, of every workspace.
/// Pure: [buildResumeSummary] turns the activities, the requests of the
/// Início and the journal into the card's groups.

/// The groups of the card, in this order (R4).
enum ResumeGroup {
  waiting('Espera por você'),
  finished('Terminou enquanto você estava fora'),
  running('Continua rodando');

  const ResumeGroup(this.label);

  final String label;

  /// `+ 4 em Terminou`.
  String get short => switch (this) {
    waiting => 'Espera por você',
    finished => 'Terminou',
    running => 'Continua rodando',
  };
}

/// What enters "Terminou" (R14).
enum ResumeKindGroup {
  specs('Specs e gates'),
  prs('PRs'),
  ci('CI'),
  releases('Releases'),
  sessions('Sessões e conversas');

  const ResumeKindGroup(this.label);

  final String label;

  static ResumeKindGroup of(JournalKind k) => switch (k) {
    JournalKind.spec || JournalKind.gate || JournalKind.autopilot => specs,
    JournalKind.pr => prs,
    JournalKind.ci => ci,
    JournalKind.release => releases,
    JournalKind.session || JournalKind.conversation => sessions,
  };

  /// `specs,ci` of the setting.
  static Set<ResumeKindGroup> decode(String? v) => {
    for (final p in (v ?? '').split(','))
      ?values.where((k) => k.name == p.trim()).firstOrNull,
  };

  static String encode(Set<ResumeKindGroup> s) => [
    for (final k in values)
      if (s.contains(k)) k.name,
  ].join(',');
}

/// The action of an item (R9).
enum ResumeAction {
  respond('Responder'),
  viewPlan('Ver plano'),
  resume('Retomar'),
  viewError('Ver erro'),
  review('Revisar'),
  viewGate('Ver gate'),
  viewInBoard('Ver no Quadro'),
  fixCi('Corrigir CI'),
  viewCi('Ver CI'),
  openPr('Abrir PR'),
  viewRelease('Ver release'),
  viewLog('Ver log'),
  open('Abrir');

  const ResumeAction(this.label);

  final String label;
}

/// One item of the card.
@immutable
class ResumeItem {
  const ResumeItem({
    required this.key,
    required this.group,
    required this.workspaceId,
    required this.tag,
    required this.title,
    required this.line,
    required this.action,
    this.workspaceName,
    this.seed,
    this.pose = ActivityPose.think,
    this.mark,
    this.at,
    this.runningFor,
    this.activity,
    this.specId,
    this.sessionId,
    this.conversationId,
    this.prNumber,
    this.releaseTag,
  });

  /// Unique in the card (`act:session:x`, `ev:spec:7`, `req:review:x`).
  final String key;
  final ResumeGroup group;
  final int workspaceId;

  /// The workspace in gray, when there is more than one (R3).
  final String? workspaceName;

  /// SPEC, PR, CI, GATE, RELEASE, VIBE, PROMPT (R5).
  final String tag;
  final String title;

  /// What happened (`passou no gate · R1–R4`).
  final String line;
  final ResumeAction action;

  /// The robot (R5); null = an icon by [tag].
  final String? seed;
  final ActivityPose pose;

  /// ✓, ✕ or ! (R15: never only the color).
  final JournalOutcome? mark;
  final DateTime? at;

  /// How long it runs ("há 38 min", Continua rodando).
  final Duration? runningFor;

  /// The live activity behind it (Espera por você, Continua rodando).
  final Activity? activity;
  final int? specId;
  final String? sessionId;
  final int? conversationId;
  final int? prNumber;
  final String? releaseTag;
}

/// What the card shows.
@immutable
class ResumeSummary {
  const ResumeSummary({
    this.waiting = const [],
    this.finished = const [],
    this.running = const [],
    this.autopilot = const [],
  });

  final List<ResumeItem> waiting;
  final List<ResumeItem> finished;
  final List<ResumeItem> running;

  /// `Autopilot: 2 specs na fila do loja-api` (P8: no item per spec).
  final List<String> autopilot;

  bool get isEmpty => waiting.isEmpty && finished.isEmpty && running.isEmpty;

  /// The card only shows with something to say (R2).
  bool get hasNews => waiting.isNotEmpty || finished.isNotEmpty;

  List<ResumeItem> of(ResumeGroup g) => switch (g) {
    ResumeGroup.waiting => waiting,
    ResumeGroup.finished => finished,
    ResumeGroup.running => running,
  };

  /// Every item, in the card's order (↑/↓, R15).
  List<ResumeItem> get all => [...waiting, ...finished, ...running];
}

/// A request of the Início of one workspace.
typedef ResumeRequests = ({int workspaceId, List<InboxGroup> groups});

/// The action of a live activity that needs you (R9).
ResumeAction _activityAction(Activity a) {
  // R9: an interrupted session resumes; one that failed shows its error.
  if (a.action == ActivityAction.resume &&
      a.status.startsWith('interrompida')) {
    return ResumeAction.resume;
  }
  if (a.error) return ResumeAction.viewError;
  return switch (a.action) {
    ActivityAction.respond => ResumeAction.respond,
    ActivityAction.viewPlan => ResumeAction.viewPlan,
    ActivityAction.resume => ResumeAction.resume,
    _ => a.kind == ActivityKind.ciFix ? ResumeAction.viewCi : ResumeAction.open,
  };
}

/// The action of the newest event of an item (R9).
ResumeAction _eventAction(JournalEntry e, {required bool ciFixing}) {
  final ok = e.outcome == JournalOutcome.ok;
  return switch (e.kind) {
    JournalKind.gate => ok ? ResumeAction.review : ResumeAction.viewGate,
    JournalKind.spec =>
      e.detail.startsWith('foi para Review')
          ? ResumeAction.review
          : ResumeAction.viewInBoard,
    JournalKind.pr =>
      e.detail.contains('mergeado') && e.specId != null
          ? ResumeAction.viewInBoard
          : ResumeAction.openPr,
    JournalKind.ci =>
      ok
          ? ResumeAction.openPr
          : ciFixing || e.detail.startsWith('Corrigir CI')
          ? ResumeAction.viewCi
          : ResumeAction.fixCi,
    JournalKind.release => ok ? ResumeAction.viewRelease : ResumeAction.viewLog,
    JournalKind.session ||
    JournalKind.conversation => ok ? ResumeAction.open : ResumeAction.viewError,
    JournalKind.autopilot =>
      e.specId == null ? ResumeAction.open : ResumeAction.viewInBoard,
  };
}

String _two(int n) => n.toString().padLeft(2, '0');

/// `23:14`, `ontem 21:02`, `14/11 08:00`.
String resumeTime(DateTime at, DateTime now) {
  final hm = '${_two(at.hour)}:${_two(at.minute)}';
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return hm;
  if (diff == 1) return 'ontem $hm';
  return '${_two(at.day)}/${_two(at.month)} $hm';
}

/// `47 min`, `13 h`, `2 dias`.
String awayLabel(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 48) return '${d.inHours} h';
  return '${d.inDays} dias';
}

/// `há 38 min`, `há 2 h 5 min`.
String runningLabel(Duration d) {
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  final m = d.inMinutes % 60;
  return 'há ${d.inHours} h${m == 0 ? '' : ' $m min'}';
}

/// What a screen reader says of an item (R15): "SPEC-077 Copiar código,
/// passou no gate, 23 horas e 14, Revisar".
String resumeSemantics(ResumeItem i) {
  final at = i.at;
  return [
    i.title.replaceAll(' · ', ' '),
    if (i.mark != null)
      switch (i.mark!) {
        JournalOutcome.ok => 'ok',
        JournalOutcome.failed => 'falhou',
        JournalOutcome.attention => 'atenção',
      },
    i.line,
    if (at != null) '${at.hour} horas e ${at.minute}',
    if (i.workspaceName != null) i.workspaceName!,
    i.action.label,
  ].join(', ');
}

/// The card's groups (R4, R5, R8, R9). [events] are the journal's after
/// the start of the window; [hidden] what the settings leave out of
/// "Terminou" (R14); [resolved] the items already acted on; [ciFixing] the
/// sessions whose Corrigir CI runs ("Ver CI" instead of "Corrigir CI").
ResumeSummary buildResumeSummary({
  required List<Activity> activities,
  required List<ResumeRequests> requests,
  required List<JournalEntry> events,
  required Map<int, String> workspaces,
  required DateTime now,
  Set<ResumeKindGroup> hidden = const {},
  Set<String> resolved = const {},
  Set<String> ciFixing = const {},
}) {
  final many = workspaces.length > 1;
  String? wsName(int id) => many ? workspaces[id] : null;

  // --- Espera por você ----------------------------------------------------
  final waiting = <ResumeItem>[];
  final waitingSpecs = <int>{};
  final waitingSessions = <String>{};
  for (final a in activities) {
    if (!a.needsYou) continue;
    final key = 'act:${a.id}';
    if (resolved.contains(key)) continue;
    final last = a.lastAction;
    final what = a.status.startsWith('quer ') && last != null
        ? '${a.status} ${last.contains(' ') ? last.substring(last.indexOf(' ') + 1) : last}'
        : [a.status, ?last].join(' · ');
    waiting.add(
      ResumeItem(
        key: key,
        group: ResumeGroup.waiting,
        workspaceId: a.workspaceId,
        workspaceName: wsName(a.workspaceId),
        tag: a.kind.tag,
        title: a.title,
        line: what,
        action: _activityAction(a),
        seed: a.seed,
        pose: a.pose,
        mark: a.error ? JournalOutcome.failed : JournalOutcome.attention,
        at: a.lastActionAt ?? a.startedAt,
        activity: a,
        specId: a.specId,
        sessionId: a.sessionId,
        conversationId: a.conversationId,
      ),
    );
    if (a.specId case final s?) waitingSpecs.add(s);
    if (a.sessionId case final s?) waitingSessions.add(s);
  }
  for (final r in requests) {
    for (final g in r.groups) {
      if (g.kind != InboxKind.review &&
          g.kind != InboxKind.prProblem &&
          g.kind != InboxKind.interrupted) {
        continue;
      }
      for (final it in g.items) {
        if (it.specId != null && waitingSpecs.contains(it.specId)) continue;
        if (it.sessionId != null && waitingSessions.contains(it.sessionId)) {
          continue;
        }
        final key = 'req:${g.kind.name}:${it.sessionId ?? it.specId}';
        if (resolved.contains(key)) continue;
        final ci = g.kind == InboxKind.prProblem && it.title.startsWith('CI');
        final fixing = it.sessionId != null && ciFixing.contains(it.sessionId);
        waiting.add(
          ResumeItem(
            key: key,
            group: ResumeGroup.waiting,
            workspaceId: r.workspaceId,
            workspaceName: wsName(r.workspaceId),
            tag: switch (g.kind) {
              InboxKind.prProblem => ci ? 'CI' : 'PR',
              _ => it.specCode == null ? 'SESSÃO' : 'SPEC',
            },
            title: g.kind == InboxKind.review && it.specCode != null
                ? '${it.ref} · ${it.title}'
                : it.ref,
            line: switch (g.kind) {
              InboxKind.review => 'aguardando review',
              _ => it.title,
            },
            action: switch (g.kind) {
              InboxKind.review => ResumeAction.review,
              InboxKind.prProblem =>
                !ci
                    ? ResumeAction.review
                    : fixing
                    ? ResumeAction.viewCi
                    : ResumeAction.fixCi,
              _ => ResumeAction.resume,
            },
            seed: it.sessionId == null
                ? null
                : it.specCode == null
                ? 'session:${it.sessionId}'
                : specSeed(r.workspaceId, it.specCode!),
            pose: ActivityPose.wave,
            mark: g.kind == InboxKind.review
                ? JournalOutcome.attention
                : JournalOutcome.failed,
            at: it.at,
            specId: it.specId,
            sessionId: it.sessionId,
          ),
        );
        if (it.specId case final s?) waitingSpecs.add(s);
        if (it.sessionId case final s?) waitingSessions.add(s);
      }
    }
  }

  // --- Terminou -------------------------------------------------------------
  final byKey = <String, List<JournalEntry>>{};
  for (final e in events) {
    if (hidden.contains(ResumeKindGroup.of(e.kind))) continue;
    (byKey[e.groupKey] ??= []).add(e);
  }
  final finished = <ResumeItem>[];
  for (final MapEntry(key: groupKey, value: list) in byKey.entries) {
    list.sort((a, b) => b.at.compareTo(a.at));
    final e = list.first;
    final key = 'ev:$groupKey';
    if (resolved.contains(key)) continue;
    // R8: what waits is not repeated.
    if (e.specId != null && waitingSpecs.contains(e.specId)) continue;
    if (e.specId == null &&
        e.sessionId != null &&
        waitingSessions.contains(e.sessionId)) {
      continue;
    }
    final older = [
      for (final o in list.skip(1))
        if (o.detail != e.detail) o,
    ];
    final line = older.isEmpty
        ? e.detail
        : '${e.detail} · antes: ${[for (final o in older.take(2)) '${o.detail} (${resumeTime(o.at, now)})'].join(', ')}';
    final specItem = e.specId != null && e.kind != JournalKind.conversation;
    final outcome = e.outcome;
    finished.add(
      ResumeItem(
        key: key,
        group: ResumeGroup.finished,
        workspaceId: e.workspaceId,
        workspaceName: wsName(e.workspaceId),
        tag: specItem
            ? 'SPEC'
            : e.kind == JournalKind.conversation
            ? (e.specId != null ? 'VIBE' : 'PROMPT')
            : e.kind.tag,
        title: e.title,
        line: line,
        action: _eventAction(
          e,
          ciFixing: e.sessionId != null && ciFixing.contains(e.sessionId),
        ),
        seed: e.seed,
        pose: switch (outcome) {
          JournalOutcome.ok => ActivityPose.wait,
          JournalOutcome.failed => ActivityPose.error,
          JournalOutcome.attention => ActivityPose.wave,
        },
        mark: outcome,
        at: e.at,
        specId: e.specId,
        sessionId: e.sessionId,
        conversationId: e.conversationId,
        prNumber: list
            .map((x) => x.prNumber)
            .firstWhere((n) => n != null, orElse: () => null),
        releaseTag: e.releaseTag,
      ),
    );
  }
  finished.sort((a, b) => b.at!.compareTo(a.at!));

  // --- Continua rodando ------------------------------------------------------
  final running = <ResumeItem>[];
  final queued = <int, int>{};
  for (final a in activities) {
    if (a.needsYou) continue;
    if (a.kind == ActivityKind.queued || a.column == ActivityColumn.backlog) {
      if (a.kind == ActivityKind.queued) {
        queued[a.workspaceId] = (queued[a.workspaceId] ?? 0) + 1;
      }
      continue;
    }
    final key = 'act:${a.id}';
    if (resolved.contains(key)) continue;
    final took = a.startedAt == null ? null : now.difference(a.startedAt!);
    running.add(
      ResumeItem(
        key: key,
        group: ResumeGroup.running,
        workspaceId: a.workspaceId,
        workspaceName: wsName(a.workspaceId),
        tag: a.kind.tag,
        title: a.title,
        line: [
          a.subtitle,
          a.status,
          if (took != null) runningLabel(took),
        ].where((s) => s.isNotEmpty).join(' · '),
        action: ResumeAction.open,
        seed: a.seed,
        pose: a.pose,
        at: a.startedAt,
        runningFor: took,
        activity: a,
        specId: a.specId,
        sessionId: a.sessionId,
        conversationId: a.conversationId,
      ),
    );
  }
  return ResumeSummary(
    waiting: waiting,
    finished: finished,
    running: running,
    autopilot: [
      for (final MapEntry(key: ws, value: n) in queued.entries)
        'Autopilot: $n ${n == 1 ? 'spec' : 'specs'} na fila'
            '${many && workspaces[ws] != null ? ' do ${workspaces[ws]}' : ''}',
    ],
  );
}
