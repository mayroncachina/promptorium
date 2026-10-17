import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../board/board_rules.dart';
import '../board/board_screen.dart' show specStepsProvider;
import '../prompt/conversation_manager.dart';
import '../review/pr_babysitter.dart';
import '../review/review_logic.dart';
import '../review/review_service.dart' show reviewQueueProvider;
import '../sessions/session_manager.dart';
import '../sessions/timeline.dart' show toolTarget;

/// "Para você" (UX v2, U1): everything of the active workspace that waits
/// for a human decision, grouped by kind. Pure data; the screen renders it
/// and the sidebar counts it.

enum InboxKind {
  /// A `control_request` of a session or a Prompt conversation.
  approval,

  /// A step in `needs_input` (the gate refused it or the session ended
  /// without the marker).
  needsAnswer,

  /// A spec / session in "Aguardando review".
  review,

  /// A watched PR with failing checks, a conflict or changes requested.
  prProblem,

  /// A session interrupted (app closed) or failed, not running now.
  interrupted,
}

@immutable
class InboxItem {
  const InboxItem({
    required this.kind,
    required this.ref,
    required this.title,
    required this.detail,
    required this.at,
    this.sessionId,
    this.conversationId,
    this.approval,
    this.specId,
    this.specCode,
  });

  final InboxKind kind;

  /// `SPEC-012 · R3`, `PR #42`…
  final String ref;
  final String title;
  final String detail;

  /// When it started waiting (newest first inside a group).
  final DateTime at;
  final String? sessionId;
  final int? conversationId;
  final PendingApproval? approval;
  final int? specId;
  final String? specCode;
}

@immutable
class InboxGroup {
  const InboxGroup(this.kind, this.items);

  final InboxKind kind;
  final List<InboxItem> items;

  String get title => switch (kind) {
    InboxKind.approval => 'Aprovações pendentes',
    InboxKind.needsAnswer => 'Precisam de resposta',
    InboxKind.review => 'Aguardando review',
    InboxKind.prProblem => 'PR com problema',
    InboxKind.interrupted => 'Interrompidas',
  };
}

/// `SPEC-012 · R3` of a step session (`steps` = `R2` or `R2,R3`).
String stepRef(Spec? spec, String? steps) {
  if (spec == null) return steps ?? '';
  return steps == null || steps.isEmpty ? spec.code : '${spec.code} · $steps';
}

/// Whether a watched PR needs the user.
bool prHasProblem(PrStatus s) =>
    s.open &&
    (s.conflicting ||
        s.reviewDecision == 'CHANGES_REQUESTED' ||
        s.checks.any((c) => c.$2 == 'FAILURE'));

