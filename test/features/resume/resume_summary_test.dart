import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/home/home_inbox.dart';
import 'package:promptorium/features/resume/activity_journal.dart';
import 'package:promptorium/features/resume/resume_summary.dart';

final now = DateTime(2026, 11, 17, 9);

Activity act(
  String id, {
  int ws = 1,
  ActivityKind kind = ActivityKind.spec,
  ActivityColumn column = ActivityColumn.running,
  bool needsYou = false,
  bool error = false,
  ActivityAction action = ActivityAction.stop,
  String status = 'Editando',
  String? lastAction,
  int? specId,
  String? sessionId,
}) => Activity(
  id: id,
  workspaceId: ws,
  workspaceName: ws == 1 ? 'loja-api' : 'site',
  kind: kind,
  column: column,
  pose: needsYou ? ActivityPose.wave : ActivityPose.edit,
  title: 'SPEC-0$id · Título',
  subtitle: 'Em execução · t2 de 3',
  status: status,
  needsYou: needsYou,
  error: error,
  action: action,
  lastAction: lastAction,
  specId: specId,
  sessionId: sessionId,
  seed: 'spec:$ws:$id',
  startedAt: now.subtract(const Duration(minutes: 38)),
);

JournalEntry ev(
  JournalKind kind,
  String detail, {
  JournalOutcome outcome = JournalOutcome.ok,
  int? specId,
  int? pr,
  String? tag,
  String? sessionId,
  int ws = 1,
  int minutesAgo = 60,
  String title = 'SPEC-077 · Copiar código',
}) => JournalEntry(
  workspaceId: ws,
  kind: kind,
  outcome: outcome,
  title: title,
  detail: detail,
  specId: specId,
  prNumber: pr,
  releaseTag: tag,
  sessionId: sessionId,
  seed: specId == null ? null : 'spec:$ws:$specId',
  at: now.subtract(Duration(minutes: minutesAgo)),
);

ResumeSummary build({
  List<Activity> activities = const [],
  List<ResumeRequests> requests = const [],
  List<JournalEntry> events = const [],
  Map<int, String> workspaces = const {1: 'loja-api'},
  Set<ResumeKindGroup> hidden = const {},
  Set<String> resolved = const {},
  Set<String> ciFixing = const {},
}) => buildResumeSummary(
  activities: activities,
  requests: requests,
  events: events,
  workspaces: workspaces,
  now: now,
  hidden: hidden,
  resolved: resolved,
  ciFixing: ciFixing,
);