/// Groups of the inbox, in the order of urgency (empty groups left out).
List<InboxGroup> buildInbox({
  required List<PendingApproval> sessionApprovals,
  required Map<int, List<PendingApproval>> conversationApprovals,
  required List<Spec> specs,
  required List<SpecStep> stepRows,
  required List<Session> sessions,
  required List<ReviewItem> reviewQueue,
  required Map<String, PrWatch> prWatches,
  required bool Function(String sessionId) isAlive,
}) {
  final byId = {for (final s in specs) s.id: s};
  final sessionById = {for (final s in sessions) s.id: s};

  String toolLine(PendingApproval a) {
    final r = a.request;
    final root = sessionById[a.sessionId]?.worktreePath;
    final target = toolTarget(r.toolName, r.input, root: root);
    return target.isEmpty ? r.toolName : '${r.toolName} · $target';
  }

  final approvals = <InboxItem>[
    for (final a in sessionApprovals)
      InboxItem(
        kind: InboxKind.approval,
        ref: stepRef(
          byId[sessionById[a.sessionId]?.specId],
          sessionById[a.sessionId]?.steps,
        ),
        title: '${a.sessionTitle} quer ${approvalVerb(a.request.toolName)}',
        detail: toolLine(a),
        at: a.receivedAt,
        sessionId: a.sessionId,
        approval: a,
        specId: sessionById[a.sessionId]?.specId,
      ),
    for (final e in conversationApprovals.entries)
      for (final a in e.value)
        InboxItem(
          kind: InboxKind.approval,
          ref: 'Prompt',
          title: '${a.sessionTitle} quer ${approvalVerb(a.request.toolName)}',
          detail: toolLine(a),
          at: a.receivedAt,
          conversationId: e.key,
          approval: a,
        ),
  ];

  final needsAnswer = <InboxItem>[];
  for (final spec in specs) {
    if (!isOnBoard(spec) || spec.stage == SpecStage.done) continue;
    for (final st in stepsOf(spec, stepRows)) {
      if (st.status != StepStatus.needsInput) continue;
      final session = st.sessionId == null ? null : sessionById[st.sessionId];
      final gate = st.gate;
      needsAnswer.add(
        InboxItem(
          kind: InboxKind.needsAnswer,
          ref: '${spec.code} · ${st.id}',
          title: st.gateFailed
              ? 'Gate recusou a etapa'
              : 'Sessão terminou sem concluir a etapa',
          detail: gate != null && !gate.ok ? gate.summary : st.text,
          at:
              session?.endedAt ??
              session?.startedAt ??
              DateTime.fromMillisecondsSinceEpoch(0),
          sessionId: st.sessionId,
          specId: spec.id,
          specCode: spec.code,
        ),
      );
    }
  }

  final review = <InboxItem>[
    for (final r in reviewQueue)
      InboxItem(
        kind: InboxKind.review,
        ref: r.spec?.code ?? sessionTitle(r.session),
        title: r.spec?.title ?? sessionTitle(r.session),
        detail: r.spec == null
            ? r.session.branch
            : [
                r.session.branch,
                if (r.spec!.reviewRounds > 0)
                  '${r.spec!.reviewRounds} correção(ões) do revisor',
              ].join(' · '),
        at: r.session.endedAt ?? r.session.startedAt,
        sessionId: r.session.id,
        specId: r.spec?.id,
        specCode: r.spec?.code,
      ),
  ];

  final prs = <InboxItem>[];
  for (final e in prWatches.entries) {
    final status = e.value.status;
    if (status == null || !prHasProblem(status)) continue;
    final session = sessionById[e.key];
    final spec = byId[session?.specId];
    final failed = status.checks.where((c) => c.$2 == 'FAILURE').toList();
    prs.add(
      InboxItem(
        kind: InboxKind.prProblem,
        ref: spec?.code ?? (session == null ? 'PR' : sessionTitle(session)),
        title: status.conflicting
            ? 'PR com conflito'
            : status.reviewDecision == 'CHANGES_REQUESTED'
            ? 'PR com mudanças pedidas'
            : 'CI falhou em ${failed.map((c) => c.$1).join(', ')}',
        detail: session?.branch ?? '',
        at: e.value.checkedAt ?? DateTime.now(),
        sessionId: e.key,
        specId: spec?.id,
        specCode: spec?.code,
      ),
    );
  }

  final interrupted = <InboxItem>[
    for (final s in sessions)
      if ((s.status == SessionStatus.interrupted ||
              s.status == SessionStatus.failed) &&
          !isAlive(s.id))
        InboxItem(
          kind: InboxKind.interrupted,
          ref: stepRef(byId[s.specId], s.steps),
          title: s.status == SessionStatus.interrupted
              ? 'Sessão interrompida ao fechar o app'
              : 'Sessão falhou',
          detail: '${sessionTitle(s)} · ${s.branch}',
          at: s.endedAt ?? s.startedAt,
          sessionId: s.id,
          specId: s.specId,
          specCode: byId[s.specId]?.code,
        ),
  ];

  List<InboxItem> sorted(List<InboxItem> l) =>
      l..sort((a, b) => b.at.compareTo(a.at));
  return [
    for (final (kind, items) in [
      (InboxKind.approval, approvals),
      (InboxKind.needsAnswer, needsAnswer),
      (InboxKind.review, review),
      (InboxKind.prProblem, prs),
      (InboxKind.interrupted, interrupted),
    ])
      if (items.isNotEmpty) InboxGroup(kind, sorted(items)),
  ];
}

/// "quer executar" / "quer editar" / "quer acessar" (as the side panel).
String approvalVerb(String tool) => switch (tool) {
  'ExitPlanMode' => 'aprovar o plano (Prompt)',
  'Bash' => 'executar',
  'Edit' || 'Write' || 'MultiEdit' || 'NotebookEdit' => 'editar',
  'WebFetch' || 'WebSearch' => 'acessar',
  _ => 'usar $tool',
};

/// Inbox of the active workspace (empty without one).
final inboxProvider = Provider.autoDispose<List<InboxGroup>>((ref) {
  final ws = ref.watch(activeWorkspaceProvider);
  if (ws == null) return const [];
  final manager = ref.watch(sessionManagerProvider);
  final conversations = ref.watch(conversationManagerProvider);
  return buildInbox(
    sessionApprovals: manager.approvals,
    conversationApprovals: {
      for (final e in conversations.live.entries)
        if (e.value.approvals.isNotEmpty) e.key: e.value.approvals,
    },
    specs: ref.watch(specsProvider(ws.id)).value ?? const [],
    stepRows: ref.watch(specStepsProvider(ws.id)).value ?? const [],
    sessions: ref.watch(sessionsProvider(ws.id)).value ?? const [],
    reviewQueue: ref.watch(reviewQueueProvider(ws.id)).value ?? const [],
    prWatches: ref.watch(prBabysitterProvider),
    isAlive: manager.isAlive,
  );
});

/// Counters of the sidebar (UX v2): what waits for the user, by screen.
final navBadgesProvider = Provider.autoDispose<Map<AppSection, int>>((ref) {
  final groups = ref.watch(inboxProvider);
  int count(InboxKind k) =>
      groups.where((g) => g.kind == k).fold(0, (a, g) => a + g.items.length);
  final total = groups.fold(0, (a, g) => a + g.items.length);
  return {
    if (total > 0) AppSection.home: total,
    if (count(InboxKind.needsAnswer) > 0)
      AppSection.tasks: count(InboxKind.needsAnswer),
    if (count(InboxKind.approval) > 0)
      AppSection.sessions: count(InboxKind.approval),
    if (count(InboxKind.review) + count(InboxKind.prProblem) > 0)
      AppSection.review: count(InboxKind.review) + count(InboxKind.prProblem),
  };
});