void main() {
  test('three groups in order, empty ones left out (R4)', () {
    final s = build(
      activities: [
        act(
          '78',
          needsYou: true,
          action: ActivityAction.respond,
          status: 'quer executar',
          lastAction: 'Bash flutter test test/features/snippets',
        ),
        act('79'),
      ],
      events: [ev(JournalKind.gate, 'passou no gate · R1–R4', specId: 77)],
    );
    expect(
      s.waiting.single.line,
      'quer executar flutter test test/features/snippets',
    );
    expect(s.waiting.single.action, ResumeAction.respond);
    expect(s.finished.single.action, ResumeAction.review);
    expect(s.running.single.action, ResumeAction.open);
    expect(s.running.single.line, contains('há 38 min'));
    expect(s.all.map((i) => i.group), ResumeGroup.values);
    expect(
      build(events: [ev(JournalKind.spec, 'concluída', specId: 1)]).waiting,
      isEmpty,
    );
    expect(build().isEmpty, isTrue);
  });

  test('the workspace in gray only with more than one (R3)', () {
    final events = [
      ev(JournalKind.release, 'publicada', tag: 'v0.18.0', ws: 2),
    ];
    expect(build(events: events).finished.single.workspaceName, isNull);
    expect(
      build(
        events: events,
        workspaces: const {1: 'loja-api', 2: 'site'},
      ).finished.single.workspaceName,
      'site',
    );
  });

  test('one item per spec, PR or release, newest first (R8)', () {
    final s = build(
      events: [
        ev(
          JournalKind.gate,
          'passou no gate · R1–R4',
          specId: 77,
          minutesAgo: 600,
        ),
        ev(JournalKind.spec, 'foi para Review', specId: 77, minutesAgo: 590),
        ev(
          JournalKind.pr,
          'PR #267 mergeado',
          specId: 77,
          pr: 267,
          minutesAgo: 62,
        ),
        ev(
          JournalKind.release,
          'publicada',
          tag: 'v0.18.0',
          title: 'v0.18.0',
          minutesAgo: 30,
        ),
      ],
    );
    expect(s.finished, hasLength(2));
    expect(s.finished.first.title, 'v0.18.0');
    final spec = s.finished.last;
    expect(
      spec.line,
      startsWith('PR #267 mergeado · antes: foi para Review ('),
    );
    expect(spec.line, contains('passou no gate · R1–R4'));
    expect(spec.action, ResumeAction.viewInBoard);
    expect(spec.prNumber, 267);
    expect(spec.tag, 'SPEC');
  });

  test('what waits is not repeated in Terminou (R8)', () {
    final s = build(
      activities: [
        act('78', needsYou: true, action: ActivityAction.respond, specId: 78),
      ],
      events: [
        ev(JournalKind.gate, 'passou no gate', specId: 78),
        ev(JournalKind.gate, 'passou no gate', specId: 77),
      ],
    );
    expect(s.finished.single.specId, 77);
  });

  test('the action of each kind (R9)', () {
    ResumeAction one(JournalEntry e, {Set<String> fixing = const {}}) =>
        build(events: [e], ciFixing: fixing).finished.single.action;
    expect(
      one(
        ev(
          JournalKind.gate,
          'falhou',
          outcome: JournalOutcome.failed,
          specId: 1,
        ),
      ),
      ResumeAction.viewGate,
    );
    expect(
      one(ev(JournalKind.spec, 'foi para Review', specId: 1)),
      ResumeAction.review,
    );
    expect(
      one(
        ev(
          JournalKind.ci,
          'CI falhou',
          outcome: JournalOutcome.failed,
          pr: 270,
          sessionId: 's',
        ),
      ),
      ResumeAction.fixCi,
    );
    expect(
      one(
        ev(
          JournalKind.ci,
          'CI falhou',
          outcome: JournalOutcome.failed,
          pr: 270,
          sessionId: 's',
        ),
        fixing: {'s'},
      ),
      ResumeAction.viewCi,
    );
    expect(one(ev(JournalKind.ci, 'CI passou', pr: 266)), ResumeAction.openPr);
    expect(
      one(ev(JournalKind.release, 'publicada', tag: 'v1')),
      ResumeAction.viewRelease,
    );
    expect(
      one(
        ev(
          JournalKind.release,
          'falhou',
          outcome: JournalOutcome.failed,
          tag: 'v1',
        ),
      ),
      ResumeAction.viewLog,
    );
    expect(
      one(ev(JournalKind.session, 'turno', sessionId: 'x')),
      ResumeAction.open,
    );
    expect(
      one(
        ev(
          JournalKind.session,
          'erro',
          outcome: JournalOutcome.failed,
          sessionId: 'x',
        ),
      ),
      ResumeAction.viewError,
    );
    expect(
      one(ev(JournalKind.pr, 'PR #5 mergeado', pr: 5)),
      ResumeAction.openPr,
    );

    // Live: plan, stopped step, error.
    ResumeAction live(Activity a) =>
        build(activities: [a]).waiting.single.action;
    expect(
      live(act('1', needsYou: true, action: ActivityAction.viewPlan)),
      ResumeAction.viewPlan,
    );
    expect(
      live(act('1', needsYou: true, action: ActivityAction.resume)),
      ResumeAction.resume,
    );
    expect(
      live(act('1', needsYou: true, error: true, action: ActivityAction.none)),
      ResumeAction.viewError,
    );
    expect(
      live(
        act(
          '1',
          needsYou: true,
          error: true,
          action: ActivityAction.resume,
          status: 'interrompida ao fechar o app',
        ),
      ),
      ResumeAction.resume,
    );
  });

  test('requests of the Início that are not activities (R4)', () {
    InboxItem item(InboxKind k, String title) => InboxItem(
      kind: k,
      ref: 'SPEC-076',
      title: title,
      detail: '',
      at: now,
      sessionId: 's-$title',
      specId: 76,
      specCode: 'SPEC-076',
    );
    final s = build(
      requests: [
        (
          workspaceId: 1,
          groups: [
            InboxGroup(InboxKind.prProblem, [
              item(InboxKind.prProblem, 'CI falhou em test'),
            ]),
            InboxGroup(InboxKind.approval, [
              item(InboxKind.approval, 'quer editar'),
            ]),
          ],
        ),
      ],
      events: [
        ev(
          JournalKind.ci,
          'CI falhou',
          outcome: JournalOutcome.failed,
          specId: 76,
        ),
      ],
    );
    expect(s.waiting.single.tag, 'CI');
    expect(s.waiting.single.action, ResumeAction.fixCi);
    // The CI of the same spec is not repeated in Terminou.
    expect(s.finished, isEmpty);
  });

  test('settings leave kinds out; resolved items go (R9, R14)', () {
    final events = [
      ev(JournalKind.pr, 'PR #5 mergeado', pr: 5),
      ev(JournalKind.release, 'publicada', tag: 'v1'),
    ];
    expect(
      build(events: events, hidden: {ResumeKindGroup.prs}).finished.single.tag,
      'RELEASE',
    );
    expect(
      build(events: events, resolved: {'ev:pr:1:5'}).finished.single.tag,
      'RELEASE',
    );
  });

  test('the queue of the Autopilot is one line, no items (P8)', () {
    final s = build(
      activities: [
        act('81', kind: ActivityKind.queued, column: ActivityColumn.backlog),
        act('82', kind: ActivityKind.queued, column: ActivityColumn.backlog),
      ],
    );
    expect(s.running, isEmpty);
    expect(s.autopilot, ['Autopilot: 2 specs na fila']);
  });

  test('more than 6 items: the whole list is kept for "+ N"', () {
    final s = build(
      events: [
        for (var i = 0; i < 10; i++)
          ev(JournalKind.release, 'publicada', tag: 'v$i', minutesAgo: i + 1),
      ],
    );
    expect(s.finished, hasLength(10));
    expect(s.finished.first.releaseTag, 'v0');
  });

  test('times, labels and what the screen reader says (R5, R15)', () {
    expect(resumeTime(DateTime(2026, 11, 17, 7, 58), now), '07:58');
    expect(resumeTime(DateTime(2026, 11, 16, 21, 2), now), 'ontem 21:02');
    expect(resumeTime(DateTime(2026, 11, 14, 8, 0), now), '14/11 08:00');
    expect(awayLabel(const Duration(minutes: 47)), '47 min');
    expect(awayLabel(const Duration(hours: 13, minutes: 18)), '13 h');
    final i = build(
      events: [
        JournalEntry(
          workspaceId: 1,
          kind: JournalKind.gate,
          outcome: JournalOutcome.ok,
          title: 'SPEC-077 · Copiar código',
          detail: 'passou no gate',
          specId: 77,
          at: DateTime(2026, 11, 16, 23, 14),
        ),
      ],
    ).finished.single;
    expect(
      resumeSemantics(i),
      'SPEC-077 Copiar código, ok, passou no gate, 23 horas e 14, Revisar',
    );
  });
}
